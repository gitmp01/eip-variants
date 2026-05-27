// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {Spender} from "../src/Spender.sol";
import {PermittedSpender} from "../src/PermittedSpender.sol";
import {Recipient} from "../src/Recipient.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast();

        Spender spender = new Spender();
        // PermittedSpender permittedSpender = new PermittedSpender();
        // Recipient recipient = new Recipient();

        vm.stopBroadcast();

        console.log("Spender         deployed at:", address(spender));
        // console.log("PermittedSpender deployed at:", address(permittedSpender));
        // console.log("Recipient        deployed at:", address(recipient));
    }
}
