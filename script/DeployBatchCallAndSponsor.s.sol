// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {BatchCallAndSponsor} from "../src/BatchCallAndSponsor.sol";

contract DeployBatchCallAndSponsor is Script {
    function run() external {
        vm.startBroadcast();

        BatchCallAndSponsor batchCallAndSponsor = new BatchCallAndSponsor();

        vm.stopBroadcast();

        console.log("BatchCallAndSponsor deployed at:", address(batchCallAndSponsor));
    }
}
