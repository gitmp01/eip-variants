// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IERC3009 {
    function transferWithAuthorization(
        address from, address to, uint256 value,
        uint256 validAfter, uint256 validBefore, bytes32 nonce,
        uint8 v, bytes32 r, bytes32 s
    ) external;
}

/// @notice Minimal contract that accepts a pre-signed ERC-3009 authorization and
///         forwards the transfer to itself.
contract Recipient {
    function receivePayment(
        address token,
        address from,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v, bytes32 r, bytes32 s
    ) external {
        IERC3009(token).transferWithAuthorization(
            from, address(this), value,
            validAfter, validBefore, nonce,
            v, r, s
        );
    }
}
