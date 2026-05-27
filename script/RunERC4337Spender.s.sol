// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {BaseAccount} from "account-abstraction/core/BaseAccount.sol";
import {Spender} from "../src/Spender.sol";

interface IERC20Minimal {
    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

interface ISimpleAccountFactory {
    function getAddress(
        address owner,
        uint256 salt
    ) external view returns (address);

    function createAccount(
        address owner,
        uint256 salt
    ) external returns (address);
}

/// @notice Deploys a SimpleAccount via ERC-4337 on first run (using initCode) then executes
///         two separate handleOps transactions with non-sequential nonces:
///           tx1: nonce key 2002, seq 0  →  raw nonce (2002 << 64) | 0
///           tx2: nonce key 1001, seq 0  →  raw nonce (1001 << 64) | 0
///         Both ops perform the same approve + pull batch. Using distinct keys means the
///         EntryPoint treats them as independent nonce sequences, so order doesn't matter.
///
/// Flow:
///   1. The sponsor pre-funds the SA's EntryPoint deposit so the SA can pay for gas.
///   2. The EOA (owner) signs two UserOperations (different nonce keys, same callData).
///   3. The sponsor calls EntryPoint.handleOps() twice (one op each), in order: key 2002 first.
///
/// Factory source:
///   https://github.com/eth-infinitism/account-abstraction/blob/develop/contracts/accounts/SimpleAccountFactory.sol
///
/// Required env vars:
///   EOA_PRIVATE_KEY      — account that owns the SA and holds USDC
///   SPONSOR_PRIVATE_KEY  — account that pays gas (and pre-funds SA deposit on first run)
///
/// Optional env var:
///   SALT                 — uint256 salt for SA CREATE2 (default: 0)
///
/// Run with:
///   EOA_PRIVATE_KEY=0x... SPONSOR_PRIVATE_KEY=0x... \
///   forge script script/RunERC4337Spender.s.sol --rpc-url base-sepolia --broadcast --gas-limit 600000
contract RunERC4337Spender is Script {
    IEntryPoint constant ENTRY_POINT =
        IEntryPoint(0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108);

    /// SimpleAccountFactory deployed at the same address on all EVM chains (deterministic CREATE2).
    /// Source: https://github.com/eth-infinitism/account-abstraction/blob/develop/deployments/ethereum/SimpleAccountFactory.json
    ISimpleAccountFactory constant FACTORY =
        ISimpleAccountFactory(0x13E9ed32155810FDbd067D4522C492D6f68E5944);

    IERC20Minimal constant USDC =
        IERC20Minimal(0x036CbD53842c5426634e7929541eC2318f3dCF7e); // USDC on Base

    Spender constant SPENDER =
        Spender(0x165435CC57e72BB54fB54C76b7907459D4C9A034);

    uint256 constant AMOUNT = 1000; // 0.001 USDC (6 decimals)

    // UserOp gas limits for Base Sepolia.
    //
    // IMPORTANT: the outer tx gas limit must be > sum of all three values below.
    // Foundry's estimator under-counts this (it simulates but doesn't fully execute the
    // EntryPoint internals), so always pass --gas-limit explicitly on the CLI:
    //   --gas-limit 600000   (sum≈450k + ~150k EntryPoint overhead)
    //
    // verificationGasLimit: covers createAccount (first run, ~200k) + _validateSignature (~6k).
    // callGasLimit:         covers executeBatch → approve + pull (~60k total).
    // preVerificationGas:   flat overhead for bundler/calldata costs.
    uint128 constant VERIFICATION_GAS_LIMIT = 250_000;
    uint128 constant CALL_GAS_LIMIT = 100_000;
    uint256 constant PRE_VERIFICATION_GAS = 100_000;
    uint128 constant MAX_PRIORITY_FEE = 1 gwei;
    uint128 constant MAX_FEE = 10 gwei; // Base Sepolia basefee is well under 1 gwei

    // prefund required = MAX_FEE × (verificationGasLimit + callGasLimit + preVerificationGas)
    //                  = 10 gwei × 450_000 = 0.0045 ETH — 0.01 ETH covers it with margin.
    uint256 constant SPONSOR_DEPOSIT = 0.01 ether;

    function run() external {
        uint256 ownerKey = vm.envUint("EOA_PRIVATE_KEY");
        uint256 sponsorKey = vm.envUint("SPONSOR_PRIVATE_KEY");
        uint256 salt = vm.envOr("SALT", uint256(5));

        address owner = vm.addr(ownerKey);
        address sponsor = vm.addr(sponsorKey);
        address sa = FACTORY.getAddress(owner, salt);

        console.log("Owner              :", owner);
        console.log("Smart Account (SA) :", sa);
        console.log("SA already deployed:", sa.code.length > 0);
        console.log(
            "SA EntryPoint deposit (before):",
            ENTRY_POINT.balanceOf(sa)
        );

        // --- Step 1: sponsor pre-funds the SA's EntryPoint deposit if needed ----------
        // The SA pays gas from its EntryPoint balance; sponsor is the beneficiary and
        // recoups actual gas spent. Top up only when the deposit is insufficient.
        vm.startBroadcast(sponsorKey);
        if (ENTRY_POINT.balanceOf(sa) < SPONSOR_DEPOSIT) {
            ENTRY_POINT.depositTo{value: SPONSOR_DEPOSIT}(sa);
            console.log(
                "Deposited",
                SPONSOR_DEPOSIT,
                "wei for SA into EntryPoint"
            );
        }
        vm.stopBroadcast();

        // --- Steps 2-5: build two UserOps (different nonce keys) and submit separately --
        // Nonce key 2002, seq 0 → raw nonce (2002 << 64) | 0. Submitted first.
        // Only the first op carries initCode; the SA is deployed after that handleOps returns.
        PackedUserOperation memory userOp1 = _buildUserOp(
            ownerKey,
            sa,
            owner,
            salt,
            2002,
            sa.code.length == 0
        );

        // Nonce key 1001, seq 0 → raw nonce (1001 << 64) | 0. Submitted last.
        PackedUserOperation memory userOp2 = _buildUserOp(
            ownerKey,
            sa,
            owner,
            salt,
            1001,
            false
        );

        PackedUserOperation[] memory ops1 = new PackedUserOperation[](1);
        ops1[0] = userOp1;

        PackedUserOperation[] memory ops2 = new PackedUserOperation[](1);
        ops2[0] = userOp2;

        vm.startBroadcast(sponsorKey);
        ENTRY_POINT.handleOps(ops1, payable(sponsor));
        vm.stopBroadcast();

        // vm.startBroadcast(sponsorKey);
        // ENTRY_POINT.handleOps(ops2, payable(sponsor));
        // vm.stopBroadcast();

        console.log(
            "Done. Spender USDC balance:",
            IERC20Minimal(USDC).balanceOf(address(SPENDER))
        );
    }

    /// @dev Builds and signs the UserOperation for the approve + pull batch.
    ///      nonceKey selects an independent nonce sequence; raw nonce = (nonceKey << 64) | seq.
    ///      withInitCode = true only for the first op; subsequent ops must pass false because
    ///      the SA is already deployed after the first handleOps executes.
    function _buildUserOp(
        uint256 ownerKey,
        address sa,
        address owner,
        uint256 salt,
        uint192 nonceKey,
        bool withInitCode
    ) internal view returns (PackedUserOperation memory userOp) {
        // Build the call batch.
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](2);

        // call[0]: SA approves Spender to move its USDC.
        calls[0] = BaseAccount.Call({
            target: address(USDC),
            value: 0,
            data: abi.encodeCall(
                IERC20Minimal.approve,
                (address(SPENDER), AMOUNT)
            )
        });

        // call[1]: Spender pulls USDC from the SA via transferFrom.
        calls[1] = BaseAccount.Call({
            target: address(SPENDER),
            value: 0,
            data: abi.encodeCall(Spender.pull, (address(USDC), sa, AMOUNT))
        });

        bytes memory initCode = withInitCode
            ? abi.encodePacked(
                address(FACTORY),
                abi.encodeCall(
                    ISimpleAccountFactory.createAccount,
                    (owner, salt)
                )
            )
            : bytes("");

        userOp = PackedUserOperation({
            sender: sa,
            nonce: ENTRY_POINT.getNonce(sa, nonceKey),
            initCode: initCode,
            callData: abi.encodeCall(BaseAccount.executeBatch, (calls)),
            accountGasLimits: _pack(VERIFICATION_GAS_LIMIT, CALL_GAS_LIMIT),
            preVerificationGas: PRE_VERIFICATION_GAS,
            gasFees: _pack(MAX_PRIORITY_FEE, MAX_FEE),
            paymasterAndData: "",
            signature: ""
        });

        // Owner signs the UserOp hash — raw ECDSA, no EIP-191 prefix.
        bytes32 userOpHash = ENTRY_POINT.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, userOpHash);
        userOp.signature = abi.encodePacked(r, s, v);
    }

    /// @dev Packs two uint128 values into a bytes32 (hi = upper 128 bits).
    function _pack(uint128 hi, uint128 lo) internal pure returns (bytes32) {
        return bytes32((uint256(hi) << 128) | uint256(lo));
    }
}
