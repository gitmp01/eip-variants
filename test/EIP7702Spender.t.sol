// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/Spender.sol";

/// @notice Minimal interface for the Alchemy smart-wallet implementation used as the
///         EIP-7702 delegate. Matches the `executeBatch` ABI from the Rust reference code.
interface ISmartWallet {
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    function executeBatch(Call[] calldata calls) external payable;
}

interface IERC20Minimal {
    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

/// @notice Gas benchmark: EIP-7702 batched approve + transferFrom.
///
/// Classic pattern (Experiment 1) requires two separate transactions:
///   tx1 (user)    — token.approve(spender, amount)
///   tx2 (spender) — spender.pull(token, user, amount)  →  token.transferFrom(...)
///
/// EIP-7702 collapses this into a single type-4 transaction from the EOA:
///   The EOA installs the Alchemy smart-wallet delegate, then calls executeBatch with:
///   call[0] — token.approve(spenderContract, amount)   (sets allowance)
///   call[1] — spenderContract.pull(token, eoa, amount) (triggers transferFrom)
///
/// Both calls are paid by the EOA in one transaction; the spender never sends a tx.
/// call[1] routes through Spender so msg.sender in USDC's transferFrom is Spender,
/// matching allowance[eoa][spender] set in call[0].
contract EIP7702SpenderTest is Test {
    /// Alchemy smart-wallet implementation — the EIP-7702 delegate.
    /// Same address used in the Rust reference (eip7702/src/main.rs).
    address constant DELEGATE = 0x69007702764179f14F51cdce752f4f775d74E139;

    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    uint256 constant AMOUNT = 100e6; // 100 USDC

    // Same EOA key used across the test suite: clean address with no mainnet code.
    uint256 constant EOA_KEY = 0x1234567890abcdef;

    address eoa;
    Spender spender;

    function setUp() public {
        vm.createSelectFork("mainnet");
        eoa = vm.addr(EOA_KEY);
        spender = new Spender();
        deal(USDC, eoa, AMOUNT);
    }

    /// @dev Single EIP-7702 transaction that atomically approves the Spender contract
    ///      and triggers the pull — replacing the two-transaction classic pattern.
    function test_eip7702_approveAndTransferFrom() public {
        // Install DELEGATE bytecode at the EOA for the next call.
        uint64 nonce = vm.getNonce(eoa) + 1;
        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(
            DELEGATE,
            EOA_KEY,
            nonce
        );

        ISmartWallet.Call[] memory calls = new ISmartWallet.Call[](2);

        // call[0]: EOA approves the Spender contract
        calls[0] = ISmartWallet.Call({
            target: USDC,
            value: 0,
            data: abi.encodeCall(
                IERC20Minimal.approve,
                (address(spender), AMOUNT)
            )
        });

        // call[1]: EOA triggers the Spender to pull its own tokens via transferFrom.
        //          Routing through Spender ensures msg.sender in USDC is Spender,
        //          matching allowance[eoa][spender] set in call[0].
        calls[1] = ISmartWallet.Call({
            target: address(spender),
            value: 0,
            data: abi.encodeCall(Spender.pull, (USDC, eoa, AMOUNT))
        });

        // The EOA now has smart-wallet code — call executeBatch on itself.
        vm.broadcast(EOA_KEY);
        vm.attachDelegation(signedDelegation);
        uint256 gasBefore = gasleft();
        ISmartWallet(eoa).executeBatch(calls);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("EIP-7702: ", gasUsed);

        assertEq(IERC20Minimal(USDC).balanceOf(address(spender)), AMOUNT);
    }
}
