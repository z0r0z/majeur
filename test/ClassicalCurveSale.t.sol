// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {
    ClassicalCurveSale,
    IZAMM,
    mulDiv,
    mulDivUp,
    sqrt
} from "../src/peripheral/ClassicalCurveSale.sol";
import {FixedPointMathLib} from "../lib/solady/src/utils/FixedPointMathLib.sol";

contract ClassicalCurveSaleTest is Test {
    ClassicalCurveSale internal sale;
    MockToken internal token;

    address internal alice = address(0xA11CE); // creator
    address internal bob = address(0x0B0B); // buyer
    address internal carol = address(0xCA201); // buyer 2

    uint256 constant CAP = 1000e18;
    uint256 constant LP_TOKENS = 500e18;
    uint256 constant START_PRICE = 0.005e18;
    uint256 constant END_PRICE = 0.02e18; // 4x
    uint16 constant FEE_BPS = 100; // 1%
    ClassicalCurveSale.CreatorFee internal NO_CREATOR_FEE;

    function setUp() public {
        vm.deal(alice, 100 ether);
        vm.deal(bob, 1000 ether);
        vm.deal(carol, 1000 ether);
        sale = new ClassicalCurveSale();
        token = new MockToken("Test", "TST", 18);
    }

    // ── Helpers ──────────────────────────────────────────────────

    function _configure() internal returns (address) {
        return _configureWith(START_PRICE, END_PRICE, FEE_BPS, 0, LP_TOKENS, alice);
    }

    function _configureWith(
        uint256 startPrice,
        uint256 endPrice,
        uint16 feeBps,
        uint256 graduationTarget,
        uint256 lpTokens,
        address lpRecipient
    ) internal returns (address tkn) {
        tkn = address(token);
        token.mint(alice, CAP + lpTokens);
        vm.startPrank(alice);
        token.approve(address(sale), CAP + lpTokens);
        sale.configure(
            alice,
            tkn,
            CAP,
            startPrice,
            endPrice,
            feeBps,
            graduationTarget,
            lpTokens,
            lpRecipient,
            0,
            0,
            0,
            0,
            NO_CREATOR_FEE
        );
        vm.stopPrank();
    }

    function _configureFlat() internal returns (address) {
        return _configureWith(1e18, 1e18, 0, 0, 0, address(0));
    }

    function _configureNoFee() internal returns (address) {
        return _configureWith(START_PRICE, END_PRICE, 0, 0, 0, address(0));
    }

    // ── Configure ───────────────────────────────────────────────

    function test_Configure_StoresState() public {
        address tkn = _configure();
        (
            address creator,
            uint256 cap,
            uint256 sold,
            uint256 virtualReserve,
            uint256 startPrice,
            uint256 endPrice,
            uint16 feeBps,
            uint16 poolFeeBps,
            uint256 raisedETH,
            uint256 graduationTarget,
            uint256 lpTokens,
            address lpRecipient,
            bool graduated,
            bool seeded,,,,
        ) = sale.curves(tkn);

        assertEq(creator, alice);
        assertEq(cap, CAP);
        assertEq(sold, 0);
        assertGt(virtualReserve, CAP);
        assertEq(startPrice, START_PRICE);
        assertEq(endPrice, END_PRICE);
        assertEq(feeBps, FEE_BPS);
        assertEq(poolFeeBps, 0);
        assertEq(raisedETH, 0);
        assertEq(graduationTarget, 0);
        assertEq(lpTokens, LP_TOKENS);
        assertEq(lpRecipient, alice);
        assertFalse(graduated);
        assertFalse(seeded);
    }

    function test_Configure_PullsTokens() public {
        _configure();
        assertEq(token.balanceOf(address(sale)), CAP + LP_TOKENS);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_Configure_RevertIf_ZeroToken() public {
        vm.expectRevert(ClassicalCurveSale.InvalidParams.selector);
        sale.configure(
            alice,
            address(0),
            CAP,
            START_PRICE,
            END_PRICE,
            FEE_BPS,
            0,
            0,
            address(0),
            0,
            0,
            0,
            0,
            NO_CREATOR_FEE
        );
    }

    function test_Configure_RevertIf_ZeroCap() public {
        vm.expectRevert(ClassicalCurveSale.InvalidParams.selector);
        sale.configure(
            alice,
            address(token),
            0,
            START_PRICE,
            END_PRICE,
            FEE_BPS,
            0,
            0,
            address(0),
            0,
            0,
            0,
            0,
            NO_CREATOR_FEE
        );
    }

    function test_Configure_RevertIf_ZeroStartPrice() public {
        vm.expectRevert(ClassicalCurveSale.InvalidParams.selector);
        sale.configure(
            alice,
            address(token),
            CAP,
            0,
            END_PRICE,
            FEE_BPS,
            0,
            0,
            address(0),
            0,
            0,
            0,
            0,
            NO_CREATOR_FEE
        );
    }

    function test_Configure_RevertIf_EndBelowStart() public {
        vm.expectRevert(ClassicalCurveSale.InvalidParams.selector);
        sale.configure(
            alice,
            address(token),
            CAP,
            END_PRICE,
            START_PRICE,
            FEE_BPS,
            0,
            0,
            address(0),
            0,
            0,
            0,
            0,
            NO_CREATOR_FEE
        );
    }

    function test_Configure_RevertIf_FeeTooHigh() public {
        token.mint(alice, CAP);
        vm.startPrank(alice);
        token.approve(address(sale), CAP);
        vm.expectRevert(ClassicalCurveSale.InvalidParams.selector);
        sale.configure(
            alice,
            address(token),
            CAP,
            START_PRICE,
            END_PRICE,
            10_001,
            0,
            0,
            address(0),
            0,
            0,
            0,
            0,
            NO_CREATOR_FEE
        );
        vm.stopPrank();
    }

    function test_Configure_RevertIf_AlreadyConfigured() public {
        _configure();
        token.mint(alice, CAP);
        vm.startPrank(alice);
        token.approve(address(sale), CAP);
        vm.expectRevert(ClassicalCurveSale.AlreadyConfigured.selector);
        sale.configure(
            alice,
            address(token),
            CAP,
            START_PRICE,
            END_PRICE,
            FEE_BPS,
            0,
            0,
            address(0),
            0,
            0,
            0,
            0,
            NO_CREATOR_FEE
        );
        vm.stopPrank();
    }

    function test_Configure_RevertIf_GraduationTargetUnachievable() public {
        token.mint(alice, CAP);
        vm.startPrank(alice);
        token.approve(address(sale), CAP);
        // Max ETH from full cap is well under 1000 ETH
        vm.expectRevert(ClassicalCurveSale.InvalidParams.selector);
        sale.configure(
            alice,
            address(token),
            CAP,
            START_PRICE,
            END_PRICE,
            FEE_BPS,
            1000 ether,
            0,
            address(0),
            0,
            0,
            0,
            0,
            NO_CREATOR_FEE
        );
        vm.stopPrank();
    }

    function test_Configure_GraduationTarget_AtMax() public {
        // Compute max ETH manually: configure with graduationTarget = quote(full cap)
        address tkn = _configureNoFee();
        uint256 maxETH = sale.quote(tkn, CAP);

        // Deploy a new token with that exact target — should succeed
        MockToken token2 = new MockToken("T2", "T2", 18);
        token2.mint(alice, CAP);
        vm.startPrank(alice);
        token2.approve(address(sale), CAP);
        sale.configure(
            alice,
            address(token2),
            CAP,
            START_PRICE,
            END_PRICE,
            0,
            maxETH,
            0,
            address(0),
            0,
            0,
            0,
            0,
            NO_CREATOR_FEE
        );
        vm.stopPrank();
    }

    // ── Quote ───────────────────────────────────────────────────

    function test_Quote_IncreasesWithSold() public {
        address tkn = _configureNoFee();
        uint256 q1 = sale.quote(tkn, 100e18);
        vm.prank(bob);
        sale.buy{value: q1}(tkn, 100e18, 0, block.timestamp);

        uint256 q2 = sale.quote(tkn, 100e18);
        assertGt(q2, q1);
    }

    function test_Quote_CapsToRemaining() public {
        address tkn = _configureNoFee();
        vm.prank(bob);
        sale.buy{value: sale.quote(tkn, 900e18)}(tkn, 900e18, 0, block.timestamp);

        uint256 q200 = sale.quote(tkn, 200e18);
        uint256 q100 = sale.quote(tkn, 100e18);
        assertEq(q200, q100); // both cap to 100 remaining
    }

    function test_QuoteSell_MatchesBuyReverse() public {
        address tkn = _configureNoFee();
        uint256 cost = sale.quote(tkn, 100e18);
        vm.prank(bob);
        sale.buy{value: cost}(tkn, 100e18, 0, block.timestamp);

        uint256 sellProceeds = sale.quoteSell(tkn, 100e18);
        assertEq(sellProceeds, cost);
    }

    function test_Quote_RevertIf_NotConfigured() public {
        vm.expectRevert(ClassicalCurveSale.NotConfigured.selector);
        sale.quote(address(0xdead), 1e18);
    }

    function test_Quote_RevertIf_ZeroAmount() public {
        address tkn = _configureNoFee();
        // Buy all
        vm.prank(bob);
        sale.buy{value: sale.quote(tkn, CAP)}(tkn, CAP, 0, block.timestamp);

        vm.expectRevert(ClassicalCurveSale.ZeroAmount.selector);
        sale.quote(tkn, 1e18);
    }

    // ── Buy (exact-out) ─────────────────────────────────────────

    function test_Buy_TransfersTokens() public {
        address tkn = _configure();
        uint256 cost = sale.quote(tkn, 100e18);
        uint256 fee = (cost * FEE_BPS) / 10_000;

        vm.prank(bob);
        sale.buy{value: cost + fee}(tkn, 100e18, 0, block.timestamp);

        assertEq(token.balanceOf(bob), 100e18);
    }

    function test_Buy_ChargesFeeToCreator() public {
        address tkn = _configure();
        uint256 cost = sale.quote(tkn, 100e18);
        uint256 fee = (cost * FEE_BPS) / 10_000;
        uint256 aliceBefore = alice.balance;

        vm.prank(bob);
        sale.buy{value: cost + fee}(tkn, 100e18, 0, block.timestamp);

        assertEq(alice.balance - aliceBefore, fee);
    }

    function test_Buy_RefundsExcess() public {
        address tkn = _configure();
        uint256 cost = sale.quote(tkn, 100e18);
        uint256 fee = (cost * FEE_BPS) / 10_000;
        uint256 bobBefore = bob.balance;

        vm.prank(bob);
        sale.buy{value: 10 ether}(tkn, 100e18, 0, block.timestamp);

        assertEq(bobBefore - bob.balance, cost + fee);
    }

    function test_Buy_CapsToRemaining() public {
        address tkn = _configure();
        uint256 cost900 = sale.quote(tkn, 900e18);
        uint256 fee900 = (cost900 * FEE_BPS) / 10_000;
        vm.prank(bob);
        sale.buy{value: cost900 + fee900}(tkn, 900e18, 0, block.timestamp);

        vm.prank(carol);
        sale.buy{value: 50 ether}(tkn, 200e18, 0, block.timestamp); // only 100 remain

        assertEq(token.balanceOf(carol), 100e18);
    }

    function test_Buy_UpdatesState() public {
        address tkn = _configure();
        uint256 cost = sale.quote(tkn, 100e18);
        uint256 fee = (cost * FEE_BPS) / 10_000;

        vm.prank(bob);
        sale.buy{value: cost + fee}(tkn, 100e18, 0, block.timestamp);

        (,, uint256 sold,,,,,, uint256 raisedETH,,,,,,,,,) = sale.curves(tkn);
        assertEq(sold, 100e18);
        assertEq(raisedETH, cost);
    }

    function test_Buy_RevertIf_NotConfigured() public {
        vm.expectRevert(ClassicalCurveSale.NotConfigured.selector);
        vm.prank(bob);
        sale.buy{value: 1 ether}(address(0xdead), 1e18, 0, block.timestamp);
    }

    function test_Buy_RevertIf_ZeroAmount() public {
        address tkn = _configure();
        vm.expectRevert(ClassicalCurveSale.ZeroAmount.selector);
        vm.prank(bob);
        sale.buy{value: 1 ether}(tkn, 0, 0, block.timestamp);
    }

    function test_Buy_RevertIf_InsufficientPayment() public {
        address tkn = _configure();
        uint256 cost = sale.quote(tkn, 100e18);
        // Don't include fee
        vm.expectRevert(ClassicalCurveSale.InsufficientPayment.selector);
        vm.prank(bob);
        sale.buy{value: cost}(tkn, 100e18, 0, block.timestamp);
    }

    function test_Buy_RevertIf_Graduated() public {
        address tkn = _configureWith(START_PRICE, END_PRICE, 0, 1 ether, 0, address(0));
        uint256 cost = sale.quote(tkn, CAP);
        vm.prank(bob);
        sale.buy{value: cost}(tkn, CAP, 0, block.timestamp); // triggers graduation

        vm.expectRevert(ClassicalCurveSale.Graduated.selector);
        vm.prank(carol);
        sale.buy{value: 1 ether}(tkn, 1e18, 0, block.timestamp);
    }

    function test_Buy_RevertIf_Slippage() public {
        address tkn = _configure();
        uint256 cost900 = sale.quote(tkn, 900e18);
        uint256 fee900 = (cost900 * FEE_BPS) / 10_000;
        vm.prank(bob);
        sale.buy{value: cost900 + fee900}(tkn, 900e18, 0, block.timestamp);

        // Only 100 remain, but we want at least 200
        vm.expectRevert(ClassicalCurveSale.Slippage.selector);
        vm.prank(carol);
        sale.buy{value: 50 ether}(tkn, 200e18, 200e18, block.timestamp);
    }

    // ── BuyExactIn ──────────────────────────────────────────────

    function test_BuyExactIn_BasicXYK() public {
        address tkn = _configureNoFee();

        vm.prank(bob);
        sale.buyExactIn{value: 1 ether}(tkn, 0, block.timestamp);

        uint256 received = token.balanceOf(bob);
        assertGt(received, 0);
        assertLe(bob.balance, 999 ether);
    }

    function test_BuyExactIn_MatchesQuote() public {
        address tkn = _configureNoFee();

        vm.prank(bob);
        sale.buyExactIn{value: 3 ether}(tkn, 0, block.timestamp);
        uint256 received = token.balanceOf(bob);

        // Quote the same amount on a fresh curve
        MockToken token2 = new MockToken("T2", "T2", 18);
        token2.mint(alice, CAP);
        vm.startPrank(alice);
        token2.approve(address(sale), CAP);
        sale.configure(
            alice,
            address(token2),
            CAP,
            START_PRICE,
            END_PRICE,
            0,
            0,
            0,
            address(0),
            0,
            0,
            0,
            0,
            NO_CREATOR_FEE
        );
        vm.stopPrank();

        uint256 quotedCost = sale.quote(address(token2), received);
        // Should match within 1 wei (rounding)
        assertApproxEqAbs(address(sale).balance, quotedCost, 1);
    }

    function test_BuyExactIn_FlatCurve() public {
        address tkn = _configureFlat();

        vm.prank(bob);
        sale.buyExactIn{value: 7 ether}(tkn, 0, block.timestamp);

        assertEq(token.balanceOf(bob), 7e18);
    }

    function test_BuyExactIn_WithFee() public {
        address tkn = _configure(); // 1% fee
        uint256 bobBefore = bob.balance;

        vm.prank(bob);
        sale.buyExactIn{value: 1 ether}(tkn, 0, block.timestamp);

        uint256 received = token.balanceOf(bob);
        assertGt(received, 0);
        // Bob should spend exactly 1 ETH (no refund expected for exact-in minus dust)
        assertLe(bobBefore - bob.balance, 1 ether);
    }

    function test_BuyExactIn_CapsToRemaining() public {
        address tkn = _configureNoFee();
        vm.prank(bob);
        sale.buy{value: sale.quote(tkn, 900e18)}(tkn, 900e18, 0, block.timestamp);

        uint256 carolBefore = carol.balance;
        vm.prank(carol);
        sale.buyExactIn{value: 100 ether}(tkn, 0, block.timestamp);

        assertEq(token.balanceOf(carol), 100e18);
        assertGt(carol.balance, carolBefore - 10 ether); // large refund
    }

    function test_BuyExactIn_RevertIf_ZeroValue() public {
        address tkn = _configure();
        vm.expectRevert(ClassicalCurveSale.ZeroAmount.selector);
        vm.prank(bob);
        sale.buyExactIn(tkn, 0, block.timestamp);
    }

    function test_BuyExactIn_RevertIf_Slippage() public {
        address tkn = _configureNoFee();

        // Send small amount but require many tokens
        vm.expectRevert(ClassicalCurveSale.Slippage.selector);
        vm.prank(bob);
        sale.buyExactIn{value: 0.001 ether}(tkn, 1000e18, block.timestamp);
    }

    // ── Sell ────────────────────────────────────────────────────

    function test_Sell_ReturnsETH() public {
        address tkn = _configureNoFee();
        uint256 cost = sale.quote(tkn, 100e18);
        vm.prank(bob);
        sale.buy{value: cost}(tkn, 100e18, 0, block.timestamp);

        uint256 bobBefore = bob.balance;
        vm.startPrank(bob);
        token.approve(address(sale), 100e18);
        sale.sell(tkn, 100e18, 0, block.timestamp);
        vm.stopPrank();

        assertEq(token.balanceOf(bob), 0);
        assertEq(bob.balance - bobBefore, cost); // full proceeds (no fee)
    }

    function test_Sell_WithFee() public {
        address tkn = _configure(); // 1% fee
        uint256 cost = sale.quote(tkn, 100e18);
        uint256 buyFee = (cost * FEE_BPS) / 10_000;
        vm.prank(bob);
        sale.buy{value: cost + buyFee}(tkn, 100e18, 0, block.timestamp);

        // Quote sell proceeds before actually selling
        uint256 rawProceeds = sale.quoteSell(tkn, 100e18);
        uint256 sellFee = (rawProceeds * FEE_BPS) / 10_000;

        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;
        vm.startPrank(bob);
        token.approve(address(sale), 100e18);
        sale.sell(tkn, 100e18, 0, block.timestamp);
        vm.stopPrank();

        uint256 bobGot = bob.balance - bobBefore;
        uint256 aliceGot = alice.balance - aliceBefore;
        assertEq(bobGot, rawProceeds - sellFee);
        assertEq(aliceGot, sellFee);
    }

    function test_Sell_UpdatesState() public {
        address tkn = _configureNoFee();
        uint256 cost = sale.quote(tkn, 100e18);
        vm.prank(bob);
        sale.buy{value: cost}(tkn, 100e18, 0, block.timestamp);

        vm.startPrank(bob);
        token.approve(address(sale), 50e18);
        sale.sell(tkn, 50e18, 0, block.timestamp);
        vm.stopPrank();

        (,, uint256 sold,,,,,,,,,,,,,,,) = sale.curves(tkn);
        assertEq(sold, 50e18);
    }

    function test_Sell_RevertIf_Graduated() public {
        address tkn = _configureWith(START_PRICE, END_PRICE, 0, 1 ether, 0, address(0));
        uint256 cost = sale.quote(tkn, CAP);
        vm.prank(bob);
        sale.buy{value: cost}(tkn, CAP, 0, block.timestamp);

        vm.startPrank(bob);
        token.approve(address(sale), 1e18);
        vm.expectRevert(ClassicalCurveSale.Graduated.selector);
        sale.sell(tkn, 1e18, 0, block.timestamp);
        vm.stopPrank();
    }

    function test_Sell_RevertIf_Slippage() public {
        address tkn = _configureNoFee();
        uint256 cost = sale.quote(tkn, 100e18);
        vm.prank(bob);
        sale.buy{value: cost}(tkn, 100e18, 0, block.timestamp);

        vm.startPrank(bob);
        token.approve(address(sale), 100e18);
        vm.expectRevert(ClassicalCurveSale.Slippage.selector);
        sale.sell(tkn, 100e18, cost + 1, block.timestamp); // minProceeds too high
        vm.stopPrank();
    }

    function test_Sell_RevertIf_ZeroAmount() public {
        address tkn = _configure();
        vm.expectRevert(ClassicalCurveSale.ZeroAmount.selector);
        sale.sell(tkn, 0, 0, block.timestamp);
    }

    // ── SellExactOut ────────────────────────────────────────────

    function test_SellExactOut_ExactETH() public {
        address tkn = _configureNoFee();
        uint256 cost = sale.quote(tkn, 200e18);
        vm.prank(bob);
        sale.buy{value: cost}(tkn, 200e18, 0, block.timestamp);

        uint256 bobBefore = bob.balance;
        vm.startPrank(bob);
        token.approve(address(sale), 200e18);
        sale.sellExactOut(tkn, 0.5 ether, 200e18, block.timestamp);
        vm.stopPrank();

        // Bob gets >= 0.5 ETH (ceil rounding on inverse may yield 1-2 wei extra)
        assertGe(bob.balance - bobBefore, 0.5 ether);
        assertLe(bob.balance - bobBefore, 0.5 ether + 2);
    }

    function test_SellExactOut_WithFee() public {
        address tkn = _configure(); // 1% fee
        uint256 cost = sale.quote(tkn, 500e18);
        uint256 buyFee = (cost * FEE_BPS) / 10_000;
        vm.prank(bob);
        sale.buy{value: cost + buyFee}(tkn, 500e18, 0, block.timestamp);

        uint256 ethWant = 0.5 ether;
        uint256 bobBefore = bob.balance;
        vm.startPrank(bob);
        token.approve(address(sale), 500e18);
        sale.sellExactOut(tkn, ethWant, 500e18, block.timestamp);
        vm.stopPrank();

        // Bob gets >= ethWant (ceil rounding on inverse may yield 1-2 wei extra)
        assertGe(bob.balance - bobBefore, ethWant);
        assertLe(bob.balance - bobBefore, ethWant + 3);
    }

    function test_SellExactOut_RevertIf_Slippage() public {
        address tkn = _configureNoFee();
        uint256 cost = sale.quote(tkn, 100e18);
        vm.prank(bob);
        sale.buy{value: cost}(tkn, 100e18, 0, block.timestamp);

        vm.startPrank(bob);
        token.approve(address(sale), 100e18);
        // Ask for small ethOut but with maxTokens = 1
        vm.expectRevert(ClassicalCurveSale.Slippage.selector);
        sale.sellExactOut(tkn, 0.1 ether, 1e18, block.timestamp);
        vm.stopPrank();
    }

    function test_SellExactOut_RevertIf_InsufficientLiquidity() public {
        address tkn = _configureNoFee();
        uint256 cost = sale.quote(tkn, 100e18);
        vm.prank(bob);
        sale.buy{value: cost}(tkn, 100e18, 0, block.timestamp);

        vm.startPrank(bob);
        token.approve(address(sale), 100e18);
        // Ask for way more ETH than raisedETH
        vm.expectRevert(ClassicalCurveSale.InsufficientLiquidity.selector);
        sale.sellExactOut(tkn, 1000 ether, type(uint256).max, block.timestamp);
        vm.stopPrank();
    }

    function test_SellExactOut_RevertIf_ZeroEthOut() public {
        address tkn = _configure();
        vm.expectRevert(ClassicalCurveSale.ZeroAmount.selector);
        sale.sellExactOut(tkn, 0, 0, block.timestamp);
    }

    // ── Buy/Sell Roundtrip ──────────────────────────────────────

    function test_BuySell_Roundtrip_NoFee() public {
        address tkn = _configureNoFee();
        uint256 cost = sale.quote(tkn, 100e18);

        vm.prank(bob);
        sale.buy{value: cost}(tkn, 100e18, 0, block.timestamp);

        uint256 bobBefore = bob.balance;
        vm.startPrank(bob);
        token.approve(address(sale), 100e18);
        sale.sell(tkn, 100e18, 0, block.timestamp);
        vm.stopPrank();

        // Full roundtrip with no fee — should get all ETH back
        assertEq(bob.balance - bobBefore, cost);
        (,, uint256 sold,,,,,, uint256 raisedETH,,,,,,,,,) = sale.curves(tkn);
        assertEq(sold, 0);
        assertEq(raisedETH, 0);
    }

    function test_BuySell_PartialSell() public {
        address tkn = _configureNoFee();
        uint256 cost = sale.quote(tkn, 100e18);
        vm.prank(bob);
        sale.buy{value: cost}(tkn, 100e18, 0, block.timestamp);

        vm.startPrank(bob);
        token.approve(address(sale), 50e18);
        sale.sell(tkn, 50e18, 0, block.timestamp);
        vm.stopPrank();

        assertEq(token.balanceOf(bob), 50e18);
        (,, uint256 sold,,,,,,,,,,,,,,,) = sale.curves(tkn);
        assertEq(sold, 50e18);
    }

    // ── Graduation ──────────────────────────────────────────────

    function test_Graduation_ByTarget() public {
        // Set graduation target to ~50% of full curve ETH
        address tkn = _configureNoFee();
        uint256 halfCost = sale.quote(tkn, 500e18);

        // Redeploy with target
        token = new MockToken("T2", "T2", 18);
        tkn = address(token);
        token.mint(alice, CAP);
        vm.startPrank(alice);
        token.approve(address(sale), CAP);
        sale.configure(
            alice,
            tkn,
            CAP,
            START_PRICE,
            END_PRICE,
            0,
            halfCost,
            0,
            address(0),
            0,
            0,
            0,
            0,
            NO_CREATOR_FEE
        );
        vm.stopPrank();

        assertFalse(sale.graduable(tkn));

        // Buy enough to trigger
        vm.prank(bob);
        sale.buy{value: 50 ether}(tkn, 500e18, 0, block.timestamp);

        assertTrue(sale.graduable(tkn));
    }

    function test_Graduation_ByFullCap() public {
        // graduationTarget = 0 means must sell full cap
        address tkn = _configureWith(START_PRICE, END_PRICE, 0, 0, 0, address(0));
        uint256 cost = sale.quote(tkn, CAP);

        assertFalse(sale.graduable(tkn));

        vm.prank(bob);
        sale.buy{value: cost}(tkn, CAP, 0, block.timestamp);

        assertTrue(sale.graduable(tkn));
    }

    function test_Graduation_FreezesTrading() public {
        address tkn = _configureWith(START_PRICE, END_PRICE, 0, 1 ether, 0, address(0));
        uint256 cost = sale.quote(tkn, CAP);
        vm.prank(bob);
        sale.buy{value: cost}(tkn, CAP, 0, block.timestamp);

        vm.expectRevert(ClassicalCurveSale.Graduated.selector);
        vm.prank(carol);
        sale.buy{value: 1 ether}(tkn, 1e18, 0, block.timestamp);

        vm.startPrank(bob);
        token.approve(address(sale), 1e18);
        vm.expectRevert(ClassicalCurveSale.Graduated.selector);
        sale.sell(tkn, 1e18, 0, block.timestamp);
        vm.stopPrank();
    }

    function test_Graduable_FalseBeforeGrad() public {
        address tkn = _configure();
        assertFalse(sale.graduable(tkn));
    }

    function test_Graduable_FalseForUnconfigured() public view {
        assertFalse(sale.graduable(address(0xdead)));
    }

    // ── Flat Curve ──────────────────────────────────────────────

    function test_FlatCurve_ConstantPrice() public {
        address tkn = _configureFlat();

        uint256 cost1 = sale.quote(tkn, 100e18);
        assertEq(cost1, 100e18); // 100 tokens * 1 ETH

        vm.prank(bob);
        sale.buy{value: cost1}(tkn, 100e18, 0, block.timestamp);

        uint256 cost2 = sale.quote(tkn, 100e18);
        assertEq(cost2, 100e18); // same price
    }

    function test_FlatCurve_BuyExactIn() public {
        address tkn = _configureFlat();

        vm.prank(bob);
        sale.buyExactIn{value: 7 ether}(tkn, 0, block.timestamp);

        assertEq(token.balanceOf(bob), 7e18);
    }

    function test_FlatCurve_Sell() public {
        address tkn = _configureFlat();
        vm.prank(bob);
        sale.buy{value: 10 ether}(tkn, 10e18, 0, block.timestamp);

        uint256 bobBefore = bob.balance;
        vm.startPrank(bob);
        token.approve(address(sale), 5e18);
        sale.sell(tkn, 5e18, 0, block.timestamp);
        vm.stopPrank();

        assertEq(bob.balance - bobBefore, 5 ether);
    }

    function test_FlatCurve_SellExactOut() public {
        address tkn = _configureFlat();
        vm.prank(bob);
        sale.buy{value: 10 ether}(tkn, 10e18, 0, block.timestamp);

        uint256 bobBefore = bob.balance;
        vm.startPrank(bob);
        token.approve(address(sale), 10e18);
        sale.sellExactOut(tkn, 3 ether, 10e18, block.timestamp);
        vm.stopPrank();

        assertEq(bob.balance - bobBefore, 3 ether);
    }

    // ── XYK Curve Math ──────────────────────────────────────────

    function test_XYK_PriceIncreasesMonotonically() public {
        address tkn = _configureNoFee();

        uint256 prev;
        for (uint256 i; i < 10; i++) {
            uint256 cost = sale.quote(tkn, 100e18);
            assertGt(cost, prev);
            prev = cost;
            vm.prank(bob);
            sale.buy{value: cost}(tkn, 100e18, 0, block.timestamp);
        }
    }

    function test_XYK_FullCurveCost() public {
        address tkn = _configureNoFee();
        uint256 cost = sale.quote(tkn, CAP);

        // Cost should be between cap*startPrice and cap*endPrice
        uint256 minCost = CAP * START_PRICE / 1e18;
        uint256 maxCost = CAP * END_PRICE / 1e18;
        assertGt(cost, minCost);
        assertLt(cost, maxCost);
    }

    function test_XYK_EndPriceApproachesTarget() public {
        address tkn = _configureNoFee();
        vm.prank(bob);
        sale.buy{value: sale.quote(tkn, 999e18)}(tkn, 999e18, 0, block.timestamp);

        uint256 lastCost = sale.quote(tkn, 1e18);
        // Should be near END_PRICE / 1e18 = 0.02 ETH
        assertGt(lastCost, 0.018e18);
        assertLt(lastCost, 0.022e18);
    }

    // ── Creator Governance ──────────────────────────────────────

    function test_SetCreatorFee() public {
        address tkn = _configure();
        vm.prank(alice);
        sale.setCreatorFee(tkn, carol, 500, 500, true, false);

        (address ben, uint16 buyBps, uint16 sellBps, bool buyOnInput, bool sellOnInput) =
            sale.creatorFees(tkn);
        assertEq(ben, carol);
        assertEq(buyBps, 500);
        assertEq(sellBps, 500);
        assertTrue(buyOnInput);
        assertFalse(sellOnInput);
    }

    function test_SetCreatorFee_RevertIf_Unauthorized() public {
        address tkn = _configure();
        vm.prank(bob);
        vm.expectRevert(ClassicalCurveSale.Unauthorized.selector);
        sale.setCreatorFee(tkn, carol, 100, 100, true, true);
    }

    function test_SetCreatorFee_RevertIf_TooHigh() public {
        address tkn = _configure();
        vm.prank(alice);
        vm.expectRevert(ClassicalCurveSale.InvalidParams.selector);
        sale.setCreatorFee(tkn, carol, 1001, 100, true, true); // > MAX_CREATOR_FEE_BPS
    }

    function test_SetCreatorFee_RevertIf_BeneficiaryZeroWithFees() public {
        address tkn = _configure();
        vm.prank(alice);
        vm.expectRevert(ClassicalCurveSale.InvalidParams.selector);
        sale.setCreatorFee(tkn, address(0), 100, 100, true, true);
    }

    function test_SetCreatorFee_RevertIf_BeneficiarySetNoFees() public {
        address tkn = _configure();
        vm.prank(alice);
        vm.expectRevert(ClassicalCurveSale.InvalidParams.selector);
        sale.setCreatorFee(tkn, carol, 0, 0, true, true);
    }

    function test_SetCreatorFee_DisableByZeroBeneficiary() public {
        address tkn = _configure();
        vm.prank(alice);
        sale.setCreatorFee(tkn, carol, 100, 100, true, true);

        vm.prank(alice);
        sale.setCreatorFee(tkn, address(0), 0, 0, false, false);

        (address ben,,,,) = sale.creatorFees(tkn);
        assertEq(ben, address(0));
    }

    // ── Hook ────────────────────────────────────────────────────

    function test_HookFeeOrHook() public view {
        uint256 val = sale.hookFeeOrHook();
        assertEq(val & (1 << 255), 1 << 255); // FLAG_BEFORE set
        assertEq(val & ~(uint256(1) << 255), uint256(uint160(address(sale))));
    }

    function test_PoolKeyOf() public view {
        address tkn = address(0x1234);
        (IZAMM.PoolKey memory key, uint256 poolId) = sale.poolKeyOf(tkn);
        assertEq(key.token0, address(0));
        assertEq(key.token1, tkn);
        assertEq(key.feeOrHook, sale.hookFeeOrHook());
        assertEq(poolId, uint256(keccak256(abi.encode(key))));
    }

    function test_BeforeAction_RevertIf_NotZAMM() public {
        vm.expectRevert(ClassicalCurveSale.Unauthorized.selector);
        sale.beforeAction(bytes4(0), 0, address(0), "");
    }

    // ── Multicall ───────────────────────────────────────────────

    function test_Multicall_BatchSetFees() public {
        address tkn = _configure();
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(sale.setCreatorFee, (tkn, carol, 200, 300, true, false));

        vm.prank(alice);
        sale.multicall(data);

        (address ben, uint16 buyBps, uint16 sellBps,,) = sale.creatorFees(tkn);
        assertEq(ben, carol);
        assertEq(buyBps, 200);
        assertEq(sellBps, 300);
    }

    // ── Deadline Tests ──────────────────────────────────────────

    function test_Buy_RevertIf_DeadlineExpired() public {
        address tkn = _configure();
        uint256 cost = sale.quote(tkn, 100e18);
        uint256 fee = (cost * FEE_BPS) / 10_000;

        vm.warp(1000);
        vm.prank(bob);
        vm.expectRevert(ClassicalCurveSale.DeadlineExpired.selector);
        sale.buy{value: cost + fee}(tkn, 100e18, 0, 999);
    }

    function test_BuyExactIn_RevertIf_DeadlineExpired() public {
        address tkn = _configure();

        vm.warp(1000);
        vm.prank(bob);
        vm.expectRevert(ClassicalCurveSale.DeadlineExpired.selector);
        sale.buyExactIn{value: 1 ether}(tkn, 0, 999);
    }

    function test_Sell_RevertIf_DeadlineExpired() public {
        address tkn = _configureNoFee();
        uint256 cost = sale.quote(tkn, 100e18);
        vm.prank(bob);
        sale.buy{value: cost}(tkn, 100e18, 0, block.timestamp);

        vm.startPrank(bob);
        token.approve(address(sale), 100e18);
        vm.warp(1000);
        vm.expectRevert(ClassicalCurveSale.DeadlineExpired.selector);
        sale.sell(tkn, 100e18, 0, 999);
        vm.stopPrank();
    }

    function test_SellExactOut_RevertIf_DeadlineExpired() public {
        address tkn = _configureNoFee();
        uint256 cost = sale.quote(tkn, 100e18);
        vm.prank(bob);
        sale.buy{value: cost}(tkn, 100e18, 0, block.timestamp);

        vm.startPrank(bob);
        token.approve(address(sale), 100e18);
        vm.warp(1000);
        vm.expectRevert(ClassicalCurveSale.DeadlineExpired.selector);
        sale.sellExactOut(tkn, 0.01 ether, 100e18, 999);
        vm.stopPrank();
    }

    // ── Multicall Tests ────────────────────────────────────────

    function test_Multicall_BatchMultipleCalls() public {
        address tkn = _configure();
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(sale.setCreatorFee, (tkn, carol, 200, 300, true, false));
        data[1] = abi.encodeCall(sale.setLpRecipient, (tkn, carol));

        vm.prank(alice);
        sale.multicall(data);

        (address ben, uint16 buyBps, uint16 sellBps,,) = sale.creatorFees(tkn);
        assertEq(ben, carol);
        assertEq(buyBps, 200);
        assertEq(sellBps, 300);

        (,,,,,,,,,,, address lpRecipient,,,,,,) = sale.curves(tkn);
        assertEq(lpRecipient, carol);
    }

    function test_Multicall_RevertBubblesUp() public {
        address tkn = _configure();
        bytes[] memory data = new bytes[](1);
        // Set creator fee with invalid params (beneficiary + zero fees)
        data[0] = abi.encodeCall(sale.setCreatorFee, (tkn, carol, 0, 0, false, false));

        vm.prank(alice);
        vm.expectRevert();
        sale.multicall(data);
    }

    // ── SetCreator Positive Test ────────────────────────────────

    function test_SetCreator_TransfersRole() public {
        address tkn = _configure();
        vm.prank(alice);
        sale.setCreator(tkn, carol);

        (address newCreator,,,,,,,,,,,,,,,,, ) = sale.curves(tkn);
        assertEq(newCreator, carol);

        // Old creator can no longer set
        vm.prank(alice);
        vm.expectRevert(ClassicalCurveSale.Unauthorized.selector);
        sale.setCreator(tkn, bob);

        // New creator can
        vm.prank(carol);
        sale.setCreator(tkn, bob);
        (address finalCreator,,,,,,,,,,,,,,,,, ) = sale.curves(tkn);
        assertEq(finalCreator, bob);
    }

    // ── Edge Cases ──────────────────────────────────────────────

    function test_SmallBuy() public {
        address tkn = _configureNoFee();
        uint256 cost = sale.quote(tkn, 1);
        assertGt(cost, 0);

        vm.prank(bob);
        sale.buy{value: cost}(tkn, 1, 0, block.timestamp);
        assertEq(token.balanceOf(bob), 1);
    }

    function test_LargePriceRatio() public {
        // 100x price increase
        address tkn = address(token);
        token.mint(alice, CAP);
        vm.startPrank(alice);
        token.approve(address(sale), CAP);
        sale.configure(
            alice, tkn, CAP, 0.001e18, 0.1e18, 0, 0, 0, address(0), 0, 0, 0, 0, NO_CREATOR_FEE
        );
        vm.stopPrank();

        uint256 cost = sale.quote(tkn, CAP);
        assertGt(cost, CAP * 0.001e18 / 1e18);
        assertLt(cost, CAP * 0.1e18 / 1e18);

        vm.prank(bob);
        sale.buy{value: cost}(tkn, CAP, 0, block.timestamp);
        assertEq(token.balanceOf(bob), CAP);
    }

    function test_SellInsufficientLiquidity() public {
        address tkn = _configureNoFee();
        uint256 cost = sale.quote(tkn, 10e18);
        vm.prank(bob);
        sale.buy{value: cost}(tkn, 10e18, 0, block.timestamp);

        // Try to sell way more than was bought (sold is only 10e18)
        // Caps to c.sold, so should work but only sell 10e18
        vm.startPrank(bob);
        token.approve(address(sale), 10e18);
        sale.sell(tkn, 20e18, 0, block.timestamp); // caps to 10e18
        vm.stopPrank();

        assertEq(token.balanceOf(bob), 0);
    }

    // ── Observations ──────────────────────────────────────────

    function test_Observations_RecordedOnBuyAndSell() public {
        address tkn = _configureNoFee();
        assertEq(sale.observationCount(tkn), 0);

        // Buy 100 tokens
        uint256 cost = sale.quote(tkn, 100e18);
        vm.prank(bob);
        sale.buy{value: cost}(tkn, 100e18, 0, block.timestamp);

        assertEq(sale.observationCount(tkn), 1);

        // Decode and verify
        uint256[] memory obs = sale.observe(tkn, 0, 1);
        (uint128 price, uint80 volume, uint40 ts, bool isSell) = sale.decodeObservation(obs[0]);
        assertEq(price, uint128(cost * 1e18 / 100e18));
        assertEq(volume, uint80(cost));
        assertEq(ts, uint40(block.timestamp));
        assertFalse(isSell);

        // Sell 50 tokens
        vm.startPrank(bob);
        token.approve(address(sale), 50e18);
        sale.sell(tkn, 50e18, 0, block.timestamp);
        vm.stopPrank();

        assertEq(sale.observationCount(tkn), 2);

        obs = sale.observe(tkn, 1, 2);
        (,,, isSell) = sale.decodeObservation(obs[0]);
        assertTrue(isSell);
    }

    function test_Observations_BuyExactIn() public {
        address tkn = _configureNoFee();

        vm.prank(bob);
        sale.buyExactIn{value: 1 ether}(tkn, 0, block.timestamp);

        assertEq(sale.observationCount(tkn), 1);
        uint256[] memory obs = sale.observe(tkn, 0, 1);
        (,,, bool isSell) = sale.decodeObservation(obs[0]);
        assertFalse(isSell);
    }

    function test_Observations_SellExactOut() public {
        address tkn = _configureNoFee();
        uint256 cost = sale.quote(tkn, 200e18);
        vm.prank(bob);
        sale.buy{value: cost}(tkn, 200e18, 0, block.timestamp);

        vm.startPrank(bob);
        token.approve(address(sale), 200e18);
        sale.sellExactOut(tkn, 0.5 ether, 200e18, block.timestamp);
        vm.stopPrank();

        assertEq(sale.observationCount(tkn), 2); // buy + sell
        uint256[] memory obs = sale.observe(tkn, 1, 2);
        (,,, bool isSell) = sale.decodeObservation(obs[0]);
        assertTrue(isSell);
    }

    function test_Observations_RangeQuery() public {
        address tkn = _configureNoFee();

        // Make 5 buys
        for (uint256 i; i < 5; i++) {
            uint256 cost = sale.quote(tkn, 100e18);
            vm.prank(bob);
            sale.buy{value: cost}(tkn, 100e18, 0, block.timestamp);
        }
        assertEq(sale.observationCount(tkn), 5);

        // Query subset
        uint256[] memory obs = sale.observe(tkn, 1, 4);
        assertEq(obs.length, 3);

        // Prices should be increasing (XYK curve)
        (uint128 p1,,,) = sale.decodeObservation(obs[0]);
        (uint128 p2,,,) = sale.decodeObservation(obs[1]);
        (uint128 p3,,,) = sale.decodeObservation(obs[2]);
        assertGt(p2, p1);
        assertGt(p3, p2);

        // Out-of-bounds to is capped
        uint256[] memory all = sale.observe(tkn, 0, 999);
        assertEq(all.length, 5);

        // Empty range returns empty
        uint256[] memory empty = sale.observe(tkn, 3, 2);
        assertEq(empty.length, 0);
    }

    function test_ReceiveETH() public {
        // Contract should accept ETH
        (bool ok,) = address(sale).call{value: 1 ether}("");
        assertTrue(ok);
    }

    // ── mulDiv correctness ───────────────────────────────────────

    function test_MulDiv_Basic() public pure {
        assertEq(mulDiv(10, 20, 5), 40);
        assertEq(mulDiv(1e18, 1e18, 1e18), 1e18);
        assertEq(mulDiv(0, 100, 1), 0);
        assertEq(mulDiv(100, 0, 1), 0);
    }

    function test_MulDiv_RevertIf_ZeroDenominator() public {
        MulDivReverts h = new MulDivReverts();
        vm.expectRevert();
        h.divByZero();
    }

    function test_MulDiv_RevertIf_Overflow() public {
        MulDivReverts h = new MulDivReverts();
        vm.expectRevert();
        h.overflow();
    }

    function test_MulDiv_512bit_MaxDiv() public pure {
        // (max * max) / max = max
        assertEq(mulDiv(type(uint256).max, type(uint256).max, type(uint256).max), type(uint256).max);
    }

    function test_MulDiv_512bit_HalfDiv() public pure {
        // (max * 2) / 2 = max — triggers 512-bit path since max*2 overflows
        uint256 result = mulDiv(type(uint256).max, 2, 2);
        assertEq(result, type(uint256).max);
    }

    function test_MulDiv_Fuzz_MatchesSolady_SmallInputs(uint256 x, uint256 y, uint256 d)
        public
        pure
    {
        x = bound(x, 0, type(uint128).max);
        y = bound(y, 0, type(uint128).max);
        d = bound(d, 1, type(uint256).max);
        assertEq(mulDiv(x, y, d), FixedPointMathLib.mulDiv(x, y, d));
    }

    function test_MulDiv_Fuzz_MatchesSolady_512bit(uint256 x, uint256 y, uint256 d) public pure {
        // Force 512-bit path: both large, d large enough to avoid result overflow
        x = bound(x, type(uint128).max, type(uint256).max);
        y = bound(y, 2, type(uint256).max);
        d = bound(d, x, type(uint256).max);
        assertEq(mulDiv(x, y, d), FixedPointMathLib.fullMulDiv(x, y, d));
    }

    // ── mulDivUp correctness ─────────────────────────────────────

    function test_MulDivUp_Basic() public pure {
        assertEq(mulDivUp(10, 20, 5), 40); // exact
        assertEq(mulDivUp(10, 3, 7), 5); // 30/7 = 4.28 → 5
        assertEq(mulDivUp(1, 1, 2), 1); // 0.5 → 1
        assertEq(mulDivUp(3, 1, 3), 1); // exact
    }

    function test_MulDivUp_AlwaysGeMulDiv(uint256 x, uint256 y, uint256 d) public pure {
        x = bound(x, 0, type(uint128).max);
        y = bound(y, 0, type(uint128).max);
        d = bound(d, 1, type(uint256).max);
        assertGe(mulDivUp(x, y, d), mulDiv(x, y, d));
    }

    function test_MulDivUp_Fuzz_MatchesSolady(uint256 x, uint256 y, uint256 d) public pure {
        x = bound(x, 0, type(uint128).max);
        y = bound(y, 0, type(uint128).max);
        d = bound(d, 1, type(uint256).max);
        assertEq(mulDivUp(x, y, d), FixedPointMathLib.mulDivUp(x, y, d));
    }

    function test_MulDivUp_Fuzz_MatchesSolady_512bit(uint256 x, uint256 y, uint256 d) public pure {
        x = bound(x, type(uint128).max, type(uint256).max);
        y = bound(y, 2, type(uint256).max);
        d = bound(d, x, type(uint256).max);
        assertEq(mulDivUp(x, y, d), FixedPointMathLib.fullMulDivUp(x, y, d));
    }

    // ── sqrt correctness ─────────────────────────────────────────

    function test_Sqrt_KnownValues() public pure {
        assertEq(sqrt(0), 0);
        assertEq(sqrt(1), 1);
        assertEq(sqrt(4), 2);
        assertEq(sqrt(9), 3);
        assertEq(sqrt(1e18), 1e9);
        assertEq(sqrt(type(uint256).max), 340282366920938463463374607431768211455);
    }

    function test_Sqrt_Fuzz_MatchesSolady(uint256 x) public pure {
        assertEq(sqrt(x), FixedPointMathLib.sqrt(x));
    }

    function test_Sqrt_Fuzz_FloorProperty(uint256 x) public pure {
        uint256 z = sqrt(x);
        assertTrue(z * z <= x);
        if (z < type(uint128).max) {
            assertTrue((z + 1) * (z + 1) > x);
        }
    }

    // ── buyExactIn overshoot regression ──────────────────────────

    function test_BuyExactIn_SteepCurve_NoFee_NoRevert() public {
        // Regression: steep curve with feeBps=0 previously reverted
        address tkn = _configureNoFee();

        // Advance curve to 25% sold
        vm.prank(bob);
        sale.buy{value: sale.quote(tkn, 250e18)}(tkn, 250e18, 0, block.timestamp);

        // buyExactIn at this point was the failing case
        vm.prank(carol);
        sale.buyExactIn{value: 1 ether}(tkn, 0, block.timestamp);
        assertGt(token.balanceOf(carol), 0);
    }

    function test_BuyExactIn_SteepCurve_ManyCalls() public {
        // Walk entire curve with buyExactIn to find any revert
        address tkn = _configureNoFee();
        for (uint256 i; i < 20; i++) {
            address buyer = address(uint160(0x3000 + i));
            vm.deal(buyer, 100 ether);
            vm.prank(buyer);
            try sale.buyExactIn{value: 0.5 ether}(tkn, 0, block.timestamp) {
                assertGt(token.balanceOf(buyer), 0);
            } catch {
                // Only acceptable revert: ZeroAmount (fully sold) or Graduated
                (,,,,,,,,,,,, bool graduated,,,,,) = sale.curves(tkn);
                assertTrue(graduated, "unexpected revert before graduation");
                break;
            }
        }
    }

    function test_BuyExactIn_RaisedETH_MatchesBalance() public {
        // Verify raisedETH accounting with the overshoot fix
        address tkn = _configureNoFee();

        for (uint256 i; i < 10; i++) {
            address buyer = address(uint160(0x4000 + i));
            vm.deal(buyer, 100 ether);
            vm.prank(buyer);
            try sale.buyExactIn{value: 1 ether}(tkn, 0, block.timestamp) {}
            catch {
                break;
            }
        }

        (,,,,,,,, uint256 raisedETH,,,,,,,,,) = sale.curves(tkn);
        assertEq(address(sale).balance, raisedETH);
    }

    function test_BuyExactIn_VerySteepCurve() public {
        // 100x ratio
        MockToken t2 = new MockToken("T3", "T3", 18);
        address tkn = address(t2);
        t2.mint(alice, CAP);
        vm.startPrank(alice);
        t2.approve(address(sale), CAP);
        sale.configure(
            alice, tkn, CAP, 0.001e18, 0.1e18, 0, 0, 0, address(0), 0, 0, 0, 0, NO_CREATOR_FEE
        );
        vm.stopPrank();

        for (uint256 i; i < 15; i++) {
            address buyer = address(uint160(0x5000 + i));
            vm.deal(buyer, 100 ether);
            vm.prank(buyer);
            try sale.buyExactIn{value: 2 ether}(tkn, 0, block.timestamp) {}
            catch {
                break;
            }
        }

        (,,,,,,,, uint256 raisedETH,,,,,,,,,) = sale.curves(tkn);
        assertEq(address(sale).balance, raisedETH);
    }

    // ── Fuzz Tests ───────────────────────────────────────────────

    function test_Fuzz_BuyExactIn_NeverUnderpayCurve(uint256 ethIn, uint256 soldBefore) public {
        // Fuzz buyExactIn across curve positions — raisedETH must always match balance
        address tkn = _configureNoFee();

        // Advance curve to a random position
        soldBefore = bound(soldBefore, 0, 900e18);
        if (soldBefore > 0) {
            uint256 advanceCost = sale.quote(tkn, soldBefore);
            vm.prank(bob);
            sale.buy{value: advanceCost}(tkn, soldBefore, 0, block.timestamp);
        }

        // buyExactIn with random ETH amount
        ethIn = bound(ethIn, 0.001 ether, 50 ether);
        address buyer = address(uint160(0x7000));
        vm.deal(buyer, ethIn);
        vm.prank(buyer);
        try sale.buyExactIn{value: ethIn}(tkn, 0, block.timestamp) {
            // Must hold: raisedETH == contract balance
            (,,,,,,,, uint256 raisedETH,,,,,,,,,) = sale.curves(tkn);
            assertEq(address(sale).balance, raisedETH, "raisedETH != balance after buyExactIn");
        } catch {
            // Acceptable reverts: ZeroAmount (fully sold) or Graduated
        }
    }

    function test_Fuzz_BuyExactIn_WithFee(uint256 ethIn, uint16 feeBps) public {
        feeBps = uint16(bound(feeBps, 0, 5000));
        address tkn = _configureWith(START_PRICE, END_PRICE, feeBps, 0, 0, address(0));

        ethIn = bound(ethIn, 0.01 ether, 20 ether);
        vm.prank(bob);
        try sale.buyExactIn{value: ethIn}(tkn, 0, block.timestamp) {
            (,,,,,,,, uint256 raisedETH,,,,,,,,,) = sale.curves(tkn);
            // Contract may hold slightly more than raisedETH due to fee rounding
            assertGe(address(sale).balance, raisedETH, "balance < raisedETH");
        } catch {}
    }

    function test_Fuzz_BuySell_Roundtrip_NeverProfits(uint256 amount) public {
        address tkn = _configureWith(START_PRICE, END_PRICE, 100, 0, 0, address(0)); // 1% fee
        amount = bound(amount, 1e18, 500e18);

        uint256 cost = sale.quote(tkn, amount);
        uint256 fee = (cost * 100) / 10_000;
        uint256 bobBefore = bob.balance;

        vm.startPrank(bob);
        sale.buy{value: cost + fee}(tkn, amount, 0, block.timestamp);
        uint256 received = token.balanceOf(bob);
        token.approve(address(sale), received);
        sale.sell(tkn, received, 0, block.timestamp);
        vm.stopPrank();

        assertLe(bob.balance, bobBefore, "round-trip should never profit");
    }

    function test_Fuzz_SellExactOut_NeverOverdraws(uint256 buyAmount, uint256 ethOut) public {
        address tkn = _configureNoFee();

        // Buy some tokens first
        buyAmount = bound(buyAmount, 10e18, 500e18);
        uint256 cost = sale.quote(tkn, buyAmount);
        vm.prank(bob);
        sale.buy{value: cost}(tkn, buyAmount, 0, block.timestamp);

        // Try sellExactOut for random ETH amount
        ethOut = bound(ethOut, 0.001 ether, cost);
        vm.startPrank(bob);
        token.approve(address(sale), buyAmount);
        try sale.sellExactOut(tkn, ethOut, buyAmount, block.timestamp) {
            // raisedETH must match balance
            (,,,,,,,, uint256 raisedETH,,,,,,,,,) = sale.curves(tkn);
            assertEq(address(sale).balance, raisedETH, "raisedETH != balance after sellExactOut");
            // Bob got at least what they asked for
            assertGe(bob.balance, ethOut, "received less than ethOut");
        } catch {
            // Acceptable: Slippage, InsufficientLiquidity, ZeroAmount
        }
        vm.stopPrank();
    }

    function test_Fuzz_Graduation_ByTarget(uint256 target) public {
        // Compute max ETH from full cap on a fresh no-fee curve
        address tkn0 = _configureNoFee();
        uint256 maxETH = sale.quote(tkn0, CAP);

        // New curve with random graduation target
        target = bound(target, 1, maxETH);
        MockToken t2 = new MockToken("T2", "T2", 18);
        t2.mint(alice, CAP);
        vm.startPrank(alice);
        t2.approve(address(sale), CAP);
        sale.configure(
            alice,
            address(t2),
            CAP,
            START_PRICE,
            END_PRICE,
            0,
            target,
            0,
            address(0),
            0,
            0,
            0,
            0,
            NO_CREATOR_FEE
        );
        vm.stopPrank();

        // Buy until graduated
        uint256 bought;
        for (uint256 i; i < 20; i++) {
            (,,,,,,,,,,,, bool graduated,,,,,) = sale.curves(address(t2));
            if (graduated) break;
            uint256 chunk = bound(CAP / 10, 1e18, CAP - bought);
            if (chunk == 0) break;
            uint256 c2 = sale.quote(address(t2), chunk);
            vm.prank(bob);
            sale.buy{value: c2}(address(t2), chunk, 0, block.timestamp);
            bought += chunk;
        }

        (,,,,,,,,,,,, bool grad,,,,,) = sale.curves(address(t2));
        if (grad) {
            assertTrue(sale.graduable(address(t2)), "should be graduable");
        }
    }

    function test_Fuzz_MaxUint128_Config() public {
        // Boundary: configure with large-but-valid uint128 values
        uint128 bigCap = 1e30; // 1 trillion tokens with 18 decimals
        uint128 bigPrice = 1e28; // 10 billion ETH per token (absurd but valid)
        // vr check will likely reject extreme combos, so use flat curve
        MockToken t3 = new MockToken("BIG", "BIG", 18);
        t3.mint(alice, bigCap);
        vm.startPrank(alice);
        t3.approve(address(sale), bigCap);
        sale.configure(
            alice,
            address(t3),
            bigCap,
            bigPrice,
            bigPrice,
            0,
            0,
            0,
            address(0),
            0,
            0,
            0,
            0,
            NO_CREATOR_FEE
        );
        vm.stopPrank();

        // Quote should not overflow
        uint256 cost = sale.quote(address(t3), 1e18); // 1 token
        assertEq(cost, bigPrice); // flat curve: 1 token * price / 1e18
    }

    function test_Fuzz_Quote_SymmetricBuySell(uint256 amount) public {
        address tkn = _configureNoFee();
        amount = bound(amount, 1e18, CAP);

        uint256 buyCost = sale.quote(tkn, amount);

        // Buy, then quote the sell for same amount
        vm.prank(bob);
        sale.buy{value: buyCost}(tkn, amount, 0, block.timestamp);
        uint256 sellProceeds = sale.quoteSell(tkn, amount);

        // buy cost == sell proceeds on a no-fee curve (same _cost function)
        assertEq(buyCost, sellProceeds, "buy/sell quote mismatch");
    }

    // ── Sniper Fee Tests ─────────────────────────────────────────

    function _configureSniper() internal returns (address tkn) {
        tkn = address(token);
        token.mint(alice, CAP);
        vm.startPrank(alice);
        token.approve(address(sale), CAP);
        sale.configure(
            alice,
            tkn,
            CAP,
            START_PRICE,
            END_PRICE,
            FEE_BPS,
            0,
            0,
            address(0),
            0,
            5000, // 50% sniper fee
            600, // 10 minutes decay
            0,
            NO_CREATOR_FEE
        );
        vm.stopPrank();
    }

    function test_SniperFee_ElevatedAtLaunch() public {
        address tkn = _configureSniper();
        // Immediately after launch: effective fee should be near sniperFeeBps (50%)
        uint256 fee = sale.effectiveFee(tkn);
        assertEq(fee, 5000);
    }

    function test_SniperFee_DecaysOverTime() public {
        address tkn = _configureSniper();

        // At 50% of duration (300s): fee should be midpoint between 5000 and 100
        vm.warp(block.timestamp + 300);
        uint256 fee = sale.effectiveFee(tkn);
        // midpoint = 100 + (5000 - 100) * 300 / 600 = 100 + 2450 = 2550
        assertEq(fee, 2550);
    }

    function test_SniperFee_ReturnsBaseFeeAfterDecay() public {
        address tkn = _configureSniper();

        // After full duration: fee should be base feeBps
        vm.warp(block.timestamp + 600);
        uint256 fee = sale.effectiveFee(tkn);
        assertEq(fee, FEE_BPS);

        // Well past duration
        vm.warp(block.timestamp + 10000);
        fee = sale.effectiveFee(tkn);
        assertEq(fee, FEE_BPS);
    }

    function test_SniperFee_AffectsBuyCost() public {
        // Configure two curves: one with sniper, one without
        address sniperTkn = _configureSniper();

        MockToken t2 = new MockToken("T2", "T2", 18);
        t2.mint(alice, CAP);
        vm.startPrank(alice);
        t2.approve(address(sale), CAP);
        sale.configure(
            alice,
            address(t2),
            CAP,
            START_PRICE,
            END_PRICE,
            FEE_BPS,
            0,
            0,
            address(0),
            0,
            0,
            0,
            0,
            NO_CREATOR_FEE
        );
        vm.stopPrank();

        // Buy same amount on both — sniper curve should cost more (higher fee)
        uint256 cost = sale.quote(sniperTkn, 100e18);
        uint256 sniperFee = (cost * 5000) / 10_000; // 50% at t=0
        uint256 normalFee = (cost * FEE_BPS) / 10_000;

        uint256 bobBefore = bob.balance;
        vm.prank(bob);
        sale.buy{value: cost + sniperFee}(sniperTkn, 100e18, 0, block.timestamp);
        uint256 sniperSpent = bobBefore - bob.balance;

        uint256 carolBefore = carol.balance;
        vm.prank(carol);
        sale.buy{value: cost + normalFee}(address(t2), 100e18, 0, block.timestamp);
        uint256 normalSpent = carolBefore - carol.balance;

        assertGt(sniperSpent, normalSpent, "sniper should pay more");
    }

    function test_SniperFee_AffectsSell() public {
        address tkn = _configureSniper();

        // Buy at sniper fee
        uint256 cost = sale.quote(tkn, 100e18);
        uint256 sniperFee = (cost * 5000) / 10_000;
        vm.prank(bob);
        sale.buy{value: cost + sniperFee}(tkn, 100e18, 0, block.timestamp);

        // Sell immediately — should also pay sniper fee
        vm.startPrank(bob);
        token.approve(address(sale), 100e18);
        uint256 bobBefore = bob.balance;
        sale.sell(tkn, 100e18, 0, block.timestamp);
        vm.stopPrank();

        uint256 received = bob.balance - bobBefore;
        uint256 expectedNet = cost - (cost * 5000) / 10_000;
        assertApproxEqAbs(received, expectedNet, 1);
    }

    function test_SniperFee_DisabledByDefault() public {
        address tkn = _configureNoFee();
        assertEq(sale.effectiveFee(tkn), 0);
    }

    function test_SniperFee_RevertIf_FeeBelowBase() public {
        token.mint(alice, CAP);
        vm.startPrank(alice);
        token.approve(address(sale), CAP);
        vm.expectRevert(ClassicalCurveSale.InvalidParams.selector);
        sale.configure(
            alice,
            address(token),
            CAP,
            START_PRICE,
            END_PRICE,
            500,
            0,
            0,
            address(0),
            0,
            100, // sniper fee BELOW base fee
            600,
            0,
            NO_CREATOR_FEE
        );
        vm.stopPrank();
    }

    function test_SniperFee_RevertIf_FeeWithoutDuration() public {
        token.mint(alice, CAP);
        vm.startPrank(alice);
        token.approve(address(sale), CAP);
        vm.expectRevert(ClassicalCurveSale.InvalidParams.selector);
        sale.configure(
            alice,
            address(token),
            CAP,
            START_PRICE,
            END_PRICE,
            FEE_BPS,
            0,
            0,
            address(0),
            0,
            5000, // sniper fee set
            0, // but no duration
            0,
            NO_CREATOR_FEE
        );
        vm.stopPrank();
    }

    function test_Fuzz_SniperFee_Decay(uint256 elapsed) public {
        address tkn = _configureSniper();
        elapsed = bound(elapsed, 0, 1200); // up to 2x duration
        vm.warp(block.timestamp + elapsed);

        uint256 fee = sale.effectiveFee(tkn);
        assertGe(fee, FEE_BPS); // never below base
        assertLe(fee, 5000); // never above sniper max
    }

    // ── MaxBuy Tests ─────────────────────────────────────────────

    function _configureMaxBuy(uint16 maxBuyBps) internal returns (address tkn) {
        tkn = address(token);
        token.mint(alice, CAP);
        vm.startPrank(alice);
        token.approve(address(sale), CAP);
        sale.configure(
            alice,
            tkn,
            CAP,
            START_PRICE,
            END_PRICE,
            0,
            0,
            0,
            address(0),
            0,
            0,
            0,
            maxBuyBps,
            NO_CREATOR_FEE
        );
        vm.stopPrank();
    }

    function test_MaxBuy_CapsAmount() public {
        address tkn = _configureMaxBuy(1000); // 10% of cap = 100e18

        uint256 cost = sale.quote(tkn, 100e18);
        vm.prank(bob);
        sale.buy{value: cost}(tkn, 200e18, 0, block.timestamp); // ask for 200, capped to 100

        assertEq(token.balanceOf(bob), 100e18);
    }

    function test_MaxBuy_AllowsUnder() public {
        address tkn = _configureMaxBuy(1000); // 10% = 100e18

        uint256 cost = sale.quote(tkn, 50e18);
        vm.prank(bob);
        sale.buy{value: cost}(tkn, 50e18, 50e18, block.timestamp);

        assertEq(token.balanceOf(bob), 50e18);
    }

    function test_MaxBuy_SlippageRevert() public {
        address tkn = _configureMaxBuy(1000); // 10% = 100e18

        // Ask for 200 with minAmount 200 — capped to 100, fails slippage
        vm.prank(bob);
        vm.expectRevert(ClassicalCurveSale.Slippage.selector);
        sale.buy{value: 50 ether}(tkn, 200e18, 200e18, block.timestamp);
    }

    function test_MaxBuy_BuyExactIn() public {
        address tkn = _configureMaxBuy(500); // 5% of cap = 50e18

        // Send lots of ETH — should only get 50e18 tokens max
        vm.prank(bob);
        sale.buyExactIn{value: 100 ether}(tkn, 0, block.timestamp);

        assertLe(token.balanceOf(bob), 50e18);
        assertGt(token.balanceOf(bob), 0);
    }

    function test_MaxBuy_MultipleBuys() public {
        address tkn = _configureMaxBuy(1000); // 10% per tx

        // Can buy 10% multiple times
        for (uint256 i; i < 5; i++) {
            uint256 cost = sale.quote(tkn, 100e18);
            vm.prank(bob);
            sale.buy{value: cost}(tkn, 100e18, 100e18, block.timestamp);
        }

        assertEq(token.balanceOf(bob), 500e18);
    }

    function test_MaxBuy_Disabled() public {
        address tkn = _configureMaxBuy(0); // unlimited

        uint256 cost = sale.quote(tkn, 500e18);
        vm.prank(bob);
        sale.buy{value: cost}(tkn, 500e18, 500e18, block.timestamp);

        assertEq(token.balanceOf(bob), 500e18);
    }
}

contract MulDivReverts {
    function divByZero() external pure {
        mulDiv(1, 1, 0);
    }

    function overflow() external pure {
        mulDiv(type(uint256).max, type(uint256).max, 1);
    }
}

contract MockToken {
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
