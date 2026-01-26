// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console} from "@forge/Script.sol";
import {Summoner, Moloch, Call} from "../src/Moloch.sol";

/// @notice Deploys only the Summoner (with new Moloch impl). Reuses existing ViewHelper.
contract DeploySummonerOnly is Script {
    // Fixed salt for CREATE2 deterministic deployment
    bytes32 constant SUMMONER_SALT = bytes32(uint256(0xdead));

    function run() external {
        uint256 deployerPrivateKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xc4382ae42dfc444c62f678d6e7b480d468fe9a97018e922ac4cf47ba028d4048)
        );

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Summoner with CREATE2 (creates Moloch implementation in constructor)
        Summoner summoner = new Summoner{salt: SUMMONER_SALT}();
        console.log("Summoner deployed at:", address(summoner));

        // Log implementation addresses
        Moloch molochImpl = summoner.molochImpl();
        console.log("Moloch impl:", address(molochImpl));
        console.log("Shares impl:", molochImpl.sharesImpl());
        console.log("Loot impl:", molochImpl.lootImpl());
        console.log("Badges impl:", molochImpl.badgesImpl());

        vm.stopBroadcast();

        console.log("");
        console.log("=== Summoner Deployment Complete ===");
        console.log("ViewHelper not deployed - reuse existing one.");
    }
}
