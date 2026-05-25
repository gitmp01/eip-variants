// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {Recipient} from "../src/Recipient.sol";

interface IUSDCFull {
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function balanceOf(address account) external view returns (uint256);
}

/// @notice Mirrors RecipientTest.test_transferWithAuthorization against the live deployment.
///         Run with: forge script ... --account <name> --broadcast
///         The account must hold enough USDC on Base.
contract RunRecipient is Script {
    // keccak256("TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
    bytes32 constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH =
        0x7c7c6cdb67a18743f49ec6fa9b35f50d52ed05cbed4cc592e13b44501c1a2267;

    IUSDCFull constant USDC =
        IUSDCFull(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    Recipient constant RECIPIENT =
        Recipient(0x6a41f762a1324aD739EB0AEB664669B3A641F70a);
    uint256 constant AMOUNT = 1000; // 100 USDC

    function run() external {
        vm.startBroadcast();
        address signer = msg.sender;

        // Nonce must be a value never used before by this (from, nonce) pair.
        // Using block.timestamp + signer mirrors the test; replace with a stored nonce tracker if needed.
        bytes32 nonce = keccak256(abi.encodePacked(block.timestamp, signer));
        uint256 validAfter = 0;
        uint256 validBefore = block.timestamp + 1 hours;

        bytes32 structHash = keccak256(
            abi.encode(
                TRANSFER_WITH_AUTHORIZATION_TYPEHASH,
                signer,
                address(RECIPIENT),
                AMOUNT,
                validAfter,
                validBefore,
                nonce
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", USDC.DOMAIN_SEPARATOR(), structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer, digest);

        RECIPIENT.receivePayment(
            address(USDC),
            signer,
            AMOUNT,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );
        vm.stopBroadcast();

        console.log(
            "Recipient.receivePayment succeeded. USDC balance of RECIPIENT:",
            USDC.balanceOf(address(RECIPIENT))
        );
    }
}
