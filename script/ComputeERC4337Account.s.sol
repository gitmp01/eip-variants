// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

interface ISimpleAccountFactory {
    function getAddress(
        address owner,
        uint256 salt
    ) external view returns (address);
}

/// @notice Computes and prints the counterfactual ERC-4337 SimpleAccount address for a given owner.
///
/// The account is not deployed; its address is deterministic via CREATE2 inside the factory.
/// Source: https://github.com/eth-infinitism/account-abstraction/blob/develop/contracts/accounts/SimpleAccountFactory.sol
///
/// Required env vars:
///   EOA_PRIVATE_KEY  — the owner key; the derived address becomes the SA owner
///
/// Optional env var:
///   SALT             — uint256 salt (default: 0)
///
/// Run with:
///   EOA_PRIVATE_KEY=0x... forge script script/ComputeERC4337Account.s.sol --rpc-url base
contract ComputeERC4337Account is Script {
    /// SimpleAccountFactory deployed at the same address on all EVM chains (deterministic CREATE2).
    /// Source: https://github.com/eth-infinitism/account-abstraction/blob/develop/deployments/ethereum/SimpleAccountFactory.json
    ISimpleAccountFactory constant FACTORY =
        ISimpleAccountFactory(0x13E9ed32155810FDbd067D4522C492D6f68E5944);

    function run() external view {
        uint256 ownerKey = vm.envUint("EOA_PRIVATE_KEY");
        address owner = vm.addr(ownerKey);
        uint256 salt = vm.envOr("SALT", uint256(5));

        address sa = FACTORY.getAddress(owner, salt);

        console.log("Owner              :", owner);
        console.log("Salt               :", salt);
        console.log("Smart Account (SA) :", sa);
        console.log("Deployed?          :", sa.code.length > 0);
    }
}
