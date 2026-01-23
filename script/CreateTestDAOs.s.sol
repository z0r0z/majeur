// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "@forge/Script.sol";
import {Summoner, Moloch, Call} from "../src/Moloch.sol";
import {MolochViewHelper} from "../src/peripheral/MolochViewHelper.sol";
import {Renderer} from "../src/Renderer.sol";
import {Tribute} from "../src/peripheral/Tribute.sol";

contract CreateTestDAOs is Script {
    // V2 addresses (deterministic via CREATE2)
    address constant V2_SUMMONER = 0xdB9aDc369424f08bBd2300571801A0ADAD0B4410;
    address constant V2_MOLOCH_IMPL = 0x7EE961133ba3D5f89a7540D559604FC2b0e72A51;
    address constant V2_VIEW_HELPER = 0xe4022b04c55ca03ED91B0B666015bA29437B7026;
    address constant RENDERER = 0x000000000011C799980827F52d3137b4abD6E654;
    // Token implementations (deployed by Moloch impl constructor)
    address constant V2_SHARES_IMPL = 0xcE799983D38D69127E3b6fa83C294A28A1F31EBb;
    address constant V2_LOOT_IMPL = 0x19C79260Ce3ce904C29cCC9c684D4DC486f00b71;

    // Test user private keys (use specific env vars to avoid conflicts with global PRIVATE_KEY)
    uint256 constant DEFAULT_USER1_KEY = 0xc4382ae42dfc444c62f678d6e7b480d468fe9a97018e922ac4cf47ba028d4048;
    uint256 constant DEFAULT_USER2_KEY = 0x40887c48a0c3d55639b0a133bfc757ad0f61540ade8882fa6dc636af8634a752;

    /// @dev Get WETH address based on chain ID
    function _getWETH() internal view returns (address) {
        uint256 chainId = block.chainid;
        if (chainId == 1) return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // Ethereum
        if (chainId == 8453) return 0x4200000000000000000000000000000000000006; // Base
        if (chainId == 42161) return 0x82aF49447D8a07e3bd95BD0d56f14241523fBab1; // Arbitrum
        return 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9; // Sepolia / localhost
    }

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

    /// @dev Predict shares token address from DAO address (minimal proxy CREATE2).
    function _predictShares(address daoAddr) internal pure returns (address) {
        bytes32 _salt = bytes32(bytes20(daoAddr));
        bytes memory creationCode = abi.encodePacked(
            hex"602d5f8160095f39f35f5f365f5f37365f73",
            V2_SHARES_IMPL,
            hex"5af43d5f5f3e6029573d5ffd5b3d5ff3"
        );
        return address(uint160(uint256(keccak256(
            abi.encodePacked(bytes1(0xff), daoAddr, _salt, keccak256(creationCode))
        ))));
    }

    /// @dev Predict loot token address from DAO address (minimal proxy CREATE2).
    function _predictLoot(address daoAddr) internal pure returns (address) {
        bytes32 _salt = bytes32(bytes20(daoAddr));
        bytes memory creationCode = abi.encodePacked(
            hex"602d5f8160095f39f35f5f365f5f37365f73",
            V2_LOOT_IMPL,
            hex"5af43d5f5f3e6029573d5ffd5b3d5ff3"
        );
        return address(uint160(uint256(keccak256(
            abi.encodePacked(bytes1(0xff), daoAddr, _salt, keccak256(creationCode))
        ))));
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
        Moloch dao3;

        // DAO 1: Standard settings with 7-day TTL and 1-day timelock + Cheap ETH Shares Sale
        {
            address[] memory holders = new address[](2);
            holders[0] = deployer;
            holders[1] = user2;

            uint256[] memory shares = new uint256[](2);
            shares[0] = 100 ether;
            shares[1] = 50 ether;

            // Predict the DAO address for init calls
            address predictedDao = _predictDAO(bytes32(uint256(101)), holders, shares);

            Call[] memory initCalls = new Call[](3);
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
            // Moloch built-in sale: ~1 ETH = 2,000,000 SHARES (very cheap!)
            initCalls[2] = Call({
                target: predictedDao,
                value: 0,
                data: abi.encodeWithSignature(
                    "setSale(address,uint256,uint256,bool,bool,bool)",
                    address(0),        // ETH payment
                    0.0000005 ether,   // price per share (~1 ETH = 2M shares)
                    uint256(0),        // unlimited cap
                    true,              // minting
                    true,              // active
                    false              // shares (not loot)
                )
            });

            dao1 = summoner.summon(
                "40 messages",
                "40MSG",
                "https://st.depositphotos.com/2892507/4212/i/600/depositphotos_42123797-stock-photo-easter-dalmatain-puppy.jpg",
                5000, // 50% quorum
                true, // ragequittable
                RENDERER,
                bytes32(uint256(101)),
                holders,
                shares,
                initCalls
            );
            console.log("DAO 1 (40 messages) deployed at:", address(dao1));
            console.log("  - Proposal TTL: 7 days, Timelock: 1 day, Ragequit: enabled");
            console.log("  - Sale: ~1 ETH = 2M SHARES (Moloch built-in, very cheap!)");
        }

        // DAO 2: No ragequit, 3-day TTL, no timelock + Expensive USDF Loot Sale
        {
            address[] memory holders = new address[](2);
            holders[0] = deployer;
            holders[1] = user2;

            uint256[] memory shares = new uint256[](2);
            shares[0] = 1000 ether;
            shares[1] = 500 ether;

            address predictedDao = _predictDAO(bytes32(uint256(102)), holders, shares);

            Call[] memory initCalls = new Call[](2);
            // Set proposal TTL to 3 days
            initCalls[0] = Call({
                target: predictedDao,
                value: 0,
                data: abi.encodeWithSignature("setProposalTTL(uint64)", uint64(3 days))
            });
            // Moloch built-in sale: 3 USDF = 1 LOOT, 1000 LOOT cap
            initCalls[1] = Call({
                target: predictedDao,
                value: 0,
                data: abi.encodeWithSignature(
                    "setSale(address,uint256,uint256,bool,bool,bool)",
                    USDF,          // USDF payment
                    3 ether,       // 3 USDF per loot
                    1000 ether,    // 1000 loot cap
                    true,          // minting
                    true,          // active
                    true           // loot (not shares)
                )
            });

            dao2 = summoner.summon(
                "All gov proposals",
                "ALLGOV",
                "",
                2500, // 25% quorum
                false, // not ragequittable
                RENDERER,
                bytes32(uint256(102)),
                holders,
                shares,
                initCalls
            );
            console.log("DAO 2 (All gov proposals) deployed at:", address(dao2));
            console.log("  - Proposal TTL: 3 days, Ragequit: disabled");
            console.log("  - Sale: 3 USDF = 1 LOOT (Moloch built-in, 1000 LOOT cap)");
        }

        // DAO 3: Two-member with 14-day TTL, proposal threshold + DAICO sale
        {
            address[] memory holders = new address[](2);
            holders[0] = deployer;
            holders[1] = user2;

            uint256[] memory shares = new uint256[](2);
            shares[0] = 1000 ether;
            shares[1] = 500 ether;

            address predictedDao = _predictDAO(bytes32(uint256(103)), holders, shares);
            address predictedShares = _predictShares(predictedDao);

            Call[] memory initCalls = new Call[](5);
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
            // Mint 1M shares to DAO for DAICO sale
            initCalls[2] = Call({
                target: predictedShares,
                value: 0,
                data: abi.encodeWithSignature("mintFromMoloch(address,uint256)", predictedDao, 1_000_000 ether)
            });
            // Approve DAICO to spend shares
            initCalls[3] = Call({
                target: predictedShares,
                value: 0,
                data: abi.encodeWithSignature("approve(address,uint256)", DAICO, 1_000_000 ether)
            });
            // DAICO sale: 1 ETH = 1,000,000 SHARES (no LP, no tap)
            initCalls[4] = Call({
                target: DAICO,
                value: 0,
                data: abi.encodeWithSignature(
                    "setSale(address,uint256,address,uint256,uint40)",
                    address(0),        // ETH tribute
                    1 ether,           // 1 ETH
                    predictedShares,   // for shares
                    1_000_000 ether,   // 1M shares
                    uint40(0)          // no deadline
                )
            });

            dao3 = summoner.summon(
                "Various tributes",
                "TRIBUTES",
                "ipfs://QmNa8mQkrNKp1WEEeGjFezDmDeodkWRevGFN8JCV7b4Xir",
                10000, // 100% quorum (all must vote)
                true,
                RENDERER,
                bytes32(uint256(103)),
                holders,
                shares,
                initCalls
            );
            console.log("DAO 3 (Various tributes) deployed at:", address(dao3));
            console.log("  - Proposal TTL: 14 days, Threshold: 100 shares, 100% quorum");
            console.log("  - DAICO Sale: 1 ETH = 1M SHARES (no LP, no tap)");
        }

        // DAO 4: DAICO Loot Sale - USDF payment, 70% LP, tap enabled
        {
            address[] memory holders = new address[](2);
            holders[0] = deployer;
            holders[1] = user2;

            uint256[] memory shares = new uint256[](2);
            shares[0] = 1000 ether;
            shares[1] = 500 ether;

            address predictedDao = _predictDAO(bytes32(uint256(104)), holders, shares);
            address predictedLoot = _predictLoot(predictedDao);

            Call[] memory initCalls = new Call[](7);
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
            // Mint 10000 loot to DAO for DAICO sale
            initCalls[3] = Call({
                target: predictedLoot,
                value: 0,
                data: abi.encodeWithSignature("mintFromMoloch(address,uint256)", predictedDao, 10_000 ether)
            });
            // Approve DAICO to spend loot
            initCalls[4] = Call({
                target: predictedLoot,
                value: 0,
                data: abi.encodeWithSignature("approve(address,uint256)", DAICO, 10_000 ether)
            });
            // DAICO sale with LP and tap: 1 USDF = 3 LOOT, 70% LP, 5% slippage, 0.3% fee
            // Tap: deployer (USER1) as ops, ~100 USDF/day = 1,157,407,407,407,407 wei/sec
            initCalls[5] = Call({
                target: DAICO,
                value: 0,
                data: abi.encodeWithSignature(
                    "setSaleWithLPAndTap(address,uint256,address,uint256,uint40,uint16,uint16,uint256,address,uint128)",
                    USDF,              // USDF payment
                    1 ether,           // 1 USDF
                    predictedLoot,     // for loot
                    3 ether,           // 3 LOOT per 1 USDF
                    uint40(block.timestamp + 30 days), // 30-day deadline
                    uint16(7000),      // 70% LP
                    uint16(500),       // 5% max slippage
                    uint256(30),       // 0.3% pool fee
                    deployer,          // ops = USER1
                    uint128(1_157_407_407_407_407) // ~100 USDF/day
                )
            });
            // Set allowance for tap budget: 10,000 USDF to DAICO
            initCalls[6] = Call({
                target: predictedDao,
                value: 0,
                data: abi.encodeWithSignature("setAllowance(address,address,uint256)", DAICO, USDF, 10_000 ether)
            });

            Moloch dao4 = summoner.summon(
                "DAICO Loot Sale",
                "DLOOT",
                "",
                1000, // 10% quorum
                true,
                RENDERER,
                bytes32(uint256(104)),
                holders,
                shares,
                initCalls
            );
            console.log("DAO 4 (DAICO Loot Sale) deployed at:", address(dao4));
            console.log("  - Proposal TTL: 5 days, Timelock: 12h, Auto-futarchy: 0.1%/5 LOOT");
            console.log("  - DAICO: 1 USDF = 3 LOOT, 70% LP, 5% slippage, 30-day deadline");
            console.log("  - Tap: User1 ops, ~100 USDF/day, 10k USDF budget");
        }

        // DAO 5: Full DAICO Test - ETH payment, 30% LP, tap enabled, both users are members
        {
            address[] memory holders = new address[](2);
            holders[0] = deployer;
            holders[1] = user2;  // User2 is now a member

            uint256[] memory shares = new uint256[](2);
            shares[0] = 50 ether;
            shares[1] = 50 ether;

            address predictedDao = _predictDAO(bytes32(uint256(105)), holders, shares);
            address predictedShares = _predictShares(predictedDao);

            Call[] memory initCalls = new Call[](6);
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
            // Mint 100000 shares to DAO for DAICO sale
            initCalls[2] = Call({
                target: predictedShares,
                value: 0,
                data: abi.encodeWithSignature("mintFromMoloch(address,uint256)", predictedDao, 100_000 ether)
            });
            // Approve DAICO to spend shares
            initCalls[3] = Call({
                target: predictedShares,
                value: 0,
                data: abi.encodeWithSignature("approve(address,uint256)", DAICO, 100_000 ether)
            });
            // DAICO sale with LP and tap: 0.001 ETH = 1000 SHARES, 30% LP, 1% slippage, 1% fee
            // Tap: user2 as ops, ~0.001 ETH/day = 11,574,074,074 wei/sec
            initCalls[4] = Call({
                target: DAICO,
                value: 0,
                data: abi.encodeWithSignature(
                    "setSaleWithLPAndTap(address,uint256,address,uint256,uint40,uint16,uint16,uint256,address,uint128)",
                    address(0),        // ETH payment
                    0.001 ether,       // 0.001 ETH
                    predictedShares,   // for shares
                    1000 ether,        // 1000 shares per 0.001 ETH
                    uint40(0),         // no deadline
                    uint16(3000),      // 30% LP
                    uint16(100),       // 1% max slippage
                    uint256(100),      // 1% pool fee
                    user2,             // ops = USER2
                    uint128(11_574_074_074) // ~0.001 ETH/day
                )
            });
            // Set allowance for tap budget: 5 ETH to DAICO
            initCalls[5] = Call({
                target: predictedDao,
                value: 0,
                data: abi.encodeWithSignature("setAllowance(address,address,uint256)", DAICO, address(0), 5 ether)
            });

            Moloch dao5 = summoner.summon(
                "Full DAICO Test",
                "FDAICO",
                "https://static9.depositphotos.com/1594920/1088/i/600/depositphotos_10881569-stock-photo-araucana-chicken-8-days-old.jpg",
                100, // 1% quorum
                true,
                RENDERER,
                bytes32(uint256(105)),
                holders,
                shares,
                initCalls
            );
            console.log("DAO 5 (Full DAICO Test) deployed at:", address(dao5));
            console.log("  - Proposal TTL: 1 day, Timelock: 1 hour (fast governance)");
            console.log("  - DAICO: 0.001 ETH = 1000 SHARES, 30% LP, 1% slippage, no deadline");
            console.log("  - Tap: User2 ops, ~0.001 ETH/day, 5 ETH budget");
            console.log("  - Both User1 and User2 are members");
        }

        vm.stopBroadcast();

        // DAO 1: Add 40 chat messages between deployer and user2 with dark jokes
        console.log("");
        console.log("Adding 40 chat messages to DAO 1...");
        string[40] memory jokes = [
            "I told my wife she was drawing her eyebrows too high. She looked surprised.",
            "My grandfather has the heart of a lion and a lifetime ban from the zoo.",
            "I have a fish that can breakdance! Only for 20 seconds though, and only once.",
            "My wife told me to stop impersonating a flamingo. I had to put my foot down.",
            "I threw a boomerang a few years ago. I now live in constant fear.",
            "My therapist says I have a preoccupation with vengeance. We'll see about that.",
            "I have a stepladder because my real ladder left when I was a kid.",
            "The cemetery is so crowded. People are just dying to get in.",
            "I told my suitcases there will be no vacation this year. Now I'm dealing with emotional baggage.",
            "My parents raised me as an only child, which really annoyed my sister.",
            "I have many jokes about unemployed people. Sadly none of them work.",
            "I asked the librarian if the library had books about paranoia. She whispered, 'They're right behind you.'",
            "I used to think the brain was the most important organ. Then I thought, look what's telling me that.",
            "Build a man a fire and he's warm for a day. Set a man on fire and he's warm for the rest of his life.",
            "I'd like to have kids one day. I don't think I could stand them any longer than that.",
            "What's the difference between a doctor and a murderer? A medical license.",
            "My favorite word is 'drool'. It just rolls off the tongue.",
            "I'm not saying I hate you, but I would unplug your life support to charge my phone.",
            "I told my psychiatrist I've been hearing voices. He said I don't have a psychiatrist.",
            "My boss told me to have a good day. So I went home.",
            "I'm reading a book about anti-gravity. It's impossible to put down.",
            "I used to be addicted to soap. I'm clean now.",
            "What do you call a fake noodle? An impasta.",
            "I'm on a seafood diet. I see food and I eat it.",
            "Why don't scientists trust atoms? Because they make up everything.",
            "I told my computer I needed a break. Now it won't stop sending me vacation ads.",
            "What do you call a bear with no teeth? A gummy bear.",
            "I'm not lazy, I'm just on energy-saving mode.",
            "Why did the scarecrow win an award? Because he was outstanding in his field.",
            "I used to play piano by ear, but now I use my hands.",
            "What do you call a dog that does magic? A Labracadabrador.",
            "I'm not arguing, I'm just explaining why I'm right.",
            "Why don't eggs tell jokes? They'd crack each other up.",
            "I told my wife she should embrace her mistakes. She hugged me.",
            "What do you call a can opener that doesn't work? A can't opener.",
            "I'm not short, I'm just more down to earth than most people.",
            "Why did the math book look so sad? Because it had too many problems.",
            "I used to hate facial hair, but then it grew on me.",
            "What do you call a sleeping dinosaur? A dino-snore.",
            "I'm not clumsy, the floor just hates me, the table and chairs are bullies, and the walls get in my way."
        ];
        for (uint256 i = 0; i < 40; i++) {
            uint256 pk = (i % 2 == 0) ? user1Key : user2Key;
            vm.broadcast(pk);
            dao1.chat(string.concat("(message #", vm.toString(i + 1), ") ", jokes[i]));
        }
        console.log("  - 40 messages added (alternating senders)");

        // DAO 3: Add 3 tributes (2 from user1, 1 from user2)
        // Note: Each (proposer, dao, tribTkn) must be unique per Tribute contract
        console.log("");
        console.log("Adding 3 tributes to DAO 3 (Various tributes)...");
        Tribute tribute = Tribute(TRIBUTE);
        address dao3Addr = address(dao3);

        // Tribute 1: User1 offers 0.1 ETH, wants 20 WETH (absurd ask)
        vm.broadcast(user1Key);
        tribute.proposeTribute{value: 0.1 ether}(
            dao3Addr,
            address(0), // ETH tribute
            0, // amount set by msg.value
            _getWETH(), // WETH (network-dependent)
            20 ether // wants 20 WETH for 0.1 ETH lol
        );
        console.log("  - Tribute 1: User1 offers 0.1 ETH, wants 20 WETH (good luck with that)");

        // Tribute 2: User1 offers 100 USDF, wants 1 ETH
        vm.broadcast(user1Key);
        IERC20(USDF).approve(TRIBUTE, 100 ether);
        vm.broadcast(user1Key);
        tribute.proposeTribute(
            dao3Addr,
            USDF, // USDF tribute
            100 ether, // 100 USDF
            address(0), // wants ETH
            1 ether // wants 1 ETH
        );
        console.log("  - Tribute 2: User1 offers 100 USDF, wants 1 ETH");

        // Tribute 3: User2 offers 0.5 ETH, wants 1000 USDF (lowballer special)
        vm.broadcast(user2Key);
        tribute.proposeTribute{value: 0.5 ether}(
            dao3Addr,
            address(0), // ETH tribute
            0,
            USDF, // wants USDF
            1000 ether // wants 1000 USDF for 0.5 ETH
        );
        console.log("  - Tribute 3: User2 offers 0.5 ETH, wants 1000 USDF (lowballer special)");

        console.log("");
        console.log("=== Phase 1 Complete ===");
        console.log("DAOs created, 40 messages added to DAO 1, 3 tributes to DAO 3");
        console.log("Run 'cast rpc evm_mine' then 'runPhase2' to add proposals");
    }

    // DAICO contract address (shared v1/v2)
    address constant DAICO = 0x000000000033e92DB97B4B3beCD2c255126C60aC;
    // Tribute contract address (shared v1/v2)
    address constant TRIBUTE = 0x000000000066524fcf78Dc1E41E9D525d9ea73D0;
    // USDF token address (test token user1 has)
    address constant USDF = 0x612f6e224F892Cc9a7f3395D4633a79D8f9c40c9;

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

        // Fetch DAO 2 address from Summoner (index 1)
        Summoner summoner = Summoner(V2_SUMMONER);
        Moloch dao2 = Moloch(payable(summoner.daos(1)));
        address dao2Addr = address(dao2);
        address sharesToken = address(dao2.shares());
        address lootToken = address(dao2.loot());

        console.log("Creating governance proposals in DAO 2...");
        console.log("  Shares token:", sharesToken);
        console.log("  Loot token:", lootToken);

        uint256[] memory proposalIds = new uint256[](24);
        uint256 idx = 0;

        // 1. Set Metadata - Change DAO name, symbol, and description
        proposalIds[idx] = _createProposal(
            dao2, user1Key, 0, dao2Addr, 0,
            abi.encodeWithSignature("setMetadata(string,string,string)", "Beta DAO Renamed", "BETA2", "ipfs://QmNewDescription"),
            bytes32(uint256(1)),
            "I told my wife she was drawing her eyebrows too high. She looked surprised."
        );
        console.log("  1. Set Metadata proposal created");
        idx++;

        // 2. Change Renderer - Update the NFT metadata renderer
        proposalIds[idx] = _createProposal(
            dao2, user2Key, 0, dao2Addr, 0,
            abi.encodeWithSignature("setRenderer(address)", RENDERER),
            bytes32(uint256(2)),
            "My grandfather has the heart of a lion and a lifetime ban from the zoo."
        );
        console.log("  2. Change Renderer proposal created");
        idx++;

        // 3. Set Quorum (BPS) - Change quorum to 30%
        proposalIds[idx] = _createProposal(
            dao2, user1Key, 0, dao2Addr, 0,
            abi.encodeWithSignature("setQuorumBps(uint16)", uint16(3000)),
            bytes32(uint256(3)),
            "I have a fish that can breakdance! Only for 20 seconds though, and only once."
        );
        console.log("  3. Set Quorum BPS proposal created");
        idx++;

        // 4. Set Absolute Quorum - Require 500 votes minimum
        proposalIds[idx] = _createProposal(
            dao2, user2Key, 0, dao2Addr, 0,
            abi.encodeWithSignature("setQuorumAbsolute(uint96)", uint96(500 ether)),
            bytes32(uint256(4)),
            "My wife told me to stop impersonating a flamingo. I had to put my foot down."
        );
        console.log("  4. Set Absolute Quorum proposal created");
        idx++;

        // 5. Set Min YES Votes - Require 200 YES votes to pass
        proposalIds[idx] = _createProposal(
            dao2, user1Key, 0, dao2Addr, 0,
            abi.encodeWithSignature("setMinYesVotesAbsolute(uint96)", uint96(200 ether)),
            bytes32(uint256(5)),
            "I threw a boomerang a few years ago. I now live in constant fear."
        );
        console.log("  5. Set Min YES Votes proposal created");
        idx++;

        // 6. Set Vote Threshold - Require 50 shares to propose
        proposalIds[idx] = _createProposal(
            dao2, user2Key, 0, dao2Addr, 0,
            abi.encodeWithSignature("setProposalThreshold(uint96)", uint96(50 ether)),
            bytes32(uint256(6)),
            "My therapist says I have a preoccupation with vengeance. We'll see about that."
        );
        console.log("  6. Set Vote Threshold proposal created");
        idx++;

        // 7. Set Proposal TTL - Change voting period to 5 days
        proposalIds[idx] = _createProposal(
            dao2, user1Key, 0, dao2Addr, 0,
            abi.encodeWithSignature("setProposalTTL(uint64)", uint64(5 days)),
            bytes32(uint256(7)),
            "I have a stepladder because my real ladder left when I was a kid."
        );
        console.log("  7. Set Proposal TTL proposal created");
        idx++;

        // 8. Set Timelock Delay - Add 2 day execution delay
        proposalIds[idx] = _createProposal(
            dao2, user2Key, 0, dao2Addr, 0,
            abi.encodeWithSignature("setTimelockDelay(uint64)", uint64(2 days)),
            bytes32(uint256(8)),
            "The cemetery is so crowded. People are just dying to get in."
        );
        console.log("  8. Set Timelock Delay proposal created");
        idx++;

        // 9. Toggle Ragequit - Enable ragequit for members
        proposalIds[idx] = _createProposal(
            dao2, user1Key, 0, dao2Addr, 0,
            abi.encodeWithSignature("setRagequittable(bool)", true),
            bytes32(uint256(9)),
            "I told my suitcases there will be no vacation this year. Now I'm dealing with emotional baggage."
        );
        console.log("  9. Toggle Ragequit proposal created");
        idx++;

        // 10. Toggle Transferability - Lock shares and loot transfers
        proposalIds[idx] = _createProposal(
            dao2, user2Key, 0, dao2Addr, 0,
            abi.encodeWithSignature("setTransfersLocked(bool,bool)", true, true),
            bytes32(uint256(10)),
            "My parents raised me as an only child, which really annoyed my sister."
        );
        console.log("  10. Toggle Transferability proposal created");
        idx++;

        // 11. Configure Auto-Futarchy - Enable 0.5% param, 10 LOOT cap
        proposalIds[idx] = _createProposal(
            dao2, user1Key, 0, dao2Addr, 0,
            abi.encodeWithSignature("setAutoFutarchy(uint256,uint256)", uint256(50), uint256(10 ether)),
            bytes32(uint256(11)),
            "I have many jokes about unemployed people. Sadly none of them work."
        );
        console.log("  11. Configure Auto-Futarchy proposal created");
        idx++;

        // 12. Set Futarchy Reward Token - Use ETH (address(0)) for rewards
        proposalIds[idx] = _createProposal(
            dao2, user2Key, 0, dao2Addr, 0,
            abi.encodeWithSignature("setFutarchyRewardToken(address)", address(0)),
            bytes32(uint256(12)),
            "I asked the librarian if the library had books about paranoia. She whispered, 'They're right behind you.'"
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
                "I used to think the brain was the most important organ. Then I thought, look what's telling me that."
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
                "Build a man a fire and he's warm for a day. Set a man on fire and he's warm for the rest of his life."
            );
            console.log("  14. DAICO Sale proposal created");
            idx++;
        }

        // 15. Set Ragequit Timelock - Add 3 day ragequit delay
        proposalIds[idx] = _createProposal(
            dao2, user1Key, 0, dao2Addr, 0,
            abi.encodeWithSignature("setRagequitTimelock(uint64)", uint64(3 days)),
            bytes32(uint256(15)),
            "I'd like to have kids one day. I don't think I could stand them any longer than that."
        );
        console.log("  15. Set Ragequit Timelock proposal created");
        idx++;

        // 16. Bump Config - Invalidate all pre-bump proposal hashes
        proposalIds[idx] = _createProposal(
            dao2, user2Key, 0, dao2Addr, 0,
            abi.encodeWithSignature("bumpConfig()"),
            bytes32(uint256(16)),
            "What's the difference between a doctor and a murderer? A medical license."
        );
        console.log("  16. Bump Config proposal created");
        idx++;

        // 17. Set Permit - Allow user2 to execute a specific action 3 times
        {
            // Permit: allow user2 to send 1 ETH to deployer, 3 times
            bytes memory permitData = abi.encodeWithSignature(
                "setPermit(uint8,address,uint256,bytes,bytes32,address,uint256)",
                uint8(0), // op = call
                deployer, // to
                1 ether, // value
                "", // data (empty = just send ETH)
                bytes32(uint256(1001)), // nonce
                user2, // spender
                uint256(3) // count
            );
            proposalIds[idx] = _createProposal(
                dao2, user1Key, 0, dao2Addr, 0,
                permitData,
                bytes32(uint256(17)),
                "My favorite word is 'drool'. It just rolls off the tongue."
            );
            console.log("  17. Set Permit proposal created");
            idx++;
        }

        // 18. Set Allowance (ETH) - Allow deployer to withdraw 5 ETH
        proposalIds[idx] = _createProposal(
            dao2, user2Key, 0, dao2Addr, 0,
            abi.encodeWithSignature("setAllowance(address,address,uint256)", deployer, address(0), 5 ether),
            bytes32(uint256(18)),
            "I'm not saying I hate you, but I would unplug your life support to charge my phone."
        );
        console.log("  18. Set Allowance (ETH) proposal created");
        idx++;

        // 19. Set Allowance (ERC20) - Allow user2 to withdraw 1000 USDF
        proposalIds[idx] = _createProposal(
            dao2, user1Key, 0, dao2Addr, 0,
            abi.encodeWithSignature("setAllowance(address,address,uint256)", user2, USDF, 1000 ether),
            bytes32(uint256(19)),
            "I told my psychiatrist I've been hearing voices. He said I don't have a psychiatrist."
        );
        console.log("  19. Set Allowance (ERC20) proposal created");
        idx++;

        // 20. Set Sale (ETH, mint shares, with cap) - Sell 50 shares at 0.2 ETH each, max 50
        proposalIds[idx] = _createProposal(
            dao2, user2Key, 0, dao2Addr, 0,
            abi.encodeWithSignature(
                "setSale(address,uint256,uint256,bool,bool,bool)",
                address(0), // ETH payment
                0.2 ether, // price per share
                50 ether, // cap of 50 shares
                true, // minting
                true, // active
                false // isLoot = false (shares)
            ),
            bytes32(uint256(20)),
            "My boss told me to have a good day. So I went home."
        );
        console.log("  20. Set Sale (ETH/mint/shares/capped) proposal created");
        idx++;

        // 21. Set Sale (ERC20, transfer shares, no cap) - Sell DAO-held shares for USDF
        proposalIds[idx] = _createProposal(
            dao2, user1Key, 0, dao2Addr, 0,
            abi.encodeWithSignature(
                "setSale(address,uint256,uint256,bool,bool,bool)",
                USDF, // USDF payment
                100 ether, // 100 USDF per share
                0, // no cap
                false, // transfer (not minting)
                true, // active
                false // isLoot = false (shares)
            ),
            bytes32(uint256(21)),
            "I'm reading a book about anti-gravity. It's impossible to put down."
        );
        console.log("  21. Set Sale (ERC20/transfer/shares/uncapped) proposal created");
        idx++;

        // 22. Set Sale (ETH, mint loot, with cap) - Sell 100 loot at 0.05 ETH each
        proposalIds[idx] = _createProposal(
            dao2, user2Key, 0, dao2Addr, 0,
            abi.encodeWithSignature(
                "setSale(address,uint256,uint256,bool,bool,bool)",
                address(0), // ETH payment
                0.05 ether, // price per loot
                100 ether, // cap of 100 loot
                true, // minting
                true, // active
                true // isLoot = true
            ),
            bytes32(uint256(22)),
            "I used to be addicted to soap. I'm clean now."
        );
        console.log("  22. Set Sale (ETH/mint/loot/capped) proposal created");
        idx++;

        // 23. Set Sale (ERC20, transfer loot, no cap) - Sell DAO-held loot for USDF
        proposalIds[idx] = _createProposal(
            dao2, user1Key, 0, dao2Addr, 0,
            abi.encodeWithSignature(
                "setSale(address,uint256,uint256,bool,bool,bool)",
                USDF, // USDF payment
                50 ether, // 50 USDF per loot
                0, // no cap
                false, // transfer (not minting)
                true, // active
                true // isLoot = true
            ),
            bytes32(uint256(23)),
            "What do you call a fake noodle? An impasta."
        );
        console.log("  23. Set Sale (ERC20/transfer/loot/uncapped) proposal created");
        idx++;

        // 24. Slash Member (Loot) - Burn 20 loot from user2
        {
            Call[] memory slashLootCalls = new Call[](1);
            slashLootCalls[0] = Call({
                target: lootToken,
                value: 0,
                data: abi.encodeWithSignature("burnFromMoloch(address,uint256)", user2, 20 ether)
            });
            bytes memory batchData = abi.encodeWithSignature("batchCalls((address,uint256,bytes)[])", slashLootCalls);
            proposalIds[idx] = _createProposal(
                dao2, user2Key, 0, dao2Addr, 0,
                batchData,
                bytes32(uint256(24)),
                "I'm on a seafood diet. I see food and I eat it."
            );
            console.log("  24. Slash Member (Loot) proposal created");
            idx++;
        }

        // Vote on proposals 13-15 and 22-24
        console.log("");
        console.log("Voting on proposals 13, 14, 15, 22, 23, 24...");

        // Proposal 13 (Slash Shares): Both vote FOR
        vm.broadcast(user1Key);
        dao2.castVote(proposalIds[12], 1);
        vm.broadcast(user2Key);
        dao2.castVote(proposalIds[12], 1);
        console.log("  - Proposal 13 (Slash Shares): Both voted FOR");

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

        // Proposal 22 (Sale ETH/mint/loot): User1 FOR, User2 AGAINST (contested)
        vm.broadcast(user1Key);
        dao2.castVote(proposalIds[21], 1);
        vm.broadcast(user2Key);
        dao2.castVote(proposalIds[21], 0);
        console.log("  - Proposal 22 (Sale loot): User1 FOR, User2 AGAINST");

        // Proposal 23 (Sale ERC20/loot): Both vote FOR
        vm.broadcast(user1Key);
        dao2.castVote(proposalIds[22], 1);
        vm.broadcast(user2Key);
        dao2.castVote(proposalIds[22], 1);
        console.log("  - Proposal 23 (Sale loot ERC20): Both voted FOR");

        // Proposal 24 (Slash Loot): User1 ABSTAIN, User2 FOR (mixed)
        vm.broadcast(user1Key);
        dao2.castVote(proposalIds[23], 2);
        vm.broadcast(user2Key);
        dao2.castVote(proposalIds[23], 1);
        console.log("  - Proposal 24 (Slash Loot): User1 ABSTAIN, User2 FOR");

        console.log("");
        console.log("=== Phase 2 Complete ===");
        console.log("Total DAOs in Summoner:", summoner.getDAOCount());
        console.log("");
        console.log("24 governance proposals created covering:");
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
        console.log("  13. Slash Member (Shares)");
        console.log("  14. DAICO Sale");
        console.log("  15. Set Ragequit Timelock");
        console.log("  16. Bump Config");
        console.log("  17. Set Permit");
        console.log("  18. Set Allowance (ETH)");
        console.log("  19. Set Allowance (ERC20)");
        console.log("  20. Set Sale (ETH/mint/shares/capped)");
        console.log("  21. Set Sale (ERC20/transfer/shares/uncapped)");
        console.log("  22. Set Sale (ETH/mint/loot/capped)");
        console.log("  23. Set Sale (ERC20/transfer/loot/uncapped)");
        console.log("  24. Slash Member (Loot)");
        console.log("");
        console.log("Votes cast on proposals 13-15 and 22-24 with varied voting patterns");
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // Individual Deploy Functions (for selective deployment via deploy-dao.sh)
    // ═══════════════════════════════════════════════════════════════════════════════

    /// @notice Deploy only DAO 1: "40 messages" with cheap ETH shares sale
    function deployDAO1() public {
        uint256 user1Key = vm.envOr("TEST_USER1_KEY", DEFAULT_USER1_KEY);
        uint256 user2Key = vm.envOr("TEST_USER2_KEY", DEFAULT_USER2_KEY);
        address deployer = vm.addr(user1Key);
        address user2 = vm.addr(user2Key);

        vm.startBroadcast(user1Key);
        Summoner summoner = Summoner(V2_SUMMONER);

        address[] memory holders = new address[](2);
        holders[0] = deployer;
        holders[1] = user2;

        uint256[] memory shares = new uint256[](2);
        shares[0] = 100 ether;
        shares[1] = 50 ether;

        address predictedDao = _predictDAO(bytes32(uint256(101)), holders, shares);

        Call[] memory initCalls = new Call[](3);
        initCalls[0] = Call({
            target: predictedDao,
            value: 0,
            data: abi.encodeWithSignature("setProposalTTL(uint64)", uint64(7 days))
        });
        initCalls[1] = Call({
            target: predictedDao,
            value: 0,
            data: abi.encodeWithSignature("setTimelockDelay(uint64)", uint64(1 days))
        });
        initCalls[2] = Call({
            target: predictedDao,
            value: 0,
            data: abi.encodeWithSignature(
                "setSale(address,uint256,uint256,bool,bool,bool)",
                address(0), 0.0000005 ether, uint256(0), true, true, false
            )
        });

        Moloch dao = summoner.summon(
            "40 messages", "40MSG",
            "https://st.depositphotos.com/2892507/4212/i/600/depositphotos_42123797-stock-photo-easter-dalmatain-puppy.jpg",
            5000, true, RENDERER, bytes32(uint256(101)), holders, shares, initCalls
        );
        vm.stopBroadcast();
        console.log("DAO 1 deployed at:", address(dao));
    }

    /// @notice Deploy only DAO 2: "All gov proposals" with USDF loot sale
    function deployDAO2() public {
        uint256 user1Key = vm.envOr("TEST_USER1_KEY", DEFAULT_USER1_KEY);
        uint256 user2Key = vm.envOr("TEST_USER2_KEY", DEFAULT_USER2_KEY);
        address deployer = vm.addr(user1Key);
        address user2 = vm.addr(user2Key);

        vm.startBroadcast(user1Key);
        Summoner summoner = Summoner(V2_SUMMONER);

        address[] memory holders = new address[](2);
        holders[0] = deployer;
        holders[1] = user2;

        uint256[] memory shares = new uint256[](2);
        shares[0] = 1000 ether;
        shares[1] = 500 ether;

        address predictedDao = _predictDAO(bytes32(uint256(102)), holders, shares);

        Call[] memory initCalls = new Call[](2);
        initCalls[0] = Call({
            target: predictedDao,
            value: 0,
            data: abi.encodeWithSignature("setProposalTTL(uint64)", uint64(3 days))
        });
        initCalls[1] = Call({
            target: predictedDao,
            value: 0,
            data: abi.encodeWithSignature(
                "setSale(address,uint256,uint256,bool,bool,bool)",
                USDF, 3 ether, 1000 ether, true, true, true
            )
        });

        Moloch dao = summoner.summon(
            "All gov proposals", "ALLGOV", "",
            2500, false, RENDERER, bytes32(uint256(102)), holders, shares, initCalls
        );
        vm.stopBroadcast();
        console.log("DAO 2 deployed at:", address(dao));
    }

    /// @notice Deploy only DAO 3: "Various tributes" with DAICO sale
    function deployDAO3() public {
        uint256 user1Key = vm.envOr("TEST_USER1_KEY", DEFAULT_USER1_KEY);
        uint256 user2Key = vm.envOr("TEST_USER2_KEY", DEFAULT_USER2_KEY);
        address deployer = vm.addr(user1Key);
        address user2 = vm.addr(user2Key);

        vm.startBroadcast(user1Key);
        Summoner summoner = Summoner(V2_SUMMONER);

        address[] memory holders = new address[](2);
        holders[0] = deployer;
        holders[1] = user2;

        uint256[] memory shares = new uint256[](2);
        shares[0] = 1000 ether;
        shares[1] = 500 ether;

        address predictedDao = _predictDAO(bytes32(uint256(103)), holders, shares);
        address predictedShares = _predictShares(predictedDao);

        Call[] memory initCalls = new Call[](5);
        initCalls[0] = Call({
            target: predictedDao,
            value: 0,
            data: abi.encodeWithSignature("setProposalTTL(uint64)", uint64(14 days))
        });
        initCalls[1] = Call({
            target: predictedDao,
            value: 0,
            data: abi.encodeWithSignature("setProposalThreshold(uint96)", uint96(100 ether))
        });
        initCalls[2] = Call({
            target: predictedShares,
            value: 0,
            data: abi.encodeWithSignature("mintFromMoloch(address,uint256)", predictedDao, 1_000_000 ether)
        });
        initCalls[3] = Call({
            target: predictedShares,
            value: 0,
            data: abi.encodeWithSignature("approve(address,uint256)", DAICO, 1_000_000 ether)
        });
        initCalls[4] = Call({
            target: DAICO,
            value: 0,
            data: abi.encodeWithSignature(
                "setSale(address,uint256,address,uint256,uint40)",
                address(0), 1 ether, predictedShares, 1_000_000 ether, uint40(0)
            )
        });

        Moloch dao = summoner.summon(
            "Various tributes", "TRIBUTES",
            "ipfs://QmNa8mQkrNKp1WEEeGjFezDmDeodkWRevGFN8JCV7b4Xir",
            10000, true, RENDERER, bytes32(uint256(103)), holders, shares, initCalls
        );
        vm.stopBroadcast();
        console.log("DAO 3 deployed at:", address(dao));
    }

    /// @notice Deploy only DAO 4: "DAICO Loot Sale" with LP and tap
    function deployDAO4() public {
        uint256 user1Key = vm.envOr("TEST_USER1_KEY", DEFAULT_USER1_KEY);
        uint256 user2Key = vm.envOr("TEST_USER2_KEY", DEFAULT_USER2_KEY);
        address deployer = vm.addr(user1Key);
        address user2 = vm.addr(user2Key);

        vm.startBroadcast(user1Key);
        Summoner summoner = Summoner(V2_SUMMONER);

        address[] memory holders = new address[](2);
        holders[0] = deployer;
        holders[1] = user2;

        uint256[] memory shares = new uint256[](2);
        shares[0] = 1000 ether;
        shares[1] = 500 ether;

        address predictedDao = _predictDAO(bytes32(uint256(104)), holders, shares);
        address predictedLoot = _predictLoot(predictedDao);

        Call[] memory initCalls = new Call[](7);
        initCalls[0] = Call({
            target: predictedDao,
            value: 0,
            data: abi.encodeWithSignature("setProposalTTL(uint64)", uint64(5 days))
        });
        initCalls[1] = Call({
            target: predictedDao,
            value: 0,
            data: abi.encodeWithSignature("setTimelockDelay(uint64)", uint64(12 hours))
        });
        initCalls[2] = Call({
            target: predictedDao,
            value: 0,
            data: abi.encodeWithSignature("setAutoFutarchy(uint256,uint256)", uint256(10), uint256(5 ether))
        });
        initCalls[3] = Call({
            target: predictedLoot,
            value: 0,
            data: abi.encodeWithSignature("mintFromMoloch(address,uint256)", predictedDao, 10_000 ether)
        });
        initCalls[4] = Call({
            target: predictedLoot,
            value: 0,
            data: abi.encodeWithSignature("approve(address,uint256)", DAICO, 10_000 ether)
        });
        initCalls[5] = Call({
            target: DAICO,
            value: 0,
            data: abi.encodeWithSignature(
                "setSaleWithLPAndTap(address,uint256,address,uint256,uint40,uint16,uint16,uint256,address,uint128)",
                USDF, 1 ether, predictedLoot, 3 ether,
                uint40(block.timestamp + 30 days), uint16(7000), uint16(500), uint256(30),
                deployer, uint128(1_157_407_407_407_407)
            )
        });
        initCalls[6] = Call({
            target: predictedDao,
            value: 0,
            data: abi.encodeWithSignature("setAllowance(address,address,uint256)", DAICO, USDF, 10_000 ether)
        });

        Moloch dao = summoner.summon(
            "DAICO Loot Sale", "DLOOT", "",
            1000, true, RENDERER, bytes32(uint256(104)), holders, shares, initCalls
        );
        vm.stopBroadcast();
        console.log("DAO 4 deployed at:", address(dao));
    }

    /// @notice Deploy only DAO 5: "Full DAICO Test" with LP and tap
    function deployDAO5() public {
        uint256 user1Key = vm.envOr("TEST_USER1_KEY", DEFAULT_USER1_KEY);
        uint256 user2Key = vm.envOr("TEST_USER2_KEY", DEFAULT_USER2_KEY);
        address deployer = vm.addr(user1Key);
        address user2 = vm.addr(user2Key);

        vm.startBroadcast(user1Key);
        Summoner summoner = Summoner(V2_SUMMONER);

        address[] memory holders = new address[](2);
        holders[0] = deployer;
        holders[1] = user2;

        uint256[] memory shares = new uint256[](2);
        shares[0] = 50 ether;
        shares[1] = 50 ether;

        address predictedDao = _predictDAO(bytes32(uint256(105)), holders, shares);
        address predictedShares = _predictShares(predictedDao);

        Call[] memory initCalls = new Call[](6);
        initCalls[0] = Call({
            target: predictedDao,
            value: 0,
            data: abi.encodeWithSignature("setProposalTTL(uint64)", uint64(1 days))
        });
        initCalls[1] = Call({
            target: predictedDao,
            value: 0,
            data: abi.encodeWithSignature("setTimelockDelay(uint64)", uint64(1 hours))
        });
        initCalls[2] = Call({
            target: predictedShares,
            value: 0,
            data: abi.encodeWithSignature("mintFromMoloch(address,uint256)", predictedDao, 100_000 ether)
        });
        initCalls[3] = Call({
            target: predictedShares,
            value: 0,
            data: abi.encodeWithSignature("approve(address,uint256)", DAICO, 100_000 ether)
        });
        initCalls[4] = Call({
            target: DAICO,
            value: 0,
            data: abi.encodeWithSignature(
                "setSaleWithLPAndTap(address,uint256,address,uint256,uint40,uint16,uint16,uint256,address,uint128)",
                address(0), 0.001 ether, predictedShares, 1000 ether,
                uint40(0), uint16(3000), uint16(100), uint256(100),
                user2, uint128(11_574_074_074)
            )
        });
        initCalls[5] = Call({
            target: predictedDao,
            value: 0,
            data: abi.encodeWithSignature("setAllowance(address,address,uint256)", DAICO, address(0), 5 ether)
        });

        Moloch dao = summoner.summon(
            "Full DAICO Test", "FDAICO",
            "https://static9.depositphotos.com/1594920/1088/i/600/depositphotos_10881569-stock-photo-araucana-chicken-8-days-old.jpg",
            100, true, RENDERER, bytes32(uint256(105)), holders, shares, initCalls
        );
        vm.stopBroadcast();
        console.log("DAO 5 deployed at:", address(dao));
    }
}

// Minimal ERC20 interface for approve
interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
}
