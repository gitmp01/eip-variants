// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {Spender} from "../src/Spender.sol";

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

/// @notice Mirrors EIP7702SpenderTest.test_eip7702_approveAndTransferFrom against the live deployment.
///         Run with: SIGNER_PRIVATE_KEY=0x... forge script ... --broadcast
///         The account must hold enough USDC on Base.
contract RunEIP7702Spender is Script {
    /// Alchemy smart-wallet implementation — the EIP-7702 delegate.
    address constant DELEGATE = 0x69007702764179f14F51cdce752f4f775d74E139;

    IERC20Minimal constant USDC =
        IERC20Minimal(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    Spender constant SPENDER =
        Spender(0x89f4916479c81470CA90737e3cc60e99062d3388);
    uint256 constant AMOUNT = 1000;

    function run() external {
        uint256 signerKey = vm.envUint("SIGNER_PRIVATE_KEY");
        address eoa = vm.addr(signerKey);

        // The authorization nonce must be eoa's current nonce + 1: the broadcast tx
        // increments the nonce by 1 when it lands, so the delegation must be signed
        // over the post-tx nonce to remain valid — matching vm.getNonce(eoa) + 1 in the test.
        uint64 nonce = vm.getNonce(eoa) + 1;
        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(
            DELEGATE,
            signerKey,
            nonce
        );

        ISmartWallet.Call[] memory calls = new ISmartWallet.Call[](2);

        // call[0]: EOA approves the Spender contract
        calls[0] = ISmartWallet.Call({
            target: address(USDC),
            value: 0,
            data: abi.encodeCall(
                IERC20Minimal.approve,
                (address(SPENDER), AMOUNT)
            )
        });

        // call[1]: EOA triggers the Spender to pull its own tokens via transferFrom.
        //          Routing through Spender ensures msg.sender in USDC is Spender,
        //          matching allowance[eoa][spender] set in call[0].
        calls[1] = ISmartWallet.Call({
            target: address(SPENDER),
            value: 0,
            data: abi.encodeCall(Spender.pull, (address(USDC), eoa, AMOUNT))
        });

        // The EOA now has smart-wallet code — call executeBatch on itself.
        vm.startBroadcast(signerKey);
        vm.attachDelegation(signedDelegation);
        ISmartWallet(eoa).executeBatch(calls);
        vm.stopBroadcast();

        console.log(
            "EIP-7702 batch succeeded. USDC balance of SPENDER:",
            USDC.balanceOf(address(SPENDER))
        );
    }
}
