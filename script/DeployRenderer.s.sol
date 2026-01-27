// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Script, console} from "@forge/Script.sol";
import {Renderer} from "../src/Renderer.sol";
import {CovenantRenderer} from "../src/renderers/CovenantRenderer.sol";
import {ProposalRenderer} from "../src/renderers/ProposalRenderer.sol";
import {ReceiptRenderer} from "../src/renderers/ReceiptRenderer.sol";
import {PermitRenderer} from "../src/renderers/PermitRenderer.sol";
import {BadgeRenderer} from "../src/renderers/BadgeRenderer.sol";

/// @notice Deploys the Renderer router + 5 sub-renderers with CREATE2.
///         Addresses are deterministic across all EVM chains when using the same deployer.
///         Idempotent: skips contracts already deployed at their predicted addresses.
///         Usage: forge script script/DeployRenderer.s.sol --rpc-url $RPC --broadcast --skip-simulation
contract DeployRenderer is Script {
    bytes32 constant COVENANT_SALT = bytes32(uint256(0xc0));
    bytes32 constant PROPOSAL_SALT = bytes32(uint256(0xc1));
    bytes32 constant RECEIPT_SALT = bytes32(uint256(0xc2));
    bytes32 constant PERMIT_SALT = bytes32(uint256(0xc3));
    bytes32 constant BADGE_SALT = bytes32(uint256(0xc4));
    bytes32 constant RENDERER_SALT = bytes32(uint256(0xcafe));

    /// @dev Forge's deterministic CREATE2 deployer (used for `new X{salt: s}()` in scripts)
    address constant FORGE_CREATE2 = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function run() external {
        uint256 deployerPrivateKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xc4382ae42dfc444c62f678d6e7b480d468fe9a97018e922ac4cf47ba028d4048)
        );

        // Predict CREATE2 addresses (forge routes CREATE2 through the deterministic deployer)
        address c =
            vm.computeCreate2Address(COVENANT_SALT, hashInitCode(type(CovenantRenderer).creationCode), FORGE_CREATE2);
        address p =
            vm.computeCreate2Address(PROPOSAL_SALT, hashInitCode(type(ProposalRenderer).creationCode), FORGE_CREATE2);
        address r =
            vm.computeCreate2Address(RECEIPT_SALT, hashInitCode(type(ReceiptRenderer).creationCode), FORGE_CREATE2);
        address pm =
            vm.computeCreate2Address(PERMIT_SALT, hashInitCode(type(PermitRenderer).creationCode), FORGE_CREATE2);
        address b =
            vm.computeCreate2Address(BADGE_SALT, hashInitCode(type(BadgeRenderer).creationCode), FORGE_CREATE2);
        address router = vm.computeCreate2Address(
            RENDERER_SALT, hashInitCode(type(Renderer).creationCode, abi.encode(c, p, r, pm, b)), FORGE_CREATE2
        );

        console.log("=== Renderer Deployment ===");

        vm.startBroadcast(deployerPrivateKey);

        if (c.code.length == 0) new CovenantRenderer{salt: COVENANT_SALT}();
        else console.log("  CovenantRenderer: already deployed");

        if (p.code.length == 0) new ProposalRenderer{salt: PROPOSAL_SALT}();
        else console.log("  ProposalRenderer: already deployed");

        if (r.code.length == 0) new ReceiptRenderer{salt: RECEIPT_SALT}();
        else console.log("  ReceiptRenderer: already deployed");

        if (pm.code.length == 0) new PermitRenderer{salt: PERMIT_SALT}();
        else console.log("  PermitRenderer: already deployed");

        if (b.code.length == 0) new BadgeRenderer{salt: BADGE_SALT}();
        else console.log("  BadgeRenderer: already deployed");

        if (router.code.length == 0) new Renderer{salt: RENDERER_SALT}(c, p, r, pm, b);
        else console.log("  Renderer (Router): already deployed");

        vm.stopBroadcast();

        console.log("CovenantRenderer:", c);
        console.log("ProposalRenderer:", p);
        console.log("ReceiptRenderer:", r);
        console.log("PermitRenderer:", pm);
        console.log("BadgeRenderer:", b);
        console.log("Renderer (Router):", router);
    }
}
