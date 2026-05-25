// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Minimal contract that pulls pre-approved tokens from a sender.
contract Spender {
    using SafeERC20 for IERC20;

    /// @dev Caller must have already called token.approve(address(this), amount).
    function pull(address token, address from, uint256 amount) external {
        IERC20(token).safeTransferFrom(from, address(this), amount);
    }
}
