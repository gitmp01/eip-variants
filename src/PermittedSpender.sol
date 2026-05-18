// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IERC20 {
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

interface IERC2612 {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

/// @notice Calls permit to set the allowance, then immediately pulls tokens —
///         all in a single transaction.
contract PermittedSpender {
    function pullWithPermit(
        address token,
        address owner,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        IERC2612(token).permit(owner, address(this), amount, deadline, v, r, s);
        IERC20(token).transferFrom(owner, address(this), amount);
    }
}
