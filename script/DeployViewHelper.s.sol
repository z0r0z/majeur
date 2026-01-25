// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "@forge/Script.sol";
import {MolochViewHelper} from "../src/peripheral/MolochViewHelper.sol";

/// @notice Deploy ViewHelper with hardcoded V2 Summoner address
contract DeployViewHelper is Script {
    // Salt for CREATE2
    bytes32 constant VIEW_HELPER_SALT = bytes32(uint256(0xbeef2));

    function run() external {
        uint256 deployerPrivateKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xc4382ae42dfc444c62f678d6e7b480d468fe9a97018e922ac4cf47ba028d4048)
        );

        vm.startBroadcast(deployerPrivateKey);

        // ViewHelper has hardcoded SUMMONER and DAICO constants
        MolochViewHelper viewHelper = new MolochViewHelper{salt: VIEW_HELPER_SALT}();
        console.log("ViewHelper deployed at:", address(viewHelper));
        console.log("  SUMMONER:", address(viewHelper.SUMMONER()));
        console.log("  DAICO:", address(viewHelper.DAICO()));

        vm.stopBroadcast();
    }
}
