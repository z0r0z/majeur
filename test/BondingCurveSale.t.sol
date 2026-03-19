// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Moloch, Shares, Loot} from "../src/Moloch.sol";
import {SafeSummoner, Call} from "../src/peripheral/SafeSummoner.sol";
import {BondingCurveSale} from "../src/peripheral/BondingCurveSale.sol";

contract BondingCurveSaleTest is Test {
    SafeSummoner internal safe;
    BondingCurveSale internal sale;

    address internal alice = address(0xA11CE);
    address internal bob = address(0x0B0B);
    address internal carol = address(0xCA201);

    function setUp() public {
        vm.createSelectFork("main");
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);
        vm.deal(carol, 1000 ether);
        safe = new SafeSummoner();
        sale = new BondingCurveSale();
    }

    // ── Helpers ──────────────────────────────────────────────────

    /// @dev Deploy a DAO with a linear bonding curve sale: startPrice=0.005 ETH, endPrice=0.015 ETH, cap=1000e18
    function _deployDAO(bytes32 salt) internal returns (address dao) {
        return
            _deployDAOWithCurve(
                salt, 0.005e18, 0.015e18, 1000e18, BondingCurveSale.CurveType.LINEAR
            );
    }

    /// @dev Deploy a flat-price bonding curve (startPrice == endPrice) for comparison with ShareSale
    function _deployFlatDAO(bytes32 salt) internal returns (address dao) {
        return _deployDAOWithCurve(salt, 1e18, 1e18, 1000e18, BondingCurveSale.CurveType.LINEAR);
    }

    /// @dev Deploy a DAO with a specific curve type
    function _deployDAOWithCurve(
        bytes32 salt,
        uint256 startPrice,
        uint256 endPrice,
        uint256 cap,
        BondingCurveSale.CurveType curveType
    ) internal returns (address dao) {
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        dao = safe.predictDAO(salt, h, s);

        Call[] memory extra = new Call[](2);
        extra[0] = Call(dao, 0, abi.encodeCall(Moloch.setAllowance, (address(sale), dao, cap)));
        extra[1] = Call(
            address(sale),
            0,
            abi.encodeCall(
                sale.configure, (dao, address(0), startPrice, endPrice, cap, uint40(0), curveType)
            )
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        address deployed = safe.safeSummon(
            "CurveDAO", "CURVE", "", 1000, true, address(0), salt, h, s, new uint256[](0), c, extra
        );
        assertEq(deployed, dao);
    }

    // ── Core Buy Tests (LINEAR) ──────────────────────────────────

    function test_BuyFirstTokens_CheapestPrice() public {
        address dao = _deployDAO(bytes32(uint256(1)));
        address sharesAddr = address(Moloch(payable(dao)).shares());

        // Buy 100e18 shares at the start of the curve
        // avg price = (0.005 + 0.005 + 0.01*100/1000) / 2 = (0.005 + 0.006) / 2 = 0.0055
        // cost ~ 100 * 0.0055 = 0.55 ETH
        uint256 cost = sale.quote(dao, 100e18);

        vm.prank(bob);
        sale.buy{value: cost}(dao, 100e18);

        assertEq(Shares(sharesAddr).balanceOf(bob), 100e18);
        // First 100 of 1000 shares — price should be low
        assertGt(cost, 0.5e18); // > 0.5 ETH
        assertLt(cost, 0.6e18); // < 0.6 ETH
    }

    function test_BuyLastTokens_MostExpensive() public {
        address dao = _deployDAO(bytes32(uint256(2)));
        address sharesAddr = address(Moloch(payable(dao)).shares());

        // Quote the first 100e18 before any buys (cheapest block)
        uint256 firstCost = sale.quote(dao, 100e18);

        // Buy 900e18 first to advance the curve
        uint256 cost1 = sale.quote(dao, 900e18);
        vm.prank(bob);
        sale.buy{value: cost1}(dao, 900e18);

        // Buy the last 100e18 — should be the most expensive 100-token block
        uint256 lastCost = sale.quote(dao, 100e18);
        vm.prank(carol);
        sale.buy{value: lastCost}(dao, 100e18);

        assertEq(Shares(sharesAddr).balanceOf(carol), 100e18);
        // Last 100 should be significantly more expensive than first 100
        assertGt(lastCost, firstCost * 2); // at least 2x more expensive
    }

    function test_BuyEntireCurve_TotalCost() public {
        address dao = _deployDAO(bytes32(uint256(3)));
        address sharesAddr = address(Moloch(payable(dao)).shares());

        // Total cost = cap * (startPrice + endPrice) / 2 / 1e18
        // = 1000e18 * (0.005e18 + 0.015e18) / 2 / 1e18
        // = 1000e18 * 0.01e18 / 1e18 = 10 ETH
        uint256 cost = sale.quote(dao, 1000e18);

        vm.prank(bob);
        sale.buy{value: cost}(dao, 1000e18);

        assertEq(Shares(sharesAddr).balanceOf(bob), 1000e18);
        assertEq(cost, 10e18); // exactly 10 ETH for the full curve
    }

    function test_PriceIncreases_SequentialBuys() public {
        address dao = _deployDAO(bytes32(uint256(4)));

        // Buy 3 equal blocks of 333e18 and verify each costs more
        uint256 cost1 = sale.quote(dao, 333e18);
        vm.prank(bob);
        sale.buy{value: cost1}(dao, 333e18);

        uint256 cost2 = sale.quote(dao, 333e18);
        vm.prank(bob);
        sale.buy{value: cost2}(dao, 333e18);

        uint256 cost3 = sale.quote(dao, 333e18);
        vm.prank(bob);
        sale.buy{value: cost3}(dao, 333e18);

        assertGt(cost2, cost1); // second block more expensive
        assertGt(cost3, cost2); // third block most expensive
    }

    // ── Flat Curve (ShareSale equivalent) ─────────────────────

    function test_FlatCurve_ConstantPrice() public {
        address dao = _deployFlatDAO(bytes32(uint256(10)));
        address sharesAddr = address(Moloch(payable(dao)).shares());

        // startPrice == endPrice == 1e18 → flat line → cost = amount * price / 1e18
        uint256 cost = sale.quote(dao, 10e18);
        assertEq(cost, 10e18); // 10 shares * 1 ETH/share

        vm.prank(bob);
        sale.buy{value: cost}(dao, 10e18);
        assertEq(Shares(sharesAddr).balanceOf(bob), 10e18);
    }

    // ── Allowance Capping ─────────────────────────────────────

    function test_CapsToRemaining() public {
        address dao = _deployDAO(bytes32(uint256(20)));
        address sharesAddr = address(Moloch(payable(dao)).shares());

        // Buy 900e18 first
        uint256 cost1 = sale.quote(dao, 900e18);
        vm.prank(bob);
        sale.buy{value: cost1}(dao, 900e18);

        // Request 200e18 but only 100e18 remains — should cap
        uint256 cost2 = sale.quote(dao, 200e18);
        vm.prank(carol);
        sale.buy{value: cost2 + 1 ether}(dao, 200e18);

        assertEq(Shares(sharesAddr).balanceOf(carol), 100e18); // capped to remaining
    }

    function test_RevertIf_SoldOut() public {
        address dao = _deployDAO(bytes32(uint256(21)));

        // Buy all 1000e18
        uint256 cost = sale.quote(dao, 1000e18);
        vm.prank(bob);
        sale.buy{value: cost}(dao, 1000e18);

        // Next buy should revert
        vm.prank(carol);
        vm.expectRevert(BondingCurveSale.ZeroAmount.selector);
        sale.buy{value: 1 ether}(dao, 1e18);
    }

    // ── Refund ─────────────────────────────────────────────────

    function test_RefundsExcessETH() public {
        address dao = _deployDAO(bytes32(uint256(30)));

        uint256 cost = sale.quote(dao, 100e18);
        uint256 overpay = 5 ether;
        uint256 bobBalBefore = bob.balance;

        vm.prank(bob);
        sale.buy{value: cost + overpay}(dao, 100e18);

        assertEq(bobBalBefore - bob.balance, cost); // only cost deducted
    }

    // ── Quote View ────────────────────────────────────────────

    function test_QuoteMatchesBuyCost() public {
        address dao = _deployDAO(bytes32(uint256(40)));

        uint256 quoted = sale.quote(dao, 500e18);
        uint256 daoBefore = dao.balance;

        vm.prank(bob);
        sale.buy{value: quoted}(dao, 500e18);

        assertEq(dao.balance - daoBefore, quoted); // DAO received exactly the quoted amount
    }

    function test_QuoteCapsToRemaining() public {
        address dao = _deployDAO(bytes32(uint256(41)));

        // Buy 900e18 first
        vm.prank(bob);
        sale.buy{value: sale.quote(dao, 900e18)}(dao, 900e18);

        // Quote for 200e18 should cap to 100e18 remaining
        uint256 fullQuote = sale.quote(dao, 200e18);
        uint256 exactQuote = sale.quote(dao, 100e18);
        assertEq(fullQuote, exactQuote); // both quote the same (capped)
    }

    // ── Configure Reverts ─────────────────────────────────────

    function test_RevertIf_ZeroStartPrice() public {
        vm.expectRevert(BondingCurveSale.ZeroPrice.selector);
        sale.configure(
            address(0xDA0),
            address(0),
            0,
            1e18,
            1000e18,
            uint40(0),
            BondingCurveSale.CurveType.LINEAR
        );
    }

    function test_RevertIf_EndPriceBelowStart() public {
        vm.expectRevert(BondingCurveSale.InvalidCurve.selector);
        sale.configure(
            address(0xDA0),
            address(0),
            1e18,
            0.5e18,
            1000e18,
            uint40(0),
            BondingCurveSale.CurveType.LINEAR
        );
    }

    function test_RevertIf_ZeroCap() public {
        vm.expectRevert(BondingCurveSale.ZeroAmount.selector);
        sale.configure(
            address(0xDA0), address(0), 1e18, 2e18, 0, uint40(0), BondingCurveSale.CurveType.LINEAR
        );
    }

    function test_RevertIf_NotConfigured() public {
        vm.prank(bob);
        vm.expectRevert(BondingCurveSale.NotConfigured.selector);
        sale.buy{value: 1 ether}(address(0xdead), 1e18);
    }

    function test_RevertIf_InsufficientPayment() public {
        address dao = _deployDAO(bytes32(uint256(50)));
        uint256 cost = sale.quote(dao, 100e18);

        vm.prank(bob);
        vm.expectRevert(BondingCurveSale.InsufficientPayment.selector);
        sale.buy{value: cost - 1}(dao, 100e18);
    }

    function test_RevertIf_ZeroAmount() public {
        address dao = _deployDAO(bytes32(uint256(51)));
        vm.prank(bob);
        vm.expectRevert(BondingCurveSale.ZeroAmount.selector);
        sale.buy{value: 1 ether}(dao, 0);
    }

    // ── Deadline ──────────────────────────────────────────────

    function test_RevertIf_Expired() public {
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        bytes32 salt = bytes32(uint256(60));
        address dao = safe.predictDAO(salt, h, s);

        uint40 deadline = uint40(block.timestamp + 1 days);
        Call[] memory extra = new Call[](2);
        extra[0] = Call(dao, 0, abi.encodeCall(Moloch.setAllowance, (address(sale), dao, 1000e18)));
        extra[1] = Call(
            address(sale),
            0,
            abi.encodeCall(
                sale.configure,
                (
                    dao,
                    address(0),
                    0.005e18,
                    0.015e18,
                    1000e18,
                    deadline,
                    BondingCurveSale.CurveType.LINEAR
                )
            )
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        safe.safeSummon(
            "DeadlineDAO", "DL", "", 1000, true, address(0), salt, h, s, new uint256[](0), c, extra
        );

        // Buy before deadline — should work
        vm.prank(bob);
        sale.buy{value: 1 ether}(dao, 100e18);

        // Warp past deadline
        vm.warp(deadline + 1);

        vm.prank(bob);
        vm.expectRevert(BondingCurveSale.Expired.selector);
        sale.buy{value: 1 ether}(dao, 100e18);
    }

    // ── Exact-in (ETH) ──────────────────────────────────────────

    function test_BuyExactIn_BasicCurve() public {
        address dao = _deployDAO(bytes32(uint256(100)));
        address sharesAddr = address(Moloch(payable(dao)).shares());

        // Send 1 ETH — should buy some shares at the start of the curve
        uint256 bobBalBefore = bob.balance;
        vm.prank(bob);
        sale.buyExactIn{value: 1 ether}(dao);

        uint256 sharesReceived = Shares(sharesAddr).balanceOf(bob);
        uint256 ethSpent = bobBalBefore - bob.balance;

        assertGt(sharesReceived, 0);
        assertLe(ethSpent, 1 ether); // spent at most what was sent
    }

    function test_BuyExactIn_MatchesQuotedCost() public {
        address dao = _deployDAO(bytes32(uint256(101)));
        address sharesAddr = address(Moloch(payable(dao)).shares());

        // Buy via exact-in
        vm.prank(bob);
        sale.buyExactIn{value: 5 ether}(dao);
        uint256 amountReceived = Shares(sharesAddr).balanceOf(bob);

        // Deploy fresh DAO and verify quote matches
        address dao2 = _deployDAO(bytes32(uint256(102)));
        uint256 quotedCost = sale.quote(dao2, amountReceived);

        // The exact-in path should have spent exactly the quoted cost for the same amount
        uint256 daoBal = dao.balance;
        assertEq(daoBal, quotedCost);
    }

    function test_BuyExactIn_CapsToRemaining() public {
        address dao = _deployDAO(bytes32(uint256(103)));
        address sharesAddr = address(Moloch(payable(dao)).shares());

        // Buy 900e18 first
        vm.prank(bob);
        sale.buy{value: sale.quote(dao, 900e18)}(dao, 900e18);

        // Send way more ETH than needed for the last 100e18
        uint256 carolBalBefore = carol.balance;
        vm.prank(carol);
        sale.buyExactIn{value: 100 ether}(dao);

        assertEq(Shares(sharesAddr).balanceOf(carol), 100e18); // capped to remaining
        // Carol should get a large refund
        assertGt(carol.balance, carolBalBefore - 10 ether); // refunded most of the 100 ETH
    }

    function test_BuyExactIn_FlatCurve() public {
        address dao = _deployFlatDAO(bytes32(uint256(104)));
        address sharesAddr = address(Moloch(payable(dao)).shares());

        // Flat curve at 1 ETH/share — 7 ETH should buy 7 shares
        uint256 bobBalBefore = bob.balance;
        vm.prank(bob);
        sale.buyExactIn{value: 7 ether}(dao);

        assertEq(Shares(sharesAddr).balanceOf(bob), 7e18);
        assertEq(bobBalBefore - bob.balance, 7 ether);
    }

    function test_BuyExactIn_RevertIf_ERC20Sale() public {
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        bytes32 salt = bytes32(uint256(105));
        address dao = safe.predictDAO(salt, h, s);

        MockERC20 payToken = new MockERC20("Pay", "PAY", 18);

        Call[] memory extra = new Call[](2);
        extra[0] = Call(dao, 0, abi.encodeCall(Moloch.setAllowance, (address(sale), dao, 100e18)));
        extra[1] = Call(
            address(sale),
            0,
            abi.encodeCall(
                sale.configure,
                (
                    dao,
                    address(payToken),
                    0.01e18,
                    0.02e18,
                    100e18,
                    uint40(0),
                    BondingCurveSale.CurveType.LINEAR
                )
            )
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        safe.safeSummon(
            "ERC20DAO", "ERC", "", 1000, true, address(0), salt, h, s, new uint256[](0), c, extra
        );

        vm.prank(bob);
        vm.expectRevert(BondingCurveSale.UnexpectedETH.selector);
        sale.buyExactIn{value: 1 ether}(dao);
    }

    function test_BuyExactIn_RevertIf_ZeroValue() public {
        address dao = _deployDAO(bytes32(uint256(106)));
        vm.prank(bob);
        vm.expectRevert(BondingCurveSale.ZeroAmount.selector);
        sale.buyExactIn(dao);
    }

    function test_BuyExactIn_RevertIf_SoldOut() public {
        address dao = _deployDAO(bytes32(uint256(107)));

        // Buy all
        vm.prank(bob);
        sale.buy{value: sale.quote(dao, 1000e18)}(dao, 1000e18);

        vm.prank(carol);
        vm.expectRevert(BondingCurveSale.ZeroAmount.selector);
        sale.buyExactIn{value: 1 ether}(dao);
    }

    function test_BuyExactIn_EntireCurve() public {
        address dao = _deployDAO(bytes32(uint256(108)));
        address sharesAddr = address(Moloch(payable(dao)).shares());

        // Total cost for full curve = 10 ETH. Send exactly that.
        vm.prank(bob);
        sale.buyExactIn{value: 10 ether}(dao);

        assertEq(Shares(sharesAddr).balanceOf(bob), 1000e18); // bought all
    }

    // ── IShareSale Compatibility ──────────────────────────────

    function test_SalesGetter_ReturnsEndPrice() public {
        address dao = _deployDAO(bytes32(uint256(70)));

        // The public getter should return endPrice as the `price` field
        (address token, address payToken, uint40 deadline, uint256 price,,,,) = sale.sales(dao);

        assertEq(token, dao); // shares sentinel
        assertEq(payToken, address(0)); // ETH
        assertEq(deadline, 0); // no deadline
        assertEq(price, 0.015e18); // endPrice
    }

    // ── Loot Minting ──────────────────────────────────────────

    function test_BuyLootOnCurve() public {
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        bytes32 salt = bytes32(uint256(80));
        address dao = safe.predictDAO(salt, h, s);

        Call[] memory extra = new Call[](2);
        extra[0] = Call(
            dao, 0, abi.encodeCall(Moloch.setAllowance, (address(sale), address(1007), 500e18))
        );
        extra[1] = Call(
            address(sale),
            0,
            abi.encodeCall(
                sale.configure,
                (
                    address(1007),
                    address(0),
                    0.01e18,
                    0.02e18,
                    500e18,
                    uint40(0),
                    BondingCurveSale.CurveType.LINEAR
                )
            )
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        safe.safeSummon(
            "LootDAO", "LOOT", "", 1000, true, address(0), salt, h, s, new uint256[](0), c, extra
        );

        address lootAddr = address(Moloch(payable(dao)).loot());
        uint256 cost = sale.quote(dao, 100e18);

        vm.prank(bob);
        sale.buy{value: cost}(dao, 100e18);

        assertEq(Loot(lootAddr).balanceOf(bob), 100e18);
    }

    // ── InitCalls Helper ──────────────────────────────────────

    function test_SaleInitCallsHelper() public view {
        address dao = address(0xDA0);
        (address t1, bytes memory d1, address t2, bytes memory d2) = sale.saleInitCalls(
            dao, dao, 1000e18, address(0), 0.005e18, 0.015e18, 0, BondingCurveSale.CurveType.LINEAR
        );

        assertEq(t1, dao);
        assertEq(t2, address(sale));
        assertTrue(d1.length > 0);
        assertTrue(d2.length > 0);
    }

    // ── ERC20 PayToken ────────────────────────────────────────

    function test_BuyWithERC20() public {
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        bytes32 salt = bytes32(uint256(90));
        address dao = safe.predictDAO(salt, h, s);

        MockERC20 payToken = new MockERC20("Pay", "PAY", 18);
        payToken.mint(bob, 1000e18);

        Call[] memory extra = new Call[](2);
        extra[0] = Call(dao, 0, abi.encodeCall(Moloch.setAllowance, (address(sale), dao, 1000e18)));
        extra[1] = Call(
            address(sale),
            0,
            abi.encodeCall(
                sale.configure,
                (
                    dao,
                    address(payToken),
                    0.005e18,
                    0.015e18,
                    1000e18,
                    uint40(0),
                    BondingCurveSale.CurveType.LINEAR
                )
            )
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        safe.safeSummon(
            "ERC20DAO", "EPAY", "", 1000, true, address(0), salt, h, s, new uint256[](0), c, extra
        );

        address sharesAddr = address(Moloch(payable(dao)).shares());
        uint256 cost = sale.quote(dao, 100e18);

        vm.startPrank(bob);
        payToken.approve(address(sale), cost);
        sale.buy(dao, 100e18);
        vm.stopPrank();

        assertEq(Shares(sharesAddr).balanceOf(bob), 100e18);
        assertEq(payToken.balanceOf(dao), cost);
    }

    function test_RevertIf_UnexpectedETH_ERC20Sale() public {
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        bytes32 salt = bytes32(uint256(91));
        address dao = safe.predictDAO(salt, h, s);

        MockERC20 payToken = new MockERC20("Pay", "PAY", 18);

        Call[] memory extra = new Call[](2);
        extra[0] = Call(dao, 0, abi.encodeCall(Moloch.setAllowance, (address(sale), dao, 100e18)));
        extra[1] = Call(
            address(sale),
            0,
            abi.encodeCall(
                sale.configure,
                (
                    dao,
                    address(payToken),
                    0.01e18,
                    0.02e18,
                    100e18,
                    uint40(0),
                    BondingCurveSale.CurveType.LINEAR
                )
            )
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        safe.safeSummon(
            "NoETH", "NO", "", 1000, true, address(0), salt, h, s, new uint256[](0), c, extra
        );

        vm.prank(bob);
        vm.expectRevert(BondingCurveSale.UnexpectedETH.selector);
        sale.buy{value: 1 ether}(dao, 10e18);
    }

    // ── QUADRATIC Curve Tests ──────────────────────────────────

    function test_Quadratic_PriceIncreases() public {
        address dao = _deployDAOWithCurve(
            bytes32(uint256(200)), 0.005e18, 0.015e18, 1000e18, BondingCurveSale.CurveType.QUADRATIC
        );

        // Buy 3 equal blocks and verify each costs more
        uint256 cost1 = sale.quote(dao, 333e18);
        vm.prank(bob);
        sale.buy{value: cost1}(dao, 333e18);

        uint256 cost2 = sale.quote(dao, 333e18);
        vm.prank(bob);
        sale.buy{value: cost2}(dao, 333e18);

        uint256 cost3 = sale.quote(dao, 333e18);
        vm.prank(bob);
        sale.buy{value: cost3}(dao, 333e18);

        assertGt(cost2, cost1);
        assertGt(cost3, cost2);
    }

    function test_Quadratic_SteeperThanLinear() public {
        // Deploy both a linear and quadratic DAO with same params
        address linearDAO = _deployDAOWithCurve(
            bytes32(uint256(201)), 0.005e18, 0.015e18, 1000e18, BondingCurveSale.CurveType.LINEAR
        );
        address quadDAO = _deployDAOWithCurve(
            bytes32(uint256(202)), 0.005e18, 0.015e18, 1000e18, BondingCurveSale.CurveType.QUADRATIC
        );

        // First 100 tokens on quadratic should be CHEAPER than linear
        // (quadratic is concave up: low early, steep late)
        uint256 linearFirst = sale.quote(linearDAO, 100e18);
        uint256 quadFirst = sale.quote(quadDAO, 100e18);
        assertLt(quadFirst, linearFirst);

        // Buy 900 on both to advance to end of curve
        vm.prank(bob);
        sale.buy{value: sale.quote(linearDAO, 900e18)}(linearDAO, 900e18);
        vm.prank(bob);
        sale.buy{value: sale.quote(quadDAO, 900e18)}(quadDAO, 900e18);

        // Last/first price ratio should be HIGHER for quadratic (steeper curve shape)
        uint256 linearLast = sale.quote(linearDAO, 100e18);
        uint256 quadLast = sale.quote(quadDAO, 100e18);
        assertGt(quadLast * linearFirst, linearLast * quadFirst);
    }

    function test_Quadratic_BuyExactIn() public {
        address dao = _deployDAOWithCurve(
            bytes32(uint256(203)), 0.005e18, 0.015e18, 1000e18, BondingCurveSale.CurveType.QUADRATIC
        );
        address sharesAddr = address(Moloch(payable(dao)).shares());

        vm.prank(bob);
        sale.buyExactIn{value: 1 ether}(dao);

        uint256 received = Shares(sharesAddr).balanceOf(bob);
        assertGt(received, 0);

        // Cost should be <= msg.value
        uint256 ethSpent = 1000 ether - bob.balance;
        assertLe(ethSpent, 1 ether);
    }

    function test_Quadratic_BuyExactIn_CapsToRemaining() public {
        address dao = _deployDAOWithCurve(
            bytes32(uint256(204)), 0.005e18, 0.015e18, 1000e18, BondingCurveSale.CurveType.QUADRATIC
        );
        address sharesAddr = address(Moloch(payable(dao)).shares());

        // Buy 900 first
        vm.prank(bob);
        sale.buy{value: sale.quote(dao, 900e18)}(dao, 900e18);

        // Send way more ETH than needed
        vm.prank(carol);
        sale.buyExactIn{value: 100 ether}(dao);

        assertEq(Shares(sharesAddr).balanceOf(carol), 100e18);
        assertGt(carol.balance, 900 ether); // big refund
    }

    function test_Quadratic_FlatCurve() public {
        // Quadratic with startPrice == endPrice degenerates to flat
        address dao = _deployDAOWithCurve(
            bytes32(uint256(205)), 1e18, 1e18, 1000e18, BondingCurveSale.CurveType.QUADRATIC
        );

        uint256 cost = sale.quote(dao, 10e18);
        assertEq(cost, 10e18); // 10 shares * 1 ETH/share
    }

    // ── XYK Curve Tests ──────────────────────────────────────────

    function test_XYK_PriceIncreases() public {
        address dao = _deployDAOWithCurve(
            bytes32(uint256(300)), 0.005e18, 0.015e18, 1000e18, BondingCurveSale.CurveType.XYK
        );

        // Buy 3 blocks and verify each costs more
        uint256 cost1 = sale.quote(dao, 333e18);
        vm.prank(bob);
        sale.buy{value: cost1}(dao, 333e18);

        uint256 cost2 = sale.quote(dao, 333e18);
        vm.prank(bob);
        sale.buy{value: cost2}(dao, 333e18);

        uint256 cost3 = sale.quote(dao, 333e18);
        vm.prank(bob);
        sale.buy{value: cost3}(dao, 333e18);

        assertGt(cost2, cost1);
        assertGt(cost3, cost2);
    }

    function test_XYK_EndPriceApproachesTarget() public {
        address dao = _deployDAOWithCurve(
            bytes32(uint256(301)), 0.005e18, 0.015e18, 1000e18, BondingCurveSale.CurveType.XYK
        );

        // Buy 999e18, then quote the last 1e18 — should be close to endPrice
        vm.prank(bob);
        sale.buy{value: sale.quote(dao, 999e18)}(dao, 999e18);

        uint256 lastCost = sale.quote(dao, 1e18);
        // cost for 1 token near the end ≈ endPrice / 1e18 = 0.015 ETH
        // Allow 10% tolerance for rounding/curve shape
        assertGt(lastCost, 0.013e18);
        assertLt(lastCost, 0.017e18);
    }

    function test_XYK_BuyExactIn() public {
        address dao = _deployDAOWithCurve(
            bytes32(uint256(302)), 0.005e18, 0.015e18, 1000e18, BondingCurveSale.CurveType.XYK
        );
        address sharesAddr = address(Moloch(payable(dao)).shares());

        vm.prank(bob);
        sale.buyExactIn{value: 1 ether}(dao);

        uint256 received = Shares(sharesAddr).balanceOf(bob);
        assertGt(received, 0);

        uint256 ethSpent = 1000 ether - bob.balance;
        assertLe(ethSpent, 1 ether);
    }

    function test_XYK_BuyExactIn_MatchesQuote() public {
        address dao = _deployDAOWithCurve(
            bytes32(uint256(303)), 0.005e18, 0.015e18, 1000e18, BondingCurveSale.CurveType.XYK
        );
        address sharesAddr = address(Moloch(payable(dao)).shares());

        vm.prank(bob);
        sale.buyExactIn{value: 3 ether}(dao);
        uint256 amountReceived = Shares(sharesAddr).balanceOf(bob);

        // Deploy fresh XYK DAO and verify quote matches
        address dao2 = _deployDAOWithCurve(
            bytes32(uint256(304)), 0.005e18, 0.015e18, 1000e18, BondingCurveSale.CurveType.XYK
        );
        uint256 quotedCost = sale.quote(dao2, amountReceived);

        // dao received ETH ≈ quotedCost (±1 wei from XYK rounding)
        assertApproxEqAbs(dao.balance, quotedCost, 1);
    }

    function test_XYK_BuyExactIn_CapsToRemaining() public {
        address dao = _deployDAOWithCurve(
            bytes32(uint256(305)), 0.005e18, 0.015e18, 1000e18, BondingCurveSale.CurveType.XYK
        );
        address sharesAddr = address(Moloch(payable(dao)).shares());

        // Buy 900 first
        vm.prank(bob);
        sale.buy{value: sale.quote(dao, 900e18)}(dao, 900e18);

        // Overpay for remaining
        vm.prank(carol);
        sale.buyExactIn{value: 100 ether}(dao);

        assertEq(Shares(sharesAddr).balanceOf(carol), 100e18);
        assertGt(carol.balance, 900 ether);
    }

    function test_XYK_FlatCurve() public {
        // XYK with startPrice == endPrice degenerates to flat
        address dao = _deployDAOWithCurve(
            bytes32(uint256(306)), 1e18, 1e18, 1000e18, BondingCurveSale.CurveType.XYK
        );

        uint256 cost = sale.quote(dao, 10e18);
        assertEq(cost, 10e18);
    }

    function test_XYK_BuyEntireCurve() public {
        address dao = _deployDAOWithCurve(
            bytes32(uint256(307)), 0.005e18, 0.015e18, 1000e18, BondingCurveSale.CurveType.XYK
        );
        address sharesAddr = address(Moloch(payable(dao)).shares());

        uint256 cost = sale.quote(dao, 1000e18);
        vm.prank(bob);
        sale.buy{value: cost}(dao, 1000e18);

        assertEq(Shares(sharesAddr).balanceOf(bob), 1000e18);
        // XYK total cost should be between linear endpoints
        assertGt(cost, 5e18); // > 5 ETH (all at startPrice)
        assertLt(cost, 15e18); // < 15 ETH (all at endPrice)
    }

    function test_XYK_HighRatio() public {
        // 10x price increase (larger ratio stress test)
        address dao = _deployDAOWithCurve(
            bytes32(uint256(308)), 0.01e18, 0.1e18, 500e18, BondingCurveSale.CurveType.XYK
        );
        address sharesAddr = address(Moloch(payable(dao)).shares());

        uint256 cost = sale.quote(dao, 500e18);
        vm.prank(bob);
        sale.buy{value: cost}(dao, 500e18);

        assertEq(Shares(sharesAddr).balanceOf(bob), 500e18);
        assertGt(cost, 5e18); // > 500 * 0.01
        assertLt(cost, 50e18); // < 500 * 0.1
    }
}

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}
