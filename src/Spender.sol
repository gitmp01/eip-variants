// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @notice Minimal contract that pulls pre-approved tokens from a sender.
contract Spender {
    /// @dev Caller must have already called token.approve(address(this), amount).
    function pull(address token, address from, uint256 amount) external {
        IERC20(token).transferFrom(from, address(this), amount);
    }
}
