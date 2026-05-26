// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/Spender.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {BaseAccount} from "account-abstraction/core/BaseAccount.sol";

interface IERC20Minimal {
    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

/// @notice Gas benchmark: EIP-7702 sponsored approve + transferFrom.
///
/// Extends Experiment 4 with gas sponsorship: same atomic batch (approve + pull) but a
/// separate sponsor address broadcasts the transaction and pays all gas fees.
///
/// The EOA only:
///   - holds USDC
///   - signs the EIP-7702 delegation (installs Simple7702Account code at its address)
///   - signs the UserOperation (authorises the call batch off-chain)
///
/// The sponsor:
///   - pre-funds the EOA's EntryPoint deposit (no paymaster needed)
///   - broadcasts the type-4 tx: attaches the delegation, calls EntryPoint.handleOps
///   - is the beneficiary in handleOps, recouping actual gas from the EOA's deposit
///
/// Key differences from Experiment 4:
///   - DELEGATE is Simple7702Account (deployed with EntryPoint v0.8), not the Alchemy wallet.
///     The Alchemy wallet is an ERC-6900 modular account that requires module installation
///     before it can process ERC-4337 UserOps without prior initialization.
///   - Delegation nonce: no +1 (sponsor sends the tx, not the EOA).
///   - initCode = 0x7702 marker so getUserOpHash includes the delegate address in its digest.
contract EIP7702SponsoredSpenderTest is Test {
    /// Simple7702Account deployed on mainnet (constructed with ENTRY_POINT below).
    address constant DELEGATE = 0x4Cd241E8d1510e30b2076397afc7508Ae59C66c9;
    IEntryPoint constant ENTRY_POINT =
        IEntryPoint(0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108);

    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    uint256 constant AMOUNT = 100e6; // 100 USDC

    uint256 constant EOA_KEY = 0x1234567890abcdef;
    uint256 constant SPONSOR_KEY = 0xdeadbeefdeadbeef;

    address eoa;
    address sponsor;
    Spender spender;

    function setUp() public {
        vm.createSelectFork("mainnet");
        eoa = vm.addr(EOA_KEY);
        sponsor = vm.addr(SPONSOR_KEY);
        spender = new Spender();

        deal(USDC, eoa, AMOUNT);

        // Sponsor pre-funds the EOA's EntryPoint deposit.
        // Sponsor is named beneficiary in handleOps and recoups actual gas spent.
        vm.deal(sponsor, 1 ether);
        vm.prank(sponsor);
        ENTRY_POINT.depositTo{value: 0.1 ether}(eoa);
    }

    function test_eip7702_sponsored_approveAndTransferFrom() public {
        // No +1: the sponsor (not the EOA) sends the tx, so the EOA's nonce is not
        // incremented by tx submission — only by the auth-list processing itself.
        uint64 delegationNonce = uint64(vm.getNonce(eoa));
        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(
            DELEGATE,
            EOA_KEY,
            delegationNonce
        );

        // Same two-call batch as Experiment 4.
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](2);
        calls[0] = BaseAccount.Call({
            target: USDC,
            value: 0,
            data: abi.encodeCall(
                IERC20Minimal.approve,
                (address(spender), AMOUNT)
            )
        });
        calls[1] = BaseAccount.Call({
            target: address(spender),
            value: 0,
            data: abi.encodeCall(Spender.pull, (USDC, eoa, AMOUNT))
        });

        // initCode = "" because getUserOpHash with 0x7702 tries to read the delegate from
        // the EOA's code before the delegation is attached. Empty initCode skips the 7702
        // hash override; signature validation still works since address(this) == EOA.
        PackedUserOperation memory userOp = PackedUserOperation({
            sender: eoa,
            nonce: ENTRY_POINT.getNonce(eoa, 0),
            initCode: "",
            callData: abi.encodeCall(BaseAccount.executeBatch, (calls)),
            accountGasLimits: _pack(200_000, 300_000), // verificationGasLimit | callGasLimit
            preVerificationGas: 100_000,
            gasFees: _pack(1 gwei, 100 gwei), // maxPriorityFeePerGas | maxFeePerGas
            paymasterAndData: "",
            signature: ""
        });

        // EOA signs the UserOp hash — raw ECDSA, no EIP-191 prefix or EIP-712 wrapping.
        bytes32 userOpHash = ENTRY_POINT.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(EOA_KEY, userOpHash);
        userOp.signature = abi.encodePacked(r, s, v);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        // Sponsor broadcasts: attaches the EOA's delegation, submits the UserOp.
        vm.broadcast(SPONSOR_KEY);
        vm.attachDelegation(signedDelegation);
        uint256 gasBefore = gasleft();
        ENTRY_POINT.handleOps(ops, payable(sponsor));
        uint256 gasUsed = gasBefore - gasleft();
        console.log("EIP-7702 sponsored: ", gasUsed);

        assertEq(IERC20Minimal(USDC).balanceOf(address(spender)), AMOUNT);
    }

    /// @dev Packs two uint128 values into a bytes32 (hi occupies upper 128 bits).
    function _pack(uint128 hi, uint128 lo) internal pure returns (bytes32) {
        return bytes32((uint256(hi) << 128) | uint256(lo));
    }
}
