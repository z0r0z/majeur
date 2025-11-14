// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "../lib/forge-std/src/Test.sol";
import {Moloch, Shares, Loot, Badges, Summoner, Call} from "../src/Moloch.sol";

contract ContractURITest is Test {
    Summoner internal summoner;
    Moloch internal moloch;
    Shares internal shares;
    Loot internal loot;

    address internal alice = address(0xA11CE);
    address internal bob = address(0x0B0B);

    function setUp() public {
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);

        summoner = new Summoner();

        address[] memory initialHolders = new address[](2);
        initialHolders[0] = alice;
        initialHolders[1] = bob;

        uint256[] memory initialAmounts = new uint256[](2);
        initialAmounts[0] = 60e18;
        initialAmounts[1] = 40e18;

        moloch = summoner.summon(
            "Majeur DAO",
            "MAJ",
            "", // Empty contractURI - will use default DUNA covenant
            5000,
            true, // ragequit enabled
            bytes32(0),
            initialHolders,
            initialAmounts,
            new Call[](0)
        );

        shares = moloch.shares();
        loot = moloch.loot();

        // ✅ separate the initial minting checkpoint from future snapshots
        vm.roll(block.number + 2);
        vm.warp(block.timestamp + 1);
    }

    function test_contractURI_default_duna_covenant() public view {
        console2.log("\n========================================");
        console2.log("  DEFAULT CONTRACT URI - DUNA COVENANT");
        console2.log("========================================\n");

        string memory uri = moloch.contractURI();

        console2.log("Full URI (paste in browser to view):");
        console2.log(uri);
        console2.log("");
        console2.log("--- CARD DETAILS ---");
        console2.log("Type: Wyoming DUNA Covenant Card");
        console2.log("Organization:", moloch.name(0));
        console2.log("Symbol:", moloch.symbol(0));
        console2.log("Address:", address(moloch));
        console2.log("");
        console2.log("Share Supply:", shares.totalSupply() / 1e18);
        console2.log("Loot Supply:", loot.totalSupply() / 1e18);
        console2.log("Share Transfers Locked:", shares.transfersLocked());
        console2.log("Loot Transfers Locked:", loot.transfersLocked());
        console2.log("Ragequit Enabled:", moloch.ragequittable());
        console2.log("");
        console2.log("--- COVENANT INCLUDES ---");
        console2.log("- W.S. Section 17-32-101 et seq. reference");
        console2.log("- Member agreement terms");
        console2.log("- Limited liability provisions");
        console2.log("- Dispute resolution framework");
        console2.log("- Governance participation requirements");
        console2.log("- Transfer and ragequit status");
        console2.log("- Code-as-law principles");
        console2.log("");
        console2.log("--- EXTRACTION GUIDE ---");
        console2.log("To view this covenant card:");
        console2.log("1. Copy the full URI above");
        console2.log("2. Paste into browser address bar (renders instantly)");
        console2.log("3. Or decode base64 to get JSON with embedded SVG");
        console2.log("");
        console2.log("The card displays:");
        console2.log("- DUNA sigil (ASCII art)");
        console2.log("- Organization details");
        console2.log("- Covenant legal text");
        console2.log("- Member agreement terms");
        console2.log("- Transfer/ragequit status");
        console2.log("- Legal disclaimers");
        console2.log("- 'CODE IS LAW' seal");
        console2.log("========================================\n");
    }

    function test_contractURI_with_loot() public {
        console2.log("\n========================================");
        console2.log("  DUNA COVENANT WITH LOOT");
        console2.log("========================================\n");

        // ---- Prepare a governance action that mints LOOT directly ----
        address charlie = address(0xCAFE);

        // Build calldata to mint loot to `charlie`.
        // If your Loot uses a different name/signature, adjust selector accordingly:
        // e.g. Loot.mint(address,uint256)
        bytes memory mintLootData =
            abi.encodeWithSelector(Loot.mintFromMoloch.selector, charlie, 50e18);

        // Make sure the snapshot sees the initial supply (block > deployment block).
        vm.roll(block.number + 2);
        vm.warp(block.timestamp + 1);

        // Create proposal id targeting the Loot contract (NOT the DAO itself).
        uint256 h = moloch.proposalId(
            0, // nonce/domain if used
            address(loot), // target = Loot contract
            0, // value
            mintLootData, // calldata
            keccak256("mint-loot")
        );

        // Open proposal (takes snapshot at current/prev block internally).
        moloch.openProposal(h);

        // Cast votes (use snapshot block inside openProposal).
        vm.prank(alice);
        moloch.castVote(h, 1);
        vm.prank(bob);
        moloch.castVote(h, 1);

        // Advance blocks/time to clear voting + grace windows.
        // (Adjust these bumps if your constants differ.)
        vm.roll(block.number + 10);
        vm.warp(block.timestamp + 8 days);

        // Execute: DAO calls Loot.mint(charlie, 50e18).
        moloch.executeByVotes(0, address(loot), 0, mintLootData, keccak256("mint-loot"));

        // Now render the contractURI (loot supply should be non-zero).
        string memory uri = moloch.contractURI();

        console2.log("Full URI (with loot supply):");
        console2.log(uri);
        console2.log("");
        console2.log("Share Supply:", shares.totalSupply() / 1e18);
        console2.log("Loot Supply:", loot.totalSupply() / 1e18);
        console2.log("");
        console2.log("Card displays both share and loot supplies");
        console2.log("Plus separate transfer status for each");
        console2.log("========================================\n");
    }

    function test_contractURI_with_custom_uri() public {
        console2.log("\n========================================");
        console2.log("  CUSTOM CONTRACT URI");
        console2.log("========================================\n");

        // Set custom URI via governance
        bytes memory customData = abi.encodeWithSelector(
            Moloch.setMetadata.selector, "Custom DAO", "CUST", "ipfs://QmCustomCovenantHash123"
        );

        uint256 h = moloch.proposalId(0, address(moloch), 0, customData, keccak256("custom-uri"));
        moloch.openProposal(h);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        vm.prank(alice);
        moloch.castVote(h, 1);
        vm.prank(bob);
        moloch.castVote(h, 1);

        // ✅ past voting/grace:
        vm.roll(block.number + 10);
        vm.warp(block.timestamp + 8 days);

        moloch.executeByVotes(0, address(moloch), 0, customData, keccak256("custom-uri"));

        string memory uri = moloch.contractURI();

        console2.log("Custom URI:");
        console2.log(uri);
        console2.log("");
        console2.log("When custom URI is set, it overrides the default");
        console2.log("DUNA covenant card generation");
        console2.log("========================================\n");
    }

    function test_contractURI_with_locked_transfers() public {
        console2.log("\n========================================");
        console2.log("  DUNA COVENANT - TRANSFERS LOCKED");
        console2.log("========================================\n");

        // Deploy new DAO with ragequit disabled
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        Moloch lockedDao = summoner.summon(
            "Locked DAO",
            "LOCK",
            "",
            5000,
            false, // ragequit disabled
            bytes32(uint256(1)),
            holders,
            amounts,
            new Call[](0)
        );

        string memory uri = lockedDao.contractURI();

        console2.log("Full URI:");
        console2.log(uri);
        console2.log("");
        console2.log("Ragequit Enabled:", lockedDao.ragequittable());
        console2.log("");
        console2.log("Card shows:");
        console2.log("- Transfer status: DISABLED or ENABLED");
        console2.log("- Ragequit status: DISABLED or ENABLED");
        console2.log("- Dynamic based on current settings");
        console2.log("========================================\n");
    }
}
