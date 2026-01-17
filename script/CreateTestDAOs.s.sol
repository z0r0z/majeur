// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "@forge/Script.sol";
import {Summoner, Moloch, Call} from "../src/Moloch.sol";
import {MolochViewHelper} from "../src/peripheral/MolochViewHelper.sol";
import {Renderer} from "../src/Renderer.sol";

contract CreateTestDAOs is Script {
    // V2 addresses (deterministic via CREATE2)
    address constant V2_SUMMONER = 0xC1fE5F7163A3fe20b40f0410Dbdea1D0e4AE0d2A;
    address constant V2_MOLOCH_IMPL = 0xAFB72C54658f7332f695EbFfd9797C4eC1DAC863;
    address constant V2_VIEW_HELPER = 0x851D78aeE76329A0e8E0B8896214976A4059B37c;
    address constant RENDERER = 0x000000000011C799980827F52d3137b4abD6E654;

    // Test user private keys (use specific env vars to avoid conflicts with global PRIVATE_KEY)
    uint256 constant DEFAULT_USER1_KEY = 0xc4382ae42dfc444c62f678d6e7b480d468fe9a97018e922ac4cf47ba028d4048;
    uint256 constant DEFAULT_USER2_KEY = 0x40887c48a0c3d55639b0a133bfc757ad0f61540ade8882fa6dc636af8634a752;

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

    /// @dev Build tagged proposal message for UI verification (matches Majeur.html format)
    function _buildProposalMessage(
        uint8 op,
        address to,
        uint256 value,
        bytes memory data,
        bytes32 nonce,
        string memory description
    ) internal pure returns (string memory) {
        return string.concat(
            "<<<PROPOSAL_DATA\n{\"type\":\"PROPOSAL\",\"op\":",
            vm.toString(op),
            ",\"to\":\"",
            vm.toString(to),
            "\",\"value\":\"",
            vm.toString(value),
            "\",\"data\":\"",
            vm.toString(data),
            "\",\"nonce\":\"",
            vm.toString(nonce),
            "\",\"description\":\"",
            description,
            "\"}\nPROPOSAL_DATA>>>"
        );
    }

    /// @dev Create a proposal with verified message using multicall
    function _createProposal(
        Moloch dao,
        uint256 pk,
        uint8 op,
        address to,
        uint256 value,
        bytes memory data,
        bytes32 nonce,
        string memory description
    ) internal returns (uint256 id) {
        string memory message = _buildProposalMessage(op, to, value, data, nonce, description);
        id = dao.proposalId(op, to, value, data, nonce);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSignature("chat(string)", message);
        calls[1] = abi.encodeWithSignature("openProposal(uint256)", id);

        vm.broadcast(pk);
        dao.multicall(calls);
    }

    function run() external {
        runPhase1();
    }

    /// @dev Phase 1: Create DAOs and add messages (shares need to checkpoint before voting)
    function runPhase1() public {
        // Use TEST_USER1_KEY to avoid conflicts with global PRIVATE_KEY env var
        uint256 user1Key = vm.envOr("TEST_USER1_KEY", DEFAULT_USER1_KEY);
        uint256 user2Key = vm.envOr("TEST_USER2_KEY", DEFAULT_USER2_KEY);
        address deployer = vm.addr(user1Key);
        address user2 = vm.addr(user2Key);

        console.log("User 1 (deployer):", deployer);
        console.log("User 2:", user2);

        vm.startBroadcast(user1Key);

        Summoner summoner = Summoner(V2_SUMMONER);

        // Store DAO references for post-creation interactions
        Moloch dao1;
        Moloch dao2;

        // DAO 1: Standard settings with 7-day TTL and 1-day timelock
        {
            address[] memory holders = new address[](2);
            holders[0] = deployer;
            holders[1] = user2;

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

            dao1 = summoner.summon(
                "Alpha DAO",
                "ALPHA",
                "https://st.depositphotos.com/2892507/4212/i/600/depositphotos_42123797-stock-photo-easter-dalmatain-puppy.jpg",
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
            address[] memory holders = new address[](2);
            holders[0] = deployer;
            holders[1] = user2;

            uint256[] memory shares = new uint256[](2);
            shares[0] = 1000 ether;
            shares[1] = 500 ether;

            address predictedDao = _predictDAO(bytes32(uint256(102)), holders, shares);

            Call[] memory initCalls = new Call[](1);
            // Set proposal TTL to 3 days
            initCalls[0] = Call({
                target: predictedDao,
                value: 0,
                data: abi.encodeWithSignature("setProposalTTL(uint64)", uint64(3 days))
            });

            dao2 = summoner.summon(
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

        // DAO 3: Two-member with 14-day TTL and proposal threshold
        {
            address[] memory holders = new address[](2);
            holders[0] = deployer;
            holders[1] = user2;

            uint256[] memory shares = new uint256[](2);
            shares[0] = 1000 ether;
            shares[1] = 500 ether;

            address predictedDao = _predictDAO(bytes32(uint256(103)), holders, shares);

            Call[] memory initCalls = new Call[](2);
            // Set proposal TTL to 14 days
            initCalls[0] = Call({
                target: predictedDao,
                value: 0,
                data: abi.encodeWithSignature("setProposalTTL(uint64)", uint64(14 days))
            });
            // Set proposal threshold to 100 shares (~6.7% of 1500 total)
            initCalls[1] = Call({
                target: predictedDao,
                value: 0,
                data: abi.encodeWithSignature("setProposalThreshold(uint96)", uint96(100 ether))
            });

            Moloch dao3 = summoner.summon(
                "Solo DAO",
                "SOLO",
                "ipfs://QmNa8mQkrNKp1WEEeGjFezDmDeodkWRevGFN8JCV7b4Xir",
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

        // DAO 4: Two members with auto-futarchy enabled
        {
            address[] memory holders = new address[](2);
            holders[0] = deployer;
            holders[1] = user2;

            uint256[] memory shares = new uint256[](2);
            shares[0] = 1000 ether;
            shares[1] = 500 ether;

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
                "https://static9.depositphotos.com/1594920/1088/i/600/depositphotos_10881569-stock-photo-araucana-chicken-8-days-old.jpg",
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

        // DAO 1: Add 40 chat messages between deployer and user2
        console.log("");
        console.log("Adding 40 chat messages to DAO 1...");
        for (uint256 i = 0; i < 40; i++) {
            uint256 pk = (i % 2 == 0) ? user1Key : user2Key;
            vm.broadcast(pk);
            dao1.chat(string.concat("Test message #", vm.toString(i + 1)));
        }
        console.log("  - 40 messages added (alternating senders)");

        console.log("");
        console.log("=== Phase 1 Complete ===");
        console.log("DAOs created, 40 messages added to DAO 1");
        console.log("Run 'cast rpc evm_mine' then 'runPhase2' to add proposals");
    }

    // DAICO contract address (shared v1/v2)
    address constant DAICO = 0x000000000033e92DB97B4B3beCD2c255126C60aC;

    /// @dev Phase 2: Create governance proposals and vote (run after mining a block)
    /// Call with: forge script script/CreateTestDAOs.s.sol --sig "runPhase2()" --rpc-url ... --broadcast
    function runPhase2() public {
        // Use TEST_USER1_KEY to avoid conflicts with global PRIVATE_KEY env var
        uint256 user1Key = vm.envOr("TEST_USER1_KEY", DEFAULT_USER1_KEY);
        uint256 user2Key = vm.envOr("TEST_USER2_KEY", DEFAULT_USER2_KEY);
        address deployer = vm.addr(user1Key);
        address user2 = vm.addr(user2Key);

        console.log("User 1 (deployer):", deployer);
        console.log("User 2:", user2);

        // DAO 2 address (deterministic from Phase 1)
        Moloch dao2 = Moloch(payable(0x1A79d36bcAA43891B99bB749FF6e016B683dDAaa));
        address dao2Addr = address(dao2);
        address sharesToken = address(dao2.shares());
        address lootToken = address(dao2.loot());
        Summoner summoner = Summoner(V2_SUMMONER);

        console.log("Creating governance proposals in DAO 2...");
        console.log("  Shares token:", sharesToken);
        console.log("  Loot token:", lootToken);

        uint256[] memory proposalIds = new uint256[](15);
        uint256 idx = 0;

        // 1. Set Metadata - Change DAO name, symbol, and description
        proposalIds[idx] = _createProposal(
            dao2, user1Key, 0, dao2Addr, 0,
            abi.encodeWithSignature("setMetadata(string,string,string)", "Beta DAO Renamed", "BETA2", "ipfs://QmNewDescription"),
            bytes32(uint256(1)),
            "Set Metadata: Rename to Beta DAO Renamed"
        );
        console.log("  1. Set Metadata proposal created");
        idx++;

        // 2. Change Renderer - Update the NFT metadata renderer
        proposalIds[idx] = _createProposal(
            dao2, user2Key, 0, dao2Addr, 0,
            abi.encodeWithSignature("setRenderer(address)", RENDERER),
            bytes32(uint256(2)),
            "Change Renderer: Set to official renderer"
        );
        console.log("  2. Change Renderer proposal created");
        idx++;

        // 3. Set Quorum (BPS) - Change quorum to 30%
        proposalIds[idx] = _createProposal(
            dao2, user1Key, 0, dao2Addr, 0,
            abi.encodeWithSignature("setQuorumBps(uint16)", uint16(3000)),
            bytes32(uint256(3)),
            "Set Quorum BPS: Change to 30%"
        );
        console.log("  3. Set Quorum BPS proposal created");
        idx++;

        // 4. Set Absolute Quorum - Require 500 votes minimum
        proposalIds[idx] = _createProposal(
            dao2, user2Key, 0, dao2Addr, 0,
            abi.encodeWithSignature("setQuorumAbsolute(uint96)", uint96(500 ether)),
            bytes32(uint256(4)),
            "Set Absolute Quorum: Require 500 votes minimum"
        );
        console.log("  4. Set Absolute Quorum proposal created");
        idx++;

        // 5. Set Min YES Votes - Require 200 YES votes to pass
        proposalIds[idx] = _createProposal(
            dao2, user1Key, 0, dao2Addr, 0,
            abi.encodeWithSignature("setMinYesVotesAbsolute(uint96)", uint96(200 ether)),
            bytes32(uint256(5)),
            "Set Min YES Votes: Require 200 YES to pass"
        );
        console.log("  5. Set Min YES Votes proposal created");
        idx++;

        // 6. Set Vote Threshold - Require 50 shares to propose
        proposalIds[idx] = _createProposal(
            dao2, user2Key, 0, dao2Addr, 0,
            abi.encodeWithSignature("setProposalThreshold(uint96)", uint96(50 ether)),
            bytes32(uint256(6)),
            "Set Vote Threshold: Require 50 shares to propose"
        );
        console.log("  6. Set Vote Threshold proposal created");
        idx++;

        // 7. Set Proposal TTL - Change voting period to 5 days
        proposalIds[idx] = _createProposal(
            dao2, user1Key, 0, dao2Addr, 0,
            abi.encodeWithSignature("setProposalTTL(uint64)", uint64(5 days)),
            bytes32(uint256(7)),
            "Set Proposal TTL: Change voting period to 5 days"
        );
        console.log("  7. Set Proposal TTL proposal created");
        idx++;

        // 8. Set Timelock Delay - Add 2 day execution delay
        proposalIds[idx] = _createProposal(
            dao2, user2Key, 0, dao2Addr, 0,
            abi.encodeWithSignature("setTimelockDelay(uint64)", uint64(2 days)),
            bytes32(uint256(8)),
            "Set Timelock Delay: Add 2 day execution delay"
        );
        console.log("  8. Set Timelock Delay proposal created");
        idx++;

        // 9. Toggle Ragequit - Enable ragequit for members
        proposalIds[idx] = _createProposal(
            dao2, user1Key, 0, dao2Addr, 0,
            abi.encodeWithSignature("setRagequittable(bool)", true),
            bytes32(uint256(9)),
            "Toggle Ragequit: Enable ragequit for members"
        );
        console.log("  9. Toggle Ragequit proposal created");
        idx++;

        // 10. Toggle Transferability - Lock shares and loot transfers
        proposalIds[idx] = _createProposal(
            dao2, user2Key, 0, dao2Addr, 0,
            abi.encodeWithSignature("setTransfersLocked(bool,bool)", true, true),
            bytes32(uint256(10)),
            "Toggle Transferability: Lock shares and loot transfers"
        );
        console.log("  10. Toggle Transferability proposal created");
        idx++;

        // 11. Configure Auto-Futarchy - Enable 0.5% param, 10 LOOT cap
        proposalIds[idx] = _createProposal(
            dao2, user1Key, 0, dao2Addr, 0,
            abi.encodeWithSignature("setAutoFutarchy(uint256,uint256)", uint256(50), uint256(10 ether)),
            bytes32(uint256(11)),
            "Configure Auto-Futarchy: Enable 0.5% param, 10 LOOT cap"
        );
        console.log("  11. Configure Auto-Futarchy proposal created");
        idx++;

        // 12. Set Futarchy Reward Token - Use ETH (address(0)) for rewards
        proposalIds[idx] = _createProposal(
            dao2, user2Key, 0, dao2Addr, 0,
            abi.encodeWithSignature("setFutarchyRewardToken(address)", address(0)),
            bytes32(uint256(12)),
            "Set Futarchy Reward Token: Use ETH for rewards"
        );
        console.log("  12. Set Futarchy Reward Token proposal created");
        idx++;

        // 13. Slash Member - Burn 10 shares from user2 (uses batchCalls)
        {
            Call[] memory slashCalls = new Call[](1);
            slashCalls[0] = Call({
                target: sharesToken,
                value: 0,
                data: abi.encodeWithSignature("burnFromMoloch(address,uint256)", user2, 10 ether)
            });
            bytes memory batchData = abi.encodeWithSignature("batchCalls((address,uint256,bytes)[])", slashCalls);
            proposalIds[idx] = _createProposal(
                dao2, user1Key, 0, dao2Addr, 0,
                batchData,
                bytes32(uint256(13)),
                "Slash Member: Burn 10 shares from user2"
            );
            console.log("  13. Slash Member proposal created");
            idx++;
        }

        // 14. DAICO Sale - Start a token sale (mint shares, approve DAICO, configure sale)
        {
            // Sale config: sell 100 shares for 0.1 ETH each, no deadline
            uint256 saleAmount = 100 ether; // 100 shares
            uint256 tributeAmount = 10 ether; // 10 ETH total (0.1 ETH per share)

            Call[] memory daicoCalls = new Call[](3);
            // 1. Mint shares to DAO treasury
            daicoCalls[0] = Call({
                target: sharesToken,
                value: 0,
                data: abi.encodeWithSignature("mintFromMoloch(address,uint256)", dao2Addr, saleAmount)
            });
            // 2. Approve DAICO to spend shares
            daicoCalls[1] = Call({
                target: sharesToken,
                value: 0,
                data: abi.encodeWithSignature("approve(address,uint256)", DAICO, saleAmount)
            });
            // 3. Configure the sale on DAICO
            // setSale(address tribTkn, uint256 tribAmt, address forTkn, uint256 forAmt, uint40 deadline)
            daicoCalls[2] = Call({
                target: DAICO,
                value: 0,
                data: abi.encodeWithSignature(
                    "setSale(address,uint256,address,uint256,uint40)",
                    address(0), // ETH as tribute token
                    tributeAmount,
                    sharesToken,
                    saleAmount,
                    uint40(0) // no deadline
                )
            });
            bytes memory batchData = abi.encodeWithSignature("batchCalls((address,uint256,bytes)[])", daicoCalls);
            proposalIds[idx] = _createProposal(
                dao2, user2Key, 0, dao2Addr, 0,
                batchData,
                bytes32(uint256(14)),
                "DAICO Sale: Sell 100 shares for 10 ETH (0.1 ETH each)"
            );
            console.log("  14. DAICO Sale proposal created");
            idx++;
        }

        // 15. Set Ragequit Timelock - Add 3 day ragequit delay
        proposalIds[idx] = _createProposal(
            dao2, user1Key, 0, dao2Addr, 0,
            abi.encodeWithSignature("setRagequitTimelock(uint64)", uint64(3 days)),
            bytes32(uint256(15)),
            "Set Ragequit Timelock: Add 3 day ragequit delay"
        );
        console.log("  15. Set Ragequit Timelock proposal created");
        idx++;

        // Vote on last 3 proposals (13, 14, 15)
        console.log("");
        console.log("Voting on proposals 13, 14, 15...");

        // Proposal 13 (Slash): Both vote FOR
        vm.broadcast(user1Key);
        dao2.castVote(proposalIds[12], 1);
        vm.broadcast(user2Key);
        dao2.castVote(proposalIds[12], 1);
        console.log("  - Proposal 13 (Slash): Both voted FOR");

        // Proposal 14 (DAICO): Both vote AGAINST
        vm.broadcast(user1Key);
        dao2.castVote(proposalIds[13], 0);
        vm.broadcast(user2Key);
        dao2.castVote(proposalIds[13], 0);
        console.log("  - Proposal 14 (DAICO): Both voted AGAINST");

        // Proposal 15 (Ragequit Timelock): Both vote ABSTAIN
        vm.broadcast(user1Key);
        dao2.castVote(proposalIds[14], 2);
        vm.broadcast(user2Key);
        dao2.castVote(proposalIds[14], 2);
        console.log("  - Proposal 15 (Ragequit Timelock): Both voted ABSTAIN");

        console.log("");
        console.log("=== Phase 2 Complete ===");
        console.log("Total DAOs in Summoner:", summoner.getDAOCount());
        console.log("");
        console.log("15 governance proposals created covering:");
        console.log("  1. Set Metadata");
        console.log("  2. Change Renderer");
        console.log("  3. Set Quorum (BPS)");
        console.log("  4. Set Absolute Quorum");
        console.log("  5. Set Min YES Votes");
        console.log("  6. Set Vote Threshold");
        console.log("  7. Set Proposal TTL");
        console.log("  8. Set Timelock Delay");
        console.log("  9. Toggle Ragequit");
        console.log("  10. Toggle Transferability");
        console.log("  11. Configure Auto-Futarchy");
        console.log("  12. Set Futarchy Reward Token");
        console.log("  13. Slash Member");
        console.log("  14. DAICO Sale");
        console.log("  15. Set Ragequit Timelock");
        console.log("");
        console.log("Votes cast on proposals 13, 14, 15 (FOR, AGAINST, ABSTAIN)");
    }
}
