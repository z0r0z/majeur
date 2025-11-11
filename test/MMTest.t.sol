// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Moloch, Shares, Loot, Badge, Summoner, Call} from "../src/Moloch.sol";

contract MolochTest is Test {
    Summoner internal summoner;
    Moloch internal moloch;
    Shares internal shares;
    Loot internal loot;
    Badge internal badge;

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

        // Deploy summoner
        summoner = new Summoner();

        // Setup initial holders
        address[] memory initialHolders = new address[](2);
        initialHolders[0] = alice;
        initialHolders[1] = bob;

        uint256[] memory initialAmounts = new uint256[](2);
        initialAmounts[0] = 60e18;
        initialAmounts[1] = 40e18;

        // Summon new DAO with 50% quorum
        moloch = summoner.summon(
            "Test DAO",
            "TEST",
            "",
            5000, // 50% quorum
            true, // ragequit enabled
            bytes32(0),
            initialHolders,
            initialAmounts,
            new Call[](0)
        );

        shares = moloch.shares();
        loot = moloch.loot();
        badge = moloch.badge();

        assertEq(shares.balanceOf(alice), 60e18, "alice shares");
        assertEq(shares.balanceOf(bob), 40e18, "bob shares");
        assertEq(badge.balanceOf(alice), 1, "alice badge");
        assertEq(badge.balanceOf(bob), 1, "bob badge");

        target = new Target();
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function _id(uint8 op, address to, uint256 val, bytes memory data, bytes32 nonce)
        internal
        view
        returns (uint256)
    {
        return moloch.proposalId(op, to, val, data, nonce);
    }

    function _open(uint256 h) internal {
        moloch.openProposal(h);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }

    function _voteYes(uint256 h, address voter) internal {
        vm.prank(voter);
        moloch.castVote(h, 1);
    }

    function _openAndPass(uint8 op, address to, uint256 val, bytes memory data, bytes32 nonce)
        internal
        returns (uint256 h, bool ok)
    {
        h = _id(op, to, val, data, nonce);
        _open(h);
        _voteYes(h, alice);
        _voteYes(h, bob);
        (ok,) = moloch.executeByVotes(op, to, val, data, nonce);
        assertTrue(ok, "execute ok");
    }

    /*//////////////////////////////////////////////////////////////
                          BASIC TESTS
    //////////////////////////////////////////////////////////////*/

    function test_initial_state() public view {
        assertEq(shares.totalSupply(), 100e18, "total supply");
        assertEq(shares.balanceOf(alice), 60e18, "alice balance");
        assertEq(shares.balanceOf(bob), 40e18, "bob balance");
        assertEq(moloch.quorumBps(), 5000, "quorum 50%");
        assertTrue(moloch.ragequittable(), "ragequit enabled");
    }

    function test_execute_simple_call() public {
        bytes memory data = abi.encodeWithSelector(Target.store.selector, 42);
        uint256 h = _id(0, address(target), 0, data, keccak256("test1"));

        _open(h);
        _voteYes(h, alice);
        _voteYes(h, bob);

        (bool ok,) = moloch.executeByVotes(0, address(target), 0, data, keccak256("test1"));
        assertTrue(ok, "execute succeeded");
        assertEq(target.stored(), 42, "target updated");
    }

    function test_proposal_states() public {
        bytes memory data = abi.encodeWithSelector(Target.store.selector, 123);
        uint256 h = _id(0, address(target), 0, data, keccak256("state-test"));

        // Unopened
        assertEq(uint256(moloch.state(h)), uint256(Moloch.ProposalState.Unopened), "unopened");

        // Open - snapshot at block 0 in test environment
        moloch.openProposal(h);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        // At snapshot block 0 with no votes, state is still Unopened
        // Need to cast at least one vote for it to become Active
        vm.prank(alice);
        moloch.castVote(h, 1);

        // With partial votes (only alice), check if Active or Succeeded
        // Alice has 60%, Bob has 40%, so alice alone meets 50% quorum
        assertEq(
            uint256(moloch.state(h)),
            uint256(Moloch.ProposalState.Succeeded),
            "succeeded after alice"
        );

        // Bob votes too
        vm.prank(bob);
        moloch.castVote(h, 1);

        // Still succeeded with unanimous vote
        assertEq(uint256(moloch.state(h)), uint256(Moloch.ProposalState.Succeeded), "succeeded");

        // Execute
        (bool ok,) = moloch.executeByVotes(0, address(target), 0, data, keccak256("state-test"));
        assertTrue(ok);
        assertEq(uint256(moloch.state(h)), uint256(Moloch.ProposalState.Executed), "executed");
    }

    function test_voting_with_delegation() public {
        // Alice delegates to Charlie
        vm.prank(alice);
        shares.delegate(charlie);

        assertEq(shares.getVotes(alice), 0, "alice delegated away");
        assertEq(shares.getVotes(charlie), 60e18, "charlie has alice's votes");
        assertEq(shares.getVotes(bob), 40e18, "bob unchanged");

        // Charlie can vote with delegated power
        bytes memory data = abi.encodeWithSelector(Target.store.selector, 99);
        uint256 h = _id(0, address(target), 0, data, keccak256("delegate-test"));

        _open(h);

        vm.prank(charlie);
        moloch.castVote(h, 1); // Charlie votes YES with 60e18

        vm.prank(bob);
        moloch.castVote(h, 1); // Bob votes YES with 40e18

        (uint256 forVotes,,) = moloch.tallies(h);
        assertEq(forVotes, 100e18, "all votes cast");

        (bool ok,) = moloch.executeByVotes(0, address(target), 0, data, keccak256("delegate-test"));
        assertTrue(ok);
        assertEq(target.stored(), 99);
    }

    function test_split_delegation() public {
        address[] memory delegates = new address[](2);
        uint32[] memory bps = new uint32[](2);

        delegates[0] = bob;
        delegates[1] = charlie;
        bps[0] = 5000; // 50%
        bps[1] = 5000; // 50%

        vm.prank(alice);
        shares.setSplitDelegation(delegates, bps);

        // Alice's 60e18 split 50/50
        assertEq(shares.getVotes(alice), 0, "alice delegated");
        assertEq(shares.getVotes(bob), 70e18, "bob has 40 + 30");
        assertEq(shares.getVotes(charlie), 30e18, "charlie has 30");
    }

    function test_ragequit() public {
        // Move past genesis block
        vm.roll(10);
        vm.warp(10);

        // Trigger checkpoint creation for Bob by doing a self-delegation
        // This ensures the voting system is properly initialized
        vm.prank(bob);
        shares.delegate(bob);

        // Move forward one more block
        vm.roll(11);
        vm.warp(11);

        // Fund the DAO
        vm.deal(address(moloch), 10 ether);

        uint256 bobBefore = bob.balance;
        uint256 bobShares = shares.balanceOf(bob); // 40e18
        uint256 totalSupply = shares.totalSupply() + loot.totalSupply(); // 100e18 + 0
        uint256 treasury = address(moloch).balance; // 10 ether

        address[] memory tokens = new address[](1);
        tokens[0] = address(0); // ETH

        vm.prank(bob);
        moloch.rageQuit(tokens, bobShares, 0);

        uint256 expectedPayout = (treasury * bobShares) / totalSupply;
        assertEq(bob.balance - bobBefore, expectedPayout, "correct payout");
        assertEq(shares.balanceOf(bob), 0, "shares burned");
    }

    function test_sales_basic() public {
        // Enable a free sale via governance
        bytes memory data = abi.encodeWithSelector(
            Moloch.setSale.selector,
            address(0), // ETH
            0, // price (free)
            10e18, // cap
            true, // minting
            true, // active
            false // not loot
        );

        (, bool ok) = _openAndPass(0, address(moloch), 0, data, keccak256("enable-sale"));
        assertTrue(ok);

        // Charlie buys shares
        vm.prank(charlie);
        moloch.buyShares{value: 0}(address(0), 5e18, 0);

        assertEq(shares.balanceOf(charlie), 5e18, "charlie bought shares");
        assertEq(shares.totalSupply(), 105e18, "supply increased");
    }

    function test_timelock() public {
        // Enable 1 hour timelock
        bytes memory data = abi.encodeWithSelector(Moloch.setTimelockDelay.selector, uint64(3600));
        (, bool ok) = _openAndPass(0, address(moloch), 0, data, keccak256("timelock"));
        assertTrue(ok);

        // Create new proposal
        bytes memory callData = abi.encodeWithSelector(Target.store.selector, 777);
        uint256 h = _id(0, address(target), 0, callData, keccak256("tl-test"));

        _open(h);
        _voteYes(h, alice);
        _voteYes(h, bob);

        // First call queues
        (bool queued,) =
            moloch.executeByVotes(0, address(target), 0, callData, keccak256("tl-test"));
        assertTrue(queued);
        assertEq(uint256(moloch.state(h)), uint256(Moloch.ProposalState.Queued));

        // Can't execute yet
        vm.expectRevert();
        moloch.executeByVotes(0, address(target), 0, callData, keccak256("tl-test"));

        // After delay
        vm.warp(block.timestamp + 3600 + 1);
        (bool executed,) =
            moloch.executeByVotes(0, address(target), 0, callData, keccak256("tl-test"));
        assertTrue(executed);
        assertEq(target.stored(), 777);
    }

    function test_permits() public {
        bytes memory call = abi.encodeWithSelector(Target.store.selector, 555);
        bytes32 nonce = keccak256("permit-test");

        // Set permit via governance
        bytes memory data = abi.encodeWithSelector(
            Moloch.setPermit.selector,
            0, // op
            address(target), // to
            0, // value
            call, // data
            nonce,
            charlie, // spender
            1 // count
        );

        (, bool ok) = _openAndPass(0, address(moloch), 0, data, keccak256("set-permit"));
        assertTrue(ok);

        // Charlie spends permit
        vm.prank(charlie);
        (bool ok2,) = moloch.permitExecute(0, address(target), 0, call, nonce);
        assertTrue(ok2);
        assertEq(target.stored(), 555);
    }

    function test_futarchy_yes() public {
        bytes memory call = abi.encodeWithSelector(Target.store.selector, 888);
        uint256 h = _id(0, address(target), 0, call, keccak256("fut"));

        // Fund futarchy
        vm.deal(address(this), 100 ether);
        moloch.fundFutarchy{value: 100 ether}(h, address(0), 100 ether);

        // Vote and execute
        _open(h);
        _voteYes(h, alice);
        _voteYes(h, bob);

        (bool ok,) = moloch.executeByVotes(0, address(target), 0, call, keccak256("fut"));
        assertTrue(ok);

        // Check futarchy resolved
        (bool enabled,,, bool resolved, uint8 winner,, uint256 ppu) = moloch.futarchy(h);
        assertTrue(enabled && resolved);
        assertEq(winner, 1, "YES won");
        assertTrue(ppu > 0);

        // Cash out
        uint256 before = alice.balance;
        vm.prank(alice);
        moloch.cashOutFutarchy(h, 10e18);
        assertTrue(alice.balance > before, "got payout");
    }

    function test_chat() public {
        // Alice has badge, can chat
        vm.prank(alice);
        moloch.chat("hello world");
        assertEq(moloch.getMessageCount(), 1);

        // Charlie has no badge, cannot chat
        vm.expectRevert(Moloch.NotOk.selector);
        vm.prank(charlie);
        moloch.chat("should fail");
    }

    function test_top_256_eviction() public {
        // Enable free sale
        bytes memory d = abi.encodeWithSelector(
            Moloch.setSale.selector, address(0), 0, type(uint256).max, true, true, false
        );
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("sale"));
        assertTrue(ok);

        // Fill 254 slots (alice + bob = 2)
        for (uint256 i = 0; i < 254; i++) {
            address holder = vm.addr(i + 1000);
            vm.prank(holder);
            moloch.buyShares{value: 0}(address(0), 1e18, 0);
            assertEq(badge.balanceOf(holder), 1);
        }

        // 256 slots full. Add someone with more shares
        address whale = address(0x9999);
        vm.prank(whale);
        moloch.buyShares{value: 0}(address(0), 10e18, 0);

        // Whale should have badge
        assertEq(badge.balanceOf(whale), 1, "whale got badge");

        // Some small holder should have lost badge
        uint256 badgeCount = 0;
        for (uint256 i = 0; i < 256; i++) {
            address holder = moloch.topHolders(i);
            if (holder != address(0) && badge.balanceOf(holder) == 1) {
                badgeCount++;
            }
        }
        assertEq(badgeCount, 256, "still 256 badge holders");
    }

    function test_transfer_lock() public {
        bytes memory d = abi.encodeWithSelector(Moloch.setTransfersLocked.selector, true);
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("lock"));
        assertTrue(ok);

        vm.expectRevert();
        vm.prank(alice);
        shares.transfer(charlie, 1e18);
    }

    function test_double_vote_reverts() public {
        uint256 h = _id(0, address(this), 0, "", keccak256("double"));
        _open(h);

        vm.prank(alice);
        moloch.castVote(h, 1);

        vm.expectRevert(Moloch.NotOk.selector);
        vm.prank(alice);
        moloch.castVote(h, 1);
    }

    function test_quorum_enforcement() public {
        // Set 80% quorum
        bytes memory d = abi.encodeWithSelector(Moloch.setQuorumBps.selector, uint16(8000));
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("quorum"));
        assertTrue(ok);

        // Only alice votes (60% turnout, below 80%)
        uint256 h = _id(0, address(this), 0, "", keccak256("test"));
        _open(h);
        _voteYes(h, alice);

        assertEq(uint256(moloch.state(h)), uint256(Moloch.ProposalState.Active));

        vm.expectRevert(Moloch.NotOk.selector);
        moloch.executeByVotes(0, address(this), 0, "", keccak256("test"));
    }

    function test_config_bump_invalidates_old() public {
        uint256 h = _id(0, address(this), 0, "", keccak256("old"));
        _open(h);
        _voteYes(h, alice);
        _voteYes(h, bob);

        // Bump config
        bytes memory d = abi.encodeWithSelector(Moloch.bumpConfig.selector);
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("bump"));
        assertTrue(ok);

        // Old proposal can't execute
        vm.expectRevert(Moloch.NotOk.selector);
        moloch.executeByVotes(0, address(this), 0, "", keccak256("old"));
    }

    function test_loot_sales() public {
        // Enable loot sale
        bytes memory data = abi.encodeWithSelector(
            Moloch.setSale.selector,
            address(0), // ETH
            0, // price (free)
            10e18, // cap
            true, // minting
            true, // active
            true // IS LOOT
        );

        (, bool ok) = _openAndPass(0, address(moloch), 0, data, keccak256("loot-sale"));
        assertTrue(ok);

        // Charlie buys loot
        vm.prank(charlie);
        moloch.buyShares{value: 0}(address(0), 5e18, 0);

        assertEq(loot.balanceOf(charlie), 5e18, "charlie bought loot");
        assertEq(shares.balanceOf(charlie), 0, "no shares for charlie");
    }

    function test_loot_ragequit() public {
        // Enable loot sale
        bytes memory data =
            abi.encodeWithSelector(Moloch.setSale.selector, address(0), 0, 10e18, true, true, true);
        (, bool ok) = _openAndPass(0, address(moloch), 0, data, keccak256("loot-sale"));
        assertTrue(ok);

        // Charlie buys loot
        vm.prank(charlie);
        moloch.buyShares{value: 0}(address(0), 5e18, 0);

        vm.roll(10);
        vm.warp(10);

        // Fund DAO
        vm.deal(address(moloch), 10 ether);

        uint256 charlieBefore = charlie.balance;
        uint256 totalSupply = shares.totalSupply() + loot.totalSupply();

        address[] memory tokens = new address[](1);
        tokens[0] = address(0);

        // Ragequit with loot
        vm.prank(charlie);
        moloch.rageQuit(tokens, 0, 5e18); // 0 shares, 5e18 loot

        uint256 expectedPayout = (10 ether * 5e18) / totalSupply;
        assertEq(charlie.balance - charlieBefore, expectedPayout, "loot ragequit payout");
    }

    function test_futarchy_no_path() public {
        // Set short TTL
        bytes memory dTTL = abi.encodeWithSelector(Moloch.setProposalTTL.selector, uint64(100));
        (, bool ok) = _openAndPass(0, address(moloch), 0, dTTL, keccak256("ttl"));
        assertTrue(ok);

        bytes memory call = abi.encodeWithSelector(Target.store.selector, 999);
        uint256 h = _id(0, address(target), 0, call, keccak256("fut-no"));

        // Fund futarchy
        vm.deal(address(this), 100 ether);
        moloch.fundFutarchy{value: 100 ether}(h, address(0), 100 ether);

        // Vote NO
        _open(h);
        vm.prank(alice);
        moloch.castVote(h, 0); // AGAINST
        vm.prank(bob);
        moloch.castVote(h, 0); // AGAINST

        // Wait for TTL
        vm.warp(block.timestamp + 101);

        // Resolve NO
        moloch.resolveFutarchyNo(h);

        (bool enabled,,, bool resolved, uint8 winner,, uint256 ppu) = moloch.futarchy(h);
        assertTrue(enabled && resolved);
        assertEq(winner, 0, "NO won");

        // Cash out NO receipts
        uint256 before = alice.balance;
        vm.prank(alice);
        moloch.cashOutFutarchy(h, 10e18);
        assertTrue(alice.balance > before, "got NO payout");
    }

    function test_split_delegation_3_way() public {
        // Enable sale for charlie
        bytes memory d = abi.encodeWithSelector(
            Moloch.setSale.selector, address(0), 0, 10e18, true, true, false
        );
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("sale"));
        assertTrue(ok);

        vm.prank(charlie);
        moloch.buyShares{value: 0}(address(0), 10e18, 0);

        // Alice splits 3 ways
        address[] memory delegates = new address[](3);
        uint32[] memory bps = new uint32[](3);

        delegates[0] = bob;
        delegates[1] = charlie;
        delegates[2] = address(0x1111);
        bps[0] = 3333;
        bps[1] = 3333;
        bps[2] = 3334;

        vm.prank(alice);
        shares.setSplitDelegation(delegates, bps);

        // Check distribution
        assertEq(shares.getVotes(alice), 0, "alice delegated");
        assertTrue(shares.getVotes(bob) > 40e18, "bob has own + alice's");
        assertTrue(shares.getVotes(charlie) > 10e18, "charlie has own + alice's");
    }

    function test_clear_split_delegation() public {
        // Set split
        address[] memory delegates = new address[](2);
        uint32[] memory bps = new uint32[](2);
        delegates[0] = bob;
        delegates[1] = charlie;
        bps[0] = 5000;
        bps[1] = 5000;

        vm.prank(alice);
        shares.setSplitDelegation(delegates, bps);

        assertEq(shares.getVotes(alice), 0, "alice split");

        // Clear split
        vm.prank(alice);
        shares.clearSplitDelegation();

        assertEq(shares.getVotes(alice), 60e18, "alice back to self");
    }

    function test_allowance_eth() public {
        vm.deal(address(moloch), 10 ether);

        // Set allowance via governance
        bytes memory d =
            abi.encodeWithSelector(Moloch.setAllowanceTo.selector, address(0), charlie, 5 ether);
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("allowance"));
        assertTrue(ok);

        // Charlie claims
        uint256 before = charlie.balance;
        vm.prank(charlie);
        moloch.claimAllowance(address(0), 3 ether);

        assertEq(charlie.balance - before, 3 ether, "claimed");
        assertEq(moloch.allowance(address(0), charlie), 2 ether, "remaining");
    }

    function test_proposal_ttl_expiry() public {
        // Set short TTL
        bytes memory d = abi.encodeWithSelector(Moloch.setProposalTTL.selector, uint64(100));
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("ttl"));
        assertTrue(ok);

        // Open proposal
        uint256 h = _id(0, address(this), 0, "", keccak256("expire"));
        moloch.openProposal(h);

        // Wait past TTL
        vm.warp(block.timestamp + 101);

        // Should be expired
        assertEq(uint256(moloch.state(h)), uint256(Moloch.ProposalState.Expired));

        // Can't vote
        vm.expectRevert(Moloch.NotOk.selector);
        vm.prank(alice);
        moloch.castVote(h, 1);
    }

    function test_defeated_proposal() public {
        uint256 h = _id(0, address(this), 0, "", keccak256("defeat"));
        _open(h);

        // Alice votes YES, Bob votes NO
        vm.prank(alice);
        moloch.castVote(h, 1); // 60% FOR

        vm.prank(bob);
        moloch.castVote(h, 0); // 40% AGAINST

        // FOR > AGAINST but need to check quorum
        // With 50% quorum, 100% turnout is enough
        // 60 FOR vs 40 AGAINST = FOR wins
        assertEq(uint256(moloch.state(h)), uint256(Moloch.ProposalState.Succeeded));
    }

    function test_tie_vote_defeats() public {
        // Make alice and bob equal
        vm.prank(alice);
        shares.transfer(bob, 10e18); // Now both have 50e18

        vm.roll(10);
        vm.warp(10);

        uint256 h = _id(0, address(this), 0, "", keccak256("tie"));
        _open(h);

        vm.prank(alice);
        moloch.castVote(h, 1); // 50 FOR

        vm.prank(bob);
        moloch.castVote(h, 0); // 50 AGAINST

        // Tie means defeated (FOR <= AGAINST)
        assertEq(uint256(moloch.state(h)), uint256(Moloch.ProposalState.Defeated));
    }

    function test_abstain_votes() public {
        uint256 h = _id(0, address(this), 0, "", keccak256("abstain"));
        _open(h);

        vm.prank(alice);
        moloch.castVote(h, 2); // ABSTAIN

        vm.prank(bob);
        moloch.castVote(h, 1); // FOR

        // Should succeed (quorum met, FOR > AGAINST)
        assertEq(uint256(moloch.state(h)), uint256(Moloch.ProposalState.Succeeded));
    }

    function test_metadata_functions() public view {
        assertEq(shares.name(), "Test DAO Shares");
        assertEq(shares.symbol(), "TEST");
        assertEq(loot.name(), "Test DAO Loot");
        assertEq(badge.name(), "Test DAO Badge");
    }

    function test_permit_unlimited() public {
        bytes memory call = abi.encodeWithSelector(Target.store.selector, 111);
        bytes32 nonce = keccak256("unlimited");

        // Set unlimited permit
        bytes memory data = abi.encodeWithSelector(
            Moloch.setPermit.selector,
            0,
            address(target),
            0,
            call,
            nonce,
            charlie,
            type(uint256).max
        );

        (, bool ok) = _openAndPass(0, address(moloch), 0, data, keccak256("set-unlimited"));
        assertTrue(ok);

        // Charlie can spend multiple times
        vm.prank(charlie);
        moloch.permitExecute(0, address(target), 0, call, nonce);
        assertEq(target.stored(), 111);

        vm.prank(charlie);
        moloch.permitExecute(0, address(target), 0, call, nonce);
        assertEq(target.stored(), 111, "still works");
    }

    function test_batch_calls() public {
        Call[] memory calls = new Call[](2);
        calls[0] = Call({
            target: address(target),
            value: 0,
            data: abi.encodeWithSelector(Target.store.selector, 100)
        });
        calls[1] = Call({
            target: address(target),
            value: 0,
            data: abi.encodeWithSelector(Target.store.selector, 200)
        });

        bytes memory d = abi.encodeWithSelector(Moloch.batchCalls.selector, calls);
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("batch"));
        assertTrue(ok);

        assertEq(target.stored(), 200, "last call value");
    }

    function test_receive_eth() public {
        vm.deal(alice, 5 ether);
        vm.prank(alice);
        (bool ok,) = payable(address(moloch)).call{value: 5 ether}("");
        assertTrue(ok);
        assertEq(address(moloch).balance, 5 ether);
    }

    function test_multi_proposal_workflow() public {
        // Multiple proposals in sequence
        for (uint256 i = 0; i < 5; i++) {
            bytes memory data = abi.encodeWithSelector(Target.store.selector, i);
            uint256 h = _id(0, address(target), 0, data, bytes32(i));

            _open(h);
            _voteYes(h, alice);
            _voteYes(h, bob);

            (bool ok,) = moloch.executeByVotes(0, address(target), 0, data, bytes32(i));
            assertTrue(ok);
        }

        assertEq(target.stored(), 4, "last value stored");
    }

    function test_proposal_threshold() public {
        // Set proposal threshold to 50e18
        bytes memory d = abi.encodeWithSelector(Moloch.setProposalThreshold.selector, 50e18);
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("threshold"));
        assertTrue(ok);

        // Alice can propose (60e18 >= 50e18)
        uint256 h1 = _id(0, address(this), 0, "", keccak256("prop1"));
        vm.prank(alice);
        moloch.openProposal(h1);
        assertTrue(moloch.snapshotBlock(h1) > 0, "alice opened");

        // Bob cannot propose (40e18 < 50e18)
        uint256 h2 = _id(0, address(this), 0, "", keccak256("prop2"));
        vm.expectRevert();
        vm.prank(bob);
        moloch.openProposal(h2);
    }

    function test_min_yes_votes_absolute() public {
        // Set minimum YES votes to 70e18
        bytes memory d = abi.encodeWithSelector(Moloch.setMinYesVotesAbsolute.selector, 70e18);
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("min-yes"));
        assertTrue(ok);

        // Only alice votes YES (60e18 < 70e18)
        uint256 h = _id(0, address(this), 0, "", keccak256("test"));
        _open(h);
        vm.prank(alice);
        moloch.castVote(h, 1);

        // Should be defeated
        assertEq(uint256(moloch.state(h)), uint256(Moloch.ProposalState.Defeated));
    }

    function test_quorum_absolute() public {
        // Set absolute quorum to 90e18
        bytes memory d = abi.encodeWithSelector(Moloch.setQuorumAbsolute.selector, 90e18);
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("q-abs"));
        assertTrue(ok);

        // Both vote (100e18 >= 90e18)
        uint256 h = _id(0, address(this), 0, "", keccak256("test"));
        _open(h);
        _voteYes(h, alice);
        _voteYes(h, bob);

        assertEq(uint256(moloch.state(h)), uint256(Moloch.ProposalState.Succeeded));
    }

    function test_member_joins_and_votes() public {
        // Enable sale
        bytes memory d = abi.encodeWithSelector(
            Moloch.setSale.selector, address(0), 1 wei, 30e18, true, true, false
        );
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("sale"));
        assertTrue(ok);

        // Charlie joins
        vm.deal(charlie, 30e18);
        vm.prank(charlie);
        moloch.buyShares{value: 30e18}(address(0), 30e18, 30e18);

        vm.roll(10);
        vm.warp(10);

        // New proposal after charlie joined
        uint256 h = _id(0, address(this), 0, "", keccak256("new-vote"));
        _open(h);

        // All three vote
        _voteYes(h, alice);
        _voteYes(h, bob);
        vm.prank(charlie);
        moloch.castVote(h, 1);

        (uint256 forVotes,,) = moloch.tallies(h);
        assertEq(forVotes, 130e18, "all three voted");
    }

    function test_delegation_then_transfer() public {
        // Alice delegates to Bob
        vm.prank(alice);
        shares.delegate(bob);

        assertEq(shares.getVotes(bob), 100e18, "bob has all votes");

        vm.roll(10);
        vm.warp(10);

        // Alice transfers shares to charlie
        vm.prank(alice);
        shares.transfer(charlie, 30e18);

        // Bob still has 40e18 (his own) + 30e18 (alice's remaining) = 70e18
        // Charlie self-delegates his 30e18
        assertEq(shares.getVotes(bob), 70e18, "bob has less");
        assertEq(shares.getVotes(charlie), 30e18, "charlie self-delegated");
    }

    function test_transfer_updates_voting_power() public {
        vm.roll(10);
        vm.warp(10);

        uint256 aliceVotesBefore = shares.getVotes(alice);
        uint256 bobVotesBefore = shares.getVotes(bob);

        // Alice transfers to bob
        vm.prank(alice);
        shares.transfer(bob, 20e18);

        assertEq(shares.getVotes(alice), aliceVotesBefore - 20e18);
        assertEq(shares.getVotes(bob), bobVotesBefore + 20e18);
    }

    function test_getPastVotes() public {
        vm.roll(10);
        vm.warp(10);

        uint32 snapshot = uint32(block.number);

        // Transfer happens after snapshot
        vm.roll(20);
        vm.prank(alice);
        shares.transfer(bob, 10e18);

        // Query past votes at snapshot
        assertEq(shares.getPastVotes(alice, snapshot), 60e18, "alice past");
        assertEq(shares.getPastVotes(bob, snapshot), 40e18, "bob past");

        // Current votes are different
        assertEq(shares.getVotes(alice), 50e18, "alice current");
        assertEq(shares.getVotes(bob), 50e18, "bob current");
    }

    function test_getPastTotalSupply() public {
        vm.roll(10);
        vm.warp(10);

        // Record supply at block 10
        uint256 supplyAtBlock10 = shares.totalSupply();
        assertEq(supplyAtBlock10, 100e18);

        // Move forward to create checkpoint
        vm.roll(11);
        vm.warp(11);

        uint32 snapshot = uint32(10); // Snapshot is at block 10

        // Enable sale and mint more at a later block
        bytes memory d = abi.encodeWithSelector(
            Moloch.setSale.selector, address(0), 0, 50e18, true, true, false
        );
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("sale"));
        assertTrue(ok);

        vm.roll(20);
        vm.warp(20);

        vm.prank(charlie);
        moloch.buyShares{value: 0}(address(0), 50e18, 0);

        // Past supply at snapshot (block 10)
        assertEq(shares.getPastTotalSupply(snapshot), 100e18, "past supply");
        assertEq(shares.totalSupply(), 150e18, "current supply");
    }

    function test_ragequit_disabled() public {
        // Disable ragequit
        bytes memory d = abi.encodeWithSelector(Moloch.setRagequittable.selector, false);
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("disable-rq"));
        assertTrue(ok);

        address[] memory tokens = new address[](1);
        tokens[0] = address(0);

        vm.expectRevert(Moloch.NotOk.selector);
        vm.prank(bob);
        moloch.rageQuit(tokens, 1e18, 0);
    }

    function test_ragequit_zero_amount_reverts() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(0);

        vm.expectRevert(Moloch.NotOk.selector);
        vm.prank(bob);
        moloch.rageQuit(tokens, 0, 0);
    }

    function test_ragequit_sorted_tokens() public {
        vm.roll(10);
        vm.warp(10);

        vm.deal(address(moloch), 10 ether);

        // Must be sorted: ETH first, then token addresses
        address[] memory tokens = new address[](2);
        tokens[0] = address(0);
        tokens[1] = address(0x1234); // Some token address

        vm.prank(bob);
        moloch.rageQuit(tokens, 1e18, 0);
    }

    function test_ragequit_unsorted_reverts() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(0x1234);
        tokens[1] = address(0); // Wrong order

        vm.expectRevert(Moloch.NotOk.selector);
        vm.prank(bob);
        moloch.rageQuit(tokens, 1e18, 0);
    }

    function test_sales_cap_decrements() public {
        bytes memory d = abi.encodeWithSelector(
            Moloch.setSale.selector, address(0), 0, 20e18, true, true, false
        );
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("cap-test"));
        assertTrue(ok);

        // First purchase
        vm.prank(charlie);
        moloch.buyShares{value: 0}(address(0), 15e18, 0);

        (, uint256 cap,,,) = moloch.sales(address(0));
        assertEq(cap, 5e18, "cap decreased");

        // Second purchase up to cap
        address dave = address(0xDADE);
        vm.prank(dave);
        moloch.buyShares{value: 0}(address(0), 5e18, 0);

        (, uint256 cap2,,,) = moloch.sales(address(0));
        assertEq(cap2, 0, "cap exhausted");
    }

    function test_sales_exceeds_cap_reverts() public {
        bytes memory d = abi.encodeWithSelector(
            Moloch.setSale.selector, address(0), 0, 10e18, true, true, false
        );
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("cap"));
        assertTrue(ok);

        vm.expectRevert(Moloch.NotOk.selector);
        vm.prank(charlie);
        moloch.buyShares{value: 0}(address(0), 11e18, 0);
    }

    function test_sales_inactive_reverts() public {
        bytes memory d = abi.encodeWithSelector(
            Moloch.setSale.selector,
            address(0),
            0,
            10e18,
            true,
            false,
            false // inactive
        );
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("inactive"));
        assertTrue(ok);

        vm.expectRevert(Moloch.NotOk.selector);
        vm.prank(charlie);
        moloch.buyShares{value: 0}(address(0), 5e18, 0);
    }

    function test_top_256_zero_balance_removes() public {
        vm.roll(10);
        vm.warp(10);

        // Alice transfers all shares away
        vm.prank(alice);
        shares.transfer(bob, 60e18);

        // Alice should lose badge
        assertEq(shares.balanceOf(alice), 0);
        assertEq(badge.balanceOf(alice), 0, "badge removed");
        assertEq(moloch.rankOf(alice), 0, "no rank");
    }

    function test_top_256_balance_change_keeps_slot() public {
        uint256 rankBefore = moloch.rankOf(alice);
        assertTrue(rankBefore > 0);

        // Alice increases balance
        bytes memory d = abi.encodeWithSelector(
            Moloch.setSale.selector, address(0), 0, 100e18, true, true, false
        );
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("sale"));
        assertTrue(ok);

        vm.prank(alice);
        moloch.buyShares{value: 0}(address(0), 40e18, 0);

        // Alice keeps same slot
        assertEq(moloch.rankOf(alice), rankBefore, "same rank");
        assertEq(badge.balanceOf(alice), 1, "still has badge");
    }

    function test_badge_non_transferable() public {
        uint256 tokenId = uint256(uint160(alice));

        vm.expectRevert();
        badge.transferFrom(alice, bob, tokenId);
    }

    function test_chat_multiple_messages() public {
        vm.prank(alice);
        moloch.chat("message 1");

        vm.prank(bob);
        moloch.chat("message 2");

        assertEq(moloch.getMessageCount(), 2);
    }

    function test_futarchy_multiple_fundings() public {
        uint256 h = _id(0, address(this), 0, "", keccak256("multi-fund"));

        vm.deal(address(this), 100 ether);

        // Fund in multiple transactions
        moloch.fundFutarchy{value: 30 ether}(h, address(0), 30 ether);
        moloch.fundFutarchy{value: 40 ether}(h, address(0), 40 ether);
        moloch.fundFutarchy{value: 30 ether}(h, address(0), 30 ether);

        (,, uint256 pool,,,,) = moloch.futarchy(h);
        assertEq(pool, 100 ether, "accumulated pool");
    }

    function test_futarchy_zero_amount_reverts() public {
        uint256 h = _id(0, address(this), 0, "", keccak256("zero-fund"));

        vm.expectRevert(Moloch.NotOk.selector);
        moloch.fundFutarchy{value: 0}(h, address(0), 0);
    }

    function test_futarchy_cashout_zero_payout() public {
        bytes memory call = abi.encodeWithSelector(Target.store.selector, 999);
        uint256 h = _id(0, address(target), 0, call, keccak256("zero-payout"));

        // Fund tiny amount
        vm.deal(address(this), 1 wei);
        moloch.fundFutarchy{value: 1 wei}(h, address(0), 1 wei);

        _open(h);
        _voteYes(h, alice);
        _voteYes(h, bob);

        // Actually execute the proposal to resolve futarchy
        (bool ok,) = moloch.executeByVotes(0, address(target), 0, call, keccak256("zero-payout"));
        assertTrue(ok);

        // Verify futarchy resolved
        (bool enabled,,, bool resolved, uint8 winner,,) = moloch.futarchy(h);
        assertTrue(enabled && resolved);
        assertEq(winner, 1, "YES won");

        // Cashout rounds to zero due to tiny pool
        vm.prank(alice);
        uint256 payout = moloch.cashOutFutarchy(h, 60e18); // alice's full voting weight

        // With 1 wei pool and 100e18 total votes, payout per unit = 1 / 100e18 = 0 (rounds down)
        assertEq(payout, 0, "zero payout due to rounding");
    }

    function test_permit_replace_count() public {
        bytes memory call = abi.encodeWithSelector(Target.store.selector, 100);
        bytes32 nonce = keccak256("replace");

        // Set to 5
        bytes memory d1 = abi.encodeWithSelector(
            Moloch.setPermit.selector, 0, address(target), 0, call, nonce, charlie, 5
        );
        (, bool ok1) = _openAndPass(0, address(moloch), 0, d1, keccak256("set-5"));
        assertTrue(ok1);

        uint256 h = _id(0, address(target), 0, call, nonce);
        assertEq(moloch.balanceOf(charlie, h), 5);

        // Replace with 10
        bytes memory d2 = abi.encodeWithSelector(
            Moloch.setPermit.selector, 0, address(target), 0, call, nonce, charlie, 10
        );
        (, bool ok2) = _openAndPass(0, address(moloch), 0, d2, keccak256("set-10"));
        assertTrue(ok2);

        assertEq(moloch.balanceOf(charlie, h), 10, "replaced");
    }

    function test_permit_reduce_count() public {
        bytes memory call = abi.encodeWithSelector(Target.store.selector, 200);
        bytes32 nonce = keccak256("reduce");

        // Set to 10
        bytes memory d1 = abi.encodeWithSelector(
            Moloch.setPermit.selector, 0, address(target), 0, call, nonce, charlie, 10
        );
        (, bool ok1) = _openAndPass(0, address(moloch), 0, d1, keccak256("set-10"));
        assertTrue(ok1);

        // Reduce to 3
        bytes memory d2 = abi.encodeWithSelector(
            Moloch.setPermit.selector, 0, address(target), 0, call, nonce, charlie, 3
        );
        (, bool ok2) = _openAndPass(0, address(moloch), 0, d2, keccak256("set-3"));
        assertTrue(ok2);

        uint256 h = _id(0, address(target), 0, call, nonce);
        assertEq(moloch.balanceOf(charlie, h), 3, "reduced");
    }

    function test_shares_approve_and_transferFrom() public {
        // Alice approves charlie
        vm.prank(alice);
        shares.approve(charlie, 30e18);

        assertEq(shares.allowance(alice, charlie), 30e18);

        vm.roll(10);
        vm.warp(10);

        // Charlie transfers from alice to bob
        vm.prank(charlie);
        shares.transferFrom(alice, bob, 20e18);

        assertEq(shares.balanceOf(alice), 40e18);
        assertEq(shares.balanceOf(bob), 60e18);
        assertEq(shares.allowance(alice, charlie), 10e18, "allowance decreased");
    }

    function test_shares_transferFrom_max_allowance() public {
        // Alice approves charlie with max
        vm.prank(alice);
        shares.approve(charlie, type(uint256).max);

        vm.roll(10);
        vm.warp(10);

        // Charlie transfers
        vm.prank(charlie);
        shares.transferFrom(alice, bob, 10e18);

        // Max allowance doesn't decrease
        assertEq(shares.allowance(alice, charlie), type(uint256).max);
    }

    function test_timelock_queue_then_ttl_still_executes() public {
        // Set timelock (longer) and TTL (shorter)
        bytes memory d1 = abi.encodeWithSelector(Moloch.setTimelockDelay.selector, uint64(200));
        (, bool ok1) = _openAndPass(0, address(moloch), 0, d1, keccak256("tl"));
        assertTrue(ok1);

        bytes memory d2 = abi.encodeWithSelector(Moloch.setProposalTTL.selector, uint64(100));
        (, bool ok2) = _openAndPass(0, address(moloch), 0, d2, keccak256("ttl"));
        assertTrue(ok2);

        // New proposal
        bytes memory callData = abi.encodeWithSelector(Target.store.selector, 777);
        uint256 h = _id(0, address(target), 0, callData, keccak256("both"));
        _open(h);
        _voteYes(h, alice);
        _voteYes(h, bob);

        // Queue immediately (before TTL expires)
        moloch.queue(h);
        assertEq(uint256(moloch.state(h)), uint256(Moloch.ProposalState.Queued), "queued");

        // Wait past TTL but not timelock
        vm.warp(block.timestamp + 150);

        // Should still be queued (TTL doesn't apply once queued)
        assertEq(uint256(moloch.state(h)), uint256(Moloch.ProposalState.Queued), "still queued");

        // Wait for timelock to complete
        vm.warp(block.timestamp + 100); // Total 250 seconds, past the 200s timelock

        // Now execute
        (bool executed,) = moloch.executeByVotes(0, address(target), 0, callData, keccak256("both"));
        assertTrue(executed, "executes after timelock despite TTL");
        assertEq(target.stored(), 777, "execution succeeded");
    }

    function test_contract_uri() public view {
        // Just check it doesn't revert
        string memory uri = moloch.contractURI();
        assertTrue(bytes(uri).length >= 0);
    }

    function test_set_metadata() public {
        bytes memory d =
            abi.encodeWithSelector(Moloch.setMetadata.selector, "New Name", "NEW", "ipfs://newuri");
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("metadata"));
        assertTrue(ok);

        assertEq(moloch.name(0), "New Name");
        assertEq(moloch.symbol(0), "NEW");
        assertEq(moloch.contractURI(), "ipfs://newuri");
    }

    /*//////////////////////////////////////////////////////////////
                    EXECUTION & STATE EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_double_execution_reverts() public {
        bytes memory data = abi.encodeWithSelector(Target.store.selector, 123);
        uint256 h = _id(0, address(target), 0, data, keccak256("double-exec"));

        _open(h);
        vm.prank(alice);
        moloch.castVote(h, 1);
        vm.prank(bob);
        moloch.castVote(h, 1);

        (bool ok,) = moloch.executeByVotes(0, address(target), 0, data, keccak256("double-exec"));
        assertTrue(ok);

        vm.expectRevert(Moloch.AlreadyExecuted.selector);
        moloch.executeByVotes(0, address(target), 0, data, keccak256("double-exec"));
    }

    function test_vote_on_executed_proposal_reverts() public {
        bytes memory data = abi.encodeWithSelector(Target.store.selector, 456);
        uint256 h = _id(0, address(target), 0, data, keccak256("vote-exec"));

        _open(h);
        vm.prank(alice);
        moloch.castVote(h, 1);
        vm.prank(bob);
        moloch.castVote(h, 1);

        (bool ok,) = moloch.executeByVotes(0, address(target), 0, data, keccak256("vote-exec"));
        assertTrue(ok);

        vm.expectRevert(Moloch.AlreadyExecuted.selector);
        vm.prank(charlie);
        moloch.castVote(h, 1);
    }

    function test_invalid_vote_support_reverts() public {
        uint256 h = _id(0, address(this), 0, "", keccak256("invalid-vote"));
        _open(h);

        vm.expectRevert(Moloch.NotOk.selector);
        vm.prank(alice);
        moloch.castVote(h, 3);
    }

    function test_vote_with_zero_weight_reverts() public {
        uint256 h = _id(0, address(this), 0, "", keccak256("zero-weight"));
        _open(h);

        vm.expectRevert(Moloch.NotOk.selector);
        vm.prank(charlie);
        moloch.castVote(h, 1);
    }

    function test_open_proposal_twice_is_idempotent() public {
        // Move past genesis block first
        vm.roll(5);
        vm.warp(5);

        uint256 h = _id(0, address(this), 0, "", keccak256("reopen"));

        vm.prank(alice);
        moloch.openProposal(h);
        uint256 snapshot1 = moloch.snapshotBlock(h);
        assertTrue(snapshot1 > 0, "first open succeeded");

        vm.roll(block.number + 5);
        vm.warp(block.timestamp + 5);

        vm.prank(alice);
        moloch.openProposal(h);
        uint256 snapshot2 = moloch.snapshotBlock(h);

        assertEq(snapshot1, snapshot2, "snapshot unchanged");
    }

    function test_open_proposal_without_threshold_when_set() public {
        bytes memory d = abi.encodeWithSelector(Moloch.setProposalThreshold.selector, 50e18);
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("threshold"));
        assertTrue(ok);

        uint256 h = _id(0, address(this), 0, "", keccak256("no-threshold"));

        vm.expectRevert();
        vm.prank(bob);
        moloch.openProposal(h);
    }

    function test_auto_open_on_first_vote() public {
        uint256 h = _id(0, address(this), 0, "", keccak256("auto-open"));

        assertEq(moloch.snapshotBlock(h), 0, "not opened yet");

        // Move forward so we're not at genesis block
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        vm.prank(alice);
        moloch.castVote(h, 1);

        assertTrue(moloch.snapshotBlock(h) > 0, "auto-opened");
    }

    function test_auto_open_respects_threshold() public {
        bytes memory d = abi.encodeWithSelector(Moloch.setProposalThreshold.selector, 50e18);
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("threshold"));
        assertTrue(ok);

        uint256 h = _id(0, address(this), 0, "", keccak256("auto-threshold"));

        vm.expectRevert(Moloch.NotOk.selector);
        vm.prank(bob);
        moloch.castVote(h, 1);
    }

    function test_vote_after_ttl_reverts() public {
        bytes memory d = abi.encodeWithSelector(Moloch.setProposalTTL.selector, uint64(100));
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("ttl"));
        assertTrue(ok);

        uint256 h = _id(0, address(this), 0, "", keccak256("ttl-vote"));
        _open(h);

        vm.warp(block.timestamp + 101);

        vm.expectRevert(Moloch.NotOk.selector);
        vm.prank(alice);
        moloch.castVote(h, 1);
    }

    function test_execute_defeated_proposal_reverts() public {
        uint256 h = _id(0, address(this), 0, "", keccak256("defeated"));
        _open(h);

        vm.prank(alice);
        moloch.castVote(h, 0);
        vm.prank(bob);
        moloch.castVote(h, 0);

        vm.expectRevert(Moloch.NotOk.selector);
        moloch.executeByVotes(0, address(this), 0, "", keccak256("defeated"));
    }

    function test_execute_expired_proposal_reverts() public {
        bytes memory d = abi.encodeWithSelector(Moloch.setProposalTTL.selector, uint64(100));
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("ttl"));
        assertTrue(ok);

        uint256 h = _id(0, address(this), 0, "", keccak256("expired"));
        _open(h);

        vm.warp(block.timestamp + 101);

        vm.expectRevert(Moloch.NotOk.selector);
        moloch.executeByVotes(0, address(this), 0, "", keccak256("expired"));
    }

    function test_execute_active_proposal_reverts() public {
        bytes memory d = abi.encodeWithSelector(Moloch.setQuorumBps.selector, uint16(8000));
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("quorum"));
        assertTrue(ok);

        uint256 h2 = _id(0, address(this), 0, "", keccak256("active2"));
        _open(h2);

        vm.prank(alice);
        moloch.castVote(h2, 1);

        vm.expectRevert(Moloch.NotOk.selector);
        moloch.executeByVotes(0, address(this), 0, "", keccak256("active2"));
    }

    function test_queue_non_succeeded_proposal_reverts() public {
        uint256 h = _id(0, address(this), 0, "", keccak256("queue-fail"));
        _open(h);

        vm.expectRevert(Moloch.NotOk.selector);
        moloch.queue(h);
    }

    function test_queue_with_no_timelock_is_noop() public {
        uint256 h = _id(0, address(this), 0, "", keccak256("queue-noop"));
        _open(h);

        vm.prank(alice);
        moloch.castVote(h, 1);
        vm.prank(bob);
        moloch.castVote(h, 1);

        moloch.queue(h);

        assertEq(moloch.queuedAt(h), 0, "not queued");
    }

    function test_execute_before_timelock_reverts() public {
        bytes memory d = abi.encodeWithSelector(Moloch.setTimelockDelay.selector, uint64(1000));
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("tl"));
        assertTrue(ok);

        bytes memory callData = abi.encodeWithSelector(Target.store.selector, 123);
        uint256 h = _id(0, address(target), 0, callData, keccak256("tl-test"));
        _open(h);

        vm.prank(alice);
        moloch.castVote(h, 1);
        vm.prank(bob);
        moloch.castVote(h, 1);

        (bool queued,) =
            moloch.executeByVotes(0, address(target), 0, callData, keccak256("tl-test"));
        assertTrue(queued);

        vm.warp(block.timestamp + 500);

        vm.expectRevert();
        moloch.executeByVotes(0, address(target), 0, callData, keccak256("tl-test"));
    }

    /*//////////////////////////////////////////////////////////////
                        FUTARCHY EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_futarchy_wrong_token_type_reverts() public {
        uint256 h = _id(0, address(this), 0, "", keccak256("fut-token"));

        vm.expectRevert(Moloch.NotOk.selector);
        moloch.fundFutarchy(h, address(0x1234), 100);
    }

    function test_futarchy_token_mismatch_reverts() public {
        uint256 h = _id(0, address(this), 0, "", keccak256("fut-mismatch"));

        vm.deal(address(this), 100 ether);
        moloch.fundFutarchy{value: 10 ether}(h, address(0), 10 ether);

        vm.expectRevert(Moloch.NotOk.selector);
        moloch.fundFutarchy{value: 0}(h, address(shares), 10e18);
    }

    function test_futarchy_fund_after_resolved_reverts() public {
        bytes memory call = abi.encodeWithSelector(Target.store.selector, 999);
        uint256 h = _id(0, address(target), 0, call, keccak256("fut-resolved"));

        vm.deal(address(this), 100 ether);
        moloch.fundFutarchy{value: 50 ether}(h, address(0), 50 ether);

        _open(h);
        vm.prank(alice);
        moloch.castVote(h, 1);
        vm.prank(bob);
        moloch.castVote(h, 1);

        (bool ok,) = moloch.executeByVotes(0, address(target), 0, call, keccak256("fut-resolved"));
        assertTrue(ok);

        vm.expectRevert(Moloch.NotOk.selector);
        moloch.fundFutarchy{value: 50 ether}(h, address(0), 50 ether);
    }

    function test_futarchy_resolve_no_already_executed_reverts() public {
        bytes memory call = abi.encodeWithSelector(Target.store.selector, 777);
        uint256 h = _id(0, address(target), 0, call, keccak256("fut-no-exec"));

        vm.deal(address(this), 100 ether);
        moloch.fundFutarchy{value: 50 ether}(h, address(0), 50 ether);

        _open(h);
        vm.prank(alice);
        moloch.castVote(h, 0);
        vm.prank(bob);
        moloch.castVote(h, 0);

        assertEq(uint256(moloch.state(h)), uint256(Moloch.ProposalState.Defeated));

        moloch.resolveFutarchyNo(h);

        bytes memory call2 = abi.encodeWithSelector(Target.store.selector, 888);
        uint256 h2 = _id(0, address(target), 0, call2, keccak256("fut-no-exec2"));

        vm.deal(address(this), 100 ether);
        moloch.fundFutarchy{value: 50 ether}(h2, address(0), 50 ether);

        _open(h2);
        vm.prank(alice);
        moloch.castVote(h2, 1);
        vm.prank(bob);
        moloch.castVote(h2, 1);

        (bool ok,) = moloch.executeByVotes(0, address(target), 0, call2, keccak256("fut-no-exec2"));
        assertTrue(ok);

        vm.expectRevert(Moloch.NotOk.selector);
        moloch.resolveFutarchyNo(h2);
    }

    function test_futarchy_resolve_no_not_enabled_reverts() public {
        uint256 h = _id(0, address(this), 0, "", keccak256("fut-not-enabled"));

        vm.expectRevert(Moloch.NotOk.selector);
        moloch.resolveFutarchyNo(h);
    }

    function test_futarchy_cashout_not_enabled_reverts() public {
        uint256 h = _id(0, address(this), 0, "", keccak256("fut-cashout-no"));

        vm.expectRevert(Moloch.NotOk.selector);
        vm.prank(alice);
        moloch.cashOutFutarchy(h, 10e18);
    }

    function test_futarchy_cashout_not_resolved_reverts() public {
        uint256 h = _id(0, address(this), 0, "", keccak256("fut-cashout-pending"));

        vm.deal(address(this), 100 ether);
        moloch.fundFutarchy{value: 50 ether}(h, address(0), 50 ether);

        vm.expectRevert(Moloch.NotOk.selector);
        vm.prank(alice);
        moloch.cashOutFutarchy(h, 10e18);
    }

    function test_futarchy_existing_shares_reward() public {
        // First enable sale and mint shares to charlie
        bytes memory saleData = abi.encodeWithSelector(
            Moloch.setSale.selector, address(0), 0, 100e18, true, true, false
        );
        (, bool ok1) = _openAndPass(0, address(moloch), 0, saleData, keccak256("sale"));
        assertTrue(ok1);

        // Charlie buys only 100e18 (not 200e18) to keep total supply manageable
        vm.prank(charlie);
        moloch.buyShares{value: 0}(address(0), 100e18, 0);

        // Transfer shares to moloch
        vm.prank(charlie);
        shares.transfer(address(moloch), 100e18);

        // Approve moloch to spend its own shares (needed for safeTransferFrom)
        bytes memory approveCall =
            abi.encodeWithSelector(shares.approve.selector, address(moloch), 100e18);
        (, bool ok2) = _openAndPass(0, address(shares), 0, approveCall, keccak256("approve"));
        assertTrue(ok2);

        // Create the actual proposal
        bytes memory call = abi.encodeWithSelector(Target.store.selector, 666);
        uint256 h = _id(0, address(target), 0, call, keccak256("fut-existing"));

        // Fund futarchy with 100e18 shares
        vm.prank(address(moloch));
        moloch.fundFutarchy(h, address(shares), 100e18);

        // Vote and execute the actual proposal
        _open(h);
        vm.prank(alice);
        moloch.castVote(h, 1);
        vm.prank(bob);
        moloch.castVote(h, 1);

        // Pool = 100e18, winning supply = 100e18, so ppu = 1e18 (1 share per vote)
        // Alice has 60e18 votes, so she gets 60e18 shares
        uint256 aliceBalBefore = shares.balanceOf(alice);

        (bool ok3,) = moloch.executeByVotes(0, address(target), 0, call, keccak256("fut-existing"));
        assertTrue(ok3, "execution succeeded");

        // Cashout alice's portion
        vm.prank(alice);
        moloch.cashOutFutarchy(h, 60e18);

        uint256 aliceGain = shares.balanceOf(alice) - aliceBalBefore;
        assertEq(aliceGain, 60e18, "alice received correct share payout");
        assertTrue(aliceGain > 0, "received shares");
    }

    /*//////////////////////////////////////////////////////////////
                        SALES EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_sale_eth_wrong_value_reverts() public {
        bytes memory d = abi.encodeWithSelector(
            Moloch.setSale.selector, address(0), 1 ether, 10e18, true, true, false
        );
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("sale"));
        assertTrue(ok);

        vm.expectRevert(Moloch.NotOk.selector);
        vm.prank(charlie);
        moloch.buyShares{value: 0.5 ether}(address(0), 1e18, 2 ether);
    }

    function test_sale_eth_exceeds_max_pay_reverts() public {
        bytes memory d = abi.encodeWithSelector(
            Moloch.setSale.selector, address(0), 1 ether, 10e18, true, true, false
        );
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("sale"));
        assertTrue(ok);

        vm.expectRevert(Moloch.NotOk.selector);
        vm.prank(charlie);
        moloch.buyShares{value: 1 ether}(address(0), 1e18, 0.5 ether);
    }

    function test_sale_transfer_mode_non_minting() public {
        bytes memory mintSale = abi.encodeWithSelector(
            Moloch.setSale.selector, address(0), 0, 50e18, true, true, false
        );
        (, bool ok1) = _openAndPass(0, address(moloch), 0, mintSale, keccak256("mint-sale"));
        assertTrue(ok1);

        vm.prank(charlie);
        moloch.buyShares{value: 0}(address(0), 50e18, 0);

        vm.prank(charlie);
        shares.transfer(address(moloch), 50e18);

        bytes memory transferSale = abi.encodeWithSelector(
            Moloch.setSale.selector, address(0), 0, 30e18, false, true, false
        );
        (, bool ok2) = _openAndPass(0, address(moloch), 0, transferSale, keccak256("transfer-sale"));
        assertTrue(ok2);

        uint256 molochBalBefore = shares.balanceOf(address(moloch));

        address dave = address(0xDADE);
        vm.prank(dave);
        moloch.buyShares{value: 0}(address(0), 20e18, 0);

        assertEq(shares.balanceOf(dave), 20e18);
        assertEq(shares.balanceOf(address(moloch)), molochBalBefore - 20e18);
    }

    function test_sale_loot_transfer_mode() public {
        bytes memory mintData =
            abi.encodeWithSelector(Moloch.setSale.selector, address(0), 0, 50e18, true, true, true);
        (, bool ok1) = _openAndPass(0, address(moloch), 0, mintData, keccak256("loot-mint"));
        assertTrue(ok1);

        vm.prank(charlie);
        moloch.buyShares{value: 0}(address(0), 50e18, 0);

        vm.prank(charlie);
        loot.transfer(address(moloch), 50e18);

        bytes memory transferData = abi.encodeWithSelector(
            Moloch.setSale.selector, address(0), 0, 30e18, false, true, true
        );
        (, bool ok2) = _openAndPass(0, address(moloch), 0, transferData, keccak256("loot-transfer"));
        assertTrue(ok2);

        address dave = address(0xDADE);
        vm.prank(dave);
        moloch.buyShares{value: 0}(address(0), 20e18, 0);

        assertEq(loot.balanceOf(dave), 20e18);
    }

    /*//////////////////////////////////////////////////////////////
                        PERMIT EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_permit_execute_burns_receipt() public {
        bytes memory call = abi.encodeWithSelector(Target.store.selector, 111);
        bytes32 nonce = keccak256("permit-burn");

        bytes memory d = abi.encodeWithSelector(
            Moloch.setPermit.selector, 0, address(target), 0, call, nonce, charlie, 5
        );
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("set-permit"));
        assertTrue(ok);

        uint256 h = _id(0, address(target), 0, call, nonce);
        assertEq(moloch.balanceOf(charlie, h), 5);

        vm.prank(charlie);
        moloch.permitExecute(0, address(target), 0, call, nonce);

        assertEq(moloch.balanceOf(charlie, h), 4, "permit burned");
    }

    function test_permit_execute_marks_executed() public {
        bytes memory call = abi.encodeWithSelector(Target.store.selector, 222);
        bytes32 nonce = keccak256("permit-executed");

        bytes memory d = abi.encodeWithSelector(
            Moloch.setPermit.selector, 0, address(target), 0, call, nonce, charlie, 1
        );
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("set-permit"));
        assertTrue(ok);

        uint256 h = _id(0, address(target), 0, call, nonce);

        vm.prank(charlie);
        moloch.permitExecute(0, address(target), 0, call, nonce);

        assertTrue(moloch.executed(h), "marked executed");
    }

    function test_permit_execute_resolves_futarchy() public {
        bytes memory call = abi.encodeWithSelector(Target.store.selector, 333);
        bytes32 nonce = keccak256("permit-fut");

        uint256 h = _id(0, address(target), 0, call, nonce);

        vm.deal(address(this), 100 ether);
        moloch.fundFutarchy{value: 50 ether}(h, address(0), 50 ether);

        bytes memory d = abi.encodeWithSelector(
            Moloch.setPermit.selector, 0, address(target), 0, call, nonce, charlie, 1
        );
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("set-permit-fut"));
        assertTrue(ok);

        vm.prank(charlie);
        moloch.permitExecute(0, address(target), 0, call, nonce);

        (,,, bool resolved, uint8 winner,,) = moloch.futarchy(h);
        assertTrue(resolved, "futarchy resolved");
        assertEq(winner, 1, "YES won");
    }

    /*//////////////////////////////////////////////////////////////
                        DELEGATION EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_split_delegation_invalid_length_reverts() public {
        address[] memory delegates = new address[](2);
        uint32[] memory bps = new uint32[](3);

        vm.expectRevert();
        vm.prank(alice);
        shares.setSplitDelegation(delegates, bps);
    }

    function test_split_delegation_too_many_splits_reverts() public {
        address[] memory delegates = new address[](5);
        uint32[] memory bps = new uint32[](5);

        delegates[0] = bob;
        delegates[1] = charlie;
        delegates[2] = address(0xDADE);
        delegates[3] = address(0x1111);
        delegates[4] = address(0x2222);

        for (uint256 i = 0; i < 5; i++) {
            bps[i] = 2000;
        }

        vm.expectRevert();
        vm.prank(alice);
        shares.setSplitDelegation(delegates, bps);
    }

    function test_split_delegation_zero_splits_reverts() public {
        address[] memory delegates = new address[](0);
        uint32[] memory bps = new uint32[](0);

        vm.expectRevert();
        vm.prank(alice);
        shares.setSplitDelegation(delegates, bps);
    }

    function test_split_delegation_zero_address_reverts() public {
        address[] memory delegates = new address[](2);
        uint32[] memory bps = new uint32[](2);

        delegates[0] = address(0);
        delegates[1] = bob;
        bps[0] = 5000;
        bps[1] = 5000;

        vm.expectRevert();
        vm.prank(alice);
        shares.setSplitDelegation(delegates, bps);
    }

    function test_split_delegation_sum_not_10000_reverts() public {
        address[] memory delegates = new address[](2);
        uint32[] memory bps = new uint32[](2);

        delegates[0] = bob;
        delegates[1] = charlie;
        bps[0] = 5000;
        bps[1] = 4999;

        vm.expectRevert();
        vm.prank(alice);
        shares.setSplitDelegation(delegates, bps);
    }

    function test_split_delegation_duplicate_delegates_reverts() public {
        address[] memory delegates = new address[](2);
        uint32[] memory bps = new uint32[](2);

        delegates[0] = bob;
        delegates[1] = bob;
        bps[0] = 5000;
        bps[1] = 5000;

        vm.expectRevert();
        vm.prank(alice);
        shares.setSplitDelegation(delegates, bps);
    }

    function test_clear_split_when_no_split_is_noop() public {
        vm.prank(alice);
        shares.clearSplitDelegation();

        assertEq(shares.getVotes(alice), 60e18);
    }

    function test_getPastVotes_reverts_future_block() public {
        vm.expectRevert();
        shares.getPastVotes(alice, uint32(block.number));
    }

    function test_getPastTotalSupply_reverts_future_block() public {
        vm.expectRevert();
        shares.getPastTotalSupply(uint32(block.number));
    }

    /*//////////////////////////////////////////////////////////////
                        RAGEQUIT EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_ragequit_with_both_shares_and_loot() public {
        bytes memory d =
            abi.encodeWithSelector(Moloch.setSale.selector, address(0), 0, 50e18, true, true, true);
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("loot-sale"));
        assertTrue(ok);

        vm.prank(alice);
        moloch.buyShares{value: 0}(address(0), 40e18, 0);

        vm.roll(10);
        vm.warp(10);

        vm.deal(address(moloch), 10 ether);

        uint256 aliceShares = shares.balanceOf(alice);
        uint256 aliceLoot = loot.balanceOf(alice);
        uint256 totalSupply = shares.totalSupply() + loot.totalSupply();

        address[] memory tokens = new address[](1);
        tokens[0] = address(0);

        uint256 aliceBalBefore = alice.balance;

        vm.prank(alice);
        moloch.rageQuit(tokens, aliceShares, aliceLoot);

        uint256 expectedPayout = (10 ether * (aliceShares + aliceLoot)) / totalSupply;
        assertEq(alice.balance - aliceBalBefore, expectedPayout);
        assertEq(shares.balanceOf(alice), 0);
        assertEq(loot.balanceOf(alice), 0);
    }

    function test_ragequit_skips_zero_payout_tokens() public {
        vm.roll(10);
        vm.warp(10);

        vm.deal(address(moloch), 10 ether);

        address[] memory tokens = new address[](2);
        tokens[0] = address(0);
        tokens[1] = address(0x1234);

        uint256 bobBefore = bob.balance;

        vm.prank(bob);
        moloch.rageQuit(tokens, 40e18, 0);

        assertTrue(bob.balance > bobBefore);
    }

    /*//////////////////////////////////////////////////////////////
                        TOP-256 EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_top_256_rebalance_on_zero_balance() public {
        vm.roll(10);
        vm.warp(10);

        uint256 bobRank = moloch.rankOf(bob);
        assertTrue(bobRank > 0);

        vm.prank(bob);
        shares.transfer(alice, 40e18);

        assertEq(shares.balanceOf(bob), 0);
        assertEq(badge.balanceOf(bob), 0);
        assertEq(moloch.rankOf(bob), 0);
        assertEq(moloch.topHolders(bobRank - 1), address(0));
    }

    function test_top_256_newcomer_below_minimum_stays_out() public {
        bytes memory d = abi.encodeWithSelector(
            Moloch.setSale.selector, address(0), 0, type(uint256).max, true, true, false
        );
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("sale"));
        assertTrue(ok);

        for (uint256 i = 0; i < 254; i++) {
            address holder = vm.addr(i + 1000);
            vm.prank(holder);
            moloch.buyShares{value: 0}(address(0), 10e18, 0);
        }

        address small = address(0x9999);
        vm.prank(small);
        moloch.buyShares{value: 0}(address(0), 5e18, 0);

        assertEq(badge.balanceOf(small), 0);
        assertEq(moloch.rankOf(small), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        SETTINGS EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_setQuorumBps_exceeds_10000_reverts() public {
        bytes memory d = abi.encodeWithSelector(Moloch.setQuorumBps.selector, uint16(10001));

        uint256 h = _id(0, address(moloch), 0, d, keccak256("bad-quorum"));
        _open(h);
        vm.prank(alice);
        moloch.castVote(h, 1);
        vm.prank(bob);
        moloch.castVote(h, 1);

        // Should revert when executing the setQuorumBps call
        vm.expectRevert(Moloch.NotOk.selector);
        moloch.executeByVotes(0, address(moloch), 0, d, keccak256("bad-quorum"));
    }

    function test_onlySelf_modifier_reverts_external() public {
        vm.expectRevert();
        moloch.setQuorumBps(5000);
    }

    /*//////////////////////////////////////////////////////////////
                        MISC EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_chat_without_badge_reverts() public {
        vm.expectRevert(Moloch.NotOk.selector);
        vm.prank(charlie);
        moloch.chat("no badge");
    }

    function test_onERC721Received() public {
        bytes4 selector = moloch.onERC721Received(address(0), address(0), 0, "");
        assertEq(selector, moloch.onERC721Received.selector);
    }

    function test_onERC1155Received() public {
        bytes4 selector = moloch.onERC1155Received(address(0), address(0), 0, 0, "");
        assertEq(selector, moloch.onERC1155Received.selector);
    }

    function test_loot_approve() public {
        bytes memory d =
            abi.encodeWithSelector(Moloch.setSale.selector, address(0), 0, 50e18, true, true, true);
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("loot"));
        assertTrue(ok);

        vm.prank(alice);
        moloch.buyShares{value: 0}(address(0), 40e18, 0);

        vm.prank(alice);
        loot.approve(bob, 20e18);

        assertEq(loot.allowance(alice, bob), 20e18);
    }

    function test_loot_transferFrom() public {
        bytes memory d =
            abi.encodeWithSelector(Moloch.setSale.selector, address(0), 0, 50e18, true, true, true);
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("loot"));
        assertTrue(ok);

        vm.prank(alice);
        moloch.buyShares{value: 0}(address(0), 40e18, 0);

        vm.prank(alice);
        loot.approve(bob, 20e18);

        vm.roll(10);
        vm.warp(10);

        vm.prank(bob);
        loot.transferFrom(alice, charlie, 15e18);

        assertEq(loot.balanceOf(charlie), 15e18);
        assertEq(loot.allowance(alice, bob), 5e18);
    }

    function test_loot_transfer_locked() public {
        bytes memory lockData = abi.encodeWithSelector(Moloch.setTransfersLocked.selector, true);
        (, bool ok1) = _openAndPass(0, address(moloch), 0, lockData, keccak256("lock"));
        assertTrue(ok1);

        bytes memory saleData =
            abi.encodeWithSelector(Moloch.setSale.selector, address(0), 0, 50e18, true, true, true);
        (, bool ok2) = _openAndPass(0, address(moloch), 0, saleData, keccak256("loot"));
        assertTrue(ok2);

        vm.prank(alice);
        moloch.buyShares{value: 0}(address(0), 40e18, 0);

        vm.expectRevert();
        vm.prank(alice);
        loot.transfer(bob, 10e18);
    }

    function test_badge_ownerOf() public {
        uint256 tokenId = uint256(uint160(alice));
        assertEq(badge.ownerOf(tokenId), alice);
    }

    function test_badge_ownerOf_not_minted_reverts() public {
        uint256 tokenId = uint256(uint160(charlie));

        vm.expectRevert();
        badge.ownerOf(tokenId);
    }

    function test_badge_mint_double_reverts() public {
        vm.expectRevert();
        vm.prank(address(moloch));
        badge.mint(alice);
    }

    function test_badge_burn_not_minted_reverts() public {
        vm.expectRevert();
        vm.prank(address(moloch));
        badge.burn(charlie);
    }

    function test_allowance_token_transfer() public {
        MockERC20 token = new MockERC20();
        token.mint(address(moloch), 1000e18);

        bytes memory d =
            abi.encodeWithSelector(Moloch.setAllowanceTo.selector, address(token), charlie, 500e18);
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("token-allowance"));
        assertTrue(ok);

        vm.prank(charlie);
        moloch.claimAllowance(address(token), 200e18);

        assertEq(token.balanceOf(charlie), 200e18);
        assertEq(moloch.allowance(address(token), charlie), 300e18);
    }

    function test_summoner_getDAOCount() public view {
        uint256 count = summoner.getDAOCount();
        assertTrue(count >= 1);
    }

    function test_summon_with_init_calls() public {
        Call[] memory initCalls = new Call[](1);
        initCalls[0] = Call({
            target: address(target),
            value: 0,
            data: abi.encodeWithSelector(Target.store.selector, 12345)
        });

        address[] memory holders = new address[](1);
        holders[0] = address(this);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        Moloch newDao = summoner.summon(
            "Init DAO", "INIT", "", 5000, true, bytes32(uint256(1)), holders, amounts, initCalls
        );

        assertEq(target.stored(), 12345);
        assertTrue(address(newDao) != address(0));
    }

    function test_vote_receipt_metadata() public {
        uint256 h = _id(0, address(this), 0, "", keccak256("receipt-meta"));
        _open(h);

        vm.prank(alice);
        moloch.castVote(h, 1);

        uint256 receiptId = uint256(keccak256(abi.encodePacked("Moloch:receipt", h, uint8(1))));

        assertEq(moloch.receiptSupport(receiptId), 1);
        assertEq(moloch.receiptProposal(receiptId), h);

        string memory uri = moloch.tokenURI(receiptId);
        assertTrue(bytes(uri).length > 0);
    }

    function test_proposal_tokenURI() public {
        uint256 h = _id(0, address(this), 0, "", keccak256("proposal-uri"));
        _open(h);

        vm.prank(alice);
        moloch.castVote(h, 1);

        string memory uri = moloch.tokenURI(h);
        assertTrue(bytes(uri).length > 0);
    }

    function test_permit_tokenURI() public {
        bytes memory call = abi.encodeWithSelector(Target.store.selector, 100);
        bytes32 nonce = keccak256("permit-uri");

        bytes memory d = abi.encodeWithSelector(
            Moloch.setPermit.selector, 0, address(target), 0, call, nonce, charlie, 5
        );
        (, bool ok) = _openAndPass(0, address(moloch), 0, d, keccak256("set-permit"));
        assertTrue(ok);

        uint256 h = _id(0, address(target), 0, call, nonce);

        string memory uri = moloch.tokenURI(h);
        assertTrue(bytes(uri).length > 0);
    }

    function test_badge_tokenURI() public {
        uint256 tokenId = uint256(uint160(alice));
        string memory uri = badge.tokenURI(tokenId);
        assertTrue(bytes(uri).length > 0);
    }
}

contract Target {
    uint256 public stored;

    function store(uint256 x) public {
        stored = x;
    }
}

contract MockERC20 {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}
