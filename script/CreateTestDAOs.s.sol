// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "@forge/Script.sol";
import {Summoner, Moloch, Call} from "../src/Moloch.sol";
import {MolochViewHelper} from "../src/peripheral/MolochViewHelper.sol";
import {Renderer} from "../src/Renderer.sol";

contract CreateTestDAOs is Script {
    // V2 addresses (deterministic via CREATE2)
    address constant V2_SUMMONER = 0x6DC8b0F23B2040BE29187705120FD0076503e688;
    address constant V2_MOLOCH_IMPL = 0x83422479458103D9c1088d3EB036AdFa5e4fE4F6;
    address constant V2_VIEW_HELPER = 0x0cf87b3a114c78907cF7712e2Cbb61Bb3608c776;
    address constant RENDERER = 0x000000000011C799980827F52d3137b4abD6E654;

    /// @dev Predict DAO address from Summoner's CREATE2.
    function _predictDAO(
        bytes32 salt,
        address[] memory initHolders,
        uint256[] memory initShares
    ) internal pure returns (address) {
        bytes32 _salt = keccak256(abi.encode(initHolders, initShares, salt));

        // Minimal proxy creation code
        bytes memory creationCode = abi.encodePacked(
            hex"602d5f8160095f39f35f5f365f5f37365f73",
            V2_MOLOCH_IMPL,
            hex"5af43d5f5f3e6029573d5ffd5b3d5ff3"
        );

        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), V2_SUMMONER, _salt, keccak256(creationCode))
                    )
                )
            )
        );
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xc4382ae42dfc444c62f678d6e7b480d468fe9a97018e922ac4cf47ba028d4048)
        );
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        Summoner summoner = Summoner(V2_SUMMONER);

        // DAO 1: Standard settings with 7-day TTL and 1-day timelock
        {
            address[] memory holders = new address[](2);
            holders[0] = deployer;
            holders[1] = address(0x1111111111111111111111111111111111111111);

            uint256[] memory shares = new uint256[](2);
            shares[0] = 100 ether;
            shares[1] = 50 ether;

            // Predict the DAO address for init calls
            address predictedDao = _predictDAO(bytes32(uint256(101)), holders, shares);

            Call[] memory initCalls = new Call[](2);
            // Set proposal TTL to 7 days
            initCalls[0] = Call({
                target: predictedDao,
                value: 0,
                data: abi.encodeWithSignature("setProposalTTL(uint64)", uint64(7 days))
            });
            // Set timelock delay to 1 day
            initCalls[1] = Call({
                target: predictedDao,
                value: 0,
                data: abi.encodeWithSignature("setTimelockDelay(uint64)", uint64(1 days))
            });

            Moloch dao1 = summoner.summon(
                "Alpha DAO",
                "ALPHA",
                "https://example.com/alpha",
                5000, // 50% quorum
                true, // ragequittable
                RENDERER,
                bytes32(uint256(101)),
                holders,
                shares,
                initCalls
            );
            console.log("DAO 1 (Alpha DAO) deployed at:", address(dao1));
            console.log("  - Proposal TTL: 7 days, Timelock: 1 day, Ragequit: enabled");
        }

        // DAO 2: No ragequit, 3-day TTL, no timelock
        {
            address[] memory holders = new address[](3);
            holders[0] = deployer;
            holders[1] = address(0x2222222222222222222222222222222222222222);
            holders[2] = address(0x3333333333333333333333333333333333333333);

            uint256[] memory shares = new uint256[](3);
            shares[0] = 1000 ether;
            shares[1] = 500 ether;
            shares[2] = 250 ether;

            address predictedDao = _predictDAO(bytes32(uint256(102)), holders, shares);

            Call[] memory initCalls = new Call[](1);
            // Set proposal TTL to 3 days
            initCalls[0] = Call({
                target: predictedDao,
                value: 0,
                data: abi.encodeWithSignature("setProposalTTL(uint64)", uint64(3 days))
            });

            Moloch dao2 = summoner.summon(
                "Beta Collective",
                "BETA",
                "",
                2500, // 25% quorum
                false, // not ragequittable
                RENDERER,
                bytes32(uint256(102)),
                holders,
                shares,
                initCalls
            );
            console.log("DAO 2 (Beta Collective) deployed at:", address(dao2));
            console.log("  - Proposal TTL: 3 days, Ragequit: disabled");
        }

        // DAO 3: Single-member with 14-day TTL and proposal threshold
        {
            address[] memory holders = new address[](1);
            holders[0] = deployer;

            uint256[] memory shares = new uint256[](1);
            shares[0] = 1000 ether;

            address predictedDao = _predictDAO(bytes32(uint256(103)), holders, shares);

            Call[] memory initCalls = new Call[](2);
            // Set proposal TTL to 14 days
            initCalls[0] = Call({
                target: predictedDao,
                value: 0,
                data: abi.encodeWithSignature("setProposalTTL(uint64)", uint64(14 days))
            });
            // Set proposal threshold to 100 shares (10%)
            initCalls[1] = Call({
                target: predictedDao,
                value: 0,
                data: abi.encodeWithSignature("setProposalThreshold(uint96)", uint96(100 ether))
            });

            Moloch dao3 = summoner.summon(
                "Solo DAO",
                "SOLO",
                "ipfs://QmTest123456789",
                10000, // 100% quorum (all must vote)
                true,
                RENDERER,
                bytes32(uint256(103)),
                holders,
                shares,
                initCalls
            );
            console.log("DAO 3 (Solo DAO) deployed at:", address(dao3));
            console.log("  - Proposal TTL: 14 days, Threshold: 100 shares, 100% quorum");
        }

        // DAO 4: Many members with auto-futarchy enabled
        {
            address[] memory holders = new address[](5);
            holders[0] = deployer;
            holders[1] = address(0x4111111111111111111111111111111111111111);
            holders[2] = address(0x4222222222222222222222222222222222222222);
            holders[3] = address(0x4333333333333333333333333333333333333333);
            holders[4] = address(0x4444444444444444444444444444444444444444);

            uint256[] memory shares = new uint256[](5);
            shares[0] = 1000 ether;
            shares[1] = 800 ether;
            shares[2] = 600 ether;
            shares[3] = 400 ether;
            shares[4] = 200 ether;

            address predictedDao = _predictDAO(bytes32(uint256(104)), holders, shares);

            Call[] memory initCalls = new Call[](3);
            // Set proposal TTL to 5 days
            initCalls[0] = Call({
                target: predictedDao,
                value: 0,
                data: abi.encodeWithSignature("setProposalTTL(uint64)", uint64(5 days))
            });
            // Set timelock delay to 12 hours
            initCalls[1] = Call({
                target: predictedDao,
                value: 0,
                data: abi.encodeWithSignature("setTimelockDelay(uint64)", uint64(12 hours))
            });
            // Enable auto-futarchy: 0.1% of supply, 5 LOOT cap
            // autoFutarchyParam = 10 (0.1% = 10 basis points)
            // autoFutarchyCap = 5 ether (5 LOOT tokens)
            initCalls[2] = Call({
                target: predictedDao,
                value: 0,
                data: abi.encodeWithSignature("setAutoFutarchy(uint256,uint256)", uint256(10), uint256(5 ether))
            });

            Moloch dao4 = summoner.summon(
                "Gamma Guild",
                "GAMMA",
                "",
                1000, // 10% quorum
                true,
                RENDERER,
                bytes32(uint256(104)),
                holders,
                shares,
                initCalls
            );
            console.log("DAO 4 (Gamma Guild) deployed at:", address(dao4));
            console.log("  - Proposal TTL: 5 days, Timelock: 12h, Auto-futarchy: 0.1%/5 LOOT");
        }

        // DAO 5: Fast governance (1-day TTL, 1-hour timelock)
        {
            address[] memory holders = new address[](2);
            holders[0] = deployer;
            holders[1] = address(0x5555555555555555555555555555555555555555);

            uint256[] memory shares = new uint256[](2);
            shares[0] = 50 ether;
            shares[1] = 50 ether;

            address predictedDao = _predictDAO(bytes32(uint256(105)), holders, shares);

            Call[] memory initCalls = new Call[](2);
            // Set proposal TTL to 1 day (fast governance)
            initCalls[0] = Call({
                target: predictedDao,
                value: 0,
                data: abi.encodeWithSignature("setProposalTTL(uint64)", uint64(1 days))
            });
            // Set timelock delay to 1 hour
            initCalls[1] = Call({
                target: predictedDao,
                value: 0,
                data: abi.encodeWithSignature("setTimelockDelay(uint64)", uint64(1 hours))
            });

            Moloch dao5 = summoner.summon(
                "Delta Protocol",
                "DELTA",
                "https://delta.example.com",
                100, // 1% quorum
                true,
                RENDERER,
                bytes32(uint256(105)),
                holders,
                shares,
                initCalls
            );
            console.log("DAO 5 (Delta Protocol) deployed at:", address(dao5));
            console.log("  - Proposal TTL: 1 day, Timelock: 1 hour (fast governance)");
        }

        vm.stopBroadcast();

        console.log("");
        console.log("=== Test DAOs Created ===");
        console.log("Total DAOs in Summoner:", summoner.getDAOCount());
        console.log("");
        console.log("Governance variety covered:");
        console.log("  - Proposal TTL: 1d, 3d, 5d, 7d, 14d");
        console.log("  - Timelock: 0, 1h, 12h, 1d");
        console.log("  - Ragequit: enabled/disabled");
        console.log("  - Quorum: 1%, 10%, 25%, 50%, 100%");
        console.log("  - Proposal threshold: 0, 100 shares");
        console.log("  - Auto-futarchy: disabled, 0.1%/5 LOOT");
    }
}
