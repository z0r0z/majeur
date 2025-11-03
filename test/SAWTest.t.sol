// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {SAW, SAWShares, SAWBadge} from "../src/SAW.sol";

contract SAWTest is Test {
    SAW internal saw;
    SAWShares internal shares;
    SAWBadge internal badge;

    address internal alice = address(0xA11CE);
    address internal bob = address(0x0B0B);
    address internal charlie = address(0x0CAFE);

    Target internal target;
    MockERC20 internal tkn; // for ERC20 pool test

    function setUp() public payable {
        vm.label(alice, "ALICE");
        vm.label(bob, "BOB");
        vm.label(charlie, "CHARLIE");

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);

        address[] memory initialHolders = new address[](2);
        initialHolders[0] = alice;
        initialHolders[1] = bob;

        uint256[] memory initialAmounts = new uint256[](2);
        initialAmounts[0] = 60e18;
        initialAmounts[1] = 40e18;

        // quorumBps = 50%, ragequit enabled
        saw = new SAW("Neo Org", "NEO", 5000, true, initialHolders, initialAmounts);
        shares = saw.shares();
        badge = saw.badge();

        assertEq(shares.balanceOf(alice), 60e18, "alice shares");
        assertEq(shares.balanceOf(bob), 40e18, "bob shares");
        assertEq(badge.balanceOf(alice), 1, "alice badge");
        assertEq(badge.balanceOf(bob), 1, "bob badge");

        target = new Target();
        tkn = new MockERC20("Token", "TKN", 18);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/
    function _id(uint8 op, address to, uint256 val, bytes memory data, bytes32 nonce)
        internal
        view
        returns (bytes32)
    {
        return saw.proposalId(op, to, val, data, nonce);
    }

    function _open(bytes32 h) internal {
        saw.openProposal(h);
        // Ensure we’re strictly after the snapshot for ERC5805/5805
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }

    function _voteYes(bytes32 h, address voter) internal {
        vm.prank(voter);
        saw.castVote(h, 1); // YES
    }

    function _openAndPass(uint8 op, address to, uint256 val, bytes memory data, bytes32 nonce)
        internal
        returns (bytes32 h, bool ok)
    {
        h = _id(op, to, val, data, nonce);
        _open(h);
        _voteYes(h, alice);
        _voteYes(h, bob);
        (ok,) = saw.executeByVotes(op, to, val, data, nonce);
        assertTrue(ok, "execute ok");
    }

    /*//////////////////////////////////////////////////////////////
                          CORE HAPPY PATH
    //////////////////////////////////////////////////////////////*/
    function test_execute_call_then_sale_buy_rageQuit_permit_chat() public {
        // ===== Proposal #1: call target.store(42)
        {
            uint8 op = 0;
            address to = address(target);
            uint256 val = 0;
            bytes memory data = abi.encodeWithSelector(Target.store.selector, 42);
            bytes32 nonce = keccak256("proposal-1");

            (bytes32 h1, bool ok1) = _openAndPass(op, to, val, data, nonce);
            assertTrue(ok1, "exec #1 ok");
            assertEq(target.stored(), 42, "stored 42");
            assertTrue(saw.executed(h1), "h1 executed");
        }

        // ===== Proposal #2: setSale(ETH, price=1 wei per share, cap=10e18, minting=true, active=true)
        {
            address payToken = address(0);
            bytes memory data = abi.encodeWithSelector(
                SAW.setSale.selector, payToken, uint256(1), 10e18, true, true
            );

            (bytes32 h2, bool ok2) = _openAndPass(0, address(saw), 0, data, keccak256("proposal-2"));
            assertTrue(ok2, "exec #2 ok");
            assertTrue(saw.executed(h2), "h2 executed");
        }

        // ===== Charlie buys 2 shares for 2 ETH
        vm.prank(charlie);
        saw.buyShares{value: 2 ether}(address(0), 2e18, 0);
        assertEq(shares.balanceOf(charlie), 2e18, "charlie bought 2");

        // ===== Fund treasury with 10 ETH then Bob ragequits (use full pool)
        vm.deal(address(this), 10 ether);
        (bool sent,) = payable(address(saw)).call{value: 10 ether}("");
        assertTrue(sent, "fund SAW");

        uint256 bobBefore = bob.balance;
        uint256 tsBefore = shares.totalSupply(); // 102e18
        uint256 bobShares = shares.balanceOf(bob); // 40e18
        uint256 poolBefore = address(saw).balance; // 2 + 10 ETH

        address[] memory toks = new address[](1);
        toks[0] = address(0);

        vm.prank(bob);
        saw.rageQuit(toks);

        uint256 expected = (poolBefore * bobShares) / tsBefore;
        assertEq(bob.balance - bobBefore, expected, "rageQuit payout");

        // ===== Chat gating (badge holders only)
        vm.expectRevert(SAW.NotApprover.selector);
        vm.prank(bob);
        saw.chat("gm");

        assertEq(badge.balanceOf(alice), 1, "alice still has badge");
        vm.prank(alice);
        saw.chat("hello, world");
        assertEq(saw.getMessageCount(), 1, "one chat message");

        // ===== Permits: set a single-use permit then spend it
        bytes memory dataCall = abi.encodeWithSelector(Target.store.selector, 99);
        bytes32 nonceX = keccak256("permit-1");
        bytes memory data3 = abi.encodeWithSelector(
            SAW.setPermit.selector,
            uint8(0),
            address(target),
            uint256(0),
            dataCall,
            nonceX,
            uint256(1),
            true
        );

        (bytes32 h3, bool ok3) = _openAndPass(0, address(saw), 0, data3, keccak256("proposal-3"));
        assertTrue(ok3, "setPermit ok");
        assertTrue(saw.executed(h3));

        vm.prank(charlie);
        (bool ok4,) = saw.permitExecute(0, address(target), 0, dataCall, nonceX);
        assertTrue(ok4, "permitExecute ok");
        assertEq(target.stored(), 99, "stored 99");
    }

    /*//////////////////////////////////////////////////////////////
                      RAGEQUIT POOLS (ERC20 / MIXED)
    //////////////////////////////////////////////////////////////*/
    function test_rageQuit_withERC20_pool() public {
        tkn.mint(address(saw), 1000e18);

        uint256 poolBefore = tkn.balanceOf(address(saw));
        uint256 tsBefore = shares.totalSupply();
        uint256 bobShares = shares.balanceOf(bob);

        address[] memory toks = new address[](1);
        toks[0] = address(tkn);

        uint256 bobBefore = tkn.balanceOf(bob);

        vm.prank(bob);
        saw.rageQuit(toks);

        uint256 expected = (poolBefore * bobShares) / tsBefore;
        assertEq(tkn.balanceOf(bob) - bobBefore, expected, "erc20 ragequit payout");
    }

    function test_rageQuit_bothPools_ETH_and_ERC20() public {
        // Fund SAW with 5 ETH.
        vm.deal(address(this), 5 ether);
        (bool sent,) = payable(address(saw)).call{value: 5 ether}("");
        assertTrue(sent, "fund SAW ETH");

        // Fund SAW with 300 TKN (MockERC20)
        tkn.mint(address(saw), 300e18);

        uint256 tsBefore = shares.totalSupply(); // 100e18
        uint256 bobShares = shares.balanceOf(bob); // 40e18
        uint256 poolEth = address(saw).balance; // 5 ether
        uint256 poolTkn = tkn.balanceOf(address(saw)); // 300e18

        uint256 bobEthBefore = bob.balance;
        uint256 bobTknBefore = tkn.balanceOf(bob);

        // Prepare tokens array (ETH + ERC20).
        address[] memory toks = new address[](2);
        toks[0] = address(0);
        toks[1] = address(tkn);

        vm.prank(bob);
        saw.rageQuit(toks);

        uint256 expectedEth = (poolEth * bobShares) / tsBefore; // 2 ETH
        uint256 expectedTkn = (poolTkn * bobShares) / tsBefore; // 120e18

        assertEq(bob.balance - bobEthBefore, expectedEth, "ETH rageQuit payout");
        assertEq(tkn.balanceOf(bob) - bobTknBefore, expectedTkn, "ERC20 rageQuit payout");

        assertEq(shares.balanceOf(bob), 0, "bob shares burned");
        assertEq(badge.balanceOf(bob), 0, "bob badge burned");

        vm.expectRevert(SAW.NotApprover.selector);
        vm.prank(bob);
        saw.chat("gm after quit");
    }

    /*//////////////////////////////////////////////////////////////
                      BADGE CHURN + REPLAY PREVENTION
    //////////////////////////////////////////////////////////////*/
    function test_badgeChurn_and_replayPrevention() public {
        // Sale so charlie can enter top set & get a badge
        bytes memory data2 =
            abi.encodeWithSelector(SAW.setSale.selector, address(0), uint256(1), 10e18, true, true);

        (bytes32 h2, bool ok2) =
            _openAndPass(0, address(saw), 0, data2, keccak256("sale-eth-simple"));
        assertTrue(ok2, "setSale ok");
        assertTrue(saw.executed(h2));

        // charlie buys 2 shares via ETH
        vm.prank(charlie);
        saw.buyShares{value: 2 ether}(address(0), 2e18, 0);
        assertEq(shares.balanceOf(charlie), 2e18, "charlie=2 shares");

        // charlie should have a badge and be able to chat
        assertEq(badge.balanceOf(charlie), 1, "charlie badge minted");
        vm.prank(charlie);
        saw.chat("charlie here!");
        assertEq(saw.getMessageCount(), 1, "chat count=1");

        // transfer all charlie's shares away -> should burn his badge
        uint256 charlieBal = shares.balanceOf(charlie);
        vm.prank(charlie);
        shares.transfer(alice, charlieBal);

        assertEq(shares.balanceOf(charlie), 0, "charlie emptied");
        assertEq(badge.balanceOf(charlie), 0, "charlie badge burned");

        // chat now gated
        vm.expectRevert(SAW.NotApprover.selector);
        vm.prank(charlie);
        saw.chat("should fail");

        // replay prevention: execute same call twice should fail
        uint8 op1 = 0; // call
        address to1 = address(this);
        uint256 val1 = 0;
        bytes memory data1 = ""; // no-op
        bytes32 nonce1 = keccak256("replay-proposal");

        // open and pass
        bytes32 h1 = _id(op1, to1, val1, data1, nonce1);
        _open(h1);
        _voteYes(h1, alice);
        _voteYes(h1, bob);
        (bool ok1,) = saw.executeByVotes(op1, to1, val1, data1, nonce1);
        assertTrue(ok1, "first exec ok");

        vm.expectRevert(SAW.AlreadyExecuted.selector);
        saw.executeByVotes(op1, to1, val1, data1, nonce1);
    }

    /*//////////////////////////////////////////////////////////////
                               PERMITS
    //////////////////////////////////////////////////////////////*/
    function test_permitExecute_unlimited_allows_replays() public {
        // Prepare a Target call we’ll permit endlessly
        bytes memory dataCall = abi.encodeWithSelector(Target.store.selector, 777);
        bytes32 nonceX = keccak256("permit-unlimited");

        // Governance call: set unlimited permit
        bytes memory dataSet = abi.encodeWithSelector(
            SAW.setPermit.selector,
            uint8(0),
            address(target),
            uint256(0),
            dataCall,
            nonceX,
            type(uint256).max,
            true
        );

        (bytes32 hGov, bool ok) =
            _openAndPass(0, address(saw), 0, dataSet, keccak256("permit-unlimited-proposal"));
        assertTrue(ok, "setPermit ok");
        assertTrue(saw.executed(hGov));

        // Compute permit hash to check counter stays MAX
        bytes32 hPermit = _id(0, address(target), 0, dataCall, nonceX);
        assertEq(saw.permits(hPermit), type(uint256).max, "permit is MAX");

        // Spend it twice (unlimited)
        vm.prank(charlie);
        (bool ok1,) = saw.permitExecute(0, address(target), 0, dataCall, nonceX);
        assertTrue(ok1, "first permit exec");

        assertTrue(saw.executed(hPermit), "executed latch set");
        assertEq(saw.permits(hPermit), type(uint256).max, "still MAX after first");

        vm.prank(bob);
        (bool ok2,) = saw.permitExecute(0, address(target), 0, dataCall, nonceX);
        assertTrue(ok2, "second permit exec");
        assertEq(target.stored(), 777, "target updated");
        assertEq(saw.permits(hPermit), type(uint256).max, "still MAX after second");
    }

    /*//////////////////////////////////////////////////////////////
                        TRANSFER LOCK + SALES
    //////////////////////////////////////////////////////////////*/
    function test_setTransfersLocked_blocks_user_transfers() public {
        // Proposal to lock transfers
        bytes memory dataLock = abi.encodeWithSelector(SAW.setTransfersLocked.selector, true);

        (, bool ok) = _openAndPass(0, address(saw), 0, dataLock, keccak256("lock-transfers"));
        assertTrue(ok, "locked");

        // Now any user-to-user share transfer reverts with SAWShares.Locked
        vm.expectRevert(SAWShares.Locked.selector);
        vm.prank(bob);
        shares.transfer(alice, 1);
    }

    function test_buyShares_ERC20_with_cap_and_maxPay() public {
        // Mint buyer funds
        tkn.mint(charlie, 5_000e18);

        // Sale in ERC20
        bytes memory dataSale = abi.encodeWithSelector(
            SAW.setSale.selector, address(tkn), uint256(1), uint256(3e18), true, true
        );

        (, bool ok) = _openAndPass(0, address(saw), 0, dataSale, keccak256("erc20-sale"));
        assertTrue(ok, "sale set");

        // cost = 2e18 * 1 = 2e18 token wei
        uint256 cost = 2e18;
        vm.prank(charlie);
        tkn.approve(address(saw), type(uint256).max);

        // Too-low maxPay should revert
        vm.expectRevert(SAW.NotOk.selector);
        vm.prank(charlie);
        saw.buyShares(address(tkn), 2e18, cost - 1);

        // Correct maxPay → success
        vm.prank(charlie);
        saw.buyShares(address(tkn), 2e18, cost);
        assertEq(shares.balanceOf(charlie), 2e18, "got shares");
        assertEq(tkn.balanceOf(address(saw)), cost, "SAW got tokens");

        // Cap decremented: 3e18 - 2e18 = 1e18
        (uint256 price, uint256 cap,, bool active) = saw.sales(address(tkn));
        assertEq(price, 1);
        assertEq(cap, 1e18);
        assertTrue(active);
    }

    /*//////////////////////////////////////////////////////////////
                        ALLOWANCES (ETH / ERC20)
    //////////////////////////////////////////////////////////////*/
    function test_allowance_set_and_claim_ETH_and_ERC20() public {
        // Fund SAW pools it will pay out from
        vm.deal(address(this), 3 ether);
        (bool sent,) = payable(address(saw)).call{value: 3 ether}("");
        assertTrue(sent, "fund ETH");
        tkn.mint(address(saw), 100e18);

        // Allow Alice: 1 ETH
        bytes memory d1 =
            abi.encodeWithSelector(SAW.setAllowanceTo.selector, address(0), alice, 1 ether);
        // And 60 TKN
        bytes memory d2 =
            abi.encodeWithSelector(SAW.setAllowanceTo.selector, address(tkn), alice, 60e18);

        (, bool ok1) = _openAndPass(0, address(saw), 0, d1, keccak256("allow-eth"));
        assertTrue(ok1, "allow eth set");

        (, bool ok2) = _openAndPass(0, address(saw), 0, d2, keccak256("allow-tkn"));
        assertTrue(ok2, "allow tkn set");

        // Alice claims partial ETH then remaining
        uint256 ethBefore = alice.balance;
        vm.prank(alice);
        saw.claimAllowance(address(0), 0.4 ether);
        assertEq(alice.balance, ethBefore + 0.4 ether);
        assertEq(saw.allowance(address(0), alice), 0.6 ether);

        vm.prank(alice);
        saw.claimAllowance(address(0), 0.6 ether);
        assertEq(saw.allowance(address(0), alice), 0);

        // Alice claims ERC20 (partial)
        uint256 tknBefore = tkn.balanceOf(alice);
        vm.prank(alice);
        saw.claimAllowance(address(tkn), 50e18);
        assertEq(tkn.balanceOf(alice) - tknBefore, 50e18);
        assertEq(saw.allowance(address(tkn), alice), 10e18);

        // Over-claim should revert (underflow)
        vm.expectRevert();
        vm.prank(alice);
        saw.claimAllowance(address(tkn), 20e18);
    }

    /*//////////////////////////////////////////////////////////////
                       QUORUM / THRESHOLD DYNAMICS
    //////////////////////////////////////////////////////////////*/
    function test_quorum_enforcement_raise_then_lower() public {
        // Raise quorum to 80%
        bytes memory dUp = abi.encodeWithSelector(SAW.setQuorumBps.selector, uint16(8000));
        (, bool okUp) = _openAndPass(0, address(saw), 0, dUp, keccak256("th-up"));
        assertTrue(okUp, "quorum raised");

        // Proposal where only Alice votes (60% turnout) -> below 80% quorum => cannot execute
        bytes memory dataCall = abi.encodeWithSelector(Target.store.selector, 1);
        bytes32 hCall = _id(0, address(target), 0, dataCall, keccak256("tcall"));

        _open(hCall);
        _voteYes(hCall, alice);

        vm.expectRevert(SAW.NotApprover.selector);
        saw.executeByVotes(0, address(target), 0, dataCall, keccak256("tcall"));

        // Lower back to 50%
        bytes memory dDown = abi.encodeWithSelector(SAW.setQuorumBps.selector, uint16(5000));
        (, bool okDown) = _openAndPass(0, address(saw), 0, dDown, keccak256("th-down"));
        assertTrue(okDown, "quorum lowered");

        // Now the same proposal should execute at 50% quorum (60% turnout)
        (bool okCall,) = saw.executeByVotes(0, address(target), 0, dataCall, keccak256("tcall"));
        assertTrue(okCall, "call passed at 50%");
        assertEq(target.stored(), 1, "target set to 1");
    }

    /*//////////////////////////////////////////////////////////////
                          CONFIG / BUMP / SALES GUARDS
    //////////////////////////////////////////////////////////////*/
    function test_bumpConfig_invalidates_permit() public {
        // Install a single-use permit for target.store(7)
        bytes memory dataCall = abi.encodeWithSelector(Target.store.selector, 7);
        bytes32 nonceX = keccak256("bump-permit-nonce");
        bytes memory dSet = abi.encodeWithSelector(
            SAW.setPermit.selector, 0, address(target), 0, dataCall, nonceX, 1, true
        );
        (, bool okSet) = _openAndPass(0, address(saw), 0, dSet, keccak256("bump-set"));
        assertTrue(okSet, "permit installed");

        // Bump config through governance
        bytes memory dBump = abi.encodeWithSelector(SAW.bumpConfig.selector);
        (, bool okBump) = _openAndPass(0, address(saw), 0, dBump, keccak256("bump-cfg"));
        assertTrue(okBump, "config bumped");

        // Permit should no longer be spendable under new config hash
        vm.expectRevert(SAW.NotApprover.selector);
        vm.prank(charlie);
        saw.permitExecute(0, address(target), 0, dataCall, nonceX);
    }

    function test_buyShares_overflow_guard() public {
        // price = max uint, cap unlimited, minting = true
        bytes memory dSale = abi.encodeWithSelector(
            SAW.setSale.selector, address(0), type(uint256).max, 0, true, true
        );

        (, bool ok) = _openAndPass(0, address(saw), 0, dSale, keccak256("overflow-sale"));
        assertTrue(ok, "sale set");

        // 2e18 * MAX overflows under Solidity 0.8 → generic revert (panic 0x11).
        vm.expectRevert();
        vm.prank(charlie);
        saw.buyShares{value: 0}(address(0), 2e18, 0);
    }

    /*//////////////////////////////////////////////////////////////
                          MISC / RECEIVERS / URIs
    //////////////////////////////////////////////////////////////*/
    function test_onERC_receivers_return_selectors() public view {
        bytes4 erc721 = saw.onERC721Received(address(0), address(0), 123, "");
        assertEq(erc721, saw.onERC721Received.selector, "erc721 selector");

        bytes4 erc1155 = saw.onERC1155Received(address(0), address(0), 1, 2, "");
        assertEq(erc1155, saw.onERC1155Received.selector, "erc1155 selector");
    }

    function test_tokenURI_nonempty() public {
        // Prepare arbitrary proposal id and open it to snapshot
        bytes32 h = _id(0, address(this), 0, "", keccak256("uri-prop"));
        _open(h);

        string memory vuri = saw.tokenURI(uint256(h));
        assertTrue(bytes(vuri).length > 0, "proposal tokenURI");
    }

    function test_buyShares_non_minting_consumes_SAW_balance() public {
        // Preload SAW with 3e18 shares via a direct transfer from Alice
        vm.prank(alice);
        shares.transfer(address(saw), 3e18);
        uint256 sawBefore = shares.balanceOf(address(saw));
        assertEq(sawBefore, 3e18, "SAW preloaded");

        // Sale: ETH price=1, cap=2e18, minting=false, active
        bytes memory dSale =
            abi.encodeWithSelector(SAW.setSale.selector, address(0), uint256(1), 2e18, false, true);

        (, bool ok) = _openAndPass(0, address(saw), 0, dSale, keccak256("nonmint-sale"));
        assertTrue(ok, "sale set");

        // Buy 2e18 shares (cost 2 ETH)
        vm.prank(charlie);
        saw.buyShares{value: 2 ether}(address(0), 2e18, 0);

        assertEq(shares.balanceOf(charlie), 2e18, "charlie got shares");
        assertEq(shares.balanceOf(address(saw)), sawBefore - 2e18, "SAW balance reduced");
    }

    function test_chat_multiple_messages() public {
        uint256 before = saw.getMessageCount();
        vm.prank(alice);
        saw.chat("hi from alice");
        vm.prank(bob);
        saw.chat("hi from bob");
        assertEq(saw.getMessageCount(), before + 2, "two messages added");
    }

    function test_claimAllowance_eth_insufficient_balance_reverts() public {
        // Fund SAW with only 1 ETH
        vm.deal(address(this), 1 ether);
        (bool sent,) = payable(address(saw)).call{value: 1 ether}("");
        assertTrue(sent, "funded 1 ETH");

        // Set allowance to 10 ETH for Alice
        bytes memory d =
            abi.encodeWithSelector(SAW.setAllowanceTo.selector, address(0), alice, 10 ether);

        (, bool ok) = _openAndPass(0, address(saw), 0, d, keccak256("allow-large"));
        assertTrue(ok, "allow set");

        // Claiming more than SAW's ETH balance should revert NotOk
        vm.expectRevert(SAW.NotOk.selector);
        vm.prank(alice);
        saw.claimAllowance(address(0), 10 ether);
    }

    function test_buyShares_eth_wrong_msgvalue_reverts() public {
        // Sale: price=1 wei per share, cap=1e18, minting=true
        bytes memory dSale =
            abi.encodeWithSelector(SAW.setSale.selector, address(0), uint256(1), 1e18, true, true);

        (, bool ok) = _openAndPass(0, address(saw), 0, dSale, keccak256("price-1wei"));
        assertTrue(ok, "sale set");

        // Need 1e18 wei for 1e18 shares; send wrong value
        vm.expectRevert(SAW.NotOk.selector);
        vm.prank(charlie);
        saw.buyShares{value: 123}(address(0), 1e18, 0);
    }

    function test_castVote_reverts_if_id_already_executed() public {
        // Build proposal
        bytes32 salt = keccak256("exec-1");
        bytes32 id = saw.proposalId(
            0, // op
            address(this), // target
            1, // value (1 wei)
            bytes(""), // data
            salt
        );

        // Open, advance, vote FOR by both holders
        saw.openProposal(id);
        vm.roll(2);
        vm.warp(2);

        vm.prank(alice);
        saw.castVote(id, 1);
        vm.prank(bob);
        saw.castVote(id, 1);

        // FUND SAW so it can send 1 wei to target during execution
        vm.deal(address(saw), 1);

        // Execute (should succeed and mark proposal executed)
        saw.executeByVotes(0, address(this), 1, bytes(""), salt);

        // Further voting must revert with AlreadyExecuted
        vm.prank(alice);
        vm.expectRevert(SAW.AlreadyExecuted.selector);
        saw.castVote(id, 1);
    }

    /*//////////////////////////////////////////////////////////////
                         GOVERNANCE-ONLY CALLS
    //////////////////////////////////////////////////////////////*/
    function test_inactive_sale_reverts_buy() public {
        // Set sale inactive from the start
        bytes memory dataSale = abi.encodeWithSelector(
            SAW.setSale.selector, address(0), uint256(1), 10e18, true, false
        );

        (, bool ok) = _openAndPass(0, address(saw), 0, dataSale, keccak256("inactive-sale"));
        assertTrue(ok, "sale set inactive");

        // Attempt to buy → NotApprover (inactive)
        vm.expectRevert(SAW.NotApprover.selector);
        vm.prank(charlie);
        saw.buyShares{value: 1 ether}(address(0), 1e18, 0);
    }

    function test_pull_erc20_via_governance_only() public {
        // Bob holds tokens and approves SAW
        tkn.mint(bob, 50e18);
        vm.prank(bob);
        tkn.approve(address(saw), 50e18);

        // Direct call should revert (NotOwner)
        vm.expectRevert(SAW.NotOwner.selector);
        saw.pull(address(tkn), bob, 20e18);

        // Do it via governance
        bytes memory dataPull = abi.encodeWithSelector(SAW.pull.selector, address(tkn), bob, 20e18);

        (, bool ok) = _openAndPass(0, address(saw), 0, dataPull, keccak256("pull-tkn"));
        assertTrue(ok, "pull executed by SAW");

        assertEq(tkn.balanceOf(address(saw)), 20e18, "SAW received");
        assertEq(tkn.balanceOf(bob), 30e18, "bob debited");
    }

    function test_rageQuit_disabled_blocks() public {
        // Disable ragequit via governance
        bytes memory dataOff = abi.encodeWithSelector(SAW.setRagequittable.selector, false);

        (, bool ok) = _openAndPass(0, address(saw), 0, dataOff, keccak256("rq-off"));
        assertTrue(ok, "ragequit disabled");

        address[] memory toks = new address[](1);
        toks[0] = address(0);

        vm.expectRevert(SAW.NotApprover.selector);
        vm.prank(bob);
        saw.rageQuit(toks);
    }

    /*───────────────────────────────────────────────────────────────────*
    * Helpers
    *───────────────────────────────────────────────────────────────────*/
    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory a = bytes(haystack);
        bytes memory b = bytes(needle);
        if (b.length == 0 || b.length > a.length) return false;
        for (uint256 i = 0; i <= a.length - b.length; ++i) {
            bool ok = true;
            for (uint256 j = 0; j < b.length; ++j) {
                if (a[i + j] != b[j]) ok = false;
                break;
            }
            if (ok) return true;
        }
        return false;
    }

    function _voteYes(bytes32 h) internal {
        // Ensure snapshot is fixed to a past block
        saw.openProposal(h);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.prank(alice);
        saw.castVote(h, 1);
        vm.prank(bob);
        saw.castVote(h, 1);
    }

    /*───────────────────────────────────────────────────────────────────*
     * 1) Proposal tokenURI returns non-empty JSON/SVG (no OOG)
     *───────────────────────────────────────────────────────────────────*/
    function test_tokenURI_proposal_basic_json_svg_nonempty() public {
        bytes32 h = saw.proposalId(0, address(this), 0, bytes(""), bytes32("T1"));
        _voteYes(h);

        string memory uri = saw.tokenURI(uint256(h));
        assertTrue(bytes(uri).length > 0, "uri empty");
        assertTrue(_contains(uri, "Proposal"), "missing Proposal label");
        assertTrue(_contains(uri, "data:image/svg+xml;utf8,"), "missing SVG data URI");
    }

    /*───────────────────────────────────────────────────────────────────*
     * 2) tokenURI switches to receipt view when a receipt id is used
     *───────────────────────────────────────────────────────────────────*/
    function test_tokenURI_receipt_switch_after_vote() public {
        bytes32 h = saw.proposalId(0, address(this), 0, bytes(""), bytes32("R1"));
        _voteYes(h);

        // YES receipt id for the proposal
        uint256 rid = uint256(keccak256(abi.encodePacked("SAW:receipt", h, uint8(1))));
        assertEq(saw.receiptProposal(rid), h, "receiptProposal mismatch");

        // tokenURI should dispatch to the receipt view
        string memory uri = saw.tokenURI(rid);
        assertTrue(bytes(uri).length > 0, "receipt uri empty");
        assertTrue(_contains(uri, "Vote Receipt"), "not a receipt card");
        assertTrue(_contains(uri, "proposal: 0x"), "proposal hash missing");
        assertTrue(_contains(uri, "stance: YES"), "stance missing");

        // Optional: ensure unified path equals direct receiptURI
        assertEq(uri, saw.receiptURI(rid), "dispatch mismatch");
    }

    /*───────────────────────────────────────────────────────────────────*
     * 3) tokenURI must NOT mutate unopened proposals (no auto-open)
     *───────────────────────────────────────────────────────────────────*/
    function test_tokenURI_unopened_does_not_write_state() public view {
        bytes32 h = saw.proposalId(0, address(this), 0, bytes(""), bytes32("NOOPEN"));
        assertEq(saw.snapshotBlock(h), 0, "precondition");
        // Call tokenURI for an unopened id
        string memory uri = saw.tokenURI(uint256(h));
        assertTrue(bytes(uri).length > 0, "uri empty");
        // Still unopened afterwards
        assertEq(saw.snapshotBlock(h), 0, "tokenURI should not open");
    }

    /*───────────────────────────────────────────────────────────────────*
     * 4) openProposal snapshots at previous block number
     *───────────────────────────────────────────────────────────────────*/
    function test_openProposal_uses_previous_block_for_snapshot() public {
        // Jump forward a bit to avoid genesis edge cases
        vm.roll(10);
        vm.warp(10);

        bytes32 h = saw.proposalId(0, address(this), 0, bytes(""), bytes32("SNAP"));
        saw.openProposal(h);

        uint256 snap = saw.snapshotBlock(h);
        assertEq(snap, block.number - 1, "snapshot should be previous block");

        // Supply snapshot should be consistent with totalSupply at snap
        uint256 tsAtSnap = shares.getPastTotalSupply(uint32(snap));
        assertEq(saw.supplySnapshot(h), tsAtSnap, "supply snapshot mismatch");
    }

    /*───────────────────────────────────────────────────────────────────*
     * 5) tokenURI shows a Permit card for ERC6909 mirrored permits
     *   (enable 6909 for permits via governance, then set a permit)
     *───────────────────────────────────────────────────────────────────*/
    function test_tokenURI_permit_card_when_use6909_enabled() public {
        // A) enable use6909ForPermits via self-call governance
        bytes memory dataA = abi.encodeWithSelector(saw.setUse6909ForPermits.selector, true);
        bytes32 na = bytes32("A");
        bytes32 hA = saw.proposalId(0, address(saw), 0, dataA, na);
        _voteYes(hA);

        // Do NOT expect a specific first log; setUse6909ForPermits emits before Executed.
        (bool okA,) = saw.executeByVotes(0, address(saw), 0, dataA, na);
        assertTrue(okA, "execute setUse6909ForPermits");
        assertTrue(saw.use6909ForPermits(), "flag should be on");

        // B) set a permit (count=3) and ensure tokenURI renders a Permit card
        uint8 opB = 0;
        address toB = address(0xBEEF);
        uint256 valB = 0;
        bytes memory datB = "";
        bytes32 nb = bytes32("B");

        // this is the 6909 id (same as the intent hash)
        bytes32 permitHash = saw.proposalId(opB, toB, valB, datB, nb);

        bytes memory dataB = abi.encodeWithSelector(
            saw.setPermit.selector, opB, toB, valB, datB, nb, uint256(3), true
        );
        bytes32 hB = saw.proposalId(0, address(saw), 0, dataB, bytes32("B-call"));
        _voteYes(hB);
        (bool okB,) = saw.executeByVotes(0, address(saw), 0, dataB, bytes32("B-call"));
        assertTrue(okB, "execute setPermit");

        // mirror checks
        assertEq(saw.permits(permitHash), 3, "permit count");
        assertEq(saw.totalSupply(uint256(permitHash)), 3, "6909 supply mirrored");

        // tokenURI should present a Permit card with a count
        string memory uri = saw.tokenURI(uint256(permitHash));
        assertTrue(_contains(uri, "Permit"), "expected Permit card");
        assertTrue(_contains(uri, "count"), "should display count");
    }

    /*───────────────────────────────────────────────────────────────────*
     * 6) receiptURI returns non-empty JSON for a cast vote
     *───────────────────────────────────────────────────────────────────*/
    function test_receiptURI_nonempty_after_vote() public {
        bytes32 h = saw.proposalId(0, address(this), 0, bytes(""), bytes32("REC"));
        _voteYes(h);

        uint256 rid = uint256(keccak256(abi.encodePacked("SAW:receipt", h, uint8(1))));
        string memory uri = saw.receiptURI(rid);
        assertTrue(bytes(uri).length > 0, "receiptURI empty");
        assertTrue(_contains(uri, "Vote Receipt"), "missing receipt heading");
    }

    /*───────────────────────────────────────────────────────────────────*
    * Timelock queue & execute-after-delay
    *───────────────────────────────────────────────────────────────────*/
    function test_timelock_queue_and_execute_after_delay() public {
        // Install a 1-hour timelock
        bytes memory setDelay = abi.encodeWithSelector(SAW.setTimelockDelay.selector, uint64(3600));
        (, bool okDelay) = _openAndPass(0, address(saw), 0, setDelay, keccak256("set-delay"));
        assertTrue(okDelay, "timelock set");

        // Build a passing proposal
        bytes memory callData = abi.encodeWithSelector(Target.store.selector, 5);
        bytes32 h = _id(0, address(target), 0, callData, keccak256("tl-prop"));
        _open(h);
        _voteYes(h, alice);
        _voteYes(h, bob);

        // First execute queues and returns early
        (bool queued,) = saw.executeByVotes(0, address(target), 0, callData, keccak256("tl-prop"));
        assertTrue(queued, "queued");
        uint64 qAt = saw.queuedAt(h);
        assertTrue(qAt != 0, "queuedAt set");

        // Before delay elapses, a second execute MUST revert (accept any revert for robustness)
        vm.warp(uint256(qAt) + 1);
        vm.expectRevert();
        saw.executeByVotes(0, address(target), 0, callData, keccak256("tl-prop"));

        // After delay, it should execute successfully
        vm.warp(uint256(qAt) + 3600 + 1);
        (bool okExec,) = saw.executeByVotes(0, address(target), 0, callData, keccak256("tl-prop"));
        assertTrue(okExec, "executed after delay");
        assertEq(target.stored(), 5, "effect applied");
    }

    /*───────────────────────────────────────────────────────────────────*
     * TTL expiry blocks voting and execution; state=Expired
     *───────────────────────────────────────────────────────────────────*/
    function test_proposalTTL_expiry_blocks_vote_and_execute() public {
        bytes memory d = abi.encodeWithSelector(SAW.setProposalTTL.selector, uint64(2));
        (, bool ok) = _openAndPass(0, address(saw), 0, d, keccak256("ttl-2"));
        assertTrue(ok, "TTL set");

        bytes32 h = _id(0, address(target), 0, "", keccak256("ttl-prop"));
        saw.openProposal(h);
        vm.warp(block.timestamp + 3); // past TTL

        vm.expectRevert(SAW.NotOk.selector);
        vm.prank(alice);
        saw.castVote(h, 1);

        assertEq(uint256(saw.state(h)), uint256(SAW.ProposalState.Expired), "state=Expired");

        vm.expectRevert(SAW.NotOk.selector);
        saw.executeByVotes(0, address(target), 0, "", keccak256("ttl-prop"));
    }

    /*───────────────────────────────────────────────────────────────────*
     * Genesis snapshot path (snap=0) uses getVotes; receipts mint with full weight
     *───────────────────────────────────────────────────────────────────*/
    function test_genesis_snapshot_vote_path_mints_receipts() public {
        // Foundry starts at block 1 → open now => snapshotBlock=0
        bytes32 h = _id(0, address(this), 0, "", bytes32("GEN"));
        saw.openProposal(h);
        assertEq(saw.snapshotBlock(h), 0, "snap=0");

        vm.prank(alice);
        saw.castVote(h, 1);
        vm.prank(bob);
        saw.castVote(h, 1);

        uint256 ridYes = uint256(keccak256(abi.encodePacked("SAW:receipt", h, uint8(1))));
        assertEq(saw.totalSupply(ridYes), 100e18, "receipt supply = 60e18 + 40e18");
        assertEq(saw.receiptProposal(ridYes), h, "receipt->proposal");
    }

    /*───────────────────────────────────────────────────────────────────*
     * Absolute YES floor defeats if below minimum
     *───────────────────────────────────────────────────────────────────*/
    function test_minYesVotesAbsolute_defeats_if_below_floor() public {
        // Set an absolute YES floor to 70e18 (above Alice's 60e18 vote)
        bytes memory d = abi.encodeWithSelector(SAW.setMinYesVotesAbsolute.selector, uint256(70e18));
        (, bool ok) = _openAndPass(0, address(saw), 0, d, keccak256("floor-70"));
        assertTrue(ok, "floor set");

        // Open a proposal and only Alice votes YES (60e18 < 70e18)
        bytes32 h = _id(0, address(target), 0, "", keccak256("min-prop"));
        _open(h);
        _voteYes(h, alice); // Bob does NOT vote

        // Execution must fail under current semantics with NotOk (falls through to failed call)
        vm.expectRevert(SAW.NotOk.selector);
        saw.executeByVotes(0, address(target), 0, "", keccak256("min-prop"));
    }

    /*───────────────────────────────────────────────────────────────────*
     * Absolute turnout quorum blocks execution even with unanimous YES
     *───────────────────────────────────────────────────────────────────*/
    function test_quorumAbsolute_blocks_even_with_majority() public {
        uint256 req = shares.totalSupply() + 1; // unreachable
        bytes memory d = abi.encodeWithSelector(SAW.setQuorumAbsolute.selector, req);
        (, bool ok) = _openAndPass(0, address(saw), 0, d, keccak256("qabs"));
        assertTrue(ok, "abs quorum set");

        bytes32 h = _id(0, address(target), 0, "", keccak256("qabs-prop"));
        _open(h);
        _voteYes(h, alice);
        _voteYes(h, bob);

        assertEq(uint256(saw.state(h)), uint256(SAW.ProposalState.Active), "still Active");
        vm.expectRevert(SAW.NotApprover.selector);
        saw.executeByVotes(0, address(target), 0, "", keccak256("qabs-prop"));
    }

    /*───────────────────────────────────────────────────────────────────*
     * ERC6909 mirror for permits decrements on spend (finite count)
     *───────────────────────────────────────────────────────────────────*/
    function test_permit_mirror_decrements_on_spend() public {
        // enable 6909 mirroring for permits
        bytes memory en = abi.encodeWithSelector(SAW.setUse6909ForPermits.selector, true);
        (, bool ok) = _openAndPass(0, address(saw), 0, en, keccak256("perm-mirror-on"));
        assertTrue(ok, "mirror on");

        // set a 2-use permit for target.store(8)
        bytes memory call = abi.encodeWithSelector(Target.store.selector, 8);
        bytes32 nz = keccak256("perm-2");
        bytes memory set = abi.encodeWithSelector(
            SAW.setPermit.selector, 0, address(target), 0, call, nz, 2, true
        );
        (, bool ok2) = _openAndPass(0, address(saw), 0, set, keccak256("perm-set"));
        assertTrue(ok2, "permit set");

        bytes32 hPermit = _id(0, address(target), 0, call, nz);
        uint256 id = uint256(hPermit);

        assertEq(saw.permits(hPermit), 2, "count=2");
        assertEq(saw.totalSupply(id), 2, "mirror=2");

        // spend once → both on-chain permit and mirror drop by 1
        vm.prank(alice);
        saw.permitExecute(0, address(target), 0, call, nz);

        assertEq(saw.permits(hPermit), 1, "count=1");
        assertEq(saw.totalSupply(id), 1, "mirror=1");
    }

    /*───────────────────────────────────────────────────────────────────*
     * Futarchy YES path (ETH reward): resolve on success & cash out
     *───────────────────────────────────────────────────────────────────*/
    function test_futarchy_yes_eth_cashout() public {
        // futarchy-enabled proposal h (self-call to openFutarchy)
        bytes memory call = abi.encodeWithSelector(Target.store.selector, 123);
        bytes32 h = _id(0, address(target), 0, call, keccak256("FY"));
        bytes memory dOpen = abi.encodeWithSelector(SAW.openFutarchy.selector, h, address(0));
        (, bool ok) = _openAndPass(0, address(saw), 0, dOpen, keccak256("openFut-eth"));
        assertTrue(ok, "futarchy opened");

        // vote YES both
        vm.prank(alice);
        saw.castVote(h, 1);
        vm.prank(bob);
        saw.castVote(h, 1);

        // fund with ETH (100e18) → payout/unit = 1
        vm.deal(address(this), 100 ether);
        saw.fundFutarchy{value: 100e18}(h, 100e18);

        // execute call → YES wins and resolves
        (bool exec,) = saw.executeByVotes(0, address(target), 0, call, keccak256("FY"));
        assertTrue(exec, "executed");
        assertEq(target.stored(), 123, "target updated");

        (,,, bool resolved, uint8 winner,, uint256 ppu) = saw.futarchy(h);
        assertTrue(resolved, "resolved");
        assertEq(winner, 1, "YES winner");
        assertEq(ppu, 1, "payout/unit=1");

        uint256 ridYes = uint256(keccak256(abi.encodePacked("SAW:receipt", h, uint8(1))));
        uint256 balBefore = saw.balanceOf(alice, ridYes);
        uint256 ethBefore = alice.balance;

        vm.prank(alice);
        uint256 burnAmt = 10e18;
        uint256 paid = saw.cashOutFutarchy(h, burnAmt);

        assertEq(paid, burnAmt * ppu, "paid amount");
        assertEq(alice.balance, ethBefore + paid, "ETH received");
        assertEq(saw.balanceOf(alice, ridYes), balBefore - burnAmt, "receipts burned");
    }

    /*───────────────────────────────────────────────────────────────────*
     * Futarchy NO path (ERC20 reward): resolve after TTL & cash out
     *───────────────────────────────────────────────────────────────────*/
    function test_futarchy_no_erc20_cashout_after_expiry() public {
        // short TTL so we can expire quickly
        bytes memory dTTL = abi.encodeWithSelector(SAW.setProposalTTL.selector, uint64(2));
        (, bool okTTL) = _openAndPass(0, address(saw), 0, dTTL, keccak256("ttl-2"));
        assertTrue(okTTL, "TTL set");

        // futarchy-enabled proposal h with ERC20 reward
        bytes32 h = _id(0, address(this), 0, "", keccak256("FN"));
        bytes memory dOpen = abi.encodeWithSelector(SAW.openFutarchy.selector, h, address(tkn));
        (, bool ok) = _openAndPass(0, address(saw), 0, dOpen, keccak256("openFut-erc20"));
        assertTrue(ok, "futarchy opened (ERC20)");

        // vote AGAINST both so NO side has supply
        vm.prank(alice);
        saw.castVote(h, 0);
        vm.prank(bob);
        saw.castVote(h, 0);

        // fund ERC20 pool (100e18) → payout/unit = 1
        tkn.mint(address(this), 100e18);
        tkn.approve(address(saw), 100e18);
        saw.fundFutarchy(h, 100e18);

        // let TTL pass and resolve NO
        vm.warp(block.timestamp + 3);
        saw.resolveFutarchyNo(h);

        (,,, bool resolved, uint8 winner,, uint256 ppu) = saw.futarchy(h);
        assertTrue(resolved, "resolved");
        assertEq(winner, 0, "NO winner");
        assertEq(ppu, 1, "payout/unit=1");

        uint256 ridNo = uint256(keccak256(abi.encodePacked("SAW:receipt", h, uint8(0))));
        uint256 balNoBefore = saw.balanceOf(alice, ridNo);

        vm.prank(alice);
        uint256 paid = saw.cashOutFutarchy(h, 15e18);
        assertEq(paid, 15e18, "ERC20 paid");

        assertEq(tkn.balanceOf(alice), 15e18, "TKN received");
        assertEq(saw.balanceOf(alice, ridNo), balNoBefore - 15e18, "receipts burned");
    }

    /*───────────────────────────────────────────────────────────────────*
    * VOTING SAFETY / GUARDS
    *───────────────────────────────────────────────────────────────────*/
    function test_castVote_bounds_and_double_vote_reverts() public {
        bytes32 h = _id(0, address(this), 0, "", keccak256("bounds"));
        _open(h);

        // support out of range -> NotOk
        vm.expectRevert(SAW.NotOk.selector);
        vm.prank(alice);
        saw.castVote(h, 3);

        // first vote ok
        vm.prank(alice);
        saw.castVote(h, 1);

        // second vote same voter -> NotOk
        vm.expectRevert(SAW.NotOk.selector);
        vm.prank(alice);
        saw.castVote(h, 1);

        // no-weight voter -> NotOk
        vm.expectRevert(SAW.NotOk.selector);
        vm.prank(charlie); // has 0 shares
        saw.castVote(h, 1);
    }

    function test_execute_unopened_reverts() public {
        bytes32 h = _id(
            0, address(target), 0, abi.encodeWithSelector(Target.store.selector, 1), bytes32("x")
        );
        // unopened -> NotApprover
        vm.expectRevert(SAW.NotApprover.selector);
        saw.executeByVotes(
            0, address(target), 0, abi.encodeWithSelector(Target.store.selector, 1), bytes32("x")
        );
        assertEq(saw.snapshotBlock(h), 0, "still unopened");
    }

    /*───────────────────────────────────────────────────────────────────*
     * SNAPSHOT CORNER (GENESIS)
     *───────────────────────────────────────────────────────────────────*/
    function test_openProposal_at_block1_uses_block0_supply_fallback() public {
        vm.roll(1);
        vm.warp(1);
        bytes32 h = _id(0, address(this), 0, "", keccak256("genesis"));
        saw.openProposal(h);
        assertEq(saw.snapshotBlock(h), 0, "snap at block 0");
        assertEq(saw.supplySnapshot(h), shares.totalSupply(), "fallback supply recorded");
    }

    /*───────────────────────────────────────────────────────────────────*
     * QUEUE WITHOUT TIMELOCK = NO-OP (COVERAGE)
     *───────────────────────────────────────────────────────────────────*/
    function test_queue_no_timelock_is_noop() public {
        // simple passing proposal
        bytes memory callData = abi.encodeWithSelector(Target.store.selector, 123);
        bytes32 h = _id(0, address(target), 0, callData, keccak256("q-no-tl"));
        _open(h);
        _voteYes(h, alice);
        _voteYes(h, bob);

        // should not revert, and queuedAt stays zero
        saw.queue(h);
        assertEq(saw.queuedAt(h), 0, "no timelock => queue no-op");

        (bool ok,) = saw.executeByVotes(0, address(target), 0, callData, keccak256("q-no-tl"));
        assertTrue(ok, "exec ok");
        assertEq(target.stored(), 123);
    }

    /*───────────────────────────────────────────────────────────────────*
     * SALES EDGE: NON-MINTING WITHOUT INVENTORY REVERTS
     *───────────────────────────────────────────────────────────────────*/
    function test_buyShares_non_minting_without_inventory_reverts() public {
        // Set sale: minting=false but SAW has no shares preloaded
        bytes memory d =
            abi.encodeWithSelector(SAW.setSale.selector, address(0), uint256(1), 2e18, false, true);
        (, bool ok) = _openAndPass(0, address(saw), 0, d, keccak256("nonmint-noinv"));
        assertTrue(ok, "sale set");

        vm.expectRevert(); // underflow in SAWShares.transfer from SAW
        vm.prank(charlie);
        saw.buyShares{value: 2 ether}(address(0), 2e18, 0);
    }

    /*───────────────────────────────────────────────────────────────────*
     * 6909 PERMITS: MIRROR BEHAVIOR
     *───────────────────────────────────────────────────────────────────*/
    function test_permit_mirror_unlimited_does_not_mint_supply() public {
        // turn on mirroring
        bytes memory a = abi.encodeWithSelector(saw.setUse6909ForPermits.selector, true);
        (, bool okA) = _openAndPass(0, address(saw), 0, a, keccak256("6909-on"));
        assertTrue(okA && saw.use6909ForPermits(), "6909 on");

        // set MAX permit (replace)
        uint8 op = 0;
        address to = address(target);
        bytes memory dataCall = abi.encodeWithSelector(Target.store.selector, 55);
        bytes32 n = keccak256("p-max");
        bytes32 h = _id(op, to, 0, dataCall, n);

        bytes memory setMax = abi.encodeWithSelector(
            SAW.setPermit.selector, op, to, 0, dataCall, n, type(uint256).max, true
        );
        (, bool okM) = _openAndPass(0, address(saw), 0, setMax, keccak256("set-max"));
        assertTrue(okM, "set MAX");

        // mirror supply should remain zero for MAX
        assertEq(saw.totalSupply(uint256(h)), 0, "no mirror for MAX");

        // add more (no mirror mint because it's already MAX)
        bytes memory add = abi.encodeWithSelector(
            SAW.setPermit.selector, op, to, 0, dataCall, n, uint256(5), false
        );
        (, bool okAdd) = _openAndPass(0, address(saw), 0, add, keccak256("add-to-max"));
        assertTrue(okAdd, "add ignored for mirror");
        assertEq(saw.totalSupply(uint256(h)), 0, "still no mirror");
        assertEq(saw.permits(h), type(uint256).max, "still MAX");
    }

    function test_permit_no_mirror_when_flag_off() public {
        // mirroring default = off
        uint8 op = 0;
        address to = address(target);
        bytes memory dataCall = abi.encodeWithSelector(Target.store.selector, 101);
        bytes32 n = keccak256("p2");
        bytes32 h = _id(op, to, 0, dataCall, n);

        bytes memory set2 = abi.encodeWithSelector(
            SAW.setPermit.selector, op, to, 0, dataCall, n, uint256(2), true
        );
        (, bool ok) = _openAndPass(0, address(saw), 0, set2, keccak256("set2"));
        assertTrue(ok, "setPermit ok");
        assertEq(saw.permits(h), 2);
        assertEq(saw.totalSupply(uint256(h)), 0, "no mirror when off");
    }

    /*───────────────────────────────────────────────────────────────────*
     * RECEIPT ACCOUNTING
     *───────────────────────────────────────────────────────────────────*/
    function test_receipt_supply_matches_yes_votes() public {
        bytes32 h = _id(0, address(this), 0, "", keccak256("rx"));
        _open(h);
        vm.prank(alice);
        saw.castVote(h, 1);
        vm.prank(bob);
        saw.castVote(h, 1);

        uint256 ridYes = uint256(keccak256(abi.encodePacked("SAW:receipt", h, uint8(1))));
        uint256 ridNo = uint256(keccak256(abi.encodePacked("SAW:receipt", h, uint8(0))));

        // YES supply = 60e18 + 40e18
        assertEq(saw.totalSupply(ridYes), 100e18, "yes supply");
        assertEq(saw.totalSupply(ridNo), 0, "no supply");
    }

    /*───────────────────────────────────────────────────────────────────*
     * FUTARCHY — YES path, auto-resolve on execute, cash out in ETH
     *───────────────────────────────────────────────────────────────────*/
    function test_futarchy_yes_auto_resolve_and_cashout_eth() public {
        // intent to execute
        bytes memory callData = abi.encodeWithSelector(Target.store.selector, 11);
        bytes32 nonce = keccak256("FY");
        bytes32 h = _id(0, address(target), 0, callData, nonce);

        // enable futarchy for h (ETH reward)
        bytes memory openF = abi.encodeWithSelector(SAW.openFutarchy.selector, h, address(0));
        (, bool okOpen) = _openAndPass(0, address(saw), 0, openF, keccak256("f-yes-open"));
        assertTrue(okOpen, "futarchy opened");

        // fund 100 ETH
        vm.deal(address(this), 100 ether);
        saw.fundFutarchy{value: 100 ether}(h, 100 ether);

        // vote YES by both
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.prank(alice);
        saw.castVote(h, 1);
        vm.prank(bob);
        saw.castVote(h, 1);

        // execute → resolves YES side
        (bool ok,) = saw.executeByVotes(0, address(target), 0, callData, nonce);
        assertTrue(ok, "executed");
        assertEq(target.stored(), 11);

        // payout per unit = 100e18 / 100e18 = 1 wei
        (,,, bool resolved, uint8 winner,, uint256 ppu) = saw.futarchy(h);
        assertTrue(resolved && winner == 1 && ppu == 1, "resolved YES, ppu=1");

        uint256 ridYes = uint256(keccak256(abi.encodePacked("SAW:receipt", h, uint8(1))));
        uint256 aliceBefore = alice.balance;

        // cash out 10e18 units -> 10e18 wei
        vm.prank(alice);
        uint256 payout = saw.cashOutFutarchy(h, 10e18);
        assertEq(payout, 10e18, "payout matched");
        assertEq(alice.balance - aliceBefore, 10e18, "ETH received");
        assertEq(saw.balanceOf(alice, ridYes), 60e18 - 10e18, "receipts burned");
    }

    /*───────────────────────────────────────────────────────────────────*
     * FUTARCHY — NO path, resolve after TTL, cash out in ERC20
     *───────────────────────────────────────────────────────────────────*/
    function test_futarchy_no_resolve_after_TTL_and_cashout_erc20() public {
        // set TTL small (10s)
        bytes memory setTTL = abi.encodeWithSelector(SAW.setProposalTTL.selector, uint64(10));
        (, bool okTTL) = _openAndPass(0, address(saw), 0, setTTL, keccak256("ttl10"));
        assertTrue(okTTL, "ttl set");

        // intent h
        bytes memory callData = abi.encodeWithSelector(Target.store.selector, 77);
        bytes32 nonce = keccak256("FN");
        bytes32 h = _id(0, address(target), 0, callData, nonce);

        // open futarchy with ERC20 reward
        bytes memory openF = abi.encodeWithSelector(SAW.openFutarchy.selector, h, address(tkn));
        (, bool okOpen) = _openAndPass(0, address(saw), 0, openF, keccak256("f-no-open"));
        assertTrue(okOpen, "futarchy opened");

        // fund 1000 TKN from this test contract
        tkn.mint(address(this), 1000e18);
        tkn.approve(address(saw), type(uint256).max);
        saw.fundFutarchy(h, 1000e18);

        // vote AGAINST by both → proposal never executes
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.prank(alice);
        saw.castVote(h, 0);
        vm.prank(bob);
        saw.castVote(h, 0);

        // cannot resolve before TTL
        vm.expectRevert(SAW.NotOk.selector);
        saw.resolveFutarchyNo(h);

        // after TTL, resolve NO
        vm.warp(block.timestamp + 11);
        saw.resolveFutarchyNo(h);

        (,, uint256 pool, bool resolved, uint8 winner, uint256 winSupply, uint256 ppu) =
            saw.futarchy(h);
        assertTrue(resolved && winner == 0, "resolved NO");
        // pool=1000e18, winSupply=100e18 -> ppu=10
        assertEq(pool, 1000e18);
        assertEq(winSupply, 100e18);
        assertEq(ppu, 10);

        // Bob cashes out 20e18 units -> 200e18 TKN
        uint256 bobBefore = tkn.balanceOf(bob);
        vm.prank(bob);
        uint256 payout = saw.cashOutFutarchy(h, 20e18);
        assertEq(payout, 200e18, "erc20 payout");
        assertEq(tkn.balanceOf(bob) - bobBefore, 200e18, "tokens received");
    }

    /*───────────────────────────────────────────────────────────────────*
     * FUTARCHY RECEIPT URI STATUS CHANGES
     *───────────────────────────────────────────────────────────────────*/
    function test_receiptURI_status_transitions_with_futarchy() public {
        // set up a future intent h
        bytes memory callData = abi.encodeWithSelector(Target.store.selector, 202);
        bytes32 nonce = keccak256("FSTAT");
        bytes32 h = _id(0, address(target), 0, callData, nonce);

        // open futarchy (ETH)
        bytes memory openF = abi.encodeWithSelector(SAW.openFutarchy.selector, h, address(0));
        (, bool okOpen) = _openAndPass(0, address(saw), 0, openF, keccak256("f-open"));
        assertTrue(okOpen);

        // fund and vote YES
        vm.deal(address(this), 1 ether);
        saw.fundFutarchy{value: 1 ether}(h, 1 ether);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.prank(alice);
        saw.castVote(h, 1);
        vm.prank(bob);
        saw.castVote(h, 1);

        uint256 ridYes = uint256(keccak256(abi.encodePacked("SAW:receipt", h, uint8(1))));
        uint256 ridNo = uint256(keccak256(abi.encodePacked("SAW:receipt", h, uint8(0))));

        // before execution → "status: open"
        string memory u1 = saw.receiptURI(ridYes);
        assertTrue(_contains(u1, "status: open"), "should be open");

        // execute -> YES wins
        (bool ok,) = saw.executeByVotes(0, address(target), 0, callData, nonce);
        assertTrue(ok, "exec");

        // after execution → YES: winner, NO: loser + payout/unit present
        string memory uy = saw.receiptURI(ridYes);
        string memory un = saw.receiptURI(ridNo);
        assertTrue(_contains(uy, "winner"), "yes winner");
        assertTrue(_contains(un, "loser"), "no loser");
        assertTrue(_contains(uy, "payout/unit:"), "ppu present");
    }

    /*───────────────────────────────────────────────────────────────────*
     * Tiny util: pretty-print an address to compare in strings if needed
     * (not strictly required, but handy if you extend tests)
     *───────────────────────────────────────────────────────────────────*/
    function _toStringAddress(address a) internal pure returns (string memory) {
        bytes20 b = bytes20(a);
        bytes16 H = 0x30313233343536373839616263646566; // "0123456789abcdef"
        bytes memory out = new bytes(42);
        out[0] = "0";
        out[1] = "x";
        for (uint256 i = 0; i < 20; ++i) {
            uint8 v = uint8(b[i]);
            out[2 + 2 * i] = bytes1(H[v >> 4]);
            out[3 + 2 * i] = bytes1(H[v & 0x0f]);
        }
        return string(out);
    }

    function test_rageQuit_reentrancy_blocked() public {
        // Deploy reentrant token and fund SAW
        ReentrantERC20 rtkn = new ReentrantERC20("R", "R", 18);
        rtkn.mint(address(saw), 1_000e18);

        // Holder that will rageQuit
        RageQuitHook hook = new RageQuitHook(saw, address(rtkn));

        // Give hook some shares so it can rageQuit
        vm.prank(alice);
        shares.transfer(address(hook), 1e18);

        // Arm token to attempt reentry during transfer
        rtkn.arm(saw, address(hook));

        // Call rageQuit: OUTER CALL SHOULD SUCCEED (inner reentry will revert)
        vm.prank(address(hook));
        saw.rageQuit(_array(address(rtkn)));

        // Assert: the reentry was attempted and blocked
        assertTrue(rtkn.reenterAttempted(), "reentry was not attempted");

        // Optional sanity: hook got its pro-rata payout
        assertGt(rtkn.balanceOf(address(hook)), 0, "hook did not receive payout");
        // and its shares were burned
        assertEq(shares.balanceOf(address(hook)), 0, "hook shares not burned");
    }

    function _array(address a) internal pure returns (address[] memory x) {
        x = new address[](1);
        x[0] = a;
    }

    function test_permitExecute_resolves_futarchy_yes() public {
        // ===== Base intent: no-op call to this contract (so permitExecute can succeed)
        uint8 op = 0;
        address to = address(this);
        uint256 val = 0;
        bytes memory callData = "";
        bytes32 nonce = keccak256("fut-permit");
        bytes32 h = saw.proposalId(op, to, val, callData, nonce);

        // ===== Governance: open futarchy on h via self-call proposal
        bytes memory openData = abi.encodeWithSelector(SAW.openFutarchy.selector, h, address(0));
        bytes32 openH = saw.proposalId(0, address(saw), 0, openData, keccak256("open-fut"));

        vm.startPrank(alice);
        // Ensure snapshot block for openH is non-zero so state() won't treat it as Unopened.
        vm.roll(block.number + 2);
        saw.castVote(openH, 1); // auto-opens at (block.number - 1) >= 1, gives Alice 60e18 YES
        (bool ok1,) = saw.executeByVotes(0, address(saw), 0, openData, keccak256("open-fut"));
        assertTrue(ok1, "openFutarchy executed");

        // Fund futarchy pool with 1 wei (enough to make payout path defined)
        saw.fundFutarchy{value: 1}(h, 1);
        vm.stopPrank();

        // ===== YES receipts on h so winning supply > 0
        vm.roll(block.number + 1);
        vm.prank(bob);
        saw.castVote(h, 1); // Bob votes YES (auto-opens h with non-zero snapshot)

        // ===== Set a single-use PERMIT for the same tuple via governance
        bytes memory setPermitData = abi.encodeWithSelector(
            SAW.setPermit.selector, op, to, val, callData, nonce, uint256(1), true
        );
        bytes32 permitH =
            saw.proposalId(0, address(saw), 0, setPermitData, keccak256("set-permit-fut"));

        vm.startPrank(alice);
        vm.roll(block.number + 1);
        saw.castVote(permitH, 1);
        (ok1,) = saw.executeByVotes(0, address(saw), 0, setPermitData, keccak256("set-permit-fut"));
        assertTrue(ok1, "permit set");
        vm.stopPrank();

        // ===== Spend the permit (permitExecute should also resolve futarchy YES inside SAW.permitExecute)
        vm.prank(charlie);
        (bool ok2,) = saw.permitExecute(op, to, val, callData, nonce);
        assertTrue(ok2, "permit exec");

        // ===== Futarchy should now be resolved with YES winning
        (bool en,, SAW.FutarchyConfig memory F) = _getFutarchy(saw, h);
        assertTrue(en, "enabled");
        assertTrue(F.resolved, "resolved");
        assertEq(F.winner, 1, "YES wins");
    }

    // Helper to read futarchy config in a struct-friendly way.
    function _getFutarchy(SAW s, bytes32 h)
        internal
        view
        returns (bool enabled, uint8 winner, SAW.FutarchyConfig memory F)
    {
        (bool en, address rt, uint256 pool, bool res, uint8 win, uint256 fws, uint256 ppu) =
            s.futarchy(h);
        F = SAW.FutarchyConfig({
            enabled: en,
            rewardToken: rt,
            pool: pool,
            resolved: res,
            winner: win,
            finalWinningSupply: fws,
            payoutPerUnit: ppu
        });
        enabled = en;
        winner = win;
    }

    /*───────────────────────────────────────────────────────────────────*
     * A) Non-SAW spender cannot “drain” by sending to SAW repeatedly
     *───────────────────────────────────────────────────────────────────*/
    function test_shares_transferFrom_toSAW_decrements_for_nonSAW() public {
        address mallory = address(0xBADD);
        vm.label(mallory, "MALLORY");

        // Bob approves Mallory for 1e18
        vm.prank(bob);
        shares.approve(mallory, 1e18);

        // First transferFrom to SAW succeeds and MUST decrement allowance
        vm.prank(mallory);
        shares.transferFrom(bob, address(saw), 6e17);
        assertEq(shares.allowance(bob, mallory), 4e17, "allowance must decrement for non-SAW");

        // Second oversized spend should revert due to insufficient allowance
        vm.expectRevert(); // underflow on allowance
        vm.prank(mallory);
        shares.transferFrom(bob, address(saw), 5e17);
    }

    /*───────────────────────────────────────────────────────────────────*
     * B) Top-256 eviction removes the TRUE minimum holder, not slot 255
     *───────────────────────────────────────────────────────────────────*/
    function test_top256_eviction_removes_true_min_balance() public {
        // Make minting sale (price=0) so we can cheaply fill the set
        bytes memory dSale = abi.encodeWithSelector(
            SAW.setSale.selector, address(0), uint256(0), type(uint256).max, true, true
        );
        (, bool ok) = _openAndPass(0, address(saw), 0, dSale, keccak256("free-sale"));
        assertTrue(ok, "free sale enabled");

        // Fill up to 255 holders with 2e18 each (Alice/Bob already in set)
        for (uint256 i = 1; i <= 253; ++i) {
            address w = vm.addr(uint256(keccak256(abi.encode("W", i))));
            vm.deal(w, 1 ether);
            vm.prank(w);
            saw.buyShares{value: 0}(address(0), 2e18, 0);
            assertEq(badge.balanceOf(w), 1, "badge minted on entry");
        }

        // Add a unique minimum holder with 1e18 (fills slot #256)
        address minnee = vm.addr(uint256(keccak256("MINNEE")));
        vm.deal(minnee, 1 ether);
        vm.prank(minnee);
        saw.buyShares{value: 0}(address(0), 1e18, 0);
        assertEq(badge.balanceOf(minnee), 1, "minnee entered top set");

        // Newcomer with 3e18 should evict the TRUE minimum (minnee)
        address newcomer = vm.addr(uint256(keccak256("NEWCOMER")));
        vm.deal(newcomer, 1 ether);
        vm.prank(newcomer);
        saw.buyShares{value: 0}(address(0), 3e18, 0);

        // After fix: minnee evicted, newcomer in; before fix: random slot (often 255) evicted
        assertEq(saw.rankOf(minnee), 0, "true minimum was evicted");
        assertEq(badge.balanceOf(minnee), 0, "minnee badge burned");
        assertTrue(saw.rankOf(newcomer) != 0, "newcomer admitted");
        assertEq(badge.balanceOf(newcomer), 1, "newcomer badge minted");
    }

    /*───────────────────────────────────────────────────────────────*
    * FUTARCHY — ETH path: YES wins, resolve & cash out
    *───────────────────────────────────────────────────────────────*/
    function test_futarchy_eth_yes_resolve_and_cashout() public {
        // Proposal we'll resolve (dummy no-op call to this test contract)
        bytes memory dcall = "";
        bytes32 nonce = keccak256("F-ETH");
        bytes32 h = _id(0, address(this), 0, dcall, nonce);

        // Enable futarchy on the proposal via governance
        bytes memory dOpen = abi.encodeWithSelector(SAW.openFutarchy.selector, h, address(0));
        (, bool okOpen) = _openAndPass(0, address(saw), 0, dOpen, keccak256("F-ETH-open"));
        assertTrue(okOpen, "openFutarchy set");

        // Open & vote YES by both holders (mint YES receipts)
        _open(h);
        _voteYes(h, alice);
        _voteYes(h, bob);

        // Fund pool in ETH (big enough for non-zero payoutPerUnit)
        vm.deal(address(this), 200 ether);
        saw.fundFutarchy{value: 200 ether}(h, 200 ether);

        // Execute proposal to trigger _resolveFutarchyYes
        (bool okExec,) = saw.executeByVotes(0, address(this), 0, dcall, nonce);
        assertTrue(okExec, "exec ok");

        (
            bool enabled,
            address rTok,
            uint256 pool,
            bool resolved,
            uint8 winner,
            uint256 finalSupply,
            uint256 ppu
        ) = saw.futarchy(h);
        assertTrue(enabled && resolved, "futarchy not resolved");
        assertEq(rTok, address(0), "reward token != ETH");
        assertEq(pool, 200 ether);
        assertEq(winner, 1, "YES should win");
        assertGt(finalSupply, 0, "no supply?");
        assertGt(ppu, 0, "zero ppu");

        // Cash out a tiny portion of Alice’s YES receipts
        uint256 ridYes = uint256(keccak256(abi.encodePacked("SAW:receipt", h, uint8(1))));
        uint256 aliceBalBefore = alice.balance;
        uint256 aliceYesBefore = saw.balanceOf(alice, ridYes);

        vm.prank(alice);
        saw.cashOutFutarchy(h, 1e18); // burn 1e18 receipt units

        assertEq(saw.balanceOf(alice, ridYes), aliceYesBefore - 1e18, "receipt not burned");
        assertEq(alice.balance - aliceBalBefore, ppu * 1e18, "wrong ETH payout");
    }

    /*───────────────────────────────────────────────────────────────*
     * FUTARCHY — ERC20 path: NO wins via TTL expiry, resolve & cash out
     *───────────────────────────────────────────────────────────────*/
    function test_futarchy_erc20_no_resolve_after_ttl_and_cashout() public {
        // Set a short TTL via governance
        bytes memory dTTL = abi.encodeWithSelector(SAW.setProposalTTL.selector, uint64(2));
        (, bool okT) = _openAndPass(0, address(saw), 0, dTTL, keccak256("ttl=2s"));
        assertTrue(okT, "ttl set");

        // Proposal hash & enable futarchy with ERC20 reward
        bytes memory dcall = "";
        bytes32 nonce = keccak256("F-ERC20");
        bytes32 h = _id(0, address(this), 0, dcall, nonce);

        // Funder preps ERC20 and funds the pool
        tkn.mint(alice, 1_000e18);
        vm.prank(alice);
        tkn.approve(address(saw), 1_000e18);

        bytes memory dOpen = abi.encodeWithSelector(SAW.openFutarchy.selector, h, address(tkn));
        (, bool okOpen) = _openAndPass(0, address(saw), 0, dOpen, keccak256("F-ERC20-open"));
        assertTrue(okOpen, "openFutarchy set");

        _open(h);
        vm.prank(alice); // NO
        saw.castVote(h, 0);
        vm.prank(bob); // NO
        saw.castVote(h, 0);

        // Fund after votes (ok either way)
        vm.prank(alice);
        saw.fundFutarchy(h, 500e18);

        // Before resolution, cashOut should revert
        vm.expectRevert(SAW.NotOk.selector);
        vm.prank(alice);
        saw.cashOutFutarchy(h, 1e18);

        // After TTL -> resolve NO
        vm.warp(block.timestamp + 3);
        saw.resolveFutarchyNo(h);

        (,, uint256 pool, bool resolved, uint8 winner,, uint256 ppu) = saw.futarchy(h);
        assertTrue(resolved, "not resolved");
        assertEq(winner, 0, "NO should win");
        assertEq(pool, 500e18);
        assertGt(ppu, 0, "zero ppu");

        // Alice cashes out a portion of NO receipts
        uint256 ridNo = uint256(keccak256(abi.encodePacked("SAW:receipt", h, uint8(0))));
        uint256 aliceNoBefore = saw.balanceOf(alice, ridNo);
        uint256 tknBefore = tkn.balanceOf(alice);

        vm.prank(alice);
        saw.cashOutFutarchy(h, 1e18);

        assertEq(saw.balanceOf(alice, ridNo), aliceNoBefore - 1e18, "NO receipt not burned");
        assertEq(tkn.balanceOf(alice) - tknBefore, ppu * 1e18, "wrong ERC20 payout");
    }

    /*───────────────────────────────────────────────────────────────*
     * 6909 PERMIT MIRROR — replaceCount burn + burn-on-spend
     *───────────────────────────────────────────────────────────────*/
    function test_permit_mirror_replace_burns_supply() public {
        // Turn on mirroring
        bytes memory dFlag = abi.encodeWithSelector(SAW.setUse6909ForPermits.selector, true);
        (, bool okF) = _openAndPass(0, address(saw), 0, dFlag, keccak256("6909-on"));
        assertTrue(okF);

        // Create a permit with count=5 (replace)
        bytes32 pHash = _id(
            0, address(target), 0, abi.encodeWithSelector(Target.store.selector, 1), bytes32("PM")
        );
        bytes memory dSet5 = abi.encodeWithSelector(
            SAW.setPermit.selector,
            0,
            address(target),
            0,
            abi.encodeWithSelector(Target.store.selector, 1),
            bytes32("PM"),
            uint256(5),
            true
        );
        (, bool ok1) = _openAndPass(0, address(saw), 0, dSet5, keccak256("set-5"));
        assertTrue(ok1);
        assertEq(saw.permits(pHash), 5);
        assertEq(saw.totalSupply(uint256(pHash)), 5);

        // Replace with 0 -> should burn all mirrored supply
        bytes memory dZero = abi.encodeWithSelector(
            SAW.setPermit.selector,
            0,
            address(target),
            0,
            abi.encodeWithSelector(Target.store.selector, 1),
            bytes32("PM"),
            uint256(0),
            true
        );
        (, bool ok2) = _openAndPass(0, address(saw), 0, dZero, keccak256("set-0"));
        assertTrue(ok2);
        assertEq(saw.permits(pHash), 0);
        assertEq(saw.totalSupply(uint256(pHash)), 0, "mirror supply not burned");
    }

    function test_permit_mirror_burn_on_spend() public {
        // Enable mirror + set count=3
        bytes memory dFlag = abi.encodeWithSelector(SAW.setUse6909ForPermits.selector, true);
        (, bool okF) = _openAndPass(0, address(saw), 0, dFlag, keccak256("6909-on-2"));
        assertTrue(okF);

        bytes memory call = abi.encodeWithSelector(Target.store.selector, 123);
        bytes32 nonceX = keccak256("PM-SPEND");
        bytes32 pHash = _id(0, address(target), 0, call, nonceX);

        bytes memory dSet3 = abi.encodeWithSelector(
            SAW.setPermit.selector, 0, address(target), 0, call, nonceX, uint256(3), true
        );
        (, bool okS) = _openAndPass(0, address(saw), 0, dSet3, keccak256("set-3"));
        assertTrue(okS);
        assertEq(saw.totalSupply(uint256(pHash)), 3);

        // Spend one → mirrored supply & permits decrease
        vm.prank(charlie);
        (bool ok,) = saw.permitExecute(0, address(target), 0, call, nonceX);
        assertTrue(ok);
        assertEq(saw.permits(pHash), 2);
        assertEq(saw.totalSupply(uint256(pHash)), 2, "mirror supply should decrease by 1");
    }

    /*───────────────────────────────────────────────────────────────*
     * tokenURI state labels: executed & expired
     *───────────────────────────────────────────────────────────────*/
    function test_tokenURI_shows_executed_and_expired() public {
        // Executed
        bytes memory dcall = "";
        bytes32 hE = _id(0, address(this), 0, dcall, bytes32("EXEC"));
        _open(hE);
        _voteYes(hE, alice);
        _voteYes(hE, bob);
        (bool ok,) = saw.executeByVotes(0, address(this), 0, dcall, bytes32("EXEC"));
        assertTrue(ok);
        string memory u1 = saw.tokenURI(uint256(hE));
        assertTrue(_contains(u1, "state: executed"), "executed state missing");

        // Expired
        bytes memory dTTL = abi.encodeWithSelector(SAW.setProposalTTL.selector, uint64(1));
        (, bool okT) = _openAndPass(0, address(saw), 0, dTTL, keccak256("ttl-1"));
        assertTrue(okT);

        bytes32 hX = _id(0, address(this), 0, "", bytes32("EXPIRE"));
        saw.openProposal(hX);
        vm.warp(block.timestamp + 2); // after createdAt + TTL
        string memory u2 = saw.tokenURI(uint256(hX));
        assertTrue(_contains(u2, "expired"), "expired state missing");
    }

    /*───────────────────────────────────────────────────────────────*
     * Access control guards for governance-only functions
     *───────────────────────────────────────────────────────────────*/
    function test_access_controls_onlySAW_calls() public {
        bytes32 h = _id(0, address(this), 0, "", bytes32("AC"));
        // Direct external calls should revert NotOwner
        vm.expectRevert(SAW.NotOwner.selector);
        saw.openFutarchy(h, address(0));

        vm.expectRevert(SAW.NotOwner.selector);
        saw.setUse6909ForPermits(true);

        vm.expectRevert(SAW.NotOwner.selector);
        saw.setQuorumAbsolute(123);
    }

    /*───────────────────────────────────────────────────────────────*
     * Non-minting sale:
     *  (a) still works when transfers are locked (SAW is exempt)
     *  (b) reverts if SAW lacks share balance
     *───────────────────────────────────────────────────────────────*/
    function test_nonminting_sale_works_when_locked() public {
        // Preload SAW with shares
        vm.prank(alice);
        shares.transfer(address(saw), 3e18);

        // Lock transfers globally
        bytes memory dLock = abi.encodeWithSelector(SAW.setTransfersLocked.selector, true);
        (, bool okL) = _openAndPass(0, address(saw), 0, dLock, keccak256("lock"));
        assertTrue(okL);

        // Non-minting sale: cap 2e18
        bytes memory dSale =
            abi.encodeWithSelector(SAW.setSale.selector, address(0), uint256(1), 2e18, false, true);
        (, bool okS) = _openAndPass(0, address(saw), 0, dSale, keccak256("sale-nonmint"));
        assertTrue(okS);

        vm.prank(charlie);
        saw.buyShares{value: 2 ether}(address(0), 2e18, 0); // should succeed
        assertEq(shares.balanceOf(charlie), 2e18, "buy failed under lock");
    }

    function test_nonminting_sale_insufficient_SAW_balance_reverts() public {
        // SAW has 0 shares; set a non-minting sale for 2e18
        bytes memory dSale =
            abi.encodeWithSelector(SAW.setSale.selector, address(0), uint256(1), 2e18, false, true);
        (, bool okS) = _openAndPass(0, address(saw), 0, dSale, keccak256("sale-noinv"));
        assertTrue(okS);

        vm.expectRevert(); // arithmetic underflow in SAWShares.transfer()
        vm.prank(charlie);
        saw.buyShares{value: 2 ether}(address(0), 2e18, 0);
    }

    /*───────────────────────────────────────────────────────────────*
     * _safeTransfer / _safeTransferFrom hard-fails propagate (NotOk)
     *───────────────────────────────────────────────────────────────*/
    function test_claimAllowance_badERC20_transfer_false_reverts() public {
        BadERC20False bad = new BadERC20False();
        bad.mint(address(saw), 100e18);

        // Allow Alice 10 BAD via governance
        bytes memory d =
            abi.encodeWithSelector(SAW.setAllowanceTo.selector, address(bad), alice, 10e18);
        (, bool okA) = _openAndPass(0, address(saw), 0, d, keccak256("allow-bad"));
        assertTrue(okA);

        vm.expectRevert(SAW.NotOk.selector);
        vm.prank(alice);
        saw.claimAllowance(address(bad), 1e18);
    }

    function test_pull_badERC20_transferFrom_false_reverts() public {
        BadERC20False bad = new BadERC20False();
        bad.mint(bob, 50e18);
        vm.prank(bob);
        bad.approve(address(saw), 50e18);

        // Try to pull via governance -> inner call returns false -> NotOk
        bytes memory dPull = abi.encodeWithSelector(SAW.pull.selector, address(bad), bob, 10e18);
        bytes32 h = _id(0, address(saw), 0, dPull, keccak256("pull-bad"));

        // Open & pass, but expect execute to revert NotOk
        _open(h);
        _voteYes(h, alice);
        _voteYes(h, bob);
        vm.expectRevert(SAW.NotOk.selector);
        saw.executeByVotes(0, address(saw), 0, dPull, keccak256("pull-bad"));
    }

    // Accept empty calldata calls (no-op target for replay test).
    receive() external payable {}
    fallback() external payable {}
}

/// Simple call target
contract Target {
    uint256 public stored;
    event Called(uint256 val, uint256 msgValue);

    function store(uint256 x) public payable {
        stored = x;
        emit Called(x, msg.value);
    }
}

/// Minimal ERC20 for testing.
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    constructor(string memory _n, string memory _s, uint8 _d) payable {
        name = _n;
        symbol = _s;
        decimals = _d;
    }

    function mint(address to, uint256 amt) public {
        balanceOf[to] += amt;
        emit Transfer(address(0), to, amt);
    }

    function approve(address sp, uint256 amt) public virtual returns (bool) {
        allowance[msg.sender][sp] = amt;
        emit Approval(msg.sender, sp, amt);
        return true;
    }

    function transfer(address to, uint256 amt) public virtual returns (bool) {
        balanceOf[msg.sender] -= amt;
        balanceOf[to] += amt;
        emit Transfer(msg.sender, to, amt);
        return true;
    }

    function transferFrom(address from, address to, uint256 amt) public virtual returns (bool) {
        uint256 a = allowance[from][msg.sender];
        if (a != type(uint256).max) allowance[from][msg.sender] = a - amt;
        balanceOf[from] -= amt;
        balanceOf[to] += amt;
        emit Transfer(from, to, amt);
        return true;
    }
}

/// ERC20 that always returns false on transfer / transferFrom to exercise _safeTransfer code paths.
contract BadERC20False {
    string public name = "BadFalse";
    string public symbol = "BADF";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    function mint(address to, uint256 amt) public {
        balanceOf[to] += amt;
        emit Transfer(address(0), to, amt);
    }

    function approve(address sp, uint256 amt) public returns (bool) {
        allowance[msg.sender][sp] = amt;
        emit Approval(msg.sender, sp, amt);
        return true;
    }

    function transfer(address, uint256) public pure returns (bool) {
        return false; // always fail
    }

    function transferFrom(address from, address, uint256 amt) public returns (bool) {
        // simulate allowance bookkeeping, then fail
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amt;
        }
        return false;
    }
}

/*───────────────────────────────────────────────────────────────────*
 * C) RageQuit is nonReentrant (reentrancy attempt causes revert)
 *───────────────────────────────────────────────────────────────────*/
contract ReentrantERC20 is MockERC20 {
    SAW public saw;
    address public reenterCaller;
    bool internal entered;

    // NEW: visibility for the test
    bool public reenterAttempted;

    constructor(string memory n, string memory s, uint8 d) payable MockERC20(n, s, d) {}

    function arm(SAW _saw, address _caller) public {
        saw = _saw;
        reenterCaller = _caller;
    }

    function transfer(address to, uint256 amt) public override returns (bool) {
        bool ok = super.transfer(to, amt);
        if (!entered && to == reenterCaller && address(saw) != address(0)) {
            entered = true;

            // Try to reenter via the hook; it should REVERT due to nonReentrant.
            (bool s,) = reenterCaller.call(abi.encodeWithSignature("reenterRageQuit()"));

            // NEW: record that we tried (and we expect s == false)
            reenterAttempted = true;

            require(!s, "unexpected success"); // keep your original safety check
            entered = false;
        }
        return ok;
    }
}

contract RageQuitHook {
    SAW public saw;
    address[] public toks;

    constructor(SAW _saw, address tkn) payable {
        saw = _saw;
        toks = new address[](1);
        toks[0] = tkn;
    }

    function reenterRageQuit() public {
        // This runs during ERC20.transfer() → must hit nonReentrant
        saw.rageQuit(toks);
    }
}

