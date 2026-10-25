// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ConditionalsToken} from "../src/ConditionalsToken.sol";

/// @dev Four tracked holders and an independent ledger exercise successful and
///      failing transfers, allowance replacement, revocation, and delegated spend.
contract TokenHandler is Test {
    ConditionalsToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(ConditionalsToken token_) {
        token = token_;
        actors[0] = address(this);
        actors[1] = makeAddr("holder one");
        actors[2] = makeAddr("holder two");
        actors[3] = makeAddr("holder three");
        expectedBalance[address(this)] = 1_000_000_000 * 10 ** 18;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        // Generate mostly valid transfers, but also some overdrafts.
        uint256 amount = bound(amountSeed, 0, expectedBalance[from] + 1);
        bool expectedSuccess = amount <= expectedBalance[from];
        vm.prank(from);
        (bool success, bytes memory result) = address(token).call(abi.encodeCall(token.transfer, (to, amount)));
        assertEq(success, expectedSuccess, "transfer authorization differs from model");
        if (success) {
            assertTrue(abi.decode(result, (bool)));
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount;
        if (amountSeed % 4 == 0) amount = type(uint256).max;
        else if (amountSeed % 4 != 1) amount = bound(amountSeed, 0, 1_000_000_000 * 10 ** 18);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approval = expectedAllowance[owner][spender];
        uint256 available = expectedBalance[owner];
        uint256 spendable = approval < available ? approval : available;
        uint256 amount = bound(amountSeed, 0, spendable + 1);
        bool expectedSuccess = amount <= spendable;
        vm.prank(spender);
        (bool success, bytes memory result) =
            address(token).call(abi.encodeCall(token.transferFrom, (owner, to, amount)));
        assertEq(success, expectedSuccess, "delegated transfer authorization differs from model");
        if (success) {
            assertTrue(abi.decode(result, (bool)));
            expectedBalance[owner] -= amount;
            expectedBalance[to] += amount;
            if (approval != type(uint256).max) expectedAllowance[owner][spender] -= amount;
        }
    }
}

contract ConditionalsTokenInvariantTest is Test {
    ConditionalsToken private token;
    TokenHandler private handler;

    function setUp() public {
        token = new ConditionalsToken();
        handler = new TokenHandler(token);
        assertTrue(token.transfer(address(handler), token.totalSupply()));

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_SupplyIsFixedAndAllBalancesAreAccountedFor() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(token.totalSupply(), 1_000_000_000 * 10 ** 18);
        assertEq(sum, token.totalSupply());
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_BalancesAndAllowancesMatchIndependentLedger() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            assertEq(token.balanceOf(owner), handler.expectedBalance(owner));
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }
}
