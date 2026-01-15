// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "@forge/Script.sol";
import {Summoner, Moloch, Call} from "../src/Moloch.sol";
import {MolochViewHelper} from "../src/peripheral/MolochViewHelper.sol";

contract DeployV2 is Script {
    // DAICO address (shared between v1 and v2)
    address constant DAICO = 0x000000000033e92DB97B4B3beCD2c255126C60aC;

    // Fixed salts for CREATE2 deterministic deployment
    bytes32 constant SUMMONER_SALT = bytes32(uint256(0xdead));
    bytes32 constant VIEW_HELPER_SALT = bytes32(uint256(0xbeef));

    function run() external {
        uint256 deployerPrivateKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xc4382ae42dfc444c62f678d6e7b480d468fe9a97018e922ac4cf47ba028d4048)
        );

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Summoner with CREATE2 (creates Moloch implementation in constructor)
        Summoner summoner = new Summoner{salt: SUMMONER_SALT}();
        console.log("Summoner deployed at:", address(summoner));

        // Deploy ViewHelper with CREATE2
        MolochViewHelper viewHelper = new MolochViewHelper{salt: VIEW_HELPER_SALT}(address(summoner), DAICO);
        console.log("ViewHelper deployed at:", address(viewHelper));

        vm.stopBroadcast();

        console.log("");
        console.log("=== V2 Deployment Complete ===");
        console.log("Addresses are deterministic via CREATE2.");
        console.log("Summoner salt:", vm.toString(SUMMONER_SALT));
        console.log("ViewHelper salt:", vm.toString(VIEW_HELPER_SALT));
    }
}
