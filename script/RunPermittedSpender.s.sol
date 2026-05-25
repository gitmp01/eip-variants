// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {PermittedSpender} from "../src/PermittedSpender.sol";

interface IUSDCFull {
    function nonces(address owner) external view returns (uint256);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function balanceOf(address account) external view returns (uint256);
}

/// @notice Mirrors PermittedSpenderTest.test_permitAndTransferFrom against the live deployment.
///         Run with: forge script ... --account <name> --broadcast
///         The account must hold enough USDC on Base.
contract RunPermittedSpender is Script {
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    bytes32 constant PERMIT_TYPEHASH =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    IUSDCFull constant USDC =
        IUSDCFull(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    PermittedSpender constant PERMITTED_SPENDER =
        PermittedSpender(0xd7409fa426949D884E82762E0fF54145e7Fa9658);
    uint256 constant AMOUNT = 1000; // 100 USDC

    function run() external {
        vm.startBroadcast();
        address owner = msg.sender;
        console.log("msg.sender");
        console.log(msg.sender);

        uint256 nonce = USDC.nonces(owner);
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                owner,
                address(PERMITTED_SPENDER),
                AMOUNT,
                nonce,
                deadline
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", USDC.DOMAIN_SEPARATOR(), structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(owner, digest);

        PERMITTED_SPENDER.pullWithPermit(
            address(USDC),
            owner,
            AMOUNT,
            deadline,
            v,
            r,
            s
        );
        vm.stopBroadcast();

        console.log(
            "PermittedSpender.pullWithPermit succeeded. USDC balance of PERMITTED_SPENDER:",
            USDC.balanceOf(address(PERMITTED_SPENDER))
        );
    }
}
