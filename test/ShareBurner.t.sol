// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Moloch, Shares, Loot} from "../src/Moloch.sol";
import {SafeSummoner, Call, SHARE_BURNER} from "../src/peripheral/SafeSummoner.sol";
import {ShareBurner} from "../src/peripheral/ShareBurner.sol";

contract ShareBurnerTest is Test {
    SafeSummoner internal safe;

    address internal alice = address(0xA11CE);

    event SaleClosed(address indexed dao, uint256 sharesBurned);

    function setUp() public {
        vm.createSelectFork("main");
        vm.deal(alice, 100 ether);
        safe = new SafeSummoner();
    }

    // ── Helpers ──────────────────────────────────────────────────

    /// @dev Deploy DAO with ShareBurner permit for shares.
    function _deployWithBurner(bytes32 salt, uint256 deadline)
        internal
        returns (address dao, address sharesAddr)
    {
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        dao = safe.predictDAO(salt, h, s);
        sharesAddr = safe.predictShares(dao);

        SafeSummoner.SafeConfig memory config;
        config.proposalThreshold = 1e18;
        config.proposalTTL = 7 days;
        config.saleActive = true;
        config.salePricePerShare = 1; // 1 wei per share
        config.saleMinting = false;
        config.saleBurnDeadline = deadline;

        // Mint shares to DAO for the sale
        Call[] memory extra = new Call[](1);
        extra[0] = Call(
            sharesAddr, 0, abi.encodeWithSignature("mintFromMoloch(address,uint256)", dao, 50e18)
        );

        address deployed = safe.safeSummon(
            "BurnerDAO",
            "BURN",
            "",
            1000,
            true,
            address(0),
            salt,
            h,
            s,
            new uint256[](0),
            config,
            extra
        );
        assertEq(deployed, dao);
    }

    /// @dev Deploy DAO with ShareBurner permit for loot.
    function _deployWithLootBurner(bytes32 salt, uint256 deadline)
        internal
        returns (address dao, address lootAddr)
    {
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        dao = safe.predictDAO(salt, h, s);

        SafeSummoner.SafeConfig memory config;
        config.proposalThreshold = 1e18;
        config.proposalTTL = 7 days;
        config.saleActive = true;
        config.salePricePerShare = 1;
        config.saleIsLoot = true;
        config.saleMinting = false;
        config.saleBurnDeadline = deadline;
        config.quorumAbsolute = 10e18;

        lootAddr = safe.predictLoot(dao);

        // Mint loot to DAO for the sale
        Call[] memory extra = new Call[](1);
        extra[0] = Call(
            lootAddr, 0, abi.encodeWithSignature("mintFromMoloch(address,uint256)", dao, 50e18)
        );

        address deployed = safe.safeSummon(
            "LootBurnDAO",
            "LB",
            "",
            0,
            true,
            address(0),
            salt,
            h,
            s,
            new uint256[](0),
            config,
            extra
        );
        assertEq(deployed, dao);
    }

    // ── closeSale: Happy Path ─────────────────────────────────────

    function test_CloseSale_BurnsShares() public {
        uint256 deadline = block.timestamp + 30 days;
        (address dao, address sharesAddr) = _deployWithBurner(bytes32(uint256(1)), deadline);

        assertEq(Shares(sharesAddr).balanceOf(dao), 50e18);

        vm.warp(deadline + 1);

        ShareBurner(SHARE_BURNER).closeSale(dao, sharesAddr, deadline, keccak256("ShareBurner"));

        assertEq(Shares(sharesAddr).balanceOf(dao), 0);
    }

    function test_CloseSale_EmitsEvent() public {
        uint256 deadline = block.timestamp + 30 days;
        (address dao, address sharesAddr) = _deployWithBurner(bytes32(uint256(2)), deadline);

        vm.warp(deadline + 1);

        vm.expectEmit(true, false, false, true);
        emit SaleClosed(dao, 50e18);
        ShareBurner(SHARE_BURNER).closeSale(dao, sharesAddr, deadline, keccak256("ShareBurner"));
    }

    function test_CloseSale_ZeroBalance() public {
        uint256 deadline = block.timestamp + 30 days;
        (address dao, address sharesAddr) = _deployWithBurner(bytes32(uint256(3)), deadline);

        // Buy all shares so DAO balance is 0
        vm.deal(address(this), 50e18);
        Moloch(payable(dao)).buyShares{value: 50e18}(address(0), 50e18, 0);
        assertEq(Shares(sharesAddr).balanceOf(dao), 0);

        vm.warp(deadline + 1);

        // Should succeed even with 0 balance (burn is a no-op)
        ShareBurner(SHARE_BURNER).closeSale(dao, sharesAddr, deadline, keccak256("ShareBurner"));
        assertEq(Shares(sharesAddr).balanceOf(dao), 0);
    }

    function test_CloseSale_Permissionless() public {
        uint256 deadline = block.timestamp + 30 days;
        (address dao, address sharesAddr) = _deployWithBurner(bytes32(uint256(4)), deadline);

        vm.warp(deadline + 1);

        // Random caller can close the sale
        address random = address(0xCAFE);
        vm.prank(random);
        ShareBurner(SHARE_BURNER).closeSale(dao, sharesAddr, deadline, keccak256("ShareBurner"));

        assertEq(Shares(sharesAddr).balanceOf(dao), 0);
    }

    function test_CloseSale_LootBurn() public {
        uint256 deadline = block.timestamp + 30 days;
        (address dao, address lootAddr) = _deployWithLootBurner(bytes32(uint256(5)), deadline);

        assertEq(Loot(lootAddr).balanceOf(dao), 50e18);

        vm.warp(deadline + 1);

        ShareBurner(SHARE_BURNER).closeSale(dao, lootAddr, deadline, keccak256("ShareBurner"));

        assertEq(Loot(lootAddr).balanceOf(dao), 0);
    }

    // ── closeSale: Reverts ────────────────────────────────────────

    function test_RevertIf_CloseSaleBeforeDeadline() public {
        uint256 deadline = block.timestamp + 30 days;
        (address dao, address sharesAddr) = _deployWithBurner(bytes32(uint256(10)), deadline);

        // Before deadline — burnUnsold reverts with SaleActive, Moloch wraps as NotOk
        vm.expectRevert(Moloch.NotOk.selector);
        ShareBurner(SHARE_BURNER).closeSale(dao, sharesAddr, deadline, keccak256("ShareBurner"));
    }

    function test_RevertIf_CloseSaleAtExactDeadline() public {
        uint256 deadline = block.timestamp + 30 days;
        (address dao, address sharesAddr) = _deployWithBurner(bytes32(uint256(11)), deadline);

        vm.warp(deadline); // at deadline, not past it

        // burnUnsold checks `block.timestamp <= deadline`, so exact deadline should revert
        vm.expectRevert(Moloch.NotOk.selector);
        ShareBurner(SHARE_BURNER).closeSale(dao, sharesAddr, deadline, keccak256("ShareBurner"));
    }

    function test_RevertIf_CloseSaleTwice() public {
        uint256 deadline = block.timestamp + 30 days;
        (address dao, address sharesAddr) = _deployWithBurner(bytes32(uint256(12)), deadline);

        vm.warp(deadline + 1);

        ShareBurner(SHARE_BURNER).closeSale(dao, sharesAddr, deadline, keccak256("ShareBurner"));

        // One-shot: permit already spent
        vm.expectRevert();
        ShareBurner(SHARE_BURNER).closeSale(dao, sharesAddr, deadline, keccak256("ShareBurner"));
    }

    function test_RevertIf_WrongNonce() public {
        uint256 deadline = block.timestamp + 30 days;
        (address dao, address sharesAddr) = _deployWithBurner(bytes32(uint256(13)), deadline);

        vm.warp(deadline + 1);

        // Wrong nonce should fail in permit lookup
        vm.expectRevert();
        ShareBurner(SHARE_BURNER).closeSale(dao, sharesAddr, deadline, keccak256("WrongNonce"));
    }

    function test_RevertIf_WrongShares() public {
        uint256 deadline = block.timestamp + 30 days;
        (address dao,) = _deployWithBurner(bytes32(uint256(14)), deadline);

        vm.warp(deadline + 1);

        // Wrong shares address — permit data mismatch
        vm.expectRevert();
        ShareBurner(SHARE_BURNER)
            .closeSale(dao, address(0xBEEF), deadline, keccak256("ShareBurner"));
    }

    function test_RevertIf_WrongDeadline() public {
        uint256 deadline = block.timestamp + 30 days;
        (address dao, address sharesAddr) = _deployWithBurner(bytes32(uint256(15)), deadline);

        vm.warp(deadline + 1);

        // Wrong deadline — permit data mismatch
        vm.expectRevert();
        ShareBurner(SHARE_BURNER).closeSale(dao, sharesAddr, deadline + 1, keccak256("ShareBurner"));
    }

    // ── permitCall Helper ─────────────────────────────────────────

    function test_PermitCallHelper() public view {
        address dao = address(0xDA0);
        address shares = address(0x5A5);
        uint256 deadline = block.timestamp + 30 days;
        bytes32 salt = keccak256("test");

        (address target, uint256 value, bytes memory data) =
            ShareBurner(SHARE_BURNER).permitCall(dao, shares, deadline, salt);

        assertEq(target, dao);
        assertEq(value, 0);
        assertTrue(data.length > 0);
    }

    function test_PermitCallHelper_DeterministicEncoding() public view {
        address dao = address(0xDA0);
        address shares = address(0x5A5);
        uint256 deadline = block.timestamp + 30 days;
        bytes32 salt = keccak256("test");

        (,, bytes memory data1) = ShareBurner(SHARE_BURNER).permitCall(dao, shares, deadline, salt);
        (,, bytes memory data2) = ShareBurner(SHARE_BURNER).permitCall(dao, shares, deadline, salt);

        assertEq(keccak256(data1), keccak256(data2));
    }

    function test_PermitCallHelper_DifferentSalts() public view {
        address dao = address(0xDA0);
        address shares = address(0x5A5);
        uint256 deadline = block.timestamp + 30 days;

        (,, bytes memory data1) =
            ShareBurner(SHARE_BURNER).permitCall(dao, shares, deadline, keccak256("a"));
        (,, bytes memory data2) =
            ShareBurner(SHARE_BURNER).permitCall(dao, shares, deadline, keccak256("b"));

        assertTrue(keccak256(data1) != keccak256(data2));
    }
}
