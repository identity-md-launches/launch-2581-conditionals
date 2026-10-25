// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ConditionalsToken} from "../src/ConditionalsToken.sol";

/// @dev Edge cases not covered elsewhere: emitted log counts, the exact external surface,
///      arbitrary owners/spenders, and allowance arithmetic at its bounds.
contract ConditionalsTokenEdgesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    bytes32 private constant TRANSFER_TOPIC = keccak256("Transfer(address,address,uint256)");
    bytes32 private constant APPROVAL_TOPIC = keccak256("Approval(address,address,uint256)");

    ConditionalsToken private token;
    address private alice;
    address private spender;

    function setUp() public {
        alice = makeAddr("alice");
        spender = makeAddr("spender");
        token = new ConditionalsToken();
    }

    function test_TransferEmitsExactlyOneLog() public {
        vm.recordLogs();
        token.transfer(alice, 7);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(token));
        assertEq(logs[0].topics[0], TRANSFER_TOPIC);
        assertEq(address(uint160(uint256(logs[0].topics[1]))), address(this));
        assertEq(address(uint160(uint256(logs[0].topics[2]))), alice);
        assertEq(abi.decode(logs[0].data, (uint256)), 7);
    }

    /// @dev transferFrom only emits Transfer; the allowance decrease is silent (OZ v5 behaviour),
    ///      so indexers must read allowance() rather than replay Approval events.
    function test_TransferFromEmitsOnlyTransferForFiniteAndInfiniteAllowance() public {
        token.approve(spender, 10);
        vm.recordLogs();
        vm.prank(spender);
        token.transferFrom(address(this), alice, 4);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], TRANSFER_TOPIC);
        assertEq(token.allowance(address(this), spender), 6);

        token.approve(spender, type(uint256).max);
        vm.recordLogs();
        vm.prank(spender);
        token.transferFrom(address(this), alice, 4);
        logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], TRANSFER_TOPIC);
    }

    function test_ApproveEmitsExactlyOneApprovalLog() public {
        vm.recordLogs();
        token.approve(spender, type(uint256).max);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], APPROVAL_TOPIC);
        assertEq(abi.decode(logs[0].data, (uint256)), type(uint256).max);
    }

    function test_FailedCallsEmitNothingAndChangeNothing() public {
        vm.recordLogs();
        vm.prank(alice);
        (bool ok,) = address(token).call(abi.encodeCall(token.transfer, (spender, 1)));
        assertFalse(ok);
        (ok,) = address(token).call(abi.encodeCall(token.transfer, (address(0), 1)));
        assertFalse(ok);
        (ok,) = address(token).call(abi.encodeCall(token.approve, (address(0), 1)));
        assertFalse(ok);
        vm.prank(spender);
        (ok,) = address(token).call(abi.encodeCall(token.transferFrom, (address(this), alice, 1)));
        assertFalse(ok);
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_AllowanceExactlyOneBelowAmountReverts() public {
        token.approve(spender, SUPPLY - 1);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, SUPPLY - 1, SUPPLY)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, SUPPLY);
        // max - 1 is a finite allowance and is decremented, unlike max.
        token.approve(spender, type(uint256).max - 1);
        vm.prank(spender);
        token.transferFrom(address(this), alice, SUPPLY);
        assertEq(token.allowance(address(this), spender), type(uint256).max - 1 - SUPPLY);
    }

    function test_AllowanceAboveBalanceStillLimitedByBalance() public {
        token.transfer(alice, 5);
        vm.prank(alice);
        token.approve(spender, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 5, 6));
        vm.prank(spender);
        token.transferFrom(alice, spender, 6);
        assertEq(token.balanceOf(alice), 5);
    }

    function test_ApproveToSelfAndSelfSpendWorks() public {
        token.approve(address(this), 3);
        assertTrue(token.transferFrom(address(this), alice, 3));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(alice), 3);
    }

    function test_TokenCanHoldAndReturnNothingStuck() public {
        // Tokens sent to the token contract itself are accepted and cannot be recovered by
        // anyone: there is no rescue function. Informational, standard for plain ERC-20s.
        token.transfer(address(token), 1 ether);
        assertEq(token.balanceOf(address(token)), 1 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_FixedSupplyConstantMatchesTotalSupplyAcrossDeployers() public {
        for (uint256 i; i < 3; ++i) {
            address deployer = address(uint160(0x1000 + i));
            vm.prank(deployer);
            ConditionalsToken t = new ConditionalsToken();
            assertEq(t.totalSupply(), t.INITIAL_SUPPLY());
            assertEq(t.balanceOf(deployer), SUPPLY);
        }
    }

    /// @dev Only the ERC-20 surface and INITIAL_SUPPLY exist; every other 4-byte selector reverts.
    function testFuzz_UnknownSelectorsRevert(bytes4 selector, bytes calldata tail) public {
        vm.assume(
            selector != token.name.selector && selector != token.symbol.selector && selector != token.decimals.selector
                && selector != token.totalSupply.selector && selector != token.balanceOf.selector
                && selector != token.transfer.selector && selector != token.allowance.selector
                && selector != token.approve.selector && selector != token.transferFrom.selector
                && selector != token.INITIAL_SUPPLY.selector
        );
        (bool ok,) = address(token).call(abi.encodePacked(selector, tail));
        assertFalse(ok);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testFuzz_ApproveAnyPairIsIsolated(address owner, address spender_, uint256 amount) public {
        vm.assume(owner != address(0) && spender_ != address(0));
        vm.prank(owner);
        assertTrue(token.approve(spender_, amount));
        assertEq(token.allowance(owner, spender_), amount);
        if (owner != spender_) assertEq(token.allowance(spender_, owner), 0);
        assertEq(token.balanceOf(owner), owner == address(this) ? SUPPLY : 0);
    }

    function testFuzz_ApproveFromZeroOwnerReverts(address spender_, uint256 amount) public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(spender_, amount);
    }

    function testFuzz_TransferFromToZeroAlwaysReverts(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        token.approve(spender, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testFuzz_TwoHopRoundTripRestoresBalances(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        token.transfer(alice, amount);
        vm.prank(alice);
        token.transfer(address(this), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }
}

/// @dev Handler over an open-ended set of holders (any non-zero fuzzed address), including
///      the token contract itself as a recipient. Every reachable holder is recorded, so the
///      sum of recorded balances must always equal the fixed supply.
contract OpenHolderHandler is Test {
    ConditionalsToken public immutable token;
    address[] public holders;
    mapping(address => bool) public known;
    uint256 public ghostMoved;
    uint256 public ghostFailed;
    /// @dev The invariant test contract must never become a holder: its invariant checks it holds nothing.
    address public immutable excluded;

    constructor(ConditionalsToken token_, address excluded_) {
        token = token_;
        excluded = excluded_;
        _record(address(this));
    }

    function _target(address a) internal view returns (address) {
        if (a == address(0) || a == excluded || a == address(vm) || a == CONSOLE) return address(token);
        return a;
    }

    function holderCount() external view returns (uint256) {
        return holders.length;
    }

    function _record(address a) internal {
        if (!known[a]) {
            known[a] = true;
            holders.push(a);
        }
    }

    function _pick(uint256 seed) internal view returns (address) {
        return holders[seed % holders.length];
    }

    function transferToNew(uint256 fromSeed, address to, uint256 amountSeed) external {
        to = _target(to);
        address from = _pick(fromSeed);
        uint256 bal = token.balanceOf(from);
        uint256 amount = bound(amountSeed, 0, bal);
        uint256 toBefore = token.balanceOf(to);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _record(to);
        if (from != to) {
            assertEq(token.balanceOf(from), bal - amount);
            assertEq(token.balanceOf(to), toBefore + amount);
        }
        ghostMoved += amount;
    }

    function overdraft(uint256 fromSeed, uint256 extraSeed) external {
        address from = _pick(fromSeed);
        uint256 bal = token.balanceOf(from);
        uint256 extra = bound(extraSeed, 1, type(uint256).max - bal);
        vm.prank(from);
        (bool ok,) = address(token).call(abi.encodeCall(token.transfer, (address(this), bal + extra)));
        assertFalse(ok);
        assertEq(token.balanceOf(from), bal);
        ghostFailed++;
    }

    function burnAttempt(uint256 fromSeed, uint256 amountSeed) external {
        address from = _pick(fromSeed);
        uint256 amount = bound(amountSeed, 0, token.balanceOf(from));
        vm.prank(from);
        (bool ok,) = address(token).call(abi.encodeCall(token.transfer, (address(0), amount)));
        assertFalse(ok);
        ghostFailed++;
    }

    function delegated(uint256 ownerSeed, address spender, uint256 approvalSeed, uint256 amountSeed) external {
        spender = _target(spender);
        address owner = _pick(ownerSeed);
        uint256 bal = token.balanceOf(owner);
        uint256 approval = bound(approvalSeed, 0, bal);
        vm.prank(owner);
        token.approve(spender, approval);
        uint256 amount = bound(amountSeed, 0, approval + 1);
        vm.prank(spender);
        (bool ok,) = address(token).call(abi.encodeCall(token.transferFrom, (owner, spender, amount)));
        assertEq(ok, amount <= approval);
        if (ok) {
            _record(spender);
            assertEq(token.allowance(owner, spender), approval - amount);
            ghostMoved += amount;
        } else {
            assertEq(token.allowance(owner, spender), approval);
            ghostFailed++;
        }
    }
}

contract ConditionalsTokenOpenHolderInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    ConditionalsToken private token;
    OpenHolderHandler private handler;

    function setUp() public {
        token = new ConditionalsToken();
        handler = new OpenHolderHandler(token, address(this));
        token.transfer(address(handler), SUPPLY);
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 128
    /// forge-config: default.invariant.depth = 64
    function invariant_RecordedHoldersOwnWholeFixedSupply() public view {
        uint256 n = handler.holderCount();
        uint256 sum;
        for (uint256 i; i < n; ++i) {
            uint256 b = token.balanceOf(handler.holders(i));
            assertLe(b, SUPPLY);
            sum += b;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function invariant_MetadataNeverChanges() public view {
        assertEq(token.name(), "Conditionals");
        assertEq(token.symbol(), "COND");
        assertEq(token.decimals(), 18);
    }
}
