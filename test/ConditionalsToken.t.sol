// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ConditionalsToken} from "../src/ConditionalsToken.sol";

/// @dev Local deployment helper, not a production launch factory.
contract TokenFactoryFixture {
    function deploy(bytes32 salt) external returns (ConditionalsToken) {
        return new ConditionalsToken{salt: salt}();
    }
}

/// @dev A contract with no token-receiving callback; ERC-20 transfers must still work.
contract ContractRecipientFixture {}

contract ConditionalsTokenTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    ConditionalsToken private token;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        token = new ConditionalsToken();
    }

    function test_MetadataAndEntireSupply() public view {
        assertEq(token.name(), "Conditionals");
        assertEq(token.symbol(), "COND");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_ConstructorEmitsMintAndUsesImmediateDeployer() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), alice, SUPPLY);
        vm.prank(alice, bob);
        ConditionalsToken deployed = new ConditionalsToken();
        assertEq(deployed.balanceOf(alice), SUPPLY);
        assertEq(deployed.balanceOf(bob), 0);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_Create2MintsWholeSupplyToFactoryWithoutExternalDependencies() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        vm.prank(alice, alice);
        ConditionalsToken deployed = factory.deploy(keccak256("COND launch"));

        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(alice), 0);
        assertEq(deployed.balanceOf(address(this)), 0);
        assertEq(deployed.totalSupply(), SUPPLY);
        assertGt(address(deployed).code.length, 0);
        assertLe(address(deployed).code.length, 24_576);
    }

    function test_TransferMovesExactAmountAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 23 ether);
        assertTrue(token.transfer(alice, 23 ether));
        assertEq(token.balanceOf(alice), 23 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 23 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferEntireSupplyAndSmallestUnit() public {
        assertTrue(token.transfer(alice, SUPPLY));
        vm.prank(alice);
        assertTrue(token.transfer(bob, 1));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY - 1);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_SelfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferToContractNeedsNoCallback() public {
        address recipient = address(new ContractRecipientFixture());
        assertTrue(token.transfer(recipient, 10 ether));
        assertEq(token.balanceOf(recipient), 10 ether);
    }

    function test_TransferToZeroRevertsEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferInsufficientBalanceReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_SelfTransferStillChecksBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(alice, 1);
    }

    function test_ApproveEmitsEventAndDoesNotMoveTokens() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 100 ether);
        assertTrue(token.approve(spender, 100 ether));
        assertEq(token.allowance(address(this), spender), 100 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_ApprovalCanBeReplacedAndRevoked() public {
        assertTrue(token.approve(spender, 100 ether));
        assertTrue(token.approve(spender, 50 ether));
        assertEq(token.allowance(address(this), spender), 50 ether);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ApprovalIsScopedToOwnerAndSpender() public {
        token.approve(spender, 50 ether);
        vm.prank(alice);
        token.approve(bob, 10 ether);
        assertEq(token.allowance(address(this), spender), 50 ether);
        assertEq(token.allowance(alice, bob), 10 ether);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.allowance(address(this), bob), 0);
    }

    function test_ApproveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_TransferFromConsumesAllowanceAndEmitsTransfer() public {
        token.approve(spender, 100 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 40 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 40 ether));
        assertEq(token.allowance(address(this), spender), 60 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 40 ether);
        assertEq(token.balanceOf(alice), 40 ether);
        assertEq(token.balanceOf(spender), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 60 ether));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.balanceOf(bob), 60 ether);
    }

    function test_InfiniteAllowanceRemainsUnchanged() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_TransferFromToSameHolderConsumesAllowanceNotBalance() public {
        token.approve(spender, 10 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 10 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_HolderTransferFromRequiresAllowanceToo() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
    }

    function test_ZeroTransferFromNeedsNoAllowance() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_UnapprovedSpenderCannotUseAnotherSpendersAllowance() public {
        token.approve(spender, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), 100 ether);
    }

    function test_TransferFromInsufficientBalanceRollsBackAllowance() public {
        vm.prank(alice);
        token.approve(spender, 5 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 5 ether));
        vm.prank(spender);
        token.transferFrom(alice, bob, 5 ether);
        assertEq(token.allowance(alice, spender), 5 ether);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_TransferFromToZeroRollsBackAllowance() public {
        token.approve(spender, 5 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 5 ether);
        assertEq(token.allowance(address(this), spender), 5 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromZeroSenderReverts() public {
        // OpenZeppelin validates the allowance owner before attempting the transfer.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(0), alice, 0);
    }

    function test_DeployerCannotPullHolderTokensWithoutApproval() public {
        token.transfer(alice, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, address(this), 1);
        assertEq(token.balanceOf(alice), 10 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10 ether));
        assertEq(token.balanceOf(bob), 10 ether);
    }

    function test_NoAdministrativeOrAdditionalIssuanceEntrypoints() public {
        bytes[] memory calls = new bytes[](13);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, 1 ether);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1 ether);
        calls[2] = abi.encodeWithSignature("burn(uint256)", 1 ether);
        calls[3] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1 ether);
        calls[4] = abi.encodeWithSignature("pause()");
        calls[5] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[6] = abi.encodeWithSignature("freeze(address)", alice);
        calls[7] = abi.encodeWithSignature("seize(address)", alice);
        calls[8] = abi.encodeWithSignature("setMinter(address)", bob);
        calls[9] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[10] = abi.encodeWithSignature("initialize(address)", bob);
        calls[11] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[12] = abi.encodeWithSignature("owner()");
        token.transfer(alice, 10 ether);
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSuccess,) = address(token).call(calls[i]);
            assertFalse(deployerSuccess);
            vm.prank(bob);
            (bool strangerSuccess,) = address(token).call(calls[i]);
            assertFalse(strangerSuccess);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10 ether));
    }

    function test_PlainEtherPaymentReverts() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool success,) = address(token).call{value: 1 ether}("");
        assertFalse(success);
        assertEq(address(token).balance, 0);
        assertEq(alice.balance, 1 ether);
    }

    /// @dev Exercises token movements only, not Uniswap pricing or liquidity math.
    function test_LaunchDistributionClaimsAndPoolTransfersAreExact() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        ConditionalsToken launched = factory.deploy(keccak256("distribution"));
        address distributor = address(new ContractRecipientFixture());
        address poolManager = address(new ContractRecipientFixture());
        address remainder = makeAddr("remainder");
        uint256 swarm = SUPPLY / 10;
        uint256 pool = SUPPLY / 2;

        vm.startPrank(address(factory));
        assertTrue(launched.transfer(distributor, swarm));
        assertTrue(launched.transfer(poolManager, pool));
        assertTrue(launched.transfer(remainder, SUPPLY - swarm - pool));
        vm.stopPrank();
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(distributor), swarm);
        assertEq(launched.balanceOf(poolManager), pool);
        assertEq(launched.balanceOf(remainder), SUPPLY * 4 / 10);

        vm.prank(distributor);
        assertTrue(launched.transfer(alice, swarm));
        assertEq(launched.balanceOf(distributor), 0);
        assertEq(launched.balanceOf(alice), swarm);

        vm.prank(poolManager);
        assertTrue(launched.transfer(bob, 1 ether));
        assertEq(launched.balanceOf(bob), 1 ether);
        assertEq(launched.balanceOf(poolManager), pool - 1 ether);
        vm.prank(bob);
        assertTrue(launched.transfer(poolManager, 1 ether));
        assertEq(launched.balanceOf(bob), 0);
        assertEq(launched.balanceOf(poolManager), pool);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferToAnyNonzeroRecipient(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        if (recipient == address(this)) {
            assertEq(token.balanceOf(address(this)), SUPPLY);
        } else {
            assertEq(token.balanceOf(recipient), amount);
            assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferBeyondBalanceIsAtomic(uint256 balance, uint256 extra) public {
        balance = bound(balance, 0, SUPPLY);
        extra = bound(extra, 1, type(uint256).max - balance);
        token.transfer(alice, balance);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, balance + extra)
        );
        vm.prank(alice);
        token.transfer(bob, balance + extra);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferFromRespectsBalanceAndAllowance(uint256 approval, uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        approval = bound(approval, amount, type(uint256).max);
        token.approve(spender, approval);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(address(this), spender), approval == type(uint256).max ? approval : approval - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_InsufficientAllowanceIsAtomic(uint256 approval, uint256 extra) public {
        approval = bound(approval, 0, SUPPLY - 1);
        extra = bound(extra, 1, SUPPLY - approval);
        token.approve(spender, approval);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, approval, approval + extra
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, approval + extra);
        assertEq(token.allowance(address(this), spender), approval);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
