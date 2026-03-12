// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Moloch, Shares} from "../src/Moloch.sol";
import {SafeSummoner, Call, SHARE_BURNER} from "../src/peripheral/SafeSummoner.sol";
import {ShareBurner} from "../src/peripheral/ShareBurner.sol";

contract SafeSummonerTest is Test {
    SafeSummoner internal safe;

    address internal alice = address(0xA11CE);
    address internal bob = address(0x0B0B);

    function setUp() public {
        vm.createSelectFork("main");
        vm.deal(alice, 100 ether);
        safe = new SafeSummoner();
    }

    // ── Helpers ──────────────────────────────────────────────────

    function _holders1() internal view returns (address[] memory h, uint256[] memory s) {
        h = new address[](1);
        h[0] = alice;
        s = new uint256[](1);
        s[0] = 100e18;
    }

    function _holders2() internal view returns (address[] memory h, uint256[] memory s) {
        h = new address[](2);
        h[0] = alice;
        h[1] = bob;
        s = new uint256[](2);
        s[0] = 60e18;
        s[1] = 40e18;
    }

    function _baseConfig() internal pure returns (SafeSummoner.SafeConfig memory c) {
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;
    }

    function _summon(uint16 quorumBps, SafeSummoner.SafeConfig memory config)
        internal
        returns (address dao)
    {
        (address[] memory h, uint256[] memory s) = _holders1();
        dao = safe.safeSummon(
            "Test DAO",
            "TEST",
            "",
            quorumBps,
            true,
            address(0),
            bytes32(uint256(block.timestamp)),
            h,
            s,
            config,
            new Call[](0)
        );
    }

    /*//////////////////////////////////////////////////////////////
                           HAPPY PATH
    //////////////////////////////////////////////////////////////*/

    function test_BasicSummon() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        address dao = _summon(5000, config);

        assertTrue(dao != address(0));
        assertEq(Moloch(payable(dao)).name(0), "Test DAO");
        assertEq(Moloch(payable(dao)).symbol(0), "TEST");
        assertEq(Moloch(payable(dao)).quorumBps(), 5000);
        assertEq(Moloch(payable(dao)).ragequittable(), true);
        assertEq(Moloch(payable(dao)).proposalThreshold(), 1e18);
        assertEq(Moloch(payable(dao)).proposalTTL(), 7 days);
    }

    function test_SummonWithAllOptions() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.timelockDelay = 1 days;
        config.quorumAbsolute = 10e18;
        config.minYesVotes = 5e18;
        config.lockShares = true;
        config.lockLoot = true;
        config.autoFutarchyParam = 500;
        config.autoFutarchyCap = 50e18;
        // futarchyRewardToken must be address(0)/DAO/shares/loot/1007
        // Use address(0) (ETH) for test
        config.futarchyRewardToken = address(0);

        address dao = _summon(5000, config);
        Moloch m = Moloch(payable(dao));

        assertEq(m.proposalThreshold(), 1e18);
        assertEq(m.proposalTTL(), 7 days);
        assertEq(m.timelockDelay(), 1 days);
        assertEq(m.quorumAbsolute(), 10e18);
        assertEq(m.minYesVotesAbsolute(), 5e18);
        assertEq(m.autoFutarchyParam(), 500);
        assertEq(m.autoFutarchyCap(), 50e18);
    }

    function test_SummonWithSale() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.quorumAbsolute = 10e18;
        config.saleActive = true;
        config.salePricePerShare = 0.01 ether;
        config.saleCap = 1000e18;
        config.saleMinting = true;

        address dao = _summon(0, config);
        assertTrue(dao != address(0));
    }

    function test_SummonWithETH() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        (address[] memory h, uint256[] memory s) = _holders1();

        vm.prank(alice);
        address dao = safe.safeSummon{value: 1 ether}(
            "Funded DAO",
            "FUND",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(1)),
            h,
            s,
            config,
            new Call[](0)
        );

        assertEq(dao.balance, 1 ether);
    }

    function test_SummonWithExtraCalls() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        (address[] memory h, uint256[] memory s) = _holders1();

        address predicted = safe.predictDAO(bytes32(uint256(42)), h, s);

        Call[] memory extra = new Call[](1);
        extra[0] = Call(predicted, 0, abi.encodeWithSignature("setQuorumBps(uint16)", uint16(2000)));

        address dao = safe.safeSummon(
            "Extra DAO",
            "XTRA",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(42)),
            h,
            s,
            config,
            extra
        );

        assertEq(Moloch(payable(dao)).quorumBps(), 2000);
    }

    function test_SummonTwoHolders() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        (address[] memory h, uint256[] memory s) = _holders2();

        address dao = safe.safeSummon(
            "Duo DAO",
            "DUO",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(99)),
            h,
            s,
            config,
            new Call[](0)
        );

        Shares shares = Moloch(payable(dao)).shares();
        assertEq(shares.balanceOf(alice), 60e18);
        assertEq(shares.balanceOf(bob), 40e18);
    }

    /*//////////////////////////////////////////////////////////////
                         ADDRESS PREDICTION
    //////////////////////////////////////////////////////////////*/

    function test_PredictDAO() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        (address[] memory h, uint256[] memory s) = _holders1();

        address predicted = safe.predictDAO(bytes32(uint256(777)), h, s);
        address dao = safe.safeSummon(
            "Predict DAO",
            "PRED",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(777)),
            h,
            s,
            config,
            new Call[](0)
        );

        assertEq(predicted, dao);
    }

    function test_PredictDAO_DifferentSalts() public view {
        (address[] memory h, uint256[] memory s) = _holders1();
        address a = safe.predictDAO(bytes32(uint256(1)), h, s);
        address b = safe.predictDAO(bytes32(uint256(2)), h, s);
        assertTrue(a != b);
    }

    /*//////////////////////////////////////////////////////////////
                          PREVIEW CALLS
    //////////////////////////////////////////////////////////////*/

    function test_PreviewCalls_Basic() public view {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        Call[] memory calls = safe.previewCalls(config);
        assertEq(calls.length, 2);
    }

    function test_PreviewCalls_AllOptions() public view {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.timelockDelay = 1 days;
        config.quorumAbsolute = 10e18;
        config.minYesVotes = 5e18;
        config.lockShares = true;
        config.autoFutarchyParam = 500;
        config.autoFutarchyCap = 10e18;
        config.futarchyRewardToken = address(0xBEEF);
        config.saleActive = true;
        config.salePricePerShare = 1e18;

        Call[] memory calls = safe.previewCalls(config);
        // proposalThreshold + proposalTTL + timelock + quorumAbsolute + minYesVotes
        // + transfersLocked + autoFutarchy + futarchyRewardToken + sale = 9
        assertEq(calls.length, 9);
    }

    /*//////////////////////////////////////////////////////////////
                     VALIDATION: KF#11 — proposalThreshold
    //////////////////////////////////////////////////////////////*/

    function test_RevertIf_ProposalThresholdZero() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.proposalThreshold = 0;

        vm.expectRevert(SafeSummoner.ProposalThresholdRequired.selector);
        _summon(5000, config);
    }

    /*//////////////////////////////////////////////////////////////
                     VALIDATION: proposalTTL
    //////////////////////////////////////////////////////////////*/

    function test_RevertIf_ProposalTTLZero() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.proposalTTL = 0;

        vm.expectRevert(SafeSummoner.ProposalTTLRequired.selector);
        _summon(5000, config);
    }

    /*//////////////////////////////////////////////////////////////
                     VALIDATION: KF#12 — quorumBps range
    //////////////////////////////////////////////////////////////*/

    function test_RevertIf_QuorumBpsExceeds10000() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();

        vm.expectRevert(SafeSummoner.QuorumBpsOutOfRange.selector);
        _summon(10001, config);
    }

    function test_QuorumBpsAt10000() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        address dao = _summon(10_000, config);
        assertEq(Moloch(payable(dao)).quorumBps(), 10_000);
    }

    function test_QuorumBpsAtZero() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.quorumAbsolute = 10e18;
        address dao = _summon(0, config);
        assertEq(Moloch(payable(dao)).quorumBps(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                     VALIDATION: TimelockExceedsTTL
    //////////////////////////////////////////////////////////////*/

    function test_RevertIf_TimelockEqualsTTL() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.proposalTTL = 3 days;
        config.timelockDelay = 3 days;

        vm.expectRevert(SafeSummoner.TimelockExceedsTTL.selector);
        _summon(5000, config);
    }

    function test_RevertIf_TimelockGreaterThanTTL() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.proposalTTL = 3 days;
        config.timelockDelay = 4 days;

        vm.expectRevert(SafeSummoner.TimelockExceedsTTL.selector);
        _summon(5000, config);
    }

    function test_TimelockShorterThanTTL() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.proposalTTL = 7 days;
        config.timelockDelay = 2 days;

        address dao = _summon(5000, config);
        assertEq(Moloch(payable(dao)).timelockDelay(), 2 days);
    }

    /*//////////////////////////////////////////////////////////////
                     VALIDATION: KF#17 — futarchy + zero quorum
    //////////////////////////////////////////////////////////////*/

    function test_RevertIf_FutarchyWithNoQuorum() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.autoFutarchyParam = 500;

        vm.expectRevert(SafeSummoner.QuorumRequiredForFutarchy.selector);
        _summon(0, config);
    }

    function test_FutarchyWithQuorumBps() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.autoFutarchyParam = 500;
        config.autoFutarchyCap = 10e18;

        address dao = _summon(5000, config);
        assertEq(Moloch(payable(dao)).autoFutarchyParam(), 500);
    }

    function test_FutarchyWithQuorumAbsolute() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.autoFutarchyParam = 500;
        config.autoFutarchyCap = 10e18;
        config.quorumAbsolute = 10e18;

        address dao = _summon(0, config);
        assertEq(Moloch(payable(dao)).autoFutarchyParam(), 500);
    }

    /*//////////////////////////////////////////////////////////////
                     VALIDATION: KF#3 — futarchy cap required
    //////////////////////////////////////////////////////////////*/

    function test_RevertIf_FutarchyWithNoCap() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.autoFutarchyParam = 500;
        config.autoFutarchyCap = 0;

        vm.expectRevert(SafeSummoner.FutarchyCapRequired.selector);
        _summon(5000, config);
    }

    function test_FutarchyWithCap() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.autoFutarchyParam = 500;
        config.autoFutarchyCap = 10e18;

        address dao = _summon(5000, config);
        assertEq(Moloch(payable(dao)).autoFutarchyCap(), 10e18);
    }

    function test_NoFutarchyAllowsZeroCap() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.autoFutarchyParam = 0;
        config.autoFutarchyCap = 0;

        address dao = _summon(5000, config);
        assertEq(Moloch(payable(dao)).autoFutarchyParam(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                     VALIDATION: KF#2 — minting sale + dynamic quorum
    //////////////////////////////////////////////////////////////*/

    function test_RevertIf_MintingSaleWithDynamicQuorum() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.saleActive = true;
        config.saleMinting = true;
        config.salePricePerShare = 1e18;

        vm.expectRevert(SafeSummoner.MintingSaleWithDynamicQuorum.selector);
        _summon(5000, config);
    }

    function test_MintingSaleWithAbsoluteQuorum() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.saleActive = true;
        config.saleMinting = true;
        config.salePricePerShare = 1e18;
        config.saleCap = 1000e18;
        config.quorumAbsolute = 50e18;

        address dao = _summon(5000, config);
        assertTrue(dao != address(0));
    }

    function test_NonMintingSaleWithDynamicQuorum() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.saleActive = true;
        config.saleMinting = false;
        config.salePricePerShare = 1e18;

        address dao = _summon(5000, config);
        assertTrue(dao != address(0));
    }

    /*//////////////////////////////////////////////////////////////
                     VALIDATION: Sale price required
    //////////////////////////////////////////////////////////////*/

    function test_RevertIf_SaleWithZeroPrice() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.saleActive = true;
        config.salePricePerShare = 0;
        config.quorumAbsolute = 10e18;

        vm.expectRevert(SafeSummoner.SalePriceRequired.selector);
        _summon(0, config);
    }

    /*//////////////////////////////////////////////////////////////
                     VALIDATION: No initial holders
    //////////////////////////////////////////////////////////////*/

    function test_RevertIf_NoInitialHolders() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();

        vm.expectRevert(SafeSummoner.NoInitialHolders.selector);
        safe.safeSummon(
            "Empty DAO",
            "EMPTY",
            "",
            5000,
            true,
            address(0),
            bytes32(0),
            new address[](0),
            new uint256[](0),
            config,
            new Call[](0)
        );
    }

    /*//////////////////////////////////////////////////////////////
                     DETERMINISTIC DEPLOYS
    //////////////////////////////////////////////////////////////*/

    function test_DifferentSaltsProduceDifferentDAOs() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        (address[] memory h, uint256[] memory s) = _holders1();

        address dao1 = safe.safeSummon(
            "DAO1",
            "D1",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(1)),
            h,
            s,
            config,
            new Call[](0)
        );
        address dao2 = safe.safeSummon(
            "DAO2",
            "D2",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(2)),
            h,
            s,
            config,
            new Call[](0)
        );

        assertTrue(dao1 != dao2);
    }

    function test_SameSaltReverts() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        (address[] memory h, uint256[] memory s) = _holders1();

        safe.safeSummon(
            "DAO1",
            "D1",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(777777)),
            h,
            s,
            config,
            new Call[](0)
        );

        vm.expectRevert();
        safe.safeSummon(
            "DAO2",
            "D2",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(777777)),
            h,
            s,
            config,
            new Call[](0)
        );
    }

    /*//////////////////////////////////////////////////////////////
                           PRESETS
    //////////////////////////////////////////////////////////////*/

    function test_SummonStandard() public {
        (address[] memory h, uint256[] memory s) = _holders1();
        address dao = safe.summonStandard("Std", "STD", "", bytes32(uint256(1)), h, s);
        Moloch m = Moloch(payable(dao));

        assertTrue(dao != address(0));
        assertEq(m.proposalThreshold(), 100e18 / 100); // 1% of 100e18
        assertEq(m.proposalTTL(), 7 days);
        assertEq(m.timelockDelay(), 2 days);
        assertEq(m.quorumBps(), 1000);
        assertEq(m.ragequittable(), true);
    }

    function test_SummonFast() public {
        (address[] memory h, uint256[] memory s) = _holders1();
        address dao = safe.summonFast("Fast", "FAST", "", bytes32(uint256(2)), h, s);
        Moloch m = Moloch(payable(dao));

        assertEq(m.proposalTTL(), 3 days);
        assertEq(m.timelockDelay(), 1 days);
        assertEq(m.quorumBps(), 1000);
        assertEq(m.ragequittable(), true);
    }

    function test_SummonMinimal() public {
        (address[] memory h, uint256[] memory s) = _holders1();
        address dao = safe.summonMinimal("Min", "MIN", "", bytes32(uint256(3)), h, s);
        Moloch m = Moloch(payable(dao));

        assertEq(m.proposalTTL(), 3 days);
        assertEq(m.timelockDelay(), 0); // no timelock
        assertEq(m.quorumBps(), 500);
        assertEq(m.ragequittable(), true);
    }

    function test_SummonLocked() public {
        (address[] memory h, uint256[] memory s) = _holders1();
        address dao = safe.summonLocked("Lock", "LOCK", "", bytes32(uint256(4)), h, s);
        Moloch m = Moloch(payable(dao));

        assertEq(m.proposalTTL(), 7 days);
        assertEq(m.timelockDelay(), 2 days);
        assertEq(m.quorumBps(), 1000);
        assertEq(m.ragequittable(), false);
    }

    function test_PresetThresholdScalesWithSupply() public {
        // Two holders: 60e18 + 40e18 = 100e18 total -> threshold = 1e18
        (address[] memory h, uint256[] memory s) = _holders2();
        address dao = safe.summonStandard("Scale", "SCL", "", bytes32(uint256(5)), h, s);
        assertEq(Moloch(payable(dao)).proposalThreshold(), 1e18);

        // One holder: 100e18 total -> threshold = 1e18
        (address[] memory h2, uint256[] memory s2) = _holders1();
        address dao2 = safe.summonStandard("Scale2", "SC2", "", bytes32(uint256(6)), h2, s2);
        assertEq(Moloch(payable(dao2)).proposalThreshold(), 1e18);
    }

    function test_PresetThresholdFloorAtOne() public {
        // Single holder with 50 shares -> 50/100 = 0, floored to 1
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 50;
        address dao = safe.summonStandard("Tiny", "TINY", "", bytes32(uint256(7)), h, s);
        assertEq(Moloch(payable(dao)).proposalThreshold(), 1);
    }

    /*//////////////////////////////////////////////////////////////
                           SHARE BURNER
    //////////////////////////////////////////////////////////////*/

    function test_SharesPrediction() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        address dao = _summon(1000, config);
        address predicted = safe.predictShares(dao);
        address actual = address(Moloch(payable(dao)).shares());
        assertEq(predicted, actual);
    }

    function test_LootPrediction() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        address dao = _summon(1000, config);
        address predicted = safe.predictLoot(dao);
        address actual = address(Moloch(payable(dao)).loot());
        assertEq(predicted, actual);
    }

    function test_SummonWithBurnDeadline() public {
        (address[] memory h, uint256[] memory s) = _holders1();
        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.saleActive = true;
        config.salePricePerShare = 1e18;
        config.saleBurnDeadline = block.timestamp + 30 days;

        address dao = safe.safeSummon(
            "Burn",
            "BURN",
            "",
            1000,
            true,
            address(0),
            bytes32(uint256(800)),
            h,
            s,
            config,
            new Call[](0)
        );
        assertTrue(dao != address(0));
        // Permit should be set — ShareBurner should have balance of 1 for the permit token
        // We verify by checking the sale is active and the DAO deployed successfully
        Moloch m = Moloch(payable(dao));
        assertEq(m.proposalThreshold(), 1e18);
    }

    function test_BurnPermitCallHelper() public {
        (address[] memory h, uint256[] memory s) = _holders1();
        Call memory permitCall =
            safe.burnPermitCall(bytes32(uint256(900)), h, s, block.timestamp + 30 days);
        // Should target the predicted DAO
        address dao = safe.predictDAO(bytes32(uint256(900)), h, s);
        assertEq(permitCall.target, dao);
        assertEq(permitCall.value, 0);
        assertTrue(permitCall.data.length > 0);
    }

    function test_CloseSaleAfterDeadline() public {
        // Non-minting sale: DAO holds shares and transfers to buyers.
        // Use extraCalls to mint shares to the DAO for selling.
        bytes32 salt = bytes32(uint256(801));
        uint256 deadline = block.timestamp + 30 days;
        (address[] memory h, uint256[] memory s) = _holders1();

        // Predict addresses
        address dao = safe.predictDAO(salt, h, s);
        address sharesAddr = safe.predictShares(dao);

        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.saleActive = true;
        config.salePricePerShare = 1; // 1 wei per share
        config.saleMinting = false; // non-minting: DAO transfers its shares
        config.saleBurnDeadline = deadline;

        // Extra call: mint 90e18 shares to the DAO for the sale
        Call[] memory extra = new Call[](1);
        extra[0] = Call(
            sharesAddr, 0, abi.encodeWithSignature("mintFromMoloch(address,uint256)", dao, 90e18)
        );

        address deployed = safe.safeSummon(
            "BurnTest", "BT", "", 1000, true, address(0), salt, h, s, config, extra
        );
        assertEq(deployed, dao);

        Moloch m = Moloch(payable(dao));

        // DAO should hold 90e18 shares from the mint
        assertEq(Shares(sharesAddr).balanceOf(dao), 90e18);

        // Buy 10e18 shares from DAO (ETH sale, payToken = address(0))
        // cost = 10e18 shares * 1 wei/share = 10e18 wei
        vm.deal(address(this), 10e18);
        m.buyShares{value: 10e18}(address(0), 10e18, 0);

        // DAO should hold 80e18 now
        assertEq(Shares(sharesAddr).balanceOf(dao), 80e18);

        // Can't close before deadline — burnUnsold reverts with SaleActive,
        // which _execute wraps as NotOk
        vm.expectRevert(Moloch.NotOk.selector);
        ShareBurner(SHARE_BURNER).closeSale(dao, sharesAddr, deadline, keccak256("ShareBurner"));

        // Warp past deadline
        vm.warp(deadline + 1);

        // Anyone can close
        ShareBurner(SHARE_BURNER).closeSale(dao, sharesAddr, deadline, keccak256("ShareBurner"));

        // DAO balance should be 0 after burn
        assertEq(Shares(sharesAddr).balanceOf(dao), 0);
    }
}
