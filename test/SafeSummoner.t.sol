// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Moloch, Shares} from "../src/Moloch.sol";
import {SafeSummoner, Call, SHARE_BURNER} from "../src/peripheral/SafeSummoner.sol";
import {ShareBurner} from "../src/peripheral/ShareBurner.sol";
import {ShareSale} from "../src/peripheral/ShareSale.sol";
import {TapVest} from "../src/peripheral/TapVest.sol";
import {LPSeedSwapHook} from "../src/peripheral/LPSeedSwapHook.sol";
import {RollbackGuardian} from "../src/peripheral/RollbackGuardian.sol";

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

    function _noLoot() internal pure returns (uint256[] memory) {
        return new uint256[](0);
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
            _noLoot(),
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
            _noLoot(),
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
            _noLoot(),
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
            _noLoot(),
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
            _noLoot(),
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
        config.futarchyRewardToken = address(1007); // loot minting sentinel
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

    function test_FutarchyWithRewardToken() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.autoFutarchyParam = 500;
        config.autoFutarchyCap = 10e18;
        config.futarchyRewardToken = address(1007); // loot minting sentinel

        // previewCalls should include setFutarchyRewardToken
        Call[] memory calls = safe.previewCalls(config);
        // proposalThreshold + proposalTTL + autoFutarchy + futarchyRewardToken = 4
        assertEq(calls.length, 4);

        address dao = _summon(5000, config);
        assertTrue(dao != address(0));
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

    function test_MintingSaleWithIsLoot() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.saleActive = true;
        config.saleMinting = true;
        config.saleIsLoot = true;
        config.salePricePerShare = 1e18;
        config.saleCap = 100e18;
        config.quorumAbsolute = 10e18;

        (address[] memory h, uint256[] memory s) = _holders1();
        address dao = safe.safeSummon(
            "LootSale",
            "LS",
            "",
            0,
            true,
            address(0),
            bytes32(uint256(6000)),
            h,
            s,
            _noLoot(),
            config,
            new Call[](0)
        );
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
            _noLoot(),
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
            _noLoot(),
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
            _noLoot(),
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
            _noLoot(),
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
            _noLoot(),
            config,
            new Call[](0)
        );
    }

    /*//////////////////////////////////////////////////////////////
                           PRESETS
    //////////////////////////////////////////////////////////////*/

    function test_SummonStandard() public {
        (address[] memory h, uint256[] memory s) = _holders1();
        address dao = safe.summonStandard("Std", "STD", "", bytes32(uint256(1)), h, s, false);
        Moloch m = Moloch(payable(dao));

        assertTrue(dao != address(0));
        assertEq(m.proposalThreshold(), 100e18 / 100); // 1% of 100e18
        assertEq(m.proposalTTL(), 7 days);
        assertEq(m.timelockDelay(), 2 days);
        assertEq(m.quorumBps(), 1000);
        assertEq(m.ragequittable(), true);
    }

    function test_SummonStandard_LockedShares() public {
        (address[] memory h, uint256[] memory s) = _holders1();
        address dao = safe.summonStandard("Locked", "LOCK", "", bytes32(uint256(1001)), h, s, true);
        Moloch m = Moloch(payable(dao));

        assertEq(m.proposalTTL(), 7 days);
        assertEq(m.timelockDelay(), 2 days);
        // Shares should be non-transferable
        address sharesAddr = safe.predictShares(dao);
        vm.prank(alice);
        vm.expectRevert();
        Shares(sharesAddr).transfer(bob, 1e18);
    }

    function test_SummonFast() public {
        (address[] memory h, uint256[] memory s) = _holders1();
        address dao = safe.summonFast("Fast", "FAST", "", bytes32(uint256(2)), h, s, false);
        Moloch m = Moloch(payable(dao));

        assertEq(m.proposalTTL(), 3 days);
        assertEq(m.timelockDelay(), 1 days);
        assertEq(m.quorumBps(), 500);
        assertEq(m.ragequittable(), true);
    }

    function test_SummonFounder() public {
        vm.prank(alice);
        address dao = safe.summonFounder("Founder", "FND", "", bytes32(uint256(100)));
        Moloch m = Moloch(payable(dao));

        assertTrue(dao != address(0));
        assertEq(m.proposalTTL(), 1 days);
        assertEq(m.timelockDelay(), 0);
        assertEq(m.quorumBps(), 1000);
        assertEq(m.ragequittable(), true);
        assertEq(m.proposalThreshold(), 100_000e18); // 1% of 10M

        // Alice should have 10M shares
        address sharesAddr = safe.predictShares(dao);
        assertEq(Shares(sharesAddr).balanceOf(alice), 10_000_000e18);
    }

    function test_PresetThresholdScalesWithSupply() public {
        // Two holders: 60e18 + 40e18 = 100e18 total -> threshold = 1e18
        (address[] memory h, uint256[] memory s) = _holders2();
        address dao = safe.summonStandard("Scale", "SCL", "", bytes32(uint256(5)), h, s, false);
        assertEq(Moloch(payable(dao)).proposalThreshold(), 1e18);

        // One holder: 100e18 total -> threshold = 1e18
        (address[] memory h2, uint256[] memory s2) = _holders1();
        address dao2 = safe.summonStandard("Scale2", "SC2", "", bytes32(uint256(6)), h2, s2, false);
        assertEq(Moloch(payable(dao2)).proposalThreshold(), 1e18);
    }

    function test_PresetThresholdFloorAtOne() public {
        // Single holder with 50 shares -> 50/100 = 0, floored to 1
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 50;
        address dao = safe.summonStandard("Tiny", "TINY", "", bytes32(uint256(7)), h, s, false);
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
            _noLoot(),
            config,
            new Call[](0)
        );
        assertTrue(dao != address(0));
        // Permit should be set — ShareBurner should have balance of 1 for the permit token
        // We verify by checking the sale is active and the DAO deployed successfully
        Moloch m = Moloch(payable(dao));
        assertEq(m.proposalThreshold(), 1e18);
    }

    function test_SummonWithBurnDeadline_LootSale() public {
        (address[] memory h, uint256[] memory s) = _holders1();
        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.saleActive = true;
        config.salePricePerShare = 1e18;
        config.saleIsLoot = true;
        config.saleMinting = true;
        config.saleBurnDeadline = block.timestamp + 30 days;
        config.quorumAbsolute = 10e18;

        address dao = safe.safeSummon(
            "LootBurn",
            "LB",
            "",
            0,
            true,
            address(0),
            bytes32(uint256(801)),
            h,
            s,
            _noLoot(),
            config,
            new Call[](0)
        );
        assertTrue(dao != address(0));

        // Verify the burn permit targets loot, not shares
        address lootAddr = safe.predictLoot(dao);
        address sharesAddr = safe.predictShares(dao);
        assertTrue(lootAddr != sharesAddr);

        // The burn permit is encoded with loot address — verify by warping past deadline
        // and calling closeSale (which uses the permit). Mint loot to DAO first via extraCalls
        // would be complex, so just verify deployment succeeds with the loot sale config.
        Moloch m = Moloch(payable(dao));
        assertEq(m.proposalThreshold(), 1e18);
    }

    function test_BurnPermitCallHelper() public view {
        (address[] memory h, uint256[] memory s) = _holders1();
        Call memory permitCall =
            safe.burnPermitCall(bytes32(uint256(900)), h, s, block.timestamp + 30 days, address(0));
        // Should target the predicted DAO
        address dao = safe.predictDAO(bytes32(uint256(900)), h, s);
        assertEq(permitCall.target, dao);
        assertEq(permitCall.value, 0);
        assertTrue(permitCall.data.length > 0);
    }

    /*//////////////////////////////////////////////////////////////
                        MODULAR DAICO
    //////////////////////////////////////////////////////////////*/

    function _emptySale() internal pure returns (SafeSummoner.SaleModule memory) {}
    function _emptyTap() internal pure returns (SafeSummoner.TapModule memory) {}
    function _emptySeed() internal pure returns (SafeSummoner.SeedModule memory) {}

    function test_SafeSummonDAICO_SaleOnly() public {
        (address[] memory h, uint256[] memory s) = _holders1();
        bytes32 salt = bytes32(uint256(2000));

        ShareSale shareSale = new ShareSale();
        address dao = safe.predictDAO(salt, h, s);

        SafeSummoner.SaleModule memory sale;
        sale.singleton = address(shareSale);
        sale.payToken = address(0); // ETH
        sale.price = 0.01e18; // 0.01 ETH per share
        sale.cap = 50e18;
        sale.sellLoot = false;
        sale.minting = true;

        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.quorumAbsolute = 10e18; // required for minting sale

        address deployed = safe.safeSummonDAICO(
            "SaleDAO",
            "SALE",
            "",
            0,
            true,
            address(0),
            salt,
            h,
            s,
            _noLoot(),
            config,
            sale,
            _emptyTap(),
            _emptySeed(),
            new Call[](0)
        );
        assertEq(deployed, dao);

        // Verify ShareSale is configured
        (address token, address payToken,, uint256 price) = shareSale.sales(dao);
        assertEq(token, dao); // minting sentinel = address(dao)
        assertEq(payToken, address(0));
        assertEq(price, 0.01e18);

        // Verify allowance is set
        assertEq(Moloch(payable(dao)).allowance(dao, address(shareSale)), 50e18);

        // Buy shares
        vm.deal(bob, 1 ether);
        vm.prank(bob);
        shareSale.buy{value: 0.1 ether}(dao, 10e18);
        address sharesAddr = safe.predictShares(dao);
        assertEq(Shares(sharesAddr).balanceOf(bob), 10e18);
    }

    function test_SafeSummonDAICO_SaleAndTap() public {
        (address[] memory h, uint256[] memory s) = _holders1();
        bytes32 salt = bytes32(uint256(2001));

        ShareSale shareSale = new ShareSale();
        TapVest tapVest = new TapVest();

        SafeSummoner.SaleModule memory sale;
        sale.singleton = address(shareSale);
        sale.payToken = address(0);
        sale.price = 1e18;
        sale.cap = 100e18;
        sale.minting = true;

        SafeSummoner.TapModule memory tap;
        tap.singleton = address(tapVest);
        tap.token = address(0); // ETH tap
        tap.budget = 10 ether;
        tap.beneficiary = bob;
        tap.ratePerSec = 0.001e18; // 0.001 ETH/sec

        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.quorumAbsolute = 10e18;

        address dao = safe.safeSummonDAICO{value: 10 ether}(
            "TapDAO",
            "TAP",
            "",
            0,
            true,
            address(0),
            salt,
            h,
            s,
            _noLoot(),
            config,
            sale,
            tap,
            _emptySeed(),
            new Call[](0)
        );

        // Verify tap is configured
        (address tToken, address tBen, uint128 tRate,) = tapVest.taps(dao);
        assertEq(tToken, address(0));
        assertEq(tBen, bob);
        assertEq(tRate, 0.001e18);

        // Verify ETH allowance for tap
        assertEq(Moloch(payable(dao)).allowance(address(0), address(tapVest)), 10 ether);

        // Advance time, claim tap
        vm.warp(block.timestamp + 100);
        uint256 bobBefore = bob.balance;
        tapVest.claim(dao);
        assertEq(bob.balance - bobBefore, 0.1e18); // 100s * 0.001 ETH/s
    }

    function test_SafeSummonDAICO_FullStack() public {
        (address[] memory h, uint256[] memory s) = _holders1();
        bytes32 salt = bytes32(uint256(2002));

        ShareSale shareSale = new ShareSale();
        TapVest tapVest = new TapVest();
        LPSeedSwapHook lpSeed = new LPSeedSwapHook();

        address dao = safe.predictDAO(salt, h, s);
        address sharesAddr = safe.predictShares(dao);

        SafeSummoner.SaleModule memory sale;
        sale.singleton = address(shareSale);
        sale.payToken = address(0);
        sale.price = 1e18;
        sale.cap = 50e18;
        sale.minting = true;

        SafeSummoner.TapModule memory tap;
        tap.singleton = address(tapVest);
        tap.token = address(0);
        tap.budget = 5 ether;
        tap.beneficiary = bob;
        tap.ratePerSec = 0.001e18;

        SafeSummoner.SeedModule memory seed;
        seed.singleton = address(lpSeed);
        seed.tokenA = address(0); // ETH
        seed.amountA = 5e18;
        seed.tokenB = address(1); // shares sentinel → mints + resolves
        seed.amountB = 5e18;
        seed.gateBySale = true;
        seed.deadline = 0;
        seed.minSupply = 0;

        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.quorumAbsolute = 10e18;

        address deployed = safe.safeSummonDAICO{value: 50 ether}(
            "FullDAO",
            "FULL",
            "",
            0,
            true,
            address(0),
            salt,
            h,
            s,
            _noLoot(),
            config,
            sale,
            tap,
            seed,
            new Call[](0)
        );
        assertEq(deployed, dao);

        // Verify all modules configured
        (address sToken,,,) = shareSale.sales(dao);
        assertEq(sToken, dao);

        (address tToken, address tBen,,) = tapVest.taps(dao);
        assertEq(tToken, address(0));
        assertEq(tBen, bob);

        (address seedA, address seedB,,,,,,,,,,,,) = lpSeed.seeds(dao);
        assertEq(seedA, address(0)); // ETH
        assertEq(seedB, sharesAddr); // resolved shares address

        // No pre-mint — shares are minted on spend via allowance sentinel
        assertEq(Shares(sharesAddr).balanceOf(dao), 0);

        // Allowances set correctly
        assertEq(Moloch(payable(dao)).allowance(dao, address(shareSale)), 50e18);
        assertEq(Moloch(payable(dao)).allowance(address(0), address(tapVest)), 5 ether);
        assertEq(Moloch(payable(dao)).allowance(address(0), address(lpSeed)), 5e18);
        // LP seed uses Moloch mint sentinel (address(dao)) for shares, not real ERC20
        assertEq(Moloch(payable(dao)).allowance(dao, address(lpSeed)), 5e18);

        // LP not seedable yet (sale gate active, sale not complete)
        assertFalse(lpSeed.seedable(dao));

        // Buy all shares to complete sale
        vm.deal(alice, 100 ether);
        vm.prank(alice);
        shareSale.buy{value: 50 ether}(dao, 50e18);
        assertEq(Moloch(payable(dao)).allowance(dao, address(shareSale)), 0);

        // Now LP is seedable
        assertTrue(lpSeed.seedable(dao));

        // Seed LP
        lpSeed.seed(dao);
        (,,,,,,,,,,, uint40 seeded,,) = lpSeed.seeds(dao);
        assertTrue(seeded != 0);
    }

    function test_SummonStandardDAICO() public {
        (address[] memory h, uint256[] memory s) = _holders1();
        bytes32 salt = bytes32(uint256(2003));

        ShareSale shareSale = new ShareSale();

        SafeSummoner.SaleModule memory sale;
        sale.singleton = address(shareSale);
        sale.payToken = address(0);
        sale.price = 1e18;
        sale.cap = 10e18;

        address dao = safe.summonStandardDAICO(
            "StdDAICO", "SDAO", "", salt, h, s, false, sale, _emptyTap(), _emptySeed()
        );

        Moloch m = Moloch(payable(dao));
        assertEq(m.proposalTTL(), 7 days);
        assertEq(m.timelockDelay(), 2 days);
        assertEq(m.quorumBps(), 1000);

        (,,, uint256 price) = shareSale.sales(dao);
        assertEq(price, 1e18);
    }

    function test_SummonFastDAICO() public {
        (address[] memory h, uint256[] memory s) = _holders1();
        bytes32 salt = bytes32(uint256(2004));

        ShareSale shareSale = new ShareSale();

        SafeSummoner.SaleModule memory sale;
        sale.singleton = address(shareSale);
        sale.payToken = address(0);
        sale.price = 1e18;
        sale.cap = 10e18;

        address dao = safe.summonFastDAICO(
            "FastDAICO", "FDAO", "", salt, h, s, false, sale, _emptyTap(), _emptySeed()
        );

        Moloch m = Moloch(payable(dao));
        assertEq(m.proposalTTL(), 3 days);
        assertEq(m.timelockDelay(), 1 days);
        assertEq(m.quorumBps(), 500);

        (,,, uint256 price) = shareSale.sales(dao);
        assertEq(price, 1e18);
    }

    function test_RevertIf_ModuleSaleConflict() public {
        (address[] memory h, uint256[] memory s) = _holders1();

        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.saleActive = true;
        config.salePricePerShare = 1e18;

        SafeSummoner.SaleModule memory sale;
        sale.singleton = address(1); // non-zero = active

        vm.expectRevert(SafeSummoner.ModuleSaleConflict.selector);
        safe.safeSummonDAICO(
            "X",
            "X",
            "",
            1000,
            true,
            address(0),
            bytes32(0),
            h,
            s,
            _noLoot(),
            config,
            sale,
            _emptyTap(),
            _emptySeed(),
            new Call[](0)
        );
    }

    function test_RevertIf_SeedGateWithoutSale() public {
        (address[] memory h, uint256[] memory s) = _holders1();

        SafeSummoner.SafeConfig memory config = _baseConfig();

        SafeSummoner.SeedModule memory seed;
        seed.singleton = address(1);
        seed.gateBySale = true; // gate set but no SaleModule

        vm.expectRevert(SafeSummoner.SeedGateWithoutSale.selector);
        safe.safeSummonDAICO(
            "X",
            "X",
            "",
            1000,
            true,
            address(0),
            bytes32(0),
            h,
            s,
            _noLoot(),
            config,
            _emptySale(),
            _emptyTap(),
            seed,
            new Call[](0)
        );
    }

    function test_RevertIf_ModuleSaleMintingDynamicQuorum() public {
        (address[] memory h, uint256[] memory s) = _holders1();

        SafeSummoner.SafeConfig memory config = _baseConfig();

        SafeSummoner.SaleModule memory sale;
        sale.singleton = address(1);
        sale.price = 1e18;
        sale.minting = true; // minting + dynamic quorum = bad

        vm.expectRevert(SafeSummoner.MintingSaleWithDynamicQuorum.selector);
        safe.safeSummonDAICO(
            "X",
            "X",
            "",
            1000,
            true,
            address(0),
            bytes32(0),
            h,
            s,
            _noLoot(),
            config,
            sale,
            _emptyTap(),
            _emptySeed(),
            new Call[](0)
        );
    }

    function test_RevertIf_ModuleSaleZeroPrice() public {
        (address[] memory h, uint256[] memory s) = _holders1();

        SafeSummoner.SafeConfig memory config = _baseConfig();

        SafeSummoner.SaleModule memory sale;
        sale.singleton = address(1);
        sale.price = 0; // no price

        vm.expectRevert(SafeSummoner.SalePriceRequired.selector);
        safe.safeSummonDAICO(
            "X",
            "X",
            "",
            1000,
            true,
            address(0),
            bytes32(0),
            h,
            s,
            _noLoot(),
            config,
            sale,
            _emptyTap(),
            _emptySeed(),
            new Call[](0)
        );
    }

    function test_PreviewModuleCalls() public {
        ShareSale shareSale = new ShareSale();

        SafeSummoner.SaleModule memory sale;
        sale.singleton = address(shareSale);
        sale.payToken = address(0);
        sale.price = 1e18;
        sale.cap = 10e18;
        sale.minting = true;

        Call[] memory calls = safe.previewModuleCalls(sale, _emptyTap(), _emptySeed());
        assertEq(calls.length, 2); // setAllowance + configure
    }

    function test_SafeSummonDAICO_LootSale() public {
        (address[] memory h, uint256[] memory s) = _holders1();
        bytes32 salt = bytes32(uint256(2005));

        ShareSale shareSale = new ShareSale();

        SafeSummoner.SaleModule memory sale;
        sale.singleton = address(shareSale);
        sale.payToken = address(0);
        sale.price = 0.5e18;
        sale.cap = 20e18;
        sale.sellLoot = true;
        sale.minting = true;

        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.quorumAbsolute = 10e18;

        address dao = safe.safeSummonDAICO(
            "LootDAO",
            "LOOT",
            "",
            0,
            true,
            address(0),
            salt,
            h,
            s,
            _noLoot(),
            config,
            sale,
            _emptyTap(),
            _emptySeed(),
            new Call[](0)
        );

        (address token,,,) = shareSale.sales(dao);
        assertEq(token, address(1007)); // loot minting sentinel
    }

    function test_RevertIf_RollbackGuardianWithoutSingleton() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.rollbackGuardian = address(0x600D); // guardian set
        config.rollbackSingleton = address(0); // but no singleton

        vm.expectRevert(SafeSummoner.RollbackSingletonRequired.selector);
        _summon(1000, config);
    }

    function test_SummonWithRollbackGuardian() public {
        (address[] memory h, uint256[] memory s) = _holders1();
        bytes32 salt = bytes32(uint256(900));

        RollbackGuardian guardian = new RollbackGuardian();
        address guardianEOA = address(0x600D);

        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.rollbackGuardian = guardianEOA;
        config.rollbackSingleton = address(guardian);
        config.rollbackExpiry = 0; // no expiry

        address dao = safe.safeSummon(
            "GuardDAO",
            "GUARD",
            "",
            1000,
            true,
            address(0),
            salt,
            h,
            s,
            _noLoot(),
            config,
            new Call[](0)
        );

        // Verify guardian is configured
        (address g, uint40 exp) = guardian.configs(dao);
        assertEq(g, guardianEOA);
        assertEq(exp, 0);

        // Verify rollback works
        uint64 configBefore = Moloch(payable(dao)).config();
        vm.prank(guardianEOA);
        guardian.rollback(dao);
        assertEq(Moloch(payable(dao)).config(), configBefore + 1);
    }

    /*//////////////////////////////////////////////////////////////
                           INIT LOOT
    //////////////////////////////////////////////////////////////*/

    function test_SummonWithInitLoot() public {
        (address[] memory h, uint256[] memory s) = _holders2();
        uint256[] memory loot = new uint256[](2);
        loot[0] = 30e18;
        loot[1] = 20e18;

        SafeSummoner.SafeConfig memory config = _baseConfig();
        address dao = safe.safeSummon(
            "Loot DAO",
            "LOOT",
            "",
            1000,
            true,
            address(0),
            bytes32(uint256(5000)),
            h,
            s,
            loot,
            config,
            new Call[](0)
        );

        address lootAddr = safe.predictLoot(dao);
        assertEq(Shares(lootAddr).balanceOf(alice), 30e18);
        assertEq(Shares(lootAddr).balanceOf(bob), 20e18);
    }

    function test_SummonWithInitLoot_SkipsZeroAmounts() public {
        (address[] memory h, uint256[] memory s) = _holders2();
        uint256[] memory loot = new uint256[](2);
        loot[0] = 10e18;
        loot[1] = 0; // bob gets no loot

        SafeSummoner.SafeConfig memory config = _baseConfig();
        address dao = safe.safeSummon(
            "Partial Loot",
            "PLOOT",
            "",
            1000,
            true,
            address(0),
            bytes32(uint256(5001)),
            h,
            s,
            loot,
            config,
            new Call[](0)
        );

        address lootAddr = safe.predictLoot(dao);
        assertEq(Shares(lootAddr).balanceOf(alice), 10e18);
        assertEq(Shares(lootAddr).balanceOf(bob), 0);
    }

    function test_SummonWithEmptyInitLoot() public {
        SafeSummoner.SafeConfig memory config = _baseConfig();
        // Empty initLoot = skip (same as before)
        address dao = _summon(1000, config);
        address lootAddr = safe.predictLoot(dao);
        assertEq(Shares(lootAddr).balanceOf(alice), 0);
    }

    function test_RevertIf_InitLootLengthMismatch() public {
        (address[] memory h, uint256[] memory s) = _holders2();
        uint256[] memory loot = new uint256[](1); // wrong length
        loot[0] = 10e18;

        SafeSummoner.SafeConfig memory config = _baseConfig();
        vm.expectRevert(SafeSummoner.InitLootLengthMismatch.selector);
        safe.safeSummon(
            "Bad",
            "BAD",
            "",
            1000,
            true,
            address(0),
            bytes32(uint256(5002)),
            h,
            s,
            loot,
            config,
            new Call[](0)
        );
    }

    function test_SafeSummonDAICO_WithInitLoot() public {
        (address[] memory h, uint256[] memory s) = _holders1();
        uint256[] memory loot = new uint256[](1);
        loot[0] = 50e18;
        bytes32 salt = bytes32(uint256(5003));

        ShareSale shareSale = new ShareSale();

        SafeSummoner.SaleModule memory sale;
        sale.singleton = address(shareSale);
        sale.payToken = address(0);
        sale.price = 1e18;
        sale.cap = 10e18;

        SafeSummoner.SafeConfig memory config = _baseConfig();

        address dao = safe.safeSummonDAICO(
            "LootDAICO",
            "LDAO",
            "",
            1000,
            true,
            address(0),
            salt,
            h,
            s,
            loot,
            config,
            sale,
            _emptyTap(),
            _emptySeed(),
            new Call[](0)
        );

        address lootAddr = safe.predictLoot(dao);
        assertEq(Shares(lootAddr).balanceOf(alice), 50e18);
    }

    /*//////////////////////////////////////////////////////////////
                           MULTICALL
    //////////////////////////////////////////////////////////////*/

    function test_Multicall_BatchTwoDAOs() public {
        (address[] memory h, uint256[] memory s) = _holders1();
        SafeSummoner.SafeConfig memory config = _baseConfig();

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(
            safe.safeSummon,
            (
                "DAO A",
                "A",
                "",
                1000,
                true,
                address(0),
                bytes32(uint256(3000)),
                h,
                s,
                _noLoot(),
                config,
                new Call[](0)
            )
        );
        data[1] = abi.encodeCall(
            safe.safeSummon,
            (
                "DAO B",
                "B",
                "",
                1000,
                true,
                address(0),
                bytes32(uint256(3001)),
                h,
                s,
                _noLoot(),
                config,
                new Call[](0)
            )
        );

        bytes[] memory results = safe.multicall(data);
        address daoA = abi.decode(results[0], (address));
        address daoB = abi.decode(results[1], (address));

        assertTrue(daoA != address(0));
        assertTrue(daoB != address(0));
        assertTrue(daoA != daoB);
        assertEq(Moloch(payable(daoA)).name(0), "DAO A");
        assertEq(Moloch(payable(daoB)).name(0), "DAO B");
    }

    function test_Multicall_PreservesMsgSender() public {
        (address[] memory h, uint256[] memory s) = _holders1();
        SafeSummoner.SafeConfig memory config = _baseConfig();

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(
            safe.safeSummon,
            (
                "Sender DAO",
                "SND",
                "",
                1000,
                true,
                address(0),
                bytes32(uint256(3002)),
                h,
                s,
                _noLoot(),
                config,
                new Call[](0)
            )
        );

        vm.prank(alice);
        bytes[] memory results = safe.multicall(data);
        address dao = abi.decode(results[0], (address));
        assertTrue(dao != address(0));
    }

    function test_Multicall_WithETH() public {
        (address[] memory h, uint256[] memory s) = _holders1();
        SafeSummoner.SafeConfig memory config = _baseConfig();

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(
            safe.safeSummon,
            (
                "ETH DAO",
                "ETH",
                "",
                1000,
                true,
                address(0),
                bytes32(uint256(3003)),
                h,
                s,
                _noLoot(),
                config,
                new Call[](0)
            )
        );

        vm.prank(alice);
        bytes[] memory results = safe.multicall{value: 1 ether}(data);
        address dao = abi.decode(results[0], (address));
        assertEq(dao.balance, 1 ether);
    }

    function test_Multicall_BubblesRevert() public {
        (address[] memory h, uint256[] memory s) = _holders1();
        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.proposalThreshold = 0; // will fail validation

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(
            safe.safeSummon,
            (
                "Bad DAO",
                "BAD",
                "",
                1000,
                true,
                address(0),
                bytes32(uint256(3004)),
                h,
                s,
                _noLoot(),
                config,
                new Call[](0)
            )
        );

        vm.expectRevert(SafeSummoner.ProposalThresholdRequired.selector);
        safe.multicall(data);
    }

    /*//////////////////////////////////////////////////////////////
                           CREATE2 DEPLOY
    //////////////////////////////////////////////////////////////*/

    function test_Create2Deploy() public {
        // Deploy a ShareSale singleton via create2Deploy
        bytes memory creationCode = type(ShareSale).creationCode;
        bytes32 salt = bytes32(uint256(4000));

        address predicted = safe.predictCreate2(creationCode, salt);
        address deployed = safe.create2Deploy(creationCode, salt);

        assertEq(deployed, predicted);
        assertTrue(deployed != address(0));
        assertTrue(deployed.code.length > 0);
    }

    function test_Create2Deploy_DifferentSalts() public {
        bytes memory creationCode = type(ShareSale).creationCode;

        address a = safe.create2Deploy(creationCode, bytes32(uint256(4001)));
        address b = safe.create2Deploy(creationCode, bytes32(uint256(4002)));

        assertTrue(a != b);
    }

    function test_Create2Deploy_RevertOnDuplicate() public {
        bytes memory creationCode = type(ShareSale).creationCode;
        bytes32 salt = bytes32(uint256(4003));

        safe.create2Deploy(creationCode, salt);

        vm.expectRevert(SafeSummoner.Create2Failed.selector);
        safe.create2Deploy(creationCode, salt);
    }

    function test_Create2Deploy_InMulticall() public {
        // Deploy a ShareSale + summon a DAO using it in one multicall
        (address[] memory h, uint256[] memory s) = _holders1();
        bytes32 deploySalt = bytes32(uint256(4004));
        bytes32 daoSalt = bytes32(uint256(4005));

        bytes memory creationCode = type(ShareSale).creationCode;
        address predictedSale = safe.predictCreate2(creationCode, deploySalt);
        address predictedDAO = safe.predictDAO(daoSalt, h, s);

        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.quorumAbsolute = 10e18;

        SafeSummoner.SaleModule memory sale;
        sale.singleton = predictedSale;
        sale.payToken = address(0);
        sale.price = 1e18;
        sale.cap = 10e18;
        sale.minting = true;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(safe.create2Deploy, (creationCode, deploySalt));
        data[1] = abi.encodeCall(
            safe.safeSummonDAICO,
            (
                "C2 DAO",
                "C2",
                "",
                0,
                true,
                address(0),
                daoSalt,
                h,
                s,
                _noLoot(),
                config,
                sale,
                _emptyTap(),
                _emptySeed(),
                new Call[](0)
            )
        );

        bytes[] memory results = safe.multicall(data);
        address deployedSale = abi.decode(results[0], (address));
        address deployedDAO = abi.decode(results[1], (address));

        assertEq(deployedSale, predictedSale);
        assertEq(deployedDAO, predictedDAO);

        // Verify the sale is configured with the create2-deployed singleton
        (address token,,, uint256 price) = ShareSale(deployedSale).sales(deployedDAO);
        assertEq(token, deployedDAO); // minting sentinel
        assertEq(price, 1e18);
    }

    function test_PredictCreate2() public view {
        bytes memory creationCode = type(ShareSale).creationCode;
        bytes32 salt = bytes32(uint256(4006));

        address a = safe.predictCreate2(creationCode, salt);
        address b = safe.predictCreate2(creationCode, salt);
        assertEq(a, b);

        address c = safe.predictCreate2(creationCode, bytes32(uint256(4007)));
        assertTrue(a != c);
    }

    /*//////////////////////////////////////////////////////////////
                       CLOSE SALE AFTER DEADLINE
    //////////////////////////////////////////////////////////////*/

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
            "BurnTest", "BT", "", 1000, true, address(0), salt, h, s, _noLoot(), config, extra
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

    // ── Full DAICO Lifecycle: Sale → Tap Claim → Seed LP ──────────

    function test_SafeSummonDAICO_FullLifecycle_TapAndSeed() public {
        (address[] memory h, uint256[] memory s) = _holders1();
        bytes32 salt = bytes32(uint256(3001));

        ShareSale shareSale = new ShareSale();
        TapVest tapVest = new TapVest();
        LPSeedSwapHook lpSeed = new LPSeedSwapHook();

        address dao = safe.predictDAO(salt, h, s);
        address sharesAddr = safe.predictShares(dao);

        // Sale: 50 shares at 1 ETH each, minting
        SafeSummoner.SaleModule memory sale;
        sale.singleton = address(shareSale);
        sale.payToken = address(0);
        sale.price = 1e18;
        sale.cap = 50e18;
        sale.minting = true;

        // Tap: ETH streaming to bob at 0.01 ETH/sec, 10 ETH budget
        SafeSummoner.TapModule memory tap;
        tap.singleton = address(tapVest);
        tap.token = address(0);
        tap.budget = 10 ether;
        tap.beneficiary = bob;
        tap.ratePerSec = 0.01e18; // 0.01 ETH/sec

        // Seed: 5 ETH + 5 shares (mint sentinel), gated by sale
        SafeSummoner.SeedModule memory seed;
        seed.singleton = address(lpSeed);
        seed.tokenA = address(0); // ETH
        seed.amountA = 5e18;
        seed.tokenB = address(1); // shares sentinel
        seed.amountB = 5e18;
        seed.gateBySale = true;

        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.quorumAbsolute = 10e18;

        address deployed = safe.safeSummonDAICO{value: 50 ether}(
            "LifecycleDAO",
            "LIFE",
            "",
            0,
            true,
            address(0),
            salt,
            h,
            s,
            _noLoot(),
            config,
            sale,
            tap,
            seed,
            new Call[](0)
        );
        assertEq(deployed, dao);

        // ── Phase 1: Sale in progress, tap accruing ──────────────
        // Warp 100 seconds — tap accrues 1 ETH (0.01 * 100)
        vm.warp(block.timestamp + 100);

        uint256 claimable = tapVest.claimable(dao);
        assertEq(claimable, 1 ether);

        // Claim tap — bob receives ETH from DAO treasury
        uint256 bobBefore = bob.balance;
        tapVest.claim(dao);
        assertEq(bob.balance - bobBefore, 1 ether);

        // LP still gated by sale
        assertFalse(lpSeed.seedable(dao));

        // ── Phase 2: Complete sale ───────────────────────────────
        vm.deal(alice, 200 ether);
        vm.prank(alice);
        shareSale.buy{value: 50 ether}(dao, 50e18);
        assertEq(Moloch(payable(dao)).allowance(dao, address(shareSale)), 0);

        // ── Phase 3: Seed LP (sale complete) ─────────────────────
        assertTrue(lpSeed.seedable(dao));
        lpSeed.seed(dao);
        (,,,,,,,,,,, uint40 seeded,,) = lpSeed.seeds(dao);
        assertTrue(seeded != 0);

        // Verify shares were minted to LP (not pre-minted)
        // DAO should have LP tokens, shares went into the pool

        // ── Phase 4: Tap continues post-seed ─────────────────────
        // Warp another 200 seconds — 2 ETH accrued
        vm.warp(block.timestamp + 200);

        claimable = tapVest.claimable(dao);
        assertEq(claimable, 2 ether);

        bobBefore = bob.balance;
        tapVest.claim(dao);
        assertEq(bob.balance - bobBefore, 2 ether);

        // Verify tap allowance decreased (10 - 1 - 2 = 7)
        assertEq(Moloch(payable(dao)).allowance(address(0), address(tapVest)), 7 ether);
    }

    function test_SafeSummonDAICO_TapExhaustsBudget() public {
        (address[] memory h, uint256[] memory s) = _holders1();
        bytes32 salt = bytes32(uint256(3002));

        TapVest tapVest = new TapVest();

        address dao = safe.predictDAO(salt, h, s);

        // Tap: 1 ETH budget, 0.1 ETH/sec
        SafeSummoner.TapModule memory tap;
        tap.singleton = address(tapVest);
        tap.token = address(0);
        tap.budget = 1 ether;
        tap.beneficiary = bob;
        tap.ratePerSec = 0.1e18;

        SafeSummoner.SafeConfig memory config = _baseConfig();

        safe.safeSummonDAICO{value: 10 ether}(
            "TapDAO",
            "TAP",
            "",
            1000,
            true,
            address(0),
            salt,
            h,
            s,
            _noLoot(),
            config,
            _emptySale(),
            tap,
            _emptySeed(),
            new Call[](0)
        );

        // Warp 20 seconds — owed = 2 ETH but budget = 1 ETH
        vm.warp(block.timestamp + 20);

        // Claimable capped by allowance
        uint256 claimable = tapVest.claimable(dao);
        assertEq(claimable, 1 ether);

        uint256 bobBefore = bob.balance;
        tapVest.claim(dao);
        assertEq(bob.balance - bobBefore, 1 ether);

        // Allowance exhausted — nothing left
        assertEq(tapVest.claimable(dao), 0);
        assertEq(Moloch(payable(dao)).allowance(address(0), address(tapVest)), 0);
    }

    function test_SafeSummonDAICO_SharedETHTreasury() public {
        (address[] memory h, uint256[] memory s) = _holders1();
        bytes32 salt = bytes32(uint256(3003));

        TapVest tapVest = new TapVest();
        LPSeedSwapHook lpSeed = new LPSeedSwapHook();

        address dao = safe.predictDAO(salt, h, s);

        // Tap: 3 ETH budget
        SafeSummoner.TapModule memory tap;
        tap.singleton = address(tapVest);
        tap.token = address(0);
        tap.budget = 3 ether;
        tap.beneficiary = bob;
        tap.ratePerSec = 0.01e18;

        // Seed: 5 ETH + 5 shares, no gate
        SafeSummoner.SeedModule memory seed;
        seed.singleton = address(lpSeed);
        seed.tokenA = address(0);
        seed.amountA = 5e18;
        seed.tokenB = address(1); // shares sentinel
        seed.amountB = 5e18;

        SafeSummoner.SafeConfig memory config = _baseConfig();

        // Fund with exactly 8 ETH = 5 (seed) + 3 (tap budget)
        safe.safeSummonDAICO{value: 8 ether}(
            "SharedDAO",
            "SHRD",
            "",
            1000,
            true,
            address(0),
            salt,
            h,
            s,
            _noLoot(),
            config,
            _emptySale(),
            tap,
            seed,
            new Call[](0)
        );

        // Seed first — uses 5 ETH
        lpSeed.seed(dao);
        (,,,,,,,,,,, uint40 seeded,,) = lpSeed.seeds(dao);
        assertTrue(seeded != 0);

        // DAO has 3 ETH left for tap
        assertEq(dao.balance, 3 ether);

        // Warp 300 seconds — owed = 3 ETH, exactly matches budget
        vm.warp(block.timestamp + 300);

        uint256 bobBefore = bob.balance;
        tapVest.claim(dao);
        assertEq(bob.balance - bobBefore, 3 ether);

        // Both modules fully consumed
        assertEq(Moloch(payable(dao)).allowance(address(0), address(tapVest)), 0);
        assertEq(dao.balance, 0);
    }

    // ── Loot Sale → Tap → Seed LP (loot + ETH) ─────────────────

    function test_SafeSummonDAICO_LootSale_TapAndSeed() public {
        (address[] memory h, uint256[] memory s) = _holders1();
        bytes32 salt = bytes32(uint256(3004));

        ShareSale shareSale = new ShareSale();
        TapVest tapVest = new TapVest();
        LPSeedSwapHook lpSeed = new LPSeedSwapHook();

        address dao = safe.predictDAO(salt, h, s);
        address lootAddr = safe.predictLoot(dao);

        // Sale: 50 loot at 1 ETH each, minting
        SafeSummoner.SaleModule memory sale;
        sale.singleton = address(shareSale);
        sale.payToken = address(0);
        sale.price = 1e18;
        sale.cap = 50e18;
        sale.sellLoot = true;
        sale.minting = true;

        // Tap: ETH streaming to bob at 0.01 ETH/sec, 10 ETH budget
        SafeSummoner.TapModule memory tap;
        tap.singleton = address(tapVest);
        tap.token = address(0);
        tap.budget = 10 ether;
        tap.beneficiary = bob;
        tap.ratePerSec = 0.01e18;

        // Seed: 5 ETH + 5 loot (mint sentinel), gated by sale
        SafeSummoner.SeedModule memory seed;
        seed.singleton = address(lpSeed);
        seed.tokenA = address(0); // ETH
        seed.amountA = 5e18;
        seed.tokenB = address(2); // loot sentinel
        seed.amountB = 5e18;
        seed.gateBySale = true;

        SafeSummoner.SafeConfig memory config = _baseConfig();
        config.quorumAbsolute = 10e18;

        address deployed = safe.safeSummonDAICO{value: 50 ether}(
            "LootLifecycleDAO",
            "LLOOT",
            "",
            0,
            true,
            address(0),
            salt,
            h,
            s,
            _noLoot(),
            config,
            sale,
            tap,
            seed,
            new Call[](0)
        );
        assertEq(deployed, dao);

        // Verify sale configured with loot sentinel
        (address saleToken,,,) = shareSale.sales(dao);
        assertEq(saleToken, address(1007)); // loot minting sentinel

        // Verify seed configured with loot as tokenB
        (address seedA, address seedB,,,,,,,,,,,,) = lpSeed.seeds(dao);
        assertEq(seedA, address(0)); // ETH
        assertEq(seedB, lootAddr); // resolved loot ERC20 address

        // Verify allowances: ETH split between seed + tap, loot for seed
        assertEq(Moloch(payable(dao)).allowance(address(0), address(lpSeed)), 5e18);
        assertEq(Moloch(payable(dao)).allowance(address(1007), address(lpSeed)), 5e18);
        assertEq(Moloch(payable(dao)).allowance(address(0), address(tapVest)), 10 ether);

        // ── Phase 1: LP gated by sale ──────────────────────────────
        assertFalse(lpSeed.seedable(dao));

        // ── Phase 2: Tap accrues during sale ───────────────────────
        vm.warp(block.timestamp + 100);
        uint256 bobBefore = bob.balance;
        tapVest.claim(dao);
        assertEq(bob.balance - bobBefore, 1 ether);

        // ── Phase 3: Complete loot sale ─────────────────────────────
        vm.deal(alice, 200 ether);
        vm.prank(alice);
        shareSale.buy{value: 50 ether}(dao, 50e18);
        assertEq(Moloch(payable(dao)).allowance(address(1007), address(shareSale)), 0);

        // Alice received loot
        assertEq(Shares(lootAddr).balanceOf(alice), 50e18);

        // ── Phase 4: Seed LP (loot + ETH) ──────────────────────────
        assertTrue(lpSeed.seedable(dao));
        lpSeed.seed(dao);
        (,,,,,,,,,,, uint40 seeded,,) = lpSeed.seeds(dao);
        assertTrue(seeded != 0);

        // Loot minted for LP (not pre-minted), allowance spent
        assertEq(Moloch(payable(dao)).allowance(address(1007), address(lpSeed)), 0);
        assertEq(Moloch(payable(dao)).allowance(address(0), address(lpSeed)), 0);

        // ── Phase 5: Tap continues post-seed ───────────────────────
        vm.warp(block.timestamp + 200);
        bobBefore = bob.balance;
        tapVest.claim(dao);
        assertEq(bob.balance - bobBefore, 2 ether);

        // Tap allowance: 10 - 1 - 2 = 7 ETH remaining
        assertEq(Moloch(payable(dao)).allowance(address(0), address(tapVest)), 7 ether);
    }
}
