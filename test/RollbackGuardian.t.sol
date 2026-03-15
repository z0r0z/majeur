// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Moloch, Shares} from "../src/Moloch.sol";
import {SafeSummoner, Call} from "../src/peripheral/SafeSummoner.sol";
import {RollbackGuardian, Call as GCall} from "../src/peripheral/RollbackGuardian.sol";

contract RollbackGuardianTest is Test {
    SafeSummoner internal safe;
    RollbackGuardian internal guardian;

    address internal alice = address(0xA11CE);
    address internal bob = address(0x0B0B);
    address internal guardianEOA = address(0x600D);

    function setUp() public {
        vm.createSelectFork("main");
        vm.deal(alice, 100 ether);
        safe = new SafeSummoner();
        guardian = new RollbackGuardian();
    }

    // ── Helpers ──────────────────────────────────────────────────

    function _deployWithGuardian(bytes32 salt, uint40 expiry) internal returns (address dao) {
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        dao = safe.predictDAO(salt, h, s);

        // Build initCalls: configure + rollback permit + futarchy permit
        GCall[3] memory gc = guardian.initCalls(dao, guardianEOA, expiry);

        Call[] memory extra = new Call[](3);
        extra[0] = Call(gc[0].target, gc[0].value, gc[0].data);
        extra[1] = Call(gc[1].target, gc[1].value, gc[1].data);
        extra[2] = Call(gc[2].target, gc[2].value, gc[2].data);

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;
        c.timelockDelay = 2 days;

        address deployed = safe.safeSummon(
            "GuardDAO", "GUARD", "", 1000, true, address(0), salt, h, s, new uint256[](0), c, extra
        );
        assertEq(deployed, dao);
    }

    // ── Configuration ────────────────────────────────────────────

    function test_Configure() public {
        address dao = _deployWithGuardian(bytes32(uint256(1)), 0);

        (address g, uint40 exp) = guardian.configs(dao);
        assertEq(g, guardianEOA);
        assertEq(exp, 0);
    }

    function test_RevertIf_ConfigureZeroGuardian() public {
        vm.expectRevert(RollbackGuardian.Unauthorized.selector);
        guardian.configure(address(0), 0);
    }

    // ── Rollback ─────────────────────────────────────────────────

    function test_Rollback() public {
        address dao = _deployWithGuardian(bytes32(uint256(10)), 0);

        uint64 configBefore = Moloch(payable(dao)).config();

        vm.prank(guardianEOA);
        guardian.rollback(dao);

        uint64 configAfter = Moloch(payable(dao)).config();
        assertEq(configAfter, configBefore + 1);
    }

    function test_Rollback_IsOneShot() public {
        address dao = _deployWithGuardian(bytes32(uint256(11)), 0);

        vm.prank(guardianEOA);
        guardian.rollback(dao);

        // Second rollback fails — permit ID changed after config bump
        vm.prank(guardianEOA);
        vm.expectRevert(); // Moloch rejects: permit ID not found
        guardian.rollback(dao);
    }

    function test_RevertIf_NotGuardian() public {
        address dao = _deployWithGuardian(bytes32(uint256(12)), 0);

        vm.prank(bob);
        vm.expectRevert(RollbackGuardian.Unauthorized.selector);
        guardian.rollback(dao);
    }

    function test_RevertIf_Expired() public {
        uint40 expiry = uint40(block.timestamp + 1 days);
        address dao = _deployWithGuardian(bytes32(uint256(13)), expiry);

        vm.warp(expiry + 1);

        vm.prank(guardianEOA);
        vm.expectRevert(RollbackGuardian.Expired.selector);
        guardian.rollback(dao);
    }

    function test_Rollback_BeforeExpiry() public {
        uint40 expiry = uint40(block.timestamp + 30 days);
        address dao = _deployWithGuardian(bytes32(uint256(14)), expiry);

        uint64 configBefore = Moloch(payable(dao)).config();

        vm.prank(guardianEOA);
        guardian.rollback(dao);

        assertEq(Moloch(payable(dao)).config(), configBefore + 1);
    }

    function test_RevertIf_NotConfigured() public {
        vm.prank(guardianEOA);
        vm.expectRevert(RollbackGuardian.NotConfigured.selector);
        guardian.rollback(address(0xdead));
    }

    // ── Governance ───────────────────────────────────────────────

    function test_SetGuardian() public {
        address dao = _deployWithGuardian(bytes32(uint256(20)), 0);

        vm.prank(dao);
        guardian.setGuardian(bob);

        (address g,) = guardian.configs(dao);
        assertEq(g, bob);
    }

    function test_SetExpiry() public {
        address dao = _deployWithGuardian(bytes32(uint256(21)), 0);

        vm.prank(dao);
        guardian.setExpiry(uint40(block.timestamp + 365 days));

        (, uint40 exp) = guardian.configs(dao);
        assertEq(exp, uint40(block.timestamp + 365 days));
    }

    function test_Revoke() public {
        address dao = _deployWithGuardian(bytes32(uint256(22)), 0);

        vm.prank(dao);
        guardian.revoke();

        (address g,) = guardian.configs(dao);
        assertEq(g, address(0));

        // Guardian can no longer rollback
        vm.prank(guardianEOA);
        vm.expectRevert(RollbackGuardian.NotConfigured.selector);
        guardian.rollback(dao);
    }

    function test_RevertIf_SetGuardianNotDAO() public {
        _deployWithGuardian(bytes32(uint256(23)), 0);

        vm.prank(bob);
        vm.expectRevert(RollbackGuardian.NotConfigured.selector);
        guardian.setGuardian(bob);
    }

    function test_RevertIf_SetGuardianToZero() public {
        address dao = _deployWithGuardian(bytes32(uint256(24)), 0);

        vm.prank(dao);
        vm.expectRevert(RollbackGuardian.Unauthorized.selector);
        guardian.setGuardian(address(0));
    }

    // ── Init Call Helpers ────────────────────────────────────────

    function test_RollbackPermitCallHelper() public view {
        address dao = address(0xDA0);
        (address target, uint256 value, bytes memory data) = guardian.rollbackPermitCall(dao);

        assertEq(target, dao);
        assertEq(value, 0);
        assertTrue(data.length > 0);
    }

    function test_FutarchyPermitCallHelper() public view {
        address dao = address(0xDA0);
        (address target, uint256 value, bytes memory data) = guardian.futarchyPermitCall(dao);

        assertEq(target, dao);
        assertEq(value, 0);
        assertTrue(data.length > 0);
    }

    function test_InitCallsHelper() public view {
        address dao = address(0xDA0);
        GCall[3] memory gc = guardian.initCalls(dao, guardianEOA, 0);

        assertEq(gc[0].target, address(guardian)); // configure
        assertEq(gc[1].target, dao); // rollback permit
        assertEq(gc[2].target, dao); // futarchy permit
        assertTrue(gc[0].data.length > 0);
        assertTrue(gc[1].data.length > 0);
        assertTrue(gc[2].data.length > 0);
    }

    // ── Kill Futarchy ────────────────────────────────────────────

    function test_KillFutarchy() public {
        address dao = _deployWithGuardian(bytes32(uint256(40)), 0);

        // Enable auto-futarchy via DAO governance
        vm.prank(dao);
        Moloch(payable(dao)).setAutoFutarchy(500, 10e18);
        uint256 param = Moloch(payable(dao)).autoFutarchyParam();
        assertEq(param, 500);

        // Guardian kills futarchy
        vm.prank(guardianEOA);
        guardian.killFutarchy(dao);

        param = Moloch(payable(dao)).autoFutarchyParam();
        assertEq(param, 0);
    }

    function test_KillFutarchy_IsOneShot() public {
        address dao = _deployWithGuardian(bytes32(uint256(41)), 0);

        vm.prank(dao);
        Moloch(payable(dao)).setAutoFutarchy(500, 10e18);

        vm.prank(guardianEOA);
        guardian.killFutarchy(dao);

        // Re-enable futarchy
        vm.prank(dao);
        Moloch(payable(dao)).setAutoFutarchy(500, 10e18);

        // Second kill fails — permit already spent
        vm.prank(guardianEOA);
        vm.expectRevert();
        guardian.killFutarchy(dao);
    }

    function test_KillFutarchy_RevertIf_NotGuardian() public {
        address dao = _deployWithGuardian(bytes32(uint256(42)), 0);

        vm.prank(bob);
        vm.expectRevert(RollbackGuardian.Unauthorized.selector);
        guardian.killFutarchy(dao);
    }

    function test_KillFutarchy_IndependentOfRollback() public {
        address dao = _deployWithGuardian(bytes32(uint256(43)), 0);

        vm.prank(dao);
        Moloch(payable(dao)).setAutoFutarchy(500, 10e18);

        // Use killFutarchy first
        vm.prank(guardianEOA);
        guardian.killFutarchy(dao);

        // Rollback still works (separate permit)
        uint64 configBefore = Moloch(payable(dao)).config();
        vm.prank(guardianEOA);
        guardian.rollback(dao);
        assertEq(Moloch(payable(dao)).config(), configBefore + 1);
    }

    // ── No Expiry ────────────────────────────────────────────────

    function test_NoExpiry_WorksFarFuture() public {
        address dao = _deployWithGuardian(bytes32(uint256(30)), 0);

        vm.warp(block.timestamp + 3650 days); // 10 years

        vm.prank(guardianEOA);
        guardian.rollback(dao);

        // Config bumped
        assertTrue(Moloch(payable(dao)).config() > 0);
    }

    // ── Governance Access Control (additional) ────────────────────

    function test_RevertIf_SetExpiryNotDAO() public {
        _deployWithGuardian(bytes32(uint256(50)), 0);

        vm.prank(bob);
        vm.expectRevert(RollbackGuardian.NotConfigured.selector);
        guardian.setExpiry(uint40(block.timestamp + 365 days));
    }

    function test_RevertIf_RevokeNotDAO() public {
        _deployWithGuardian(bytes32(uint256(51)), 0);

        vm.prank(bob);
        vm.expectRevert(RollbackGuardian.NotConfigured.selector);
        guardian.revoke();
    }

    // ── Kill Futarchy Expired ─────────────────────────────────────

    function test_KillFutarchy_RevertIf_Expired() public {
        uint40 expiry = uint40(block.timestamp + 1 days);
        address dao = _deployWithGuardian(bytes32(uint256(52)), expiry);

        vm.prank(dao);
        Moloch(payable(dao)).setAutoFutarchy(500, 10e18);

        vm.warp(expiry + 1);

        vm.prank(guardianEOA);
        vm.expectRevert(RollbackGuardian.Expired.selector);
        guardian.killFutarchy(dao);
    }

    // ── Reconfigure Guardian ──────────────────────────────────────

    function test_SetGuardian_ThenRollback() public {
        address dao = _deployWithGuardian(bytes32(uint256(53)), 0);

        vm.prank(dao);
        guardian.setGuardian(bob);

        // Old guardian can't rollback
        vm.prank(guardianEOA);
        vm.expectRevert(RollbackGuardian.Unauthorized.selector);
        guardian.rollback(dao);

        // New guardian can
        uint64 configBefore = Moloch(payable(dao)).config();
        vm.prank(bob);
        guardian.rollback(dao);
        assertEq(Moloch(payable(dao)).config(), configBefore + 1);
    }

    // ── Revoke then reconfigure ───────────────────────────────────

    function test_Revoke_KillFutarchy_Fails() public {
        address dao = _deployWithGuardian(bytes32(uint256(54)), 0);

        vm.prank(dao);
        guardian.revoke();

        vm.prank(guardianEOA);
        vm.expectRevert(RollbackGuardian.NotConfigured.selector);
        guardian.killFutarchy(dao);
    }
}
