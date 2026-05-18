// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/PermittedSpender.sol";

interface IUSDCFull {
    function nonces(address owner) external view returns (uint256);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function balanceOf(address account) external view returns (uint256);
}

contract PermittedSpenderTest is Test {
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    bytes32 constant PERMIT_TYPEHASH =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    uint256 constant AMOUNT = 100e6;

    PermittedSpender permittedSpender;
    // Key chosen so vm.addr(signerKey) has no code on mainnet (plain EOA).
    uint256 signerKey = 0x1234567890abcdef;
    address owner;

    uint8 v;
    bytes32 r;
    bytes32 s;
    bytes32 digest;
    uint256 deadline;

    function setUp() public {
        vm.createSelectFork("mainnet");
        permittedSpender = new PermittedSpender();
        owner = vm.addr(signerKey);
        deal(USDC, owner, AMOUNT);

        bytes32 domainSeparator = IUSDCFull(USDC).DOMAIN_SEPARATOR();
        uint256 nonce = IUSDCFull(USDC).nonces(owner);
        deadline = block.timestamp + 1 hours;

        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                owner,
                address(permittedSpender),
                AMOUNT,
                nonce,
                deadline
            )
        );
        digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (v, r, s) = vm.sign(signerKey, digest);
    }

    function test_permitAndTransferFrom() public {
        uint256 gasBefore = gasleft();
        permittedSpender.pullWithPermit(USDC, owner, AMOUNT, deadline, v, r, s);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("ERC-2612:", gasUsed);
    }
}
