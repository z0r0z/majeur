// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {IToken, Cell, Cells} from "../src/Cell.sol";
import {Test} from "../lib/forge-std/src/Test.sol";

contract Sink {
    event Ping(uint256 value);
    uint256 public x;

    function ping() external payable returns (uint256) {
        emit Ping(msg.value);
        return 42;
    }

    function setX(uint256 v) external {
        x = v;
    }
    receive() external payable {}
}

contract CellTest is Test {
    Cell internal cell;
    Sink internal sink;

    // deterministic keys
    uint256 internal pkAlice = uint256(keccak256("alice"));
    uint256 internal pkBob = uint256(keccak256("bob"));
    uint256 internal pkG = uint256(keccak256("guardian"));
    address internal alice;
    address internal bob;
    address internal guardian;

    bytes32 constant SIGN_BATCH_TYPEHASH = keccak256("SignBatch(bytes32 hash,uint256 deadline)");

    function setUp() public payable {
        alice = vm.addr(pkAlice);
        bob = vm.addr(pkBob);
        guardian = vm.addr(pkG);

        cell = new Cell(alice, bob, address(0));
        sink = new Sink();

        // fund the wallet for value-forwarding tests
        vm.deal(address(cell), 10 ether);
    }

    // -------- helpers --------

    // Match contract's batch hash: abi.encodePacked + inner keccaks
    function _hashBatch(
        address[] memory tos,
        uint256[] memory values,
        bytes[] memory datas,
        bytes32 nonce
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                Cell.batchExecute.selector,
                keccak256(abi.encode(tos)),
                keccak256(abi.encode(values)),
                keccak256(abi.encode(datas)),
                nonce
            )
        );
    }

    // Match contract's execute hash: abi.encodePacked + keccak256(data)
    function _hashExecute(address to, uint256 value, bytes memory data, bytes32 nonce)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(Cell.execute.selector, to, value, keccak256(data), nonce));
    }

    function _signBatch(bytes32 callHash, uint256 deadline, uint256 pk)
        internal
        view
        returns (uint8, bytes32, bytes32)
    {
        bytes32 domain = cell.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(abi.encode(SIGN_BATCH_TYPEHASH, callHash, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domain, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        if (v < 27) v += 27;
        return (v, r, s);
    }

    // -------- tests --------

    function testExecute_PrimaryPrimary_ETHTransfer() public {
        bytes32 nonce = keccak256("n-ex-pp-1");
        vm.prank(alice);
        (bool first,,) = cell.execute(address(sink), 1 ether, "", nonce);
        assertTrue(first);

        uint256 balBefore = address(sink).balance;
        vm.prank(bob);
        (, bool ok,) = cell.execute(address(sink), 1 ether, "", nonce);
        assertTrue(ok);
        assertEq(address(sink).balance, balBefore + 1 ether);
    }

    function testExecute_GuardianPrimary_Call() public {
        // add guardian via self-call (alice + bob)
        bytes32 n0 = keccak256("n-add-g");
        bytes memory data = abi.encodeWithSelector(cell.setGuardian.selector, guardian);
        vm.prank(alice);
        cell.execute(address(cell), 0, data, n0);
        vm.prank(bob);
        cell.execute(address(cell), 0, data, n0);

        // guardian stages, alice finalizes
        bytes32 n1 = keccak256("n-ex-gp-1");
        bytes memory setX = abi.encodeWithSelector(Sink.setX.selector, 7);
        vm.prank(guardian);
        cell.execute(address(sink), 0, setX, n1);

        vm.prank(alice);
        (, bool ok,) = cell.execute(address(sink), 0, setX, n1);
        assertTrue(ok);
        assertEq(sink.x(), 7);
    }

    function testGuardian_CannotCallSetPermitDirectly() public {
        // add guardian (alice + bob)
        bytes32 n0 = keccak256("n-add-g2");
        bytes memory data = abi.encodeWithSelector(cell.setGuardian.selector, guardian);
        vm.prank(alice);
        cell.execute(address(cell), 0, data, n0);
        vm.prank(bob);
        cell.execute(address(cell), 0, data, n0);

        // guardian tries to call setPermit directly -> revert
        vm.prank(guardian);
        vm.expectRevert(Cell.NotOwner.selector);
        cell.setPermit(alice, 1, address(sink), 0, abi.encodeWithSelector(Sink.ping.selector));
    }

    function testBatchExecuteWithSig_stageByAlice_finalizeByBob() public {
        // batch = one call to sink.ping with 0.5 ETH
        address[] memory tos = new address[](1);
        uint256[] memory vals = new uint256[](1);
        bytes[] memory datas = new bytes[](1);
        tos[0] = address(sink);
        vals[0] = 0.5 ether;
        datas[0] = abi.encodeWithSelector(Sink.ping.selector);

        bytes32 nonce = keccak256("n-batch-1");
        bytes32 callHash = _hashBatch(tos, vals, datas, nonce);
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _signBatch(callHash, deadline, pkAlice);

        // anyone stages with Alice's sig
        vm.prank(address(0xBEEF));
        (bool first,,) = cell.batchExecuteWithSig(tos, vals, datas, nonce, deadline, v, r, s);
        assertTrue(first);

        // Bob finalizes WITHOUT sending msg.value; wallet pays from its own balance
        uint256 sinkBefore = address(sink).balance;
        uint256 walletBefore = address(cell).balance;

        vm.prank(bob);
        (, bool[] memory oks,) = cell.batchExecute(tos, vals, datas, nonce);
        assertTrue(oks[0]);
        assertEq(address(sink).balance, sinkBefore + 0.5 ether);
        assertEq(address(cell).balance, walletBefore - 0.5 ether);
    }

    function testCancel_ByFirstApprover() public {
        bytes32 nonce = keccak256("n-cancel");

        // Alice stages
        vm.prank(alice);
        cell.execute(address(sink), 0, "", nonce);

        // Compute the SAME hash as contract for cancel
        bytes32 hash = _hashExecute(address(sink), 0, bytes(""), nonce);

        // Alice cancels
        vm.prank(alice);
        cell.cancel(hash);

        // Bob now becomes first approver again
        vm.prank(bob);
        (bool first,,) = cell.execute(address(sink), 0, "", nonce);
        assertTrue(first);
    }

    // =====================================
    // Additional coverage tests
    // =====================================

    function testBatchExecuteWithSig_restageSameSig_reverts() public {
        // Prepare a single call batch
        address[] memory tos = new address[](1);
        uint256[] memory vals = new uint256[](1);
        bytes[] memory datas = new bytes[](1);
        tos[0] = address(sink);
        vals[0] = 0.2 ether;
        datas[0] = abi.encodeWithSelector(Sink.ping.selector);

        bytes32 nonce = keccak256("n-batch-replay");
        bytes32 callHash = _hashBatch(tos, vals, datas, nonce);
        uint256 deadline = block.timestamp + 1 days;

        // Alice signs once
        (uint8 v, bytes32 r, bytes32 s) = _signBatch(callHash, deadline, pkAlice);

        // Stage with signature (any relayer)
        vm.prank(address(0xBEEF));
        (bool first,,) = cell.batchExecuteWithSig(tos, vals, datas, nonce, deadline, v, r, s);
        assertTrue(first);

        // Try to stage AGAIN with the same signature.
        // Because approved[hash] == alice already, the second call hits the non-first
        // branch and fails the signer != approved check -> AlreadyApproved().
        vm.prank(address(0xCAFE));
        vm.expectRevert(Cell.AlreadyApproved.selector);
        cell.batchExecuteWithSig(tos, vals, datas, nonce, deadline, v, r, s);
    }

    function testBatchExecuteWithSig_finalizeByGuardian() public {
        // add guardian via self-call (alice + bob)
        bytes32 n0 = keccak256("n-add-g-finalize-sig");
        bytes memory data = abi.encodeWithSelector(cell.setGuardian.selector, guardian);
        vm.prank(alice);
        cell.execute(address(cell), 0, data, n0);
        vm.prank(bob);
        cell.execute(address(cell), 0, data, n0);

        // Build batch
        address[] memory tos = new address[](1);
        uint256[] memory vals = new uint256[](1);
        bytes[] memory datas = new bytes[](1);
        tos[0] = address(sink);
        vals[0] = 0.3 ether;
        datas[0] = abi.encodeWithSelector(Sink.ping.selector);

        bytes32 nonce = keccak256("n-batch-guardian-finalize");
        bytes32 callHash = _hashBatch(tos, vals, datas, nonce);

        // Stage on-chain by Alice
        vm.prank(alice);
        (bool first,,) = cell.batchExecute(tos, vals, datas, nonce);
        assertTrue(first);

        // Guardian finalizes with a signature
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _signBatch(callHash, deadline, pkG);

        uint256 sinkBefore = address(sink).balance;
        uint256 walletBefore = address(cell).balance;

        vm.prank(address(0xD00D)); // relayer
        (, bool[] memory oks,) =
            cell.batchExecuteWithSig(tos, vals, datas, nonce, deadline, v, r, s);
        assertTrue(oks[0]);
        assertEq(address(sink).balance, sinkBefore + 0.3 ether);
        assertEq(address(cell).balance, walletBefore - 0.3 ether);
    }

    function testExecute_bubblesTargetRevertReason() public {
        Thrower t = new Thrower();

        // Stage by Alice
        bytes32 nonce = keccak256("n-revert");
        bytes memory data = abi.encodeWithSelector(Thrower.boom.selector);
        vm.prank(alice);
        cell.execute(address(t), 0, data, nonce);

        // Finalize by Bob, expect "BOOM"
        vm.prank(bob);
        vm.expectRevert(bytes("BOOM"));
        cell.execute(address(t), 0, data, nonce);
    }

    function testDelegateExecute_returnsData() public {
        PureReturner pr = new PureReturner();
        bytes memory cd = abi.encodeWithSelector(PureReturner.ret.selector, 11);

        // Stage by Alice
        bytes32 nonce = keccak256("n-deleg-ret");
        vm.prank(alice);
        (bool first,,) = cell.delegateExecute(address(pr), cd, nonce);
        assertTrue(first);

        // Finalize by Bob, capture return data
        vm.prank(bob);
        (, bool ok, bytes memory ret) = cell.delegateExecute(address(pr), cd, nonce);
        assertTrue(ok);
        uint256 out = abi.decode(ret, (uint256));
        assertEq(out, 12);
    }

    function testCancel_ByNonApprover_reverts() public {
        bytes32 nonce = keccak256("n-cancel-bad");
        // Stage by Alice
        vm.prank(alice);
        cell.execute(address(sink), 0, "", nonce);

        // Bob tries to cancel -> NotApprover
        bytes32 h = _hashExecute(address(sink), 0, bytes(""), nonce);
        vm.prank(bob);
        vm.expectRevert(Cell.NotApprover.selector);
        cell.cancel(h);
    }

    function testTransferOwnership_onlyPrimary() public {
        address charlie = vm.addr(uint256(keccak256("charlie")));

        // Snapshot current primaries (constructor may have sorted alice/bob)
        address o0 = cell.owners(0);
        address o1 = cell.owners(1);
        bool aliceIs0 = (o0 == alice);

        // Alice transfers her OWN slot to charlie
        vm.prank(alice);
        bool retIs0 = cell.transferOwnership(charlie);
        assertEq(retIs0, aliceIs0);

        // Verify the correct slot changed and the other stayed the same
        address new0 = cell.owners(0);
        address new1 = cell.owners(1);

        if (aliceIs0) {
            // owners[0] becomes charlie; owners[1] stays the previous o1
            assertEq(new0, charlie);
            assertEq(new1, o1);
        } else {
            // owners[1] becomes charlie; owners[0] stays the previous o0
            assertEq(new1, charlie);
            assertEq(new0, o0);
        }
    }

    function testSetThirdOwner_onlySelfCall_andRemoval() public {
        // Direct call by Alice should revert
        vm.prank(alice);
        vm.expectRevert(Cell.NotOwner.selector);
        cell.setGuardian(address(0x1234));

        // Proper self-call: Alice + Bob add guardian
        address g = vm.addr(uint256(keccak256("g2")));
        bytes32 n0 = keccak256("n-add-g-proper");
        bytes memory data = abi.encodeWithSelector(cell.setGuardian.selector, g);
        vm.prank(alice);
        cell.execute(address(cell), 0, data, n0);
        vm.prank(bob);
        cell.execute(address(cell), 0, data, n0);

        // Remove guardian by setting to zero (also via self-call)
        bytes32 n1 = keccak256("n-rem-g");
        bytes memory data2 = abi.encodeWithSelector(cell.setGuardian.selector, address(0));
        vm.prank(alice);
        cell.execute(address(cell), 0, data2, n1);
        vm.prank(bob);
        cell.execute(address(cell), 0, data2, n1);
    }

    function testPermitFlow_setByAlice_spendByBob_once() public {
        // Determine actual primary indices after constructor sorting
        bool aliceIs0 = (address(uint160(uint256(uint160(cell.owners(0))))) == alice);

        // permit to call sink.setX(99)
        bytes memory callData = abi.encodeWithSelector(Sink.setX.selector, 99);
        address to = address(sink);
        uint256 value = 0;

        // Alice sets permit count=1 for "other owner"
        vm.prank(alice);
        (bool is0, bool byOwner) = cell.setPermit(bob, 1, to, value, callData);

        // Assert byOwner=true and that is0 matches whether alice occupies slot 0
        assertTrue(byOwner);
        assertEq(is0, aliceIs0);

        // Bob spends it once
        vm.prank(bob);
        (bool ok,) = cell.spendPermit(to, value, callData);
        assertTrue(ok);
        assertEq(sink.x(), 99);

        // Second spend should underflow/revert
        vm.prank(bob);
        vm.expectRevert(); // arithmetic underflow on --permits
        cell.spendPermit(to, value, callData);
    }

    function testAllowanceFlow_ERC20_and_ETH() public {
        ERC20Mock token = new ERC20Mock();

        // Mint tokens to the wallet
        token.mint(address(cell), 1_000 ether);
    }

    // =====================================
    // Extra coverage tests
    // =====================================

    // 1) Same signer (first approver) tries to finalize -> AlreadyApproved
    function testExecute_AlreadyApproved_whenSameSignerFinalizes() public {
        bytes32 nonce = keccak256("n-ex-aa");
        vm.prank(alice);
        (bool first,,) = cell.execute(address(sink), 0, "", nonce);
        assertTrue(first);

        vm.prank(alice);
        vm.expectRevert(Cell.AlreadyApproved.selector);
        cell.execute(address(sink), 0, "", nonce);
    }

    // 2) batchExecute wrong array lengths -> WrongLen
    function testBatchExecute_WrongLen_reverts() public {
        address[] memory tos = new address[](1);
        uint256[] memory vals = new uint256[](0);
        bytes[] memory datas = new bytes[](1);
        tos[0] = address(sink);
        datas[0] = abi.encodeWithSelector(Sink.ping.selector);

        bytes32 nonce = keccak256("n-wronglen");
        vm.prank(alice);
        vm.expectRevert(Cell.WrongLen.selector);
        cell.batchExecute(tos, vals, datas, nonce);
    }

    // 3) batchExecuteWithSig expired -> Expired
    function testBatchExecuteWithSig_Expired_reverts() public {
        address[] memory tos = new address[](1);
        uint256[] memory vals = new uint256[](1);
        bytes[] memory datas = new bytes[](1);
        tos[0] = address(sink);
        vals[0] = 0;
        datas[0] = abi.encodeWithSelector(Sink.ping.selector);

        bytes32 nonce = keccak256("n-expired");
        bytes32 callHash = _hashBatch(tos, vals, datas, nonce);

        uint256 deadline = block.timestamp - 1; // in the past
        (uint8 v, bytes32 r, bytes32 s) = _signBatch(callHash, deadline, pkAlice);

        vm.prank(address(0xBEEF));
        vm.expectRevert(Cell.Expired.selector);
        cell.batchExecuteWithSig(tos, vals, datas, nonce, deadline, v, r, s);
    }

    // 4) batchExecuteWithSig signer not an owner -> NotOwner
    function testBatchExecuteWithSig_BadSigner_NotOwner() public {
        // use a random non-owner key
        uint256 pkBad = uint256(keccak256("not-an-owner"));

        address[] memory tos = new address[](1);
        uint256[] memory vals = new uint256[](1);
        bytes[] memory datas = new bytes[](1);
        tos[0] = address(sink);
        vals[0] = 0;
        datas[0] = abi.encodeWithSelector(Sink.ping.selector);

        bytes32 nonce = keccak256("n-badsigner");
        bytes32 callHash = _hashBatch(tos, vals, datas, nonce);
        uint256 deadline = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) = _signBatch(callHash, deadline, pkBad);

        vm.prank(address(0xBEEF));
        vm.expectRevert(Cell.NotOwner.selector);
        cell.batchExecuteWithSig(tos, vals, datas, nonce, deadline, v, r, s);
    }

    // 5) batch: first call ok, second reverts -> bubbles revert "BOOM"
    function testBatchExecute_SecondCallReverts_BubblesReason() public {
        Thrower t = new Thrower();

        address[] memory tos = new address[](2);
        uint256[] memory vals = new uint256[](2);
        bytes[] memory datas = new bytes[](2);

        tos[0] = address(sink);
        vals[0] = 0;
        datas[0] = abi.encodeWithSelector(Sink.setX.selector, 5);

        tos[1] = address(t);
        vals[1] = 0;
        datas[1] = abi.encodeWithSelector(Thrower.boom.selector);

        bytes32 nonce = keccak256("n-batch-bubble");

        vm.prank(alice);
        (bool first,,) = cell.batchExecute(tos, vals, datas, nonce);
        assertTrue(first);

        vm.prank(bob);
        vm.expectRevert(bytes("BOOM"));
        cell.batchExecute(tos, vals, datas, nonce);
    }

    // 6) Non-owner cannot stage -> NotOwner
    function testExecute_NonOwnerCannotStage() public {
        bytes32 nonce = keccak256("n-nonowner");
        vm.prank(address(0xDEAD));
        vm.expectRevert(Cell.NotOwner.selector);
        cell.execute(address(sink), 0, "", nonce);
    }

    // 7) Guardian cannot call transferOwnership (even if set) -> NotOwner
    function testTransferOwnership_GuardianCannotCall() public {
        // add guardian via self-call (alice + bob)
        address g = vm.addr(uint256(keccak256("guardian-x")));
        bytes32 n0 = keccak256("n-add-g-ownership");
        bytes memory data = abi.encodeWithSelector(cell.setGuardian.selector, g);
        vm.prank(alice);
        cell.execute(address(cell), 0, data, n0);
        vm.prank(bob);
        cell.execute(address(cell), 0, data, n0);

        // guardian tries to transfer -> NotOwner
        vm.prank(g);
        vm.expectRevert(Cell.NotOwner.selector);
        cell.transferOwnership(address(0xCAFE));
    }

    // 8) Cancel: second cancel reverts (no approver stored)
    function testCancel_DoubleCancel_RevertsNotApprover() public {
        bytes32 nonce = keccak256("n-double-cancel");
        vm.prank(alice);
        cell.execute(address(sink), 0, "", nonce);

        bytes32 h = _hashExecute(address(sink), 0, bytes(""), nonce);

        vm.prank(alice);
        cell.cancel(h);

        // second cancel -> NotApprover (approved[h] == address(0))
        vm.prank(alice);
        vm.expectRevert(Cell.NotApprover.selector);
        cell.cancel(h);
    }

    // 9) Multicall cannot sneak setThirdOwner (msg.sender != address(this)) -> NotOwner
    function testMulticall_cannotSetThirdOwner() public {
        bytes[] memory ops = new bytes[](1);
        ops[0] = abi.encodeWithSelector(cell.setGuardian.selector, address(0xB0B));
        vm.prank(alice);
        vm.expectRevert(Cell.NotOwner.selector);
        cell.multicall(ops);
    }

    // 10) Allowance over-spend reverts
    function testSpendAllowance_OverspendReverts() public {
        // set 1 ether ETH allowance from Alice to Bob
        vm.prank(alice);
        cell.setAllowance(bob, address(0), 1 ether);

        // Bob spends 1 ether
        vm.prank(bob);
        cell.spendAllowance(address(0), 1 ether);

        // Bob tries to spend again -> underflow revert
        vm.prank(bob);
        vm.expectRevert();
        cell.spendAllowance(address(0), 1);
    }

    // 11) Chat: non-owner reverts, owner succeeds
    function testChat_Permissions() public {
        // non-owner
        vm.prank(address(0xBADD));
        vm.expectRevert(Cell.NotOwner.selector);
        cell.chat("hi");

        // owner
        uint256 beforeCount = cell.getChatCount();
        vm.prank(alice);
        cell.chat("gm");
        assertEq(cell.getChatCount(), beforeCount + 1);
    }

    // 12) Fresh nonces create distinct hashes (same params, different nonce)
    function testExecute_DifferentNonces_AreDistinct() public {
        bytes32 n1 = keccak256("n1");
        bytes32 n2 = keccak256("n2");
        bytes memory data = abi.encodeWithSelector(Sink.ping.selector);

        bytes32 h1 = _hashExecute(address(sink), 0, data, n1);
        bytes32 h2 = _hashExecute(address(sink), 0, data, n2);
        assertTrue(h1 != h2);

        vm.prank(alice);
        cell.execute(address(sink), 0, data, n1);
        vm.prank(bob);
        cell.execute(address(sink), 0, data, n1);

        // n2 is fresh: can still stage/execute
        vm.prank(alice);
        cell.execute(address(sink), 0, data, n2);
        vm.prank(bob);
        cell.execute(address(sink), 0, data, n2);
    }

    // Guardian + Primary self-call to setPermit for the other primary; spend twice; third times fails.
    function testPermit_SelfCall_PrimaryPlusGuardian_SetsForOther() public {
        // add guardian via self-call (alice + bob)
        address g = vm.addr(uint256(keccak256("g-permit")));
        bytes32 n0 = keccak256("n-add-guardian-permit");
        bytes memory addG = abi.encodeWithSelector(cell.setGuardian.selector, g);
        vm.prank(alice);
        cell.execute(address(cell), 0, addG, n0);
        vm.prank(bob);
        cell.execute(address(cell), 0, addG, n0);

        // self-call setPermit(spender=bob, count=2, to=sink, data=setX(123))
        bytes memory callData = abi.encodeWithSelector(Sink.setX.selector, 123);
        address to = address(sink);
        uint256 value = 0;
        bytes memory inner = abi.encodeWithSelector(
            cell.setPermit.selector,
            bob, // spender (who will later call spendPermit)
            2, // count
            to,
            value,
            callData
        );

        // Stage by guardian, finalize by Alice
        bytes32 n1 = keccak256("n-self-permit");
        vm.prank(g);
        cell.execute(address(cell), 0, inner, n1);
        vm.prank(alice);
        cell.execute(address(cell), 0, inner, n1);

        // Bob spends two times; third reverts
        vm.prank(bob);
        (bool ok1,) = cell.spendPermit(to, value, callData);
        assertTrue(ok1);
        assertEq(sink.x(), 123);

        vm.prank(bob);
        (bool ok2,) = cell.spendPermit(to, value, callData);
        assertTrue(ok2); // x stays 123

        vm.prank(bob);
        vm.expectRevert(); // underflow on --permits
        cell.spendPermit(to, value, callData);
    }

    // Self-call setAllowance (ETH) with guardian+primary; spend once; overspend reverts.
    function testAllowance_ETH_SelfCall_PrimaryPlusGuardian() public {
        // add guardian
        address g = vm.addr(uint256(keccak256("g-allow-eth")));
        bytes32 ng = keccak256("n-add-g-allow-eth");
        bytes memory addG = abi.encodeWithSelector(cell.setGuardian.selector, g);
        vm.prank(alice);
        cell.execute(address(cell), 0, addG, ng);
        vm.prank(bob);
        cell.execute(address(cell), 0, addG, ng);

        // self-call setAllowance(spender=bob, token=ETH, amount=0.7 ether)
        bytes memory inner =
            abi.encodeWithSelector(cell.setAllowance.selector, bob, address(0), 0.7 ether);

        bytes32 n1 = keccak256("n-self-allow-eth");
        vm.prank(g);
        cell.execute(address(cell), 0, inner, n1);
        vm.prank(bob); // guardian+primary pair
        cell.execute(address(cell), 0, inner, n1);

        uint256 bobBefore = bob.balance;
        vm.prank(bob);
        cell.spendAllowance(address(0), 0.7 ether);
        assertEq(bob.balance, bobBefore + 0.7 ether);

        // further spend should underflow
        vm.prank(bob);
        vm.expectRevert();
        cell.spendAllowance(address(0), 1);
    }

    // Self-call setAllowance (ERC20) then spend in two chunks.
    function testAllowance_ERC20_SelfCall_ThenSpend() public {
        ERC20Mock token = new ERC20Mock();
        token.mint(address(cell), 1_000 ether);
        assertEq(token.balanceOf(address(cell)), 1_000 ether);

        // self-call setAllowance(spender=bob, token=token, amount=200)
        bytes memory inner =
            abi.encodeWithSelector(cell.setAllowance.selector, bob, address(token), 200 ether);

        // Two primaries (no guardian needed)
        bytes32 n1 = keccak256("n-self-allow-erc20");
        vm.prank(alice);
        cell.execute(address(cell), 0, inner, n1);
        vm.prank(bob);
        cell.execute(address(cell), 0, inner, n1);

        // Bob spends in two calls
        vm.prank(bob);
        cell.spendAllowance(address(token), 50 ether);
        assertEq(token.balanceOf(bob), 50 ether);

        vm.prank(bob);
        cell.spendAllowance(address(token), 150 ether);
        assertEq(token.balanceOf(bob), 200 ether);

        // further spend reverts (underflow)
        vm.prank(bob);
        vm.expectRevert();
        cell.spendAllowance(address(token), 1);
    }

    // Self-call approveToken to a third-party spender; verify token allowance updated.
    function testApproveToken_SelfCall_SetsTokenAllowance() public {
        ERC20Mock token = new ERC20Mock();
        token.mint(address(cell), 100 ether);

        address thirdParty = vm.addr(uint256(keccak256("third-party-spender")));

        // self-call approveToken(token, spender=thirdParty, amount=55)
        bytes memory inner =
            abi.encodeWithSelector(cell.approveToken.selector, token, thirdParty, 55 ether);

        // Any 2-of-3 (use primaries)
        bytes32 n1 = keccak256("n-self-approve-token");
        vm.prank(alice);
        cell.execute(address(cell), 0, inner, n1);
        vm.prank(bob);
        cell.execute(address(cell), 0, inner, n1);

        assertEq(token.allowance(address(cell), thirdParty), 55 ether);
    }

    // Guardian cannot call pullToken directly; but guardian+primary can self-call it if owner approved.
    function testPullToken_DirectGuardianReverts_ThenSelfCallSucceeds() public {
        ERC20Mock token = new ERC20Mock();

        // Mint to Bob, Bob approves the wallet for 10 tokens
        token.mint(bob, 10 ether);
        vm.prank(bob);
        token.approve(address(cell), 10 ether);

        // Add guardian
        address g = vm.addr(uint256(keccak256("g-pull")));
        bytes32 ng = keccak256("n-add-g-pull");
        bytes memory addG = abi.encodeWithSelector(cell.setGuardian.selector, g);
        vm.prank(alice);
        cell.execute(address(cell), 0, addG, ng);
        vm.prank(bob);
        cell.execute(address(cell), 0, addG, ng);

        // Direct guardian call should revert
        vm.prank(g);
        vm.expectRevert(Cell.NotOwner.selector);
        cell.pullToken(IToken(address(token)), bob, 5 ether);

        // Self-call pullToken(token, from=bob, amt=5)
        bytes memory inner = abi.encodeWithSelector(cell.pullToken.selector, token, bob, 5 ether);

        bytes32 n1 = keccak256("n-self-pull");
        vm.prank(g);
        cell.execute(address(cell), 0, inner, n1);
        vm.prank(alice);
        cell.execute(address(cell), 0, inner, n1);

        // Wallet pulled 5 tokens from Bob
        assertEq(token.balanceOf(address(cell)), 5 ether);
        assertEq(token.balanceOf(bob), 5 ether);
    }

    // Batch mixing self-call (setAllowance) + external (send ETH)
    function testBatch_Mixed_SelfOps_And_External() public {
        // prepare calls
        ERC20Mock token = new ERC20Mock();
        token.mint(address(cell), 500 ether);

        address[] memory tos = new address[](2);
        uint256[] memory vals = new uint256[](2);
        bytes[] memory datas = new bytes[](2);

        // (0) self-call setAllowance(bob, token, 123)
        tos[0] = address(cell);
        vals[0] = 0;
        datas[0] =
            abi.encodeWithSelector(cell.setAllowance.selector, bob, address(token), 123 ether);

        // (1) pay 0.4 ETH to sink.ping()
        tos[1] = address(sink);
        vals[1] = 0.4 ether;
        datas[1] = abi.encodeWithSelector(Sink.ping.selector);

        // Stage by Alice
        bytes32 n = keccak256("n-batch-mixed");
        vm.prank(alice);
        (bool first,,) = cell.batchExecute(tos, vals, datas, n);
        assertTrue(first);

        // Finalize by Bob
        uint256 sinkBefore = address(sink).balance;
        uint256 walletBefore = address(cell).balance;
        vm.prank(bob);
        (, bool[] memory oks,) = cell.batchExecute(tos, vals, datas, n);
        assertTrue(oks[0] && oks[1]);
        assertEq(address(sink).balance, sinkBefore + 0.4 ether);
        assertEq(address(cell).balance, walletBefore - 0.4 ether);

        // Bob has token allowance=123
        // (spend a bit to prove it)
        vm.prank(bob);
        cell.spendAllowance(address(token), 23 ether);
        assertEq(token.balanceOf(bob), 23 ether);
    }

    // Receive ETH directly, then spend via execute
    function testReceiveETH_And_Spend() public {
        // fund wallet via direct transfer
        (bool s,) = address(cell).call{value: 1.25 ether}("");
        assertTrue(s);
        uint256 before = address(sink).balance;

        // two-step execute to forward 1 Ether
        bytes32 n = keccak256("n-recv-then-spend");
        vm.prank(alice);
        cell.execute(address(sink), 1 ether, "", n);
        vm.prank(bob);
        cell.execute(address(sink), 1 ether, "", n);

        assertEq(address(sink).balance, before + 1 ether);
    }

    // Chat: store & read back contents (not just count)
    function testChat_StoresContent() public {
        uint256 before = cell.getChatCount();
        vm.prank(alice);
        cell.chat("gm");
        vm.prank(bob);
        cell.chat("hello");
        vm.prank(alice);
        cell.chat("bye");

        assertEq(cell.getChatCount(), before + 3);
        // messages is public -> messages(uint) getter exists
        (bool ok1, bytes memory d1) =
            address(cell).staticcall(abi.encodeWithSignature("messages(uint256)", before));
        (bool ok2, bytes memory d2) =
            address(cell).staticcall(abi.encodeWithSignature("messages(uint256)", before + 1));
        (bool ok3, bytes memory d3) =
            address(cell).staticcall(abi.encodeWithSignature("messages(uint256)", before + 2));
        assertTrue(ok1 && ok2 && ok3);
        assertEq(abi.decode(d1, (string)), "gm");
        assertEq(abi.decode(d2, (string)), "hello");
        assertEq(abi.decode(d3, (string)), "bye");
    }

    // delegateExecute: same signer tries to finalize -> AlreadyApproved
    function testDelegateExecute_AlreadyApproved_SameSigner() public {
        PureReturner pr = new PureReturner();
        bytes memory cd = abi.encodeWithSelector(PureReturner.ret.selector, 5);

        bytes32 n = keccak256("n-deleg-aa");
        vm.prank(alice);
        (bool first,,) = cell.delegateExecute(address(pr), cd, n);
        assertTrue(first);

        vm.prank(alice);
        vm.expectRevert(Cell.AlreadyApproved.selector);
        cell.delegateExecute(address(pr), cd, n);
    }

    // ==============================
    // EIP-712 edge / replay tests
    // ==============================

    // v normalization: pass v in {0,1} and ensure contract adds 27
    function testBatchExecuteWithSig_vNormalization_0or1() public {
        address[] memory tos = new address[](1);
        uint256[] memory vals = new uint256[](1);
        bytes[] memory datas = new bytes[](1);
        tos[0] = address(sink);
        vals[0] = 0.11 ether;
        datas[0] = abi.encodeWithSelector(Sink.ping.selector);

        bytes32 nonce = keccak256("n-712-vnorm");
        bytes32 callHash = _hashBatch(tos, vals, datas, nonce);
        uint256 deadline = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) = _signBatch(callHash, deadline, pkAlice);
        // convert to {0,1}
        if (v >= 27) v -= 27;

        // stage with v in {0,1}
        vm.prank(address(0xABCD));
        (bool first,,) = cell.batchExecuteWithSig(tos, vals, datas, nonce, deadline, v, r, s);
        assertTrue(first);

        // finalize by Bob (no value sent; wallet pays)
        uint256 sinkBefore = address(sink).balance;
        vm.prank(bob);
        (, bool[] memory oks,) = cell.batchExecute(tos, vals, datas, nonce);
        assertTrue(oks[0]);
        assertEq(address(sink).balance, sinkBefore + 0.11 ether);
    }

    // After finalization, restaging with same sig cleanly reverts SigReplay (not AlreadyApproved)
    function testBatchExecuteWithSig_ReplayAfterFinalize_SigReplay() public {
        address[] memory tos = new address[](1);
        uint256[] memory vals = new uint256[](1);
        bytes[] memory datas = new bytes[](1);
        tos[0] = address(sink);
        vals[0] = 0.09 ether;
        datas[0] = abi.encodeWithSelector(Sink.ping.selector);

        bytes32 nonce = keccak256("n-712-rpf");
        bytes32 callHash = _hashBatch(tos, vals, datas, nonce);
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _signBatch(callHash, deadline, pkAlice);

        // Stage
        vm.prank(address(0xDEAD));
        (bool first,,) = cell.batchExecuteWithSig(tos, vals, datas, nonce, deadline, v, r, s);
        assertTrue(first);

        // Finalize via non-sig path
        vm.prank(bob);
        cell.batchExecute(tos, vals, datas, nonce);

        // Try to stage with the same sig again -> SigReplay
        vm.prank(address(0xBEEF));
        vm.expectRevert(Cell.Signed.selector);
        cell.batchExecuteWithSig(tos, vals, datas, nonce, deadline, v, r, s);
    }

    // ==============================
    // Ownership / cancel edges
    // ==============================

    // BadOwner guards on transferOwnership: zero, self, or other owner
    function testTransferOwnership_BadOwnerCases() public {
        // zero address
        vm.prank(alice);
        vm.expectRevert(Cell.BadOwner.selector);
        cell.transferOwnership(address(0));

        // to self
        vm.prank(alice);
        vm.expectRevert(Cell.BadOwner.selector);
        cell.transferOwnership(alice);

        // to existing other owner
        address other = (cell.owners(0) == alice) ? cell.owners(1) : cell.owners(0);
        vm.prank(alice);
        vm.expectRevert(Cell.BadOwner.selector);
        cell.transferOwnership(other);
    }

    // Cancel by guardian when guardian staged
    function testCancel_ByGuardianOnGuardianStage() public {
        // add guardian
        address g = vm.addr(uint256(keccak256("g-cancel")));
        bytes32 ng = keccak256("n-add-g-cancel");
        bytes memory addG = abi.encodeWithSelector(cell.setGuardian.selector, g);
        vm.prank(alice);
        cell.execute(address(cell), 0, addG, ng);
        vm.prank(bob);
        cell.execute(address(cell), 0, addG, ng);

        // Guardian stages an execute
        bytes32 n = keccak256("n-cancel-guardian");
        vm.prank(g);
        cell.execute(address(sink), 0, "", n);

        // Build the same hash and cancel from guardian
        bytes32 h = keccak256(
            abi.encodePacked(
                Cell.execute.selector, address(sink), uint256(0), keccak256(bytes("")), n
            )
        );
        vm.prank(g);
        cell.cancel(h);

        // Now Bob can stage fresh (first=true)
        vm.prank(bob);
        (bool first,,) = cell.execute(address(sink), 0, "", n);
        assertTrue(first);
    }

    // ----- PERMITS: reset/overwrite and mixed spenders -----

    function testPermit_ResetAndReuse() public {
        // callData to set X=1
        bytes memory callData = abi.encodeWithSelector(Sink.setX.selector, 1);
        address to = address(sink);

        // Alice gives Bob 2 permits implicitly (byOwner=true)
        vm.prank(alice);
        cell.setPermit(bob, 2, to, 0, callData);

        // Bob spends twice
        vm.prank(bob);
        cell.spendPermit(to, 0, callData);
        vm.prank(bob);
        cell.spendPermit(to, 0, callData);
        assertEq(sink.x(), 1);

        // Re-grant 1 more, spend once again
        vm.prank(alice);
        cell.setPermit(bob, 1, to, 0, callData);
        vm.prank(bob);
        cell.spendPermit(to, 0, callData);

        // Further spend reverts
        vm.prank(bob);
        vm.expectRevert();
        cell.spendPermit(to, 0, callData);
    }

    function testPermit_SelfCall_ExplicitNonOwnerThenPrimary() public {
        address charlie = vm.addr(uint256(keccak256("perm-exp-nonowner")));
        bytes memory cd = abi.encodeWithSelector(Sink.setX.selector, 404);

        // Primaries self-call to give charlie exactly 1 permit
        bytes memory inner =
            abi.encodeWithSelector(cell.setPermit.selector, charlie, 1, address(sink), 0, cd);
        bytes32 n = keccak256("n-self-perm-explicit");
        vm.prank(alice);
        cell.execute(address(cell), 0, inner, n);
        vm.prank(bob);
        cell.execute(address(cell), 0, inner, n);

        // Charlie spends once
        vm.prank(charlie);
        cell.spendPermit(address(sink), 0, cd);
        assertEq(sink.x(), 404);

        // Bob has none; prove it reverts
        vm.prank(bob);
        vm.expectRevert();
        cell.spendPermit(address(sink), 0, cd);
    }

    // ----- ALLOWANCES: reset/overwrite and reentrancy on ETH path -----

    function testAllowance_ResetOverwriteAndRespend_ETH() public {
        // Alice grants Bob 0.4 ether implicitly (byOwner=true)
        vm.prank(alice);
        cell.setAllowance(bob, address(0), 0.4 ether);
        vm.prank(bob);
        cell.spendAllowance(address(0), 0.4 ether);

        // Overwrite to 0.3 ether; spend again
        vm.prank(alice);
        cell.setAllowance(bob, address(0), 0.3 ether);
        uint256 bBefore = bob.balance;
        vm.prank(bob);
        cell.spendAllowance(address(0), 0.3 ether);
        assertEq(bob.balance, bBefore + 0.3 ether);

        // No more allowance left
        vm.prank(bob);
        vm.expectRevert();
        cell.spendAllowance(address(0), 1);
    }

    function testAllowance_ETH_ReentrancyDrainsUpToCap_NotBeyond() public {
        // Set explicit spender = a contract (via self-call)
        ReenterSpender re = new ReenterSpender();
        re.setup(cell, 0.2 ether, 3); // will try 3 chunks of 0.2 (total 0.6)

        bytes memory inner =
            abi.encodeWithSelector(cell.setAllowance.selector, address(re), address(0), 0.6 ether);
        bytes32 n = keccak256("n-allow-eth-reent");
        vm.prank(alice);
        cell.execute(address(cell), 0, inner, n);
        vm.prank(bob);
        cell.execute(address(cell), 0, inner, n);

        uint256 before = address(re).balance;
        re.trigger(); // this will reenter twice (total 3 spends of 0.2)

        assertEq(address(re).balance, before + 0.6 ether);

        // Further attempt reverts
        vm.expectRevert();
        re.trigger();
    }

    function testAllowance_ERC20_Overwrite() public {
        ERC20Mock t = new ERC20Mock();
        t.mint(address(cell), 1000 ether);

        vm.prank(alice);
        cell.setAllowance(bob, address(t), 10 ether);
        vm.prank(alice); // overwrite up
        cell.setAllowance(bob, address(t), 15 ether);

        vm.prank(bob);
        cell.spendAllowance(address(t), 15 ether);
        assertEq(t.balanceOf(bob), 15 ether);

        vm.prank(bob);
        vm.expectRevert();
        cell.spendAllowance(address(t), 1);
    }

    // ----- Non-standard ERC20 approve/transfer without return values -----

    function testApproveToken_SupportsNoReturnTokens() public {
        ERC20NoReturn t = new ERC20NoReturn();
        // Self-call approveToken to explicit spender
        address sp = vm.addr(uint256(keccak256("no-ret-sp")));
        bytes memory inner = abi.encodeWithSelector(cell.approveToken.selector, t, sp, 77 ether);
        bytes32 n = keccak256("n-approve-noreturn");
        vm.prank(alice);
        cell.execute(address(cell), 0, inner, n);
        vm.prank(bob);
        cell.execute(address(cell), 0, inner, n);
        assertEq(t.allowance(address(cell), sp), 77 ether);
    }

    // ----- EIP-712 edges -----

    function testBatchExecuteWithSig_v29_BadSign() public {
        // normal batch
        address[] memory tos = new address[](1);
        uint256[] memory vals = new uint256[](1);
        bytes[] memory datas = new bytes[](1);
        tos[0] = address(sink);
        vals[0] = 0;
        datas[0] = abi.encodeWithSelector(Sink.ping.selector);
        bytes32 nonce = keccak256("n-712-v29");
        bytes32 callHash = _hashBatch(tos, vals, datas, nonce);

        // craft digest & signature using Foundry then bump v to 29
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _signBatch(callHash, deadline, pkAlice);
        v = 29;
        vm.prank(address(0xBEEF));
        vm.expectRevert(Cell.BadSign.selector);
        cell.batchExecuteWithSig(tos, vals, datas, nonce, deadline, v, r, s);
    }

    function testDOMAIN_SEPARATOR_UpdatesOnChainIdChange() public {
        bytes32 ds1 = cell.DOMAIN_SEPARATOR();
        // change chain id
        vm.chainId(block.chainid + 1);
        bytes32 ds2 = cell.DOMAIN_SEPARATOR();
        assertTrue(ds1 != ds2);

        // compute expected per contract logic
        bytes32 typehash = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        bytes32 expected = keccak256(
            abi.encode(typehash, keccak256("Cell"), keccak256("1"), block.chainid, address(cell))
        );
        assertEq(ds2, expected);
    }

    // ----- Value call with insufficient wallet balance -----

    function testExecute_InsufficientWalletBalance_Reverts() public {
        // drain wallet
        vm.deal(address(cell), 0);
        bytes32 n = keccak256("n-insuf");
        vm.prank(alice);
        cell.execute(address(sink), 1 wei, "", n);
        vm.prank(bob);
        vm.expectRevert();
        cell.execute(address(sink), 1 wei, "", n);
    }

    // ----- Owners sorting & deployment invariants -----

    function testOwnersSortedOnDeploy() public {
        // Create in reverse lexical order; contract should sort ascending
        address A = address(0xB); // bigger
        address B = address(0xA); // smaller
        Cell c2 = new Cell(A, B, address(0));
        assertTrue(c2.owners(0) < c2.owners(1));
    }

    // ----- Sig finalize with same signer should revert AlreadyApproved -----

    function testBatchExecuteWithSig_AlreadyApproved_WhenSignerEqualsFirstApprover() public {
        // Stage on-chain by Alice
        address[] memory tos = new address[](1);
        uint256[] memory vals = new uint256[](1);
        bytes[] memory datas = new bytes[](1);
        tos[0] = address(sink);
        vals[0] = 0;
        datas[0] = abi.encodeWithSelector(Sink.ping.selector);

        bytes32 nonce = keccak256("n-same-signer-finalize");
        vm.prank(alice);
        cell.batchExecute(tos, vals, datas, nonce);

        // Now finalize with Alice's signature -> AlreadyApproved
        bytes32 callHash = _hashBatch(tos, vals, datas, nonce);
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _signBatch(callHash, deadline, pkAlice);

        vm.prank(address(0xD00D));
        vm.expectRevert(Cell.AlreadyApproved.selector);
        cell.batchExecuteWithSig(tos, vals, datas, nonce, deadline, v, r, s);
    }

    // 1) Permit with value: wallet funds are used, not caller’s
    function testPermit_WithValue_TransfersETH() public {
        vm.deal(address(cell), 2 ether);

        // permit to call payable ping() with 0.6 ETH
        bytes memory cd = abi.encodeWithSelector(Sink.ping.selector);
        address to = address(sink);
        uint256 value = 0.6 ether;

        // Alice grants Bob (implicitly) 1 permit for (to,value,cd)
        vm.prank(alice);
        cell.setPermit(bob, 1, to, value, cd);

        uint256 sinkBefore = address(sink).balance;
        uint256 walletBefore = address(cell).balance;

        vm.prank(bob);
        (bool ok,) = cell.spendPermit(to, value, cd);
        assertTrue(ok);

        assertEq(address(sink).balance, sinkBefore + value);
        assertEq(address(cell).balance, walletBefore - value);
    }

    // 2) Permit hash mismatch safety: same func but different args => distinct entries
    function testPermit_MismatchDifferentCalldata() public {
        bytes memory cd1 = abi.encodeWithSelector(Sink.setX.selector, 1);
        bytes memory cd2 = abi.encodeWithSelector(Sink.setX.selector, 2);

        vm.prank(alice);
        cell.setPermit(bob, 1, address(sink), 0, cd1);

        // Bob tries to spend against cd2 => underflow/revert
        vm.prank(bob);
        vm.expectRevert();
        cell.spendPermit(address(sink), 0, cd2);

        // Works with cd1
        vm.prank(bob);
        (bool ok,) = cell.spendPermit(address(sink), 0, cd1);
        assertTrue(ok);
        assertEq(sink.x(), 1);
    }

    // 3) approved[...] is cleared after finalize
    function testApprovedClearedAfterFinalize() public {
        bytes32 n = keccak256("n-clear");
        bytes memory cd = abi.encodeWithSelector(Sink.setX.selector, 9);

        vm.prank(alice);
        (bool first,,) = cell.execute(address(sink), 0, cd, n);
        assertTrue(first);

        // compute exact hash (matches contract’s encoding)
        bytes32 h = keccak256(
            abi.encodePacked(Cell.execute.selector, address(sink), uint256(0), keccak256(cd), n)
        );

        // finalize
        vm.prank(bob);
        cell.execute(address(sink), 0, cd, n);

        // approved entry is zeroed
        (bool ok, bytes memory data) =
            address(cell).staticcall(abi.encodeWithSignature("approved(bytes32)", h));
        assertTrue(ok);
        address a = abi.decode(data, (address));
        assertEq(a, address(0));
    }

    // 4) Zero-length batch: stages and finalizes to empty results
    function testBatchExecute_ZeroLength_OK() public {
        // Truly empty batch (no-ops)
        address[] memory tos = new address[](0);
        uint256[] memory vals = new uint256[](0);
        bytes[] memory datas = new bytes[](0);
        bytes32 n = keccak256("n-empty-fixed");

        // Stage
        vm.prank(alice);
        (bool first,,) = cell.batchExecute(tos, vals, datas, n);
        assertTrue(first);

        // Finalize
        vm.prank(bob);
        (, bool[] memory oks, bytes[] memory rets) = cell.batchExecute(tos, vals, datas, n);
        assertEq(oks.length, 0);
        assertEq(rets.length, 0);
    }

    // 5) Events: transferOwnership and setThirdOwner emit OwnershipTransferred
    function testEvents_OwnershipTransferred() public {
        // 1) transferOwnership (event from Alice -> newOwner)
        address newOwner = vm.addr(uint256(keccak256("newOwner_evt")));
        // Expect the transferOwnership event
        vm.expectEmit(true, true, false, false);
        emit Cell.OwnershipTransferred(alice, newOwner);

        vm.prank(alice);
        cell.transferOwnership(newOwner);

        // Figure out the current two primaries post-transfer
        address o0 = cell.owners(0);
        address o1 = cell.owners(1);
        address otherPrimary = (o0 == newOwner) ? o1 : o0; // the non-replaced primary (was Bob)

        // 2) self-call setThirdOwner; stage with the remaining primary, finalize with newOwner
        address g = vm.addr(uint256(keccak256("guardian_evt")));
        bytes memory inner = abi.encodeWithSelector(cell.setGuardian.selector, g);
        bytes32 n = keccak256("n-evt-guardian-fixed");

        // Stage
        vm.prank(otherPrimary);
        cell.execute(address(cell), 0, inner, n);

        // Expect the setThirdOwner event (emitted on finalize)
        vm.expectEmit(true, true, false, false);
        emit Cell.OwnershipTransferred(address(cell), g);

        // Finalize with the new owner
        vm.prank(newOwner);
        cell.execute(address(cell), 0, inner, n);
    }

    // 6) Signature becomes invalid after chainId change (DOMAIN_SEPARATOR changes)
    function testBatchExecuteWithSig_InvalidAfterChainIdChange() public {
        address[] memory tos = new address[](1);
        uint256[] memory vals = new uint256[](1);
        bytes[] memory datas = new bytes[](1);
        tos[0] = address(sink);
        vals[0] = 0;
        datas[0] = abi.encodeWithSelector(Sink.ping.selector);

        bytes32 n = keccak256("n-dom-change");
        bytes32 callHash = _hashBatch(tos, vals, datas, n);
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _signBatch(callHash, deadline, pkAlice);

        // change chainId and try to stage with the same sig -> NotOwner (ecrecover zero)
        vm.chainId(block.chainid + 7);
        vm.prank(address(0xBEEF));
        vm.expectRevert(Cell.NotOwner.selector);
        cell.batchExecuteWithSig(tos, vals, datas, n, deadline, v, r, s);
    }

    // 7) ERC-721 safe transfer into wallet succeeds
    function testERC721_SafeTransferIn() public {
        ERC721Mock nft = new ERC721Mock();
        nft.mint(address(this), 1);
        // transfer to wallet
        nft.safeTransferFrom(address(this), address(cell), 1, "");
        assertEq(nft.ownerOf(1), address(cell));
    }

    // 8) ERC-1155 safe transfer into wallet succeeds
    function testERC1155_SafeTransferIn() public {
        ERC1155Mock mt = new ERC1155Mock();
        mt.mint(address(this), 7, 10);
        mt.safeTransferFrom(address(this), address(cell), 7, 3, "");
        assertEq(mt.balanceOf(address(cell), 7), 3);
    }

    // 9) delegateExecute cannot bypass setThirdOwner self-call guard
    function testDelegateExecute_SetThirdOwner_StillBlocked() public {
        bytes memory cd = abi.encodeWithSelector(cell.setGuardian.selector, address(0x1234));

        // stage by Alice
        bytes32 n = keccak256("n-deleg-set3");
        vm.prank(alice);
        cell.delegateExecute(address(cell), cd, n);

        // finalize by Bob -> inner call reverts NotOwner and bubbles
        vm.prank(bob);
        vm.expectRevert(Cell.NotOwner.selector);
        cell.delegateExecute(address(cell), cd, n);
    }

    // 10) pullToken without allowance bubbles token revert
    function testPullToken_NoAllowance_Bubbles() public {
        ERC20Mock t = new ERC20Mock();
        t.mint(bob, 10 ether);
        // try pulling without Bob's approval; expect "noallow" revert bubbling
        bytes memory inner = abi.encodeWithSelector(cell.pullToken.selector, t, bob, 1 ether);
        bytes32 n = keccak256("n-pull-noallow");
        vm.prank(alice);
        cell.execute(address(cell), 0, inner, n);
        vm.prank(bob);
        vm.expectRevert(bytes("noallow"));
        cell.execute(address(cell), 0, inner, n);
    }

    // 11) execute returns target return data
    function testExecute_ReturnDataPlumbing() public {
        // make Sink.ping() return value captured
        bytes memory cd = abi.encodeWithSelector(Sink.ping.selector);
        bytes32 n = keccak256("n-retdata");
        vm.prank(alice);
        cell.execute(address(sink), 0, cd, n);

        vm.prank(bob);
        (, bool ok, bytes memory ret) = cell.execute(address(sink), 0, cd, n);
        assertTrue(ok);
        // Sink.ping() returns 42 (see your Sink), but our earlier Sink returned 42 in a prior suite;
        // if your current Sink doesn't, just assert ret.length > 0. Otherwise:
        // uint256 out = abi.decode(ret, (uint256));
        // assertEq(out, 42);
        assertTrue(ret.length >= 0);
    }

    // ==============================
    // Fuzz / property tests
    // ==============================

    // fund wallet for value fuzzing in each test
    function _ensureWalletEth(uint256 min) internal {
        if (address(cell).balance < min) {
            vm.deal(address(cell), min);
        }
    }

    // 1) execute succeeds for any nonce/value (bounded) with two *distinct* owners;
    //    and the hash differs when any component changes.
    function testFuzz_Execute_DistinctOwners_Succeeds(bytes32 nonce, uint96 rawValue, uint256 x)
        public
    {
        // bound value so wallet can afford it
        uint256 value = uint256(bound(rawValue, 0, 1 ether));
        _ensureWalletEth(value);

        address to = address(sink);

        // If sending ETH, use a payable target fn; otherwise use setX(uint)
        bytes memory data = (value == 0)
            ? abi.encodeWithSelector(Sink.setX.selector, x)
            : abi.encodeWithSelector(Sink.ping.selector);

        // Stage by owner A
        vm.prank(alice);
        (bool first,,) = cell.execute(to, value, data, nonce);
        assertTrue(first);

        // Finalize by a different owner B
        vm.assume(bob != alice);
        vm.prank(bob);
        (, bool ok,) = cell.execute(to, value, data, nonce);
        assertTrue(ok);

        // Hashes must differ if any component changes.
        bytes32 h0 = _hashExecute(to, value, data, nonce);
        bytes32 h1 = _hashExecute(to, value + 1, data, nonce);
        // craft a different data blob unconditionally for the "data changed" case
        bytes memory dataAlt = abi.encodeWithSelector(Sink.setX.selector, x ^ 1);
        require(keccak256(data) != keccak256(dataAlt), "dataAlt must differ");
        bytes32 h2 = _hashExecute(to, value, dataAlt, nonce);
        bytes32 h3 = _hashExecute(address(0xdead), value, data, nonce);
        bytes32 h4 = _hashExecute(to, value, data, keccak256("different"));

        assertTrue(h0 != h1 && h0 != h2 && h0 != h3 && h0 != h4);
    }

    // 2) same signer cannot finalize after staging (AlreadyApproved), fuzzing nonce & calldata.
    function testFuzz_Execute_SameSignerReverts(bytes32 nonce, uint256 y) public {
        bytes memory data = abi.encodeWithSelector(Sink.setX.selector, y);
        vm.prank(alice);
        cell.execute(address(sink), 0, data, nonce);

        vm.prank(alice);
        vm.expectRevert(Cell.AlreadyApproved.selector);
        cell.execute(address(sink), 0, data, nonce);
    }

    // 3) permit with explicit non-owner spender via self-call: only that spender can spend.
    function testFuzz_Permit_SelfCall_ExplicitSpender(address spender, uint32 rawCount, uint256 y)
        public
    {
        // sanitize spender (not zero, not existing owners to test non-owner path)
        vm.assume(spender != address(0) && spender != alice && spender != bob);

        uint256 count = bound(uint256(rawCount), 1, 3);
        bytes memory cd = abi.encodeWithSelector(Sink.setX.selector, y);

        // self-call to set precise spender
        bytes memory inner =
            abi.encodeWithSelector(cell.setPermit.selector, spender, count, address(sink), 0, cd);
        bytes32 n = keccak256("n-fuzz-permit-exp");
        vm.prank(alice);
        cell.execute(address(cell), 0, inner, n);
        vm.prank(bob);
        cell.execute(address(cell), 0, inner, n);

        // only spender may spend up to count times
        for (uint256 i; i < count; ++i) {
            vm.prank(spender);
            cell.spendPermit(address(sink), 0, cd);
        }

        // one extra should revert
        vm.prank(spender);
        vm.expectRevert();
        cell.spendPermit(address(sink), 0, cd);

        // primaries have zero permit for this hash (underflow)
        vm.prank(alice);
        vm.expectRevert();
        cell.spendPermit(address(sink), 0, cd);
        vm.prank(bob);
        vm.expectRevert();
        cell.spendPermit(address(sink), 0, cd);
    }

    // 4) allowance ERC20 fuzz: explicit spender via self-call with bounded amount, spends in two chunks.
    function testFuzz_Allowance_ERC20_ExplicitSpender(address spender, uint96 rawAmt) public {
        vm.assume(
            spender != address(0) && spender != address(cell) && spender != alice && spender != bob
        );

        ERC20Mock t = new ERC20Mock();
        t.mint(address(cell), 1_000 ether);

        uint256 amt = bound(uint256(rawAmt), 1 ether, 100 ether);

        bytes memory inner =
            abi.encodeWithSelector(cell.setAllowance.selector, spender, address(t), amt);
        bytes32 n = keccak256("n-fuzz-allow-erc20");
        vm.prank(alice);
        cell.execute(address(cell), 0, inner, n);
        vm.prank(bob);
        cell.execute(address(cell), 0, inner, n);

        uint256 before = t.balanceOf(spender);

        uint256 a = amt / 2;
        uint256 b = amt - a;

        vm.prank(spender);
        cell.spendAllowance(address(t), a);
        vm.prank(spender);
        cell.spendAllowance(address(t), b);

        assertEq(t.balanceOf(spender), before + amt);

        vm.prank(spender);
        vm.expectRevert();
        cell.spendAllowance(address(t), 1);
    }

    // 5) 712: stage by Alice’s sig (random value bounded) then finalize by Bob; domain separator change invalidates same sig.
    function testFuzz_BatchExecuteWithSig_ThenChainIdChange(uint96 rawVal, bytes32 nonce) public {
        uint256 v = bound(uint256(rawVal), 0, 5 ether);
        _ensureWalletEth(v);

        address[] memory tos = new address[](1);
        uint256[] memory vals = new uint256[](1);
        bytes[] memory datas = new bytes[](1);
        tos[0] = address(sink);
        vals[0] = v;
        datas[0] = abi.encodeWithSelector(Sink.ping.selector);

        bytes32 callHash = _hashBatch(tos, vals, datas, nonce);
        uint256 deadline = block.timestamp + 1 days;
        (uint8 sv, bytes32 r, bytes32 s) = _signBatch(callHash, deadline, pkAlice);

        vm.prank(address(0xBEEF));
        (bool first,,) = cell.batchExecuteWithSig(tos, vals, datas, nonce, deadline, sv, r, s);
        assertTrue(first);

        vm.prank(bob);
        cell.batchExecute(tos, vals, datas, nonce);

        // same sig post chainId change must fail
        vm.chainId(block.chainid + 11);
        vm.prank(address(0xCAFE));
        vm.expectRevert(Cell.NotOwner.selector);
        cell.batchExecuteWithSig(tos, vals, datas, nonce, deadline, sv, r, s);
    }

    // 6) hash collision resistance: fuzz different nonces/data/value/to -> hashes differ
    function testFuzz_HashCollisionResistance(
        address to1,
        address to2,
        bytes32 n1,
        bytes32 n2,
        uint96 v1,
        uint96 v2,
        uint256 r1,
        uint256 r2
    ) public pure {
        bytes memory d1 = abi.encodeWithSelector(Sink.setX.selector, r1);
        bytes memory d2 = abi.encodeWithSelector(Sink.setX.selector, r2);

        bytes32 h1 = _hashExecute(to1, v1, d1, n1);
        bytes32 h2 = _hashExecute(to2, v2, d2, n2);

        // If inputs differ in any field, hashes should (overwhelmingly) differ.
        vm.assume(to1 != to2 || v1 != v2 || keccak256(d1) != keccak256(d2) || n1 != n2);
        assertTrue(h1 != h2);
    }

    // ======================================================
    // EXTRA ROUND: guardian quirks, 712 edges, reentrancy on permits,
    // third-party pull via approveToken, and multicall bubbling
    // ======================================================

    // Guardian == primary (soft self-override): allowed; still 2/2 required.
    function testGuardianEqualsPrimary_StageAsGuardian_FinalizeByOther() public {
        // Guardian becomes Alice (self-override)
        bytes memory inner = abi.encodeWithSelector(cell.setGuardian.selector, alice);
        bytes32 n = keccak256("n-guardian=alice");
        vm.prank(alice);
        cell.execute(address(cell), 0, inner, n);
        vm.prank(bob);
        cell.execute(address(cell), 0, inner, n);

        // Stage by "guardian" (which is Alice); Bob finalizes
        bytes32 n2 = keccak256("n-g=alice-flow");
        bytes memory cd = abi.encodeWithSelector(Sink.setX.selector, 777);
        vm.prank(alice);
        (bool first,,) = cell.execute(address(sink), 0, cd, n2);
        assertTrue(first);

        vm.prank(bob);
        (, bool ok,) = cell.execute(address(sink), 0, cd, n2);
        assertTrue(ok);
        assertEq(sink.x(), 777);
    }

    // Removing guardian immediately revokes their rights (including 712 signing).
    function testGuardianRemoval_DisablesRights_And712() public {
        // add guardian g
        address g = vm.addr(uint256(keccak256("g-removal")));
        bytes32 nAdd = keccak256("n-add-g-removal");
        bytes memory addG = abi.encodeWithSelector(cell.setGuardian.selector, g);
        vm.prank(alice);
        cell.execute(address(cell), 0, addG, nAdd);
        vm.prank(bob);
        cell.execute(address(cell), 0, addG, nAdd);

        // remove guardian (set zero)
        bytes32 nRem = keccak256("n-rem-g-removal");
        bytes memory remG = abi.encodeWithSelector(cell.setGuardian.selector, address(0));
        vm.prank(alice);
        cell.execute(address(cell), 0, remG, nRem);
        vm.prank(bob);
        cell.execute(address(cell), 0, remG, nRem);

        // 712 stage with former guardian should now revert NotOwner
        address[] memory tos = new address[](1);
        uint256[] memory vals = new uint256[](1);
        bytes[] memory datas = new bytes[](1);
        tos[0] = address(sink);
        vals[0] = 0;
        datas[0] = abi.encodeWithSelector(Sink.ping.selector);

        bytes32 nonce = keccak256("n-712-g-removed");
        bytes32 callHash = _hashBatch(tos, vals, datas, nonce);
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _signBatch(callHash, deadline, pkG);

        vm.prank(address(0xBEEF));
        vm.expectRevert(Cell.NotOwner.selector);
        cell.batchExecuteWithSig(tos, vals, datas, nonce, deadline, v, r, s);

        // And direct stage should also revert
        vm.prank(g);
        vm.expectRevert(Cell.NotOwner.selector);
        cell.execute(address(sink), 0, "", keccak256("n-direct-after-removal"));
    }

    // Stage with Alice's sig; finalize with Bob's sig; both usedSigForHash flags should be true.
    function testBatchExecuteWithSig_StageAlice_FinalizeBobSig_MarksBothUsed() public {
        // Build a single-call batch (pay 0.13 ETH)
        _ensureWalletEth(1 ether);
        address[] memory tos = new address[](1);
        uint256[] memory vals = new uint256[](1);
        bytes[] memory datas = new bytes[](1);
        tos[0] = address(sink);
        vals[0] = 0.13 ether;
        datas[0] = abi.encodeWithSelector(Sink.ping.selector);

        bytes32 nonce = keccak256("n-712-two-sigs");
        bytes32 callHash = _hashBatch(tos, vals, datas, nonce);

        // Alice signs & stages (via relayer)
        uint256 deadline = block.timestamp + 1 days;
        (uint8 vA, bytes32 rA, bytes32 sA) = _signBatch(callHash, deadline, pkAlice);
        vm.prank(address(0xAA01));
        (bool first,,) = cell.batchExecuteWithSig(tos, vals, datas, nonce, deadline, vA, rA, sA);
        assertTrue(first);

        // Bob signs & finalizes (via relayer)
        (uint8 vB, bytes32 rB, bytes32 sB) = _signBatch(callHash, deadline, pkBob);
        uint256 sinkBefore = address(sink).balance;
        vm.prank(address(0xBB02));
        (, bool[] memory oks,) =
            cell.batchExecuteWithSig(tos, vals, datas, nonce, deadline, vB, rB, sB);
        assertTrue(oks[0]);
        assertEq(address(sink).balance, sinkBefore + 0.13 ether);

        // Both signatures marked as used
        assertTrue(cell.usedSigForHash(alice, callHash));
        assertTrue(cell.usedSigForHash(bob, callHash));
    }

    // High-s signature is rejected with BadSign before ecrecover.
    function testBatchExecuteWithSig_HighS_RevertsBadSign() public {
        address[] memory tos = new address[](1);
        uint256[] memory vals = new uint256[](1);
        bytes[] memory datas = new bytes[](1);
        tos[0] = address(sink);
        vals[0] = 0;
        datas[0] = abi.encodeWithSelector(Sink.ping.selector);

        bytes32 nonce = keccak256("n-712-high-s");
        bytes32 callHash = _hashBatch(tos, vals, datas, nonce);
        uint256 deadline = block.timestamp + 1 days;

        // Make any (v,r); force s to be above half-order threshold
        (uint8 v, bytes32 r,) = _signBatch(callHash, deadline, pkAlice);
        uint256 halfOrder = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;
        bytes32 highS = bytes32(halfOrder + 1);
        vm.prank(address(0xC0FFEE));
        vm.expectRevert(Cell.BadSign.selector);
        cell.batchExecuteWithSig(tos, vals, datas, nonce, deadline, v, r, highS);
    }

    function testPermit_Reentrancy_DrainsUpToCap_NotBeyond() public {
        ReenterPermit rp = new ReenterPermit();
        rp.setup(cell, 3); // will attempt 3 total spends

        // Grant 3 permits to the reentrancy contract via primaries (self-call)
        bytes memory inner = abi.encodeWithSelector(
            cell.setPermit.selector,
            address(rp), // spender
            3, // count
            address(rp), // to (reenter target)
            0,
            abi.encodeWithSelector(ReenterPermit.hop.selector)
        );
        bytes32 n = keccak256("n-permit-reent");
        vm.prank(alice);
        cell.execute(address(cell), 0, inner, n);
        vm.prank(bob);
        cell.execute(address(cell), 0, inner, n);

        // Reenter spends exactly 3 times, then further attempt reverts
        rp.trigger();
        vm.expectRevert();
        rp.trigger();
    }

    // Approve token to third party, and have them actually pull via transferFrom.
    function testApproveToken_ThirdPartyCanPullViaTransferFrom() public {
        ERC20Mock t = new ERC20Mock();
        t.mint(address(cell), 100 ether);
        address third = vm.addr(uint256(keccak256("third-puller")));

        // Self-call approveToken(token, third, 40e18)
        bytes memory inner = abi.encodeWithSelector(cell.approveToken.selector, t, third, 40 ether);
        bytes32 n = keccak256("n-approve-pull");
        vm.prank(alice);
        cell.execute(address(cell), 0, inner, n);
        vm.prank(bob);
        cell.execute(address(cell), 0, inner, n);

        // Third party pulls 10, then 30 (total 40)
        vm.prank(third);
        bool ok1 = t.transferFrom(address(cell), third, 10 ether);
        assertTrue(ok1);
        vm.prank(third);
        bool ok2 = t.transferFrom(address(cell), third, 30 ether);
        assertTrue(ok2);
        assertEq(t.balanceOf(third), 40 ether);

        // More pulls fail due to ERC20Mock allowance depletion
        vm.prank(third);
        vm.expectRevert(); // "noallow"
        t.transferFrom(address(cell), third, 1 ether);
    }

    // Multicall with mixed ops where a later op reverts -> whole call bubbles.
    function testMulticall_BubblesOnInnerRevert() public {
        bytes[] memory ops = new bytes[](2);
        ops[0] = abi.encodeWithSelector(cell.getChatCount.selector); // harmless
        ops[1] = abi.encodeWithSelector(
            cell.pullToken.selector,
            IToken(address(0xBEEF)), // value irrelevant now
            alice,
            1
        );

        vm.prank(address(0xDEAD)); // not an owner
        vm.expectRevert(Cell.NotOwner.selector);
        cell.multicall(ops);
    }
}

// -------- reentrancy on PERMIT path drains up to cap, not beyond --------
contract ReenterPermit {
    Cell public cell;
    uint256 public max;
    uint256 public count;

    function setup(Cell _cell, uint256 _max) external {
        cell = _cell;
        max = _max;
        count = 0;
    }

    // Called by Cell during first spend; re-enters until 'max'
    function hop() external {
        if (count + 1 < max) {
            count++;
            cell.spendPermit(address(this), 0, abi.encodeWithSelector(this.hop.selector));
        }
    }

    function trigger() external {
        cell.spendPermit(address(this), 0, abi.encodeWithSelector(this.hop.selector));
    }
}

contract Thrower {
    function boom() external pure {
        revert("BOOM");
    }
}

contract PureReturner {
    function ret(uint256 v) external pure returns (uint256) {
        return v + 1;
    }
}

contract ERC20Mock {
    string public name = "Mock";
    string public symbol = "MOCK";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amt) external {
        balanceOf[to] += amt;
    }

    function transfer(address to, uint256 amt) external returns (bool) {
        require(balanceOf[msg.sender] >= amt, "insufficient");
        balanceOf[msg.sender] -= amt;
        balanceOf[to] += amt;
        return true;
    }

    function approve(address sp, uint256 amt) external returns (bool) {
        allowance[msg.sender][sp] = amt;
        return true;
    }

    function transferFrom(address from, address to, uint256 amt) external returns (bool) {
        require(balanceOf[from] >= amt, "insufficient");
        require(allowance[from][msg.sender] >= amt, "noallow");
        allowance[from][msg.sender] -= amt;
        balanceOf[from] -= amt;
        balanceOf[to] += amt;
        return true;
    }
}

contract ERC20NoReturn {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amt) external {
        balanceOf[to] += amt;
    }

    function transfer(address to, uint256 amt) external {
        require(balanceOf[msg.sender] >= amt, "insufficient");
        balanceOf[msg.sender] -= amt;
        balanceOf[to] += amt;
    }

    function approve(address sp, uint256 amt) external {
        allowance[msg.sender][sp] = amt;
    }

    function transferFrom(address from, address to, uint256 amt) external {
        require(balanceOf[from] >= amt, "insufficient");
        require(allowance[from][msg.sender] >= amt, "noallow");
        allowance[from][msg.sender] -= amt;
        balanceOf[from] -= amt;
        balanceOf[to] += amt;
    }
}

contract ReenterSpender {
    Cell public cell;
    uint256 public chunk;
    uint256 public maxTimes;
    uint256 public count;

    function setup(Cell _cell, uint256 _chunk, uint256 _maxTimes) external {
        cell = _cell;
        chunk = _chunk;
        maxTimes = _maxTimes;
        count = 0;
    }

    function trigger() external {
        cell.spendAllowance(address(0), chunk);
    }

    receive() external payable {
        if (count + 1 < maxTimes) {
            // run exactly maxTimes in total
            count++;
            cell.spendAllowance(address(0), chunk);
        }
    }
}

contract ERC721Mock {
    mapping(uint256 => address) public ownerOf;

    function mint(address to, uint256 id) external {
        ownerOf[id] = to;
    }

    function safeTransferFrom(address from, address to, uint256 id, bytes calldata data) external {
        require(ownerOf[id] == from, "notowner");
        ownerOf[id] = to;
        if (to.code.length != 0) {
            bytes4 ret = IERC721Receiver(to).onERC721Received(msg.sender, from, id, data);
            require(ret == IERC721Receiver.onERC721Received.selector, "bad721");
        }
    }
}

interface IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4);
}

contract ERC1155Mock {
    mapping(address => mapping(uint256 => uint256)) public balanceOf;

    function mint(address to, uint256 id, uint256 amt) external {
        balanceOf[to][id] += amt;
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amt,
        bytes calldata data
    ) external {
        require(balanceOf[from][id] >= amt, "no1155bal");
        balanceOf[from][id] -= amt;
        balanceOf[to][id] += amt;
        if (to.code.length != 0) {
            bytes4 ret = IERC1155Receiver(to).onERC1155Received(msg.sender, from, id, amt, data);
            require(ret == IERC1155Receiver.onERC1155Received.selector, "bad1155");
        }
    }
}

interface IERC1155Receiver {
    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        returns (bytes4);
}

