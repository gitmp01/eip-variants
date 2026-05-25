// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {Spender} from "../src/Spender.sol";

interface IUSDC {
    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

/// @notice Mirrors SpenderTest.test_approveAndTransferFrom against the live deployment.
///         The broadcast account must hold enough USDC on Base.
contract RunSpender is Script {
    IUSDC constant USDC = IUSDC(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    Spender constant SPENDER =
        Spender(0x89f4916479c81470CA90737e3cc60e99062d3388);
    uint256 constant AMOUNT = 1000; // 100 USDC

    function run() external {
        vm.startBroadcast();

        USDC.approve(address(SPENDER), AMOUNT);
        SPENDER.pull(address(USDC), msg.sender, AMOUNT);

        vm.stopBroadcast();

        console.log(
            "Spender.pull succeeded. USDC balance of SPENDER:",
            USDC.balanceOf(address(SPENDER))
        );
    }
}
