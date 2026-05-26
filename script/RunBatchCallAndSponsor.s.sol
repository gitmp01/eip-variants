// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {BatchCallAndSponsor} from "../src/BatchCallAndSponsor.sol";
import {Spender} from "../src/Spender.sol";

interface IERC20Minimal {
    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

/// @notice Sponsors an EIP-7702 approve + pull batch using BatchCallAndSponsor.
///
/// The EOA signs two things off-chain:
///   1. An EIP-7702 delegation — installs BatchCallAndSponsor code at its address.
///   2. The call batch — authorises the specific calls the sponsor will submit.
///
/// The sponsor broadcasts a single type-4 tx that carries the delegation and calls
/// execute(calls, signature) on the EOA. No ETH is spent by the EOA.
///
/// Required env vars:
///   EOA_PRIVATE_KEY              — account that holds USDC and signs
///   SPONSOR_PRIVATE_KEY          — account that pays gas
///   BATCH_CALL_AND_SPONSOR_ADDR  — deployed BatchCallAndSponsor contract address
///
/// Run with:
///   EOA_PRIVATE_KEY=0x... SPONSOR_PRIVATE_KEY=0x... BATCH_CALL_AND_SPONSOR_ADDR=0x... \
///   forge script script/RunBatchCallAndSponsor.s.sol --rpc-url base --broadcast
contract RunBatchCallAndSponsor is Script {
    IERC20Minimal constant USDC =
        IERC20Minimal(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    Spender constant SPENDER =
        Spender(0x89f4916479c81470CA90737e3cc60e99062d3388);
    uint256 constant AMOUNT = 1000;

    function run() external {
        uint256 eoaKey = vm.envUint("EOA_PRIVATE_KEY");
        uint256 sponsorKey = vm.envUint("SPONSOR_PRIVATE_KEY");
        address delegate = vm.envAddress("BATCH_CALL_AND_SPONSOR_ADDR");

        address eoa = vm.addr(eoaKey);

        // Step 1: EOA signs the EIP-7702 delegation to BatchCallAndSponsor.
        // No +1: the sponsor (not the EOA) is the broadcaster, so the EOA's tx nonce
        // is not incremented by submission — only by the auth-list processing itself.
        uint64 delegationNonce = vm.getNonce(eoa);
        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(
            delegate,
            eoaKey,
            delegationNonce
        );

        // Step 2: Build the call batch (approve + pull).
        BatchCallAndSponsor.Call[]
            memory calls = new BatchCallAndSponsor.Call[](2);

        // call[0]: EOA (acting as smart account) approves Spender to move its USDC.
        calls[0] = BatchCallAndSponsor.Call({
            to: address(USDC),
            value: 0,
            data: abi.encodeCall(
                IERC20Minimal.approve,
                (address(SPENDER), AMOUNT)
            )
        });

        // call[1]: Spender pulls USDC from the EOA via transferFrom.
        calls[1] = BatchCallAndSponsor.Call({
            to: address(SPENDER),
            value: 0,
            data: abi.encodeCall(Spender.pull, (address(USDC), eoa, AMOUNT))
        });

        // Step 3: EOA signs the batch message so BatchCallAndSponsor.execute() can verify it.
        //
        // The contract's replay-protection nonce lives in the EOA's storage slot 0.
        // We read it directly — it's 0 on first use, and increments with each execute() call.
        uint256 contractNonce = uint256(vm.load(eoa, bytes32(0)));

        // Replicate the digest the contract will verify against (see BatchCallAndSponsor.execute).
        bytes memory encodedCalls;
        for (uint256 i = 0; i < calls.length; i++) {
            encodedCalls = abi.encodePacked(
                encodedCalls,
                calls[i].to,
                calls[i].value,
                calls[i].data
            );
        }
        bytes32 digest = keccak256(
            abi.encodePacked(contractNonce, encodedCalls)
        );
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            digest
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoaKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Step 4: Sponsor broadcasts — attaches EOA's delegation and submits the signed batch.
        // After vm.attachDelegation, the EOA has BatchCallAndSponsor code installed, so calling
        // execute() on it routes to the delegated implementation.
        vm.startBroadcast(sponsorKey);
        vm.attachDelegation(signedDelegation);
        BatchCallAndSponsor(payable(eoa)).execute(calls, signature);
        vm.stopBroadcast();
    }
}
