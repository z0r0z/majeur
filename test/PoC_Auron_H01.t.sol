// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Renderer} from "../src/Renderer.sol";
import {Moloch, Shares, Loot, Badges, Summoner, Call} from "../src/Moloch.sol";

/// @title Auron H-01 PoC — Self-transfer vote delta under split delegation
/// @notice Demonstrates the invariant violation: self-transfer should be a no-op for votes,
///         but under split delegation, `_targetAlloc` rounding produces non-canceling deltas.
///         With realistic 18-decimal balances, the effect is sub-wei dust (not exploitable).
///         See audit/auron.md for full analysis.
contract PoC_Auron_H01 is Test {
    Summoner internal summoner;
    Moloch internal moloch;
    Shares internal shares;

    address internal attacker = address(0xBEEF);
    address internal victim = address(0xF00D);

    function _deploy(uint256 attackerBal, uint256 victimBal) internal {
        summoner = new Summoner();
        address renderer = address(new Renderer());
        address[] memory h = new address[](0);
        uint256[] memory a = new uint256[](0);
        moloch =
            summoner.summon("T", "T", "", 5000, true, renderer, bytes32(0), h, a, new Call[](0));
        shares = moloch.shares();
        vm.startPrank(address(moloch));
        if (attackerBal > 0) shares.mintFromMoloch(attacker, attackerBal);
        if (victimBal > 0) shares.mintFromMoloch(victim, victimBal);
        vm.stopPrank();
    }

    function _setSplit2Way(uint32 bps0) internal {
        address[] memory d = new address[](2);
        d[0] = victim;
        d[1] = attacker;
        uint32[] memory b = new uint32[](2);
        b[0] = bps0;
        b[1] = uint32(10000) - bps0;
        vm.prank(attacker);
        shares.setSplitDelegation(d, b);
    }

    function _setSplit4Way() internal {
        address[] memory d = new address[](4);
        d[0] = victim;
        d[1] = address(0x1111);
        d[2] = address(0x2222);
        d[3] = attacker;
        uint32[] memory b = new uint32[](4);
        b[0] = 4999;
        b[1] = 1;
        b[2] = 1;
        b[3] = 4999;
        vm.prank(attacker);
        shares.setSplitDelegation(d, b);
    }

    function _abs(int256 x) internal pure returns (uint256) {
        return x >= 0 ? uint256(x) : uint256(-x);
    }

    // =========================================================================
    // Original PoC (0-decimal balances) — demonstrates the mechanism
    // =========================================================================

    /// @dev Original PoC: raw integer balance = 1 unit. Bug is visible.
    function test_original_0decimal_selfTransfer() public {
        _deploy(1, 1); // 1 wei each — NOT 1 share
        _setSplit2Way(5000);

        assertEq(shares.getVotes(attacker), 1);
        assertEq(shares.getVotes(victim), 1);

        vm.prank(attacker);
        shares.transfer(attacker, 1);

        // Invariant violated: votes changed despite no balance change
        assertEq(shares.getVotes(attacker), 2, "attacker inflated");
        assertEq(shares.getVotes(victim), 0, "victim drained");
    }

    // =========================================================================
    // Realistic 18-decimal tests — demonstrates the bug is not exploitable
    // =========================================================================

    /// @dev 1 ether self-transfer with 50/50 split: zero steal
    function test_18decimal_5050_transferFull() public {
        _deploy(1 ether, 200_000 ether);
        _setSplit2Way(5000);

        uint256 vBefore = shares.getVotes(victim);
        uint256 aBefore = shares.getVotes(attacker);

        vm.prank(attacker);
        shares.transfer(attacker, 1 ether);

        assertEq(shares.getVotes(victim), vBefore, "victim votes changed on full transfer");
        assertEq(shares.getVotes(attacker), aBefore, "attacker votes changed on full transfer");
    }

    /// @dev 1-wei self-transfer with 50/50 split: attacker LOSES, victim GAINS
    function test_18decimal_5050_transfer1wei() public {
        _deploy(1 ether, 200_000 ether);
        _setSplit2Way(5000);

        uint256 vBefore = shares.getVotes(victim);
        uint256 aBefore = shares.getVotes(attacker);

        vm.prank(attacker);
        shares.transfer(attacker, 1);

        int256 vDelta = int256(shares.getVotes(victim)) - int256(vBefore);
        int256 aDelta = int256(shares.getVotes(attacker)) - int256(aBefore);

        // Attacker loses, victim gains — attack goes wrong direction
        assertEq(vDelta, 1, "victim should gain 1 wei");
        assertEq(aDelta, -1, "attacker should lose 1 wei");
    }

    /// @dev Various split ratios with 1-wei transfer: all go wrong direction for attacker
    function test_18decimal_variousSplits_transfer1wei() public {
        uint32[4] memory ratios = [uint32(5000), uint32(9999), uint32(1), uint32(3333)];

        for (uint256 r; r < ratios.length; r++) {
            _deploy(1 ether, 200_000 ether);
            _setSplit2Way(ratios[r]);

            uint256 vBefore = shares.getVotes(victim);

            vm.prank(attacker);
            shares.transfer(attacker, 1);

            int256 vDelta = int256(shares.getVotes(victim)) - int256(vBefore);
            // Victim never loses more than 1 wei, and usually gains
            assertTrue(vDelta >= -1, "victim lost more than 1 wei");
        }
    }

    /// @dev 4-way split (original PoC config) with 18-decimal: attacker loses 3 wei
    function test_18decimal_4way_transfer1wei() public {
        _deploy(1 ether, 200_000 ether);
        _setSplit4Way();

        uint256 vBefore = shares.getVotes(victim);
        uint256 aBefore = shares.getVotes(attacker);

        vm.prank(attacker);
        shares.transfer(attacker, 1);

        int256 vDelta = int256(shares.getVotes(victim)) - int256(vBefore);
        int256 aDelta = int256(shares.getVotes(attacker)) - int256(aBefore);

        assertEq(vDelta, 1, "victim gains 1 wei");
        assertEq(aDelta, -3, "attacker loses 3 wei");
    }

    /// @dev 1000 iterations, 2-way split, 1-wei transfers: max accumulation = 1000 wei = 10^-15 share
    function test_18decimal_loop1000_2way() public {
        _deploy(1 ether + 1, 200_000 ether); // odd balance for max rounding
        _setSplit2Way(5000);

        uint256 vBefore = shares.getVotes(victim);
        uint256 aBefore = shares.getVotes(attacker);

        for (uint256 i; i < 1000; i++) {
            vm.prank(attacker);
            shares.transfer(attacker, 1);
        }

        int256 vDelta = int256(shares.getVotes(victim)) - int256(vBefore);
        int256 aDelta = int256(shares.getVotes(attacker)) - int256(aBefore);

        // After 1000 iterations: victim lost 1000 wei = 0.000000000000001 shares
        assertEq(vDelta, -1000);
        assertEq(aDelta, 1000);
        // To steal 1 share: need 10^15 iterations × 50k gas = 5×10^19 gas (impossible)
    }

    /// @dev 1000 iterations, 4-way split (original PoC config): exactly 0 net change
    function test_18decimal_loop1000_4way() public {
        _deploy(1 ether + 1, 200_000 ether);
        _setSplit4Way();

        uint256 vBefore = shares.getVotes(victim);

        for (uint256 i; i < 1000; i++) {
            vm.prank(attacker);
            shares.transfer(attacker, 1);
        }

        int256 vDelta = int256(shares.getVotes(victim)) - int256(vBefore);
        assertEq(vDelta, 0, "4-way loop should produce 0 net change");
    }

    /// @dev 100k-share attacker self-transferring full balance: zero steal
    function test_18decimal_largeAttacker() public {
        _deploy(100_000 ether, 200_000 ether);
        _setSplit2Way(5000);

        uint256 vBefore = shares.getVotes(victim);

        vm.prank(attacker);
        shares.transfer(attacker, 100_000 ether);

        assertEq(shares.getVotes(victim), vBefore, "victim votes changed");
    }
}
