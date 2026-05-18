// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/Recipient.sol";

interface IERC3009Like {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

contract RecipientTest is Test {
    // keccak256("TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
    bytes32 constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH =
        0x7c7c6cdb67a18743f49ec6fa9b35f50d52ed05cbed4cc592e13b44501c1a2267;

    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    uint256 constant AMOUNT = 100e6;

    Recipient recipient;
    // Key chosen so vm.addr(signerKey) has no code on mainnet (plain EOA).
    uint256 signerKey = 0x1234567890abcdef;
    address signer;

    uint8 v;
    bytes32 r;
    bytes32 s;
    bytes32 nonce;
    uint256 validAfter;
    uint256 validBefore;
    bytes32 digest;

    function setUp() public {
        vm.createSelectFork("mainnet");
        recipient = new Recipient();
        signer = vm.addr(signerKey);
        deal(USDC, signer, AMOUNT);

        bytes32 domainSeparator = IERC3009Like(USDC).DOMAIN_SEPARATOR();
        nonce = keccak256(abi.encodePacked(block.timestamp, signer));
        validAfter = 0;
        validBefore = block.timestamp + 1 hours;
        bytes32 structHash = keccak256(
            abi.encode(
                TRANSFER_WITH_AUTHORIZATION_TYPEHASH,
                signer,
                address(recipient),
                AMOUNT,
                validAfter,
                validBefore,
                nonce
            )
        );
        digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (v, r, s) = vm.sign(signerKey, digest);
    }

    function test_transferWithAuthorization() public {
        uint256 gasBefore = gasleft();
        recipient.receivePayment(
            USDC,
            signer,
            AMOUNT,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );
        uint256 gasUsed = gasBefore - gasleft();
        console.log("ERC-3009:", gasUsed);
    }
}
