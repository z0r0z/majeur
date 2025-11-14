// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "../lib/forge-std/src/Test.sol";
import {Moloch, Shares, Loot, Badges, Summoner, Call} from "../src/Moloch.sol";

contract URIVisualizationTest is Test {
    Summoner internal summoner;
    Moloch internal moloch;
    Shares internal shares;
    Loot internal loot;
    Badges internal badge;

    address internal alice = address(0xA11CE);
    address internal bob = address(0x0B0B);
    address internal charlie = address(0xCAFE);

    Target internal target;

    function setUp() public {
        vm.label(alice, "ALICE");
        vm.label(bob, "BOB");
        vm.label(charlie, "CHARLIE");

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);

        summoner = new Summoner();

        address[] memory initialHolders = new address[](2);
        initialHolders[0] = alice;
        initialHolders[1] = bob;

        uint256[] memory initialAmounts = new uint256[](2);
        initialAmounts[0] = 60e18;
        initialAmounts[1] = 40e18;

        moloch = summoner.summon(
            "Test DAO",
            "TEST",
            "ipfs://QmTest123",
            5000, // 50% quorum
            true, // ragequit enabled
            bytes32(0),
            initialHolders,
            initialAmounts,
            new Call[](0)
        );

        shares = moloch.shares();
        loot = moloch.loot();
        badge = moloch.badges();

        target = new Target();
        vm.roll(block.number + 1);
    }

    /*//////////////////////////////////////////////////////////////
                        URI VISUALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_visualize_proposal_unopened() public view {
        bytes memory data = abi.encodeWithSelector(Target.store.selector, 42);
        uint256 h = moloch.proposalId(0, address(target), 0, data, keccak256("test1"));

        string memory uri = moloch.tokenURI(h);

        console2.log("\n=== UNOPENED PROPOSAL CARD ===");
        console2.log("URI:", uri);

        _logDecodedURI(uri);
    }

    function test_visualize_proposal_active() public {
        // First, raise the quorum so Alice alone can't pass
        bytes memory quorumData = abi.encodeWithSelector(Moloch.setQuorumBps.selector, uint16(8000)); // 80%
        uint256 qH = moloch.proposalId(0, address(moloch), 0, quorumData, keccak256("set-quorum"));

        moloch.openProposal(qH);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        vm.prank(alice);
        moloch.castVote(qH, 1);
        vm.prank(bob);
        moloch.castVote(qH, 1);

        moloch.executeByVotes(0, address(moloch), 0, quorumData, keccak256("set-quorum"));

        // Now create a proposal that will be ACTIVE
        bytes memory data = abi.encodeWithSelector(Target.store.selector, 123);
        uint256 h = moloch.proposalId(0, address(target), 0, data, keccak256("active-test"));

        moloch.openProposal(h);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        // Only Alice votes (60 shares), but we need 80 for quorum
        vm.prank(alice);
        moloch.castVote(h, 1);

        string memory uri = moloch.tokenURI(h);

        console2.log("\n=== ACTIVE PROPOSAL CARD (60% voted, need 80% quorum) ===");
        console2.log("URI:", uri);

        _logDecodedURI(uri);
    }

    function test_visualize_proposal_succeeded() public {
        bytes memory data = abi.encodeWithSelector(Target.store.selector, 456);
        uint256 h = moloch.proposalId(0, address(target), 0, data, keccak256("succeeded-test"));

        moloch.openProposal(h);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        vm.prank(alice);
        moloch.castVote(h, 1);
        vm.prank(bob);
        moloch.castVote(h, 1);

        string memory uri = moloch.tokenURI(h);

        console2.log("\n=== SUCCEEDED PROPOSAL CARD ===");
        console2.log("URI:", uri);

        _logDecodedURI(uri);
    }

    function test_visualize_proposal_defeated() public {
        // Transfer shares to make Bob the majority
        vm.prank(alice);
        shares.transfer(bob, 30e18); // Alice now 30, Bob now 70

        vm.roll(block.number + 1);

        bytes memory data = abi.encodeWithSelector(Target.store.selector, 789);
        uint256 h = moloch.proposalId(0, address(target), 0, data, keccak256("defeated-test"));

        moloch.openProposal(h);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        vm.prank(alice);
        moloch.castVote(h, 1); // 30 FOR

        vm.prank(bob);
        moloch.castVote(h, 0); // 70 AGAINST → DEFEATED

        string memory uri = moloch.tokenURI(h);

        console2.log("\n=== DEFEATED PROPOSAL CARD (30 FOR vs 70 AGAINST) ===");
        console2.log("URI:", uri);

        _logDecodedURI(uri);
    }

    function test_visualize_proposal_expired() public {
        // Set TTL
        bytes memory ttlData = abi.encodeWithSelector(Moloch.setProposalTTL.selector, uint64(100));
        uint256 ttlH = moloch.proposalId(0, address(moloch), 0, ttlData, keccak256("set-ttl"));

        moloch.openProposal(ttlH);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        vm.prank(alice);
        moloch.castVote(ttlH, 1);
        vm.prank(bob);
        moloch.castVote(ttlH, 1);

        moloch.executeByVotes(0, address(moloch), 0, ttlData, keccak256("set-ttl"));

        // Create proposal that will expire
        bytes memory data = abi.encodeWithSelector(Target.store.selector, 999);
        uint256 h = moloch.proposalId(0, address(target), 0, data, keccak256("expire-test"));

        moloch.openProposal(h);
        vm.roll(block.number + 1);

        // Wait past TTL
        vm.warp(block.timestamp + 101);

        string memory uri = moloch.tokenURI(h);

        console2.log("\n=== EXPIRED PROPOSAL CARD (TTL exceeded) ===");
        console2.log("URI:", uri);

        _logDecodedURI(uri);
    }

    function test_visualize_proposal_queued() public {
        // Set timelock
        bytes memory tlData = abi.encodeWithSelector(Moloch.setTimelockDelay.selector, uint64(3600));
        uint256 tlH = moloch.proposalId(0, address(moloch), 0, tlData, keccak256("set-tl"));

        moloch.openProposal(tlH);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        vm.prank(alice);
        moloch.castVote(tlH, 1);
        vm.prank(bob);
        moloch.castVote(tlH, 1);

        moloch.executeByVotes(0, address(moloch), 0, tlData, keccak256("set-tl"));

        // Create proposal that will be queued
        bytes memory data = abi.encodeWithSelector(Target.store.selector, 777);
        uint256 h = moloch.proposalId(0, address(target), 0, data, keccak256("queue-test"));

        moloch.openProposal(h);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        vm.prank(alice);
        moloch.castVote(h, 1);
        vm.prank(bob);
        moloch.castVote(h, 1);

        // Queue it (will auto-queue on first execute attempt)
        moloch.queue(h);

        string memory uri = moloch.tokenURI(h);

        console2.log("\n=== QUEUED PROPOSAL CARD (timelock active) ===");
        console2.log("URI:", uri);

        _logDecodedURI(uri);
    }

    function test_visualize_proposal_executed() public {
        bytes memory data = abi.encodeWithSelector(Target.store.selector, 789);
        uint256 h = moloch.proposalId(0, address(target), 0, data, keccak256("executed-test"));

        moloch.openProposal(h);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        vm.prank(alice);
        moloch.castVote(h, 1);
        vm.prank(bob);
        moloch.castVote(h, 1);

        moloch.executeByVotes(0, address(target), 0, data, keccak256("executed-test"));

        string memory uri = moloch.tokenURI(h);

        console2.log("\n=== EXECUTED PROPOSAL CARD ===");
        console2.log("URI:", uri);

        _logDecodedURI(uri);
    }

    function test_visualize_vote_receipt_yes() public {
        bytes memory data = abi.encodeWithSelector(Target.store.selector, 100);
        uint256 h = moloch.proposalId(0, address(target), 0, data, keccak256("receipt-test"));

        moloch.openProposal(h);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        vm.prank(alice);
        moloch.castVote(h, 1); // YES vote

        // Calculate receipt ID for YES vote
        uint256 receiptId = uint256(keccak256(abi.encodePacked("Moloch:receipt", h, uint8(1))));

        string memory uri = moloch.tokenURI(receiptId);

        console2.log("\n=== VOTE RECEIPT - YES ===");
        console2.log("URI:", uri);

        _logDecodedURI(uri);
    }

    function test_visualize_vote_receipt_no() public {
        bytes memory data = abi.encodeWithSelector(Target.store.selector, 200);
        uint256 h = moloch.proposalId(0, address(target), 0, data, keccak256("receipt-no-test"));

        moloch.openProposal(h);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        vm.prank(bob);
        moloch.castVote(h, 0); // NO vote

        uint256 receiptId = uint256(keccak256(abi.encodePacked("Moloch:receipt", h, uint8(0))));

        string memory uri = moloch.tokenURI(receiptId);

        console2.log("\n=== VOTE RECEIPT - NO ===");
        console2.log("URI:", uri);

        _logDecodedURI(uri);
    }

    function test_visualize_vote_receipt_abstain() public {
        bytes memory data = abi.encodeWithSelector(Target.store.selector, 300);
        uint256 h = moloch.proposalId(0, address(target), 0, data, keccak256("receipt-abstain"));

        moloch.openProposal(h);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        vm.prank(alice);
        moloch.castVote(h, 2); // ABSTAIN vote

        uint256 receiptId = uint256(keccak256(abi.encodePacked("Moloch:receipt", h, uint8(2))));

        string memory uri = moloch.tokenURI(receiptId);

        console2.log("\n=== VOTE RECEIPT - ABSTAIN ===");
        console2.log("URI:", uri);

        _logDecodedURI(uri);
    }

    function test_visualize_vote_receipt_with_futarchy() public {
        bytes memory call = abi.encodeWithSelector(Target.store.selector, 888);
        uint256 h = moloch.proposalId(0, address(target), 0, call, keccak256("fut-receipt"));

        // Fund futarchy
        vm.deal(address(this), 100 ether);
        moloch.fundFutarchy{value: 100 ether}(h, address(0), 100 ether);

        moloch.openProposal(h);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        vm.prank(alice);
        moloch.castVote(h, 1);
        vm.prank(bob);
        moloch.castVote(h, 1);

        // Execute to resolve futarchy
        moloch.executeByVotes(0, address(target), 0, call, keccak256("fut-receipt"));

        uint256 receiptId = uint256(keccak256(abi.encodePacked("Moloch:receipt", h, uint8(1))));

        string memory uri = moloch.tokenURI(receiptId);

        console2.log("\n=== VOTE RECEIPT - WITH FUTARCHY (REDEEMABLE) ===");
        console2.log("URI:", uri);

        _logDecodedURI(uri);
    }

    function test_visualize_permit_active() public {
        bytes memory call = abi.encodeWithSelector(Target.store.selector, 555);
        bytes32 nonce = keccak256("permit-viz");

        // Set permit via governance
        bytes memory data = abi.encodeWithSelector(
            Moloch.setPermit.selector,
            0,
            address(target),
            0,
            call,
            nonce,
            charlie,
            5 // 5 uses
        );

        uint256 govH = moloch.proposalId(0, address(moloch), 0, data, keccak256("set-permit"));

        moloch.openProposal(govH);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        vm.prank(alice);
        moloch.castVote(govH, 1);
        vm.prank(bob);
        moloch.castVote(govH, 1);

        moloch.executeByVotes(0, address(moloch), 0, data, keccak256("set-permit"));

        // Get permit ID
        uint256 permitId = moloch.proposalId(0, address(target), 0, call, nonce);

        string memory uri = moloch.tokenURI(permitId);

        console2.log("\n=== PERMIT CARD - ACTIVE (5 uses) ===");
        console2.log("URI:", uri);

        _logDecodedURI(uri);
    }

    function test_visualize_permit_unlimited() public {
        bytes memory call = abi.encodeWithSelector(Target.store.selector, 999);
        bytes32 nonce = keccak256("permit-unlimited");

        bytes memory data = abi.encodeWithSelector(
            Moloch.setPermit.selector,
            0,
            address(target),
            0,
            call,
            nonce,
            charlie,
            type(uint256).max // unlimited
        );

        uint256 govH = moloch.proposalId(0, address(moloch), 0, data, keccak256("set-unlimited"));

        moloch.openProposal(govH);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        vm.prank(alice);
        moloch.castVote(govH, 1);
        vm.prank(bob);
        moloch.castVote(govH, 1);

        moloch.executeByVotes(0, address(moloch), 0, data, keccak256("set-unlimited"));

        uint256 permitId = moloch.proposalId(0, address(target), 0, call, nonce);

        string memory uri = moloch.tokenURI(permitId);

        console2.log("\n=== PERMIT CARD - UNLIMITED ===");
        console2.log("URI:", uri);

        _logDecodedURI(uri);
    }

    function test_visualize_member_badge_alice() public {
        // Trigger badge minting by doing a transfer
        vm.prank(alice);
        shares.transfer(bob, 1);
        vm.prank(bob);
        shares.transfer(alice, 1);

        // Alice should have a seat now
        uint256 aliceSeat = badge.seatOf(alice);
        require(aliceSeat > 0, "Alice should have a badge");

        string memory uri = badge.tokenURI(aliceSeat);

        console2.log("\n=== MEMBER BADGE - ALICE (60% ownership, Seat", aliceSeat, ") ===");
        console2.log("URI:", uri);

        _logDecodedURI(uri);
    }

    function test_visualize_member_badge_bob() public {
        // Trigger badge minting
        vm.prank(alice);
        shares.transfer(bob, 1);
        vm.prank(bob);
        shares.transfer(alice, 1);

        uint256 bobSeat = badge.seatOf(bob);
        require(bobSeat > 0, "Bob should have a badge");

        string memory uri = badge.tokenURI(bobSeat);

        console2.log("\n=== MEMBER BADGE - BOB (40% ownership, Seat", bobSeat, ") ===");
        console2.log("URI:", uri);

        _logDecodedURI(uri);
    }

    function test_visualize_member_badge_whale() public {
        // Enable sale with a price (required when active=true)
        bytes memory saleData = abi.encodeWithSelector(
            Moloch.setSale.selector,
            address(0), // payToken (ETH)
            1, // price per share (1 wei per share)
            1000e18, // cap
            true, // minting
            true, // active
            false // isLoot
        );

        uint256 saleH = moloch.proposalId(0, address(moloch), 0, saleData, keccak256("sale"));

        moloch.openProposal(saleH);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        vm.prank(alice);
        moloch.castVote(saleH, 1);
        vm.prank(bob);
        moloch.castVote(saleH, 1);

        moloch.executeByVotes(0, address(moloch), 0, saleData, keccak256("sale"));

        // Make sure Charlie has enough funds
        vm.deal(charlie, 1000 ether);

        // Charlie becomes a whale - buy 500e18 shares for 500e18 wei (0.5 ether)
        vm.prank(charlie);
        moloch.buyShares{value: 500e18}(address(0), 500e18, 0);

        // Trigger badge minting
        vm.prank(charlie);
        shares.transfer(alice, 1);
        vm.prank(alice);
        shares.transfer(charlie, 1);

        uint256 charlieSeat = badge.seatOf(charlie);
        require(charlieSeat > 0, "Charlie should have a badge");

        string memory uri = badge.tokenURI(charlieSeat);

        console2.log(
            "\n=== MEMBER BADGE - WHALE (500 shares, 83.33% ownership, Seat", charlieSeat, ") ==="
        );
        console2.log("URI:", uri);

        _logDecodedURI(uri);
    }

    function test_visualize_all_states_comprehensive() public {
        console2.log("\n\n========================================");
        console2.log("   COMPREHENSIVE URI VISUALIZATION");
        console2.log("     ALL PROPOSAL STATES");
        console2.log("========================================\n");

        // 1. Unopened Proposal
        bytes memory data1 = abi.encodeWithSelector(Target.store.selector, 1);
        uint256 h1 = moloch.proposalId(0, address(target), 0, data1, keccak256("state1"));
        _printCard("1. UNOPENED PROPOSAL", moloch.tokenURI(h1));

        // 2. Active Proposal (raise quorum first so partial votes = active)
        bytes memory quorumData = abi.encodeWithSelector(Moloch.setQuorumBps.selector, uint16(8000));
        uint256 qH = moloch.proposalId(0, address(moloch), 0, quorumData, keccak256("set-quorum"));
        moloch.openProposal(qH);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.prank(alice);
        moloch.castVote(qH, 1);
        vm.prank(bob);
        moloch.castVote(qH, 1);
        moloch.executeByVotes(0, address(moloch), 0, quorumData, keccak256("set-quorum"));

        bytes memory data2 = abi.encodeWithSelector(Target.store.selector, 2);
        uint256 h2 = moloch.proposalId(0, address(target), 0, data2, keccak256("state2"));
        moloch.openProposal(h2);
        vm.roll(block.number + 1);
        vm.prank(alice);
        moloch.castVote(h2, 1); // 60%, need 80%
        _printCard("2. ACTIVE PROPOSAL (need more votes)", moloch.tokenURI(h2));

        // 3. Succeeded Proposal
        bytes memory data3 = abi.encodeWithSelector(Target.store.selector, 3);
        uint256 h3 = moloch.proposalId(0, address(target), 0, data3, keccak256("state3"));
        moloch.openProposal(h3);
        vm.roll(block.number + 1);
        vm.prank(alice);
        moloch.castVote(h3, 1);
        vm.prank(bob);
        moloch.castVote(h3, 1); // Now 100% voted, exceeds 80% quorum
        _printCard("3. SUCCEEDED PROPOSAL", moloch.tokenURI(h3));

        // 4. Defeated Proposal
        vm.prank(alice);
        shares.transfer(bob, 30e18); // Bob now has 70
        vm.roll(block.number + 1);

        bytes memory data4 = abi.encodeWithSelector(Target.store.selector, 4);
        uint256 h4 = moloch.proposalId(0, address(target), 0, data4, keccak256("state4"));
        moloch.openProposal(h4);
        vm.roll(block.number + 1);
        vm.prank(alice);
        moloch.castVote(h4, 1); // 30 FOR
        vm.prank(bob);
        moloch.castVote(h4, 0); // 70 AGAINST
        _printCard("4. DEFEATED PROPOSAL (30 FOR vs 70 AGAINST)", moloch.tokenURI(h4));

        // Restore balance
        vm.prank(bob);
        shares.transfer(alice, 30e18);
        vm.roll(block.number + 1);

        // 5. Queued Proposal (with timelock)
        bytes memory tlData = abi.encodeWithSelector(Moloch.setTimelockDelay.selector, uint64(3600));
        uint256 tlH = moloch.proposalId(0, address(moloch), 0, tlData, keccak256("tl"));
        moloch.openProposal(tlH);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.prank(alice);
        moloch.castVote(tlH, 1);
        vm.prank(bob);
        moloch.castVote(tlH, 1);
        moloch.executeByVotes(0, address(moloch), 0, tlData, keccak256("tl"));

        bytes memory data5 = abi.encodeWithSelector(Target.store.selector, 5);
        uint256 h5 = moloch.proposalId(0, address(target), 0, data5, keccak256("state5"));
        moloch.openProposal(h5);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.prank(alice);
        moloch.castVote(h5, 1);
        vm.prank(bob);
        moloch.castVote(h5, 1);
        moloch.queue(h5);
        _printCard("5. QUEUED PROPOSAL (timelock)", moloch.tokenURI(h5));

        // 6. Expired Proposal (with TTL)
        bytes memory ttlData = abi.encodeWithSelector(Moloch.setProposalTTL.selector, uint64(100));
        uint256 ttlH2 = moloch.proposalId(0, address(moloch), 0, ttlData, keccak256("ttl"));
        moloch.openProposal(ttlH2);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.prank(alice);
        moloch.castVote(ttlH2, 1);
        vm.prank(bob);
        moloch.castVote(ttlH2, 1);
        moloch.executeByVotes(0, address(moloch), 0, ttlData, keccak256("ttl"));

        bytes memory data6 = abi.encodeWithSelector(Target.store.selector, 6);
        uint256 h6 = moloch.proposalId(0, address(target), 0, data6, keccak256("state6"));
        moloch.openProposal(h6);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 101); // Past TTL
        _printCard("6. EXPIRED PROPOSAL (TTL exceeded)", moloch.tokenURI(h6));

        // 7. Executed Proposal
        vm.warp(block.timestamp - 101); // Reset time
        bytes memory data7 = abi.encodeWithSelector(Target.store.selector, 7);
        uint256 h7 = moloch.proposalId(0, address(target), 0, data7, keccak256("state7"));
        moloch.openProposal(h7);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.prank(alice);
        moloch.castVote(h7, 1);
        vm.prank(bob);
        moloch.castVote(h7, 1);
        moloch.executeByVotes(0, address(target), 0, data7, keccak256("state7"));
        _printCard("7. EXECUTED PROPOSAL", moloch.tokenURI(h7));

        // 8. Vote Receipt (YES)
        uint256 receipt7 = uint256(keccak256(abi.encodePacked("Moloch:receipt", h7, uint8(1))));
        _printCard("8. VOTE RECEIPT - YES", moloch.tokenURI(receipt7));

        // 9. Vote Receipt (NO)
        uint256 receipt4 = uint256(keccak256(abi.encodePacked("Moloch:receipt", h4, uint8(0))));
        _printCard("9. VOTE RECEIPT - NO", moloch.tokenURI(receipt4));

        // 10. Vote Receipt (ABSTAIN)
        bytes memory data10 = abi.encodeWithSelector(Target.store.selector, 10);
        uint256 h10 = moloch.proposalId(0, address(target), 0, data10, keccak256("abstain"));
        moloch.openProposal(h10);
        vm.roll(block.number + 1);
        vm.prank(alice);
        moloch.castVote(h10, 2); // ABSTAIN
        uint256 receipt10 = uint256(keccak256(abi.encodePacked("Moloch:receipt", h10, uint8(2))));
        _printCard("10. VOTE RECEIPT - ABSTAIN", moloch.tokenURI(receipt10));

        // 11. Member Badge - trigger badge minting first
        vm.prank(alice);
        shares.transfer(bob, 1);
        vm.prank(bob);
        shares.transfer(alice, 1);

        uint256 aliceSeat = badge.seatOf(alice);
        require(aliceSeat > 0, "Alice should have a badge");
        _printCard("11. MEMBER BADGE (Alice)", badge.tokenURI(aliceSeat));

        console2.log("\n========================================");
        console2.log("   ALL STATES CAPTURED");
        console2.log("========================================\n");
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _logDecodedURI(string memory uri) internal pure {
        // Extract and log base64 data
        bytes memory uriBytes = bytes(uri);

        // Find where base64 starts (after "base64,")
        uint256 dataStart = 0;
        for (uint256 i = 0; i < uriBytes.length - 7; i++) {
            if (
                uriBytes[i] == "b" && uriBytes[i + 1] == "a" && uriBytes[i + 2] == "s"
                    && uriBytes[i + 3] == "e" && uriBytes[i + 4] == "6" && uriBytes[i + 5] == "4"
                    && uriBytes[i + 6] == ","
            ) {
                dataStart = i + 7;
                break;
            }
        }

        if (dataStart > 0) {
            console2.log("\n--- EXTRACTION GUIDE ---");
            console2.log("To view this card:");
            console2.log("1. Copy the full URI above");
            console2.log("2. Paste into browser address bar (renders instantly)");
            console2.log("3. Or decode base64 to get JSON with embedded SVG");
            console2.log("");
            console2.log("The URI contains:");
            console2.log("- JSON metadata (name, description)");
            console2.log("- Embedded SVG image (as data URI)");
            console2.log("");
            console2.log("Decoded structure will be:");
            console2.log("{");
            console2.log('  "name": "...",');
            console2.log('  "description": "...",');
            console2.log('  "image": "data:image/svg+xml;base64,<SVG_BASE64>"');
            console2.log("}");
            console2.log("");
            console2.log("To extract just the SVG:");
            console2.log("1. Decode the main base64 to get JSON");
            console2.log("2. Extract the 'image' field value");
            console2.log("3. That's another data URI - decode that base64 to get raw SVG");
            console2.log("4. Save as .svg file or paste into any SVG viewer");
            console2.log("");
            console2.log("Quick online tools:");
            console2.log("- base64decode.org");
            console2.log("- base64.guru/converter/decode/image/svg");
            console2.log("------------------------\n");
        }
    }

    function _printCard(string memory title, string memory uri) internal pure {
        console2.log("\n----------------------------------------");
        console2.log(title);
        console2.log("----------------------------------------");
        console2.log("URI:", uri);
        console2.log("");
    }
}

contract Target {
    uint256 public stored;

    function store(uint256 x) public {
        stored = x;
    }
}
