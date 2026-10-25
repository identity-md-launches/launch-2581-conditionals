// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Conditionals (COND)
/// @notice Fixed-supply ERC-20; the deployer receives all tokens at construction.
/// @dev In an IMD launch, msg.sender is the launch factory. There is no owner,
///      external mint/burn function, transfer tax, or post-deployment configuration.
contract ConditionalsToken is ERC20 {
    /// @notice One billion COND, denominated in the token's 18-decimal base units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("Conditionals", "COND") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
