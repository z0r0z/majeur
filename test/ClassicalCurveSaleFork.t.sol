// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {ClassicalCurveSale, ERC20, IZAMM, ZAMM} from "../src/peripheral/ClassicalCurveSale.sol";

/// @dev Fork tests for ClassicalCurveSale — tests launch(), graduate(), swapExactIn/Out,
///      claimVested, setLpRecipient, and beforeAction against the real ZAMM on mainnet.
contract ClassicalCurveSaleForkTest is Test {
    ClassicalCurveSale internal sale;

    address internal creator = address(0xC0FFEE);
    address internal alice = address(0xA11CE);
    address internal bob = address(0x0B0B);
    address internal feeBeneficiary = address(0xFEE);

    ClassicalCurveSale.CreatorFee internal NO_FEE =
        ClassicalCurveSale.CreatorFee(address(0), 0, 0, false, false);

    function setUp() public {
        vm.createSelectFork("main");
        sale = new ClassicalCurveSale();
        vm.deal(creator, 100 ether);
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);
    }

    // ── Helpers ──────────────────────────────────────────────────

    function _launch(
        uint256 cap,
        uint256 startPrice,
        uint256 endPrice,
        uint16 feeBps,
        uint256 graduationTarget,
        uint256 lpTokens,
        uint256 excess
    ) internal returns (address token) {
        token = sale.launch(
            creator,
            "Test",
            "TST",
            "",
            cap + lpTokens + excess,
            bytes32(block.timestamp),
            cap,
            startPrice,
            endPrice,
            feeBps,
            graduationTarget,
            lpTokens,
            address(0), // burn LP
            0,
            0,
            0,
            0,
            NO_FEE,
            0,
            0
        );
    }

    function _launchAndGraduate(
        uint256 cap,
        uint256 startPrice,
        uint256 endPrice,
        uint16 feeBps,
        uint256 lpTokens
    ) internal returns (address token) {
        token = _launch(cap, startPrice, endPrice, feeBps, 0, lpTokens, 0);

        // Buy entire cap to trigger graduation
        uint256 cost = sale.quote(token, cap);
        uint256 fee = (cost * feeBps) / 10_000;
        vm.prank(alice);
        sale.buy{value: cost + fee}(token, cap, 0);

        assertTrue(sale.graduable(token));

        // Graduate
        sale.graduate(token);
    }

    // ── Launch Tests ─────────────────────────────────────────────

    function test_Launch_DeploysAndConfigures() public {
        address token = _launch(1000e18, 0.01e18, 0.01e18, 0, 0, 0, 0);
        assertTrue(token != address(0));
        assertEq(ERC20(token).totalSupply(), 1000e18);
        assertEq(ERC20(token).balanceOf(address(sale)), 1000e18);

        (address c, uint256 cap,,,,,,,,,,,,) = sale.curves(token);
        assertEq(c, creator);
        assertEq(cap, 1000e18);
    }

    function test_Launch_ExcessToCreator() public {
        address token = _launch(1000e18, 0.01e18, 0.01e18, 0, 0, 0, 500e18);
        assertEq(ERC20(token).balanceOf(creator), 500e18);
        assertEq(ERC20(token).balanceOf(address(sale)), 1000e18);
    }

    function test_Launch_WithVesting() public {
        address token = sale.launch(
            creator,
            "V",
            "VST",
            "",
            1500e18,
            bytes32(uint256(99)),
            1000e18,
            0.01e18,
            0.01e18,
            0,
            0,
            0,
            address(0),
            0,
            0,
            0,
            0,
            NO_FEE,
            uint40(30 days),
            uint40(60 days) // cliff + linear
        );

        // Creator should NOT have excess tokens yet
        assertEq(ERC20(token).balanceOf(creator), 0);

        // Vesting should be configured
        (uint128 total, uint128 claimed,, uint40 cliff, uint40 duration) = sale.creatorVests(token);
        assertEq(total, 500e18);
        assertEq(claimed, 0);
        assertEq(cliff, 30 days);
        assertEq(duration, 60 days);
    }

    function test_Launch_WithCreatorFee() public {
        ClassicalCurveSale.CreatorFee memory cf =
            ClassicalCurveSale.CreatorFee(feeBeneficiary, 500, 300, true, false);

        address token = sale.launch(
            creator,
            "F",
            "FEE",
            "",
            1000e18,
            bytes32(uint256(77)),
            1000e18,
            0.01e18,
            0.01e18,
            100,
            0,
            0,
            address(0),
            0,
            0,
            0,
            0,
            cf,
            0,
            0
        );

        (address ben, uint16 buyBps, uint16 sellBps, bool buyOnInput, bool sellOnInput) =
            sale.creatorFees(token);
        assertEq(ben, feeBeneficiary);
        assertEq(buyBps, 500);
        assertEq(sellBps, 300);
        assertTrue(buyOnInput);
        assertFalse(sellOnInput);
    }

    function test_Launch_Revert_SupplyLessThanNeeded() public {
        vm.expectRevert(ClassicalCurveSale.InvalidParams.selector);
        sale.launch(
            creator,
            "T",
            "T",
            "",
            500e18,
            bytes32(0),
            1000e18,
            0.01e18,
            0.01e18,
            0,
            0,
            0,
            address(0),
            0,
            0,
            0,
            0,
            NO_FEE,
            0,
            0
        );
    }

    function test_Launch_Revert_ZeroCreator() public {
        vm.expectRevert(ClassicalCurveSale.InvalidParams.selector);
        sale.launch(
            address(0),
            "T",
            "T",
            "",
            1000e18,
            bytes32(0),
            1000e18,
            0.01e18,
            0.01e18,
            0,
            0,
            0,
            address(0),
            0,
            0,
            0,
            0,
            NO_FEE,
            0,
            0
        );
    }

    // ── ClaimVested Tests ────────────────────────────────────────

    function test_ClaimVested_CliffOnly() public {
        address token = sale.launch(
            creator,
            "V",
            "V",
            "",
            1500e18,
            bytes32(uint256(1)),
            1000e18,
            0.01e18,
            0.01e18,
            0,
            0,
            0,
            address(0),
            0,
            0,
            0,
            0,
            NO_FEE,
            uint40(30 days),
            0
        );

        // Before cliff
        vm.prank(creator);
        vm.expectRevert(ClassicalCurveSale.ZeroAmount.selector);
        sale.claimVested(token);

        // After cliff
        vm.warp(block.timestamp + 30 days);
        vm.prank(creator);
        sale.claimVested(token);
        assertEq(ERC20(token).balanceOf(creator), 500e18);

        // Double claim reverts
        vm.prank(creator);
        vm.expectRevert(ClassicalCurveSale.ZeroAmount.selector);
        sale.claimVested(token);
    }

    function test_ClaimVested_Linear() public {
        address token = sale.launch(
            creator,
            "V",
            "V",
            "",
            1500e18,
            bytes32(uint256(2)),
            1000e18,
            0.01e18,
            0.01e18,
            0,
            0,
            0,
            address(0),
            0,
            0,
            0,
            0,
            NO_FEE,
            0,
            uint40(100 days)
        );

        (,, uint40 vestStart,,) = sale.creatorVests(token);

        // At 25%
        vm.warp(vestStart + 25 days);
        vm.prank(creator);
        sale.claimVested(token);
        assertEq(ERC20(token).balanceOf(creator), 125e18);

        // At 75%
        vm.warp(vestStart + 75 days);
        vm.prank(creator);
        sale.claimVested(token);
        assertEq(ERC20(token).balanceOf(creator), 375e18);

        // At 100%
        vm.warp(vestStart + 100 days);
        vm.prank(creator);
        sale.claimVested(token);
        assertEq(ERC20(token).balanceOf(creator), 500e18);
    }

    function test_ClaimVested_CliffPlusLinear() public {
        address token = sale.launch(
            creator,
            "V",
            "V",
            "",
            1500e18,
            bytes32(uint256(3)),
            1000e18,
            0.01e18,
            0.01e18,
            0,
            0,
            0,
            address(0),
            0,
            0,
            0,
            0,
            NO_FEE,
            uint40(30 days),
            uint40(60 days)
        );

        (,, uint40 vestStart,,) = sale.creatorVests(token);

        // During cliff — nothing
        vm.warp(vestStart + 15 days);
        vm.prank(creator);
        vm.expectRevert(ClassicalCurveSale.ZeroAmount.selector);
        sale.claimVested(token);

        // Right after cliff — 0% of linear portion
        vm.warp(vestStart + 30 days);
        vm.prank(creator);
        vm.expectRevert(ClassicalCurveSale.ZeroAmount.selector);
        sale.claimVested(token);

        // Cliff + 30 days (50% linear)
        vm.warp(vestStart + 30 days + 30 days);
        vm.prank(creator);
        sale.claimVested(token);
        assertEq(ERC20(token).balanceOf(creator), 250e18);

        // Cliff + 60 days (100% linear)
        vm.warp(vestStart + 30 days + 60 days);
        vm.prank(creator);
        sale.claimVested(token);
        assertEq(ERC20(token).balanceOf(creator), 500e18);
    }

    function test_ClaimVested_Revert_Unauthorized() public {
        address token = sale.launch(
            creator,
            "V",
            "V",
            "",
            1500e18,
            bytes32(uint256(4)),
            1000e18,
            0.01e18,
            0.01e18,
            0,
            0,
            0,
            address(0),
            0,
            0,
            0,
            0,
            NO_FEE,
            0,
            uint40(100 days)
        );

        vm.warp(block.timestamp + 50 days);
        vm.prank(alice); // not creator
        vm.expectRevert(ClassicalCurveSale.Unauthorized.selector);
        sale.claimVested(token);
    }

    function test_ClaimVested_Revert_NoVesting() public {
        address token = _launch(1000e18, 0.01e18, 0.01e18, 0, 0, 0, 0);
        vm.prank(creator);
        vm.expectRevert(ClassicalCurveSale.NotConfigured.selector);
        sale.claimVested(token);
    }

    // ── SetLpRecipient Tests ─────────────────────────────────────

    function test_SetLpRecipient() public {
        address token = _launch(1000e18, 0.01e18, 0.01e18, 0, 0, 500e18, 0);

        vm.prank(creator);
        sale.setLpRecipient(token, alice);

        (,,,,,,,,,,, address lpRecipient,,) = sale.curves(token);
        assertEq(lpRecipient, alice);
    }

    function test_SetLpRecipient_Revert_Unauthorized() public {
        address token = _launch(1000e18, 0.01e18, 0.01e18, 0, 0, 500e18, 0);

        vm.prank(alice);
        vm.expectRevert(ClassicalCurveSale.Unauthorized.selector);
        sale.setLpRecipient(token, alice);
    }

    function test_SetLpRecipient_Revert_AfterGraduation() public {
        address token = _launchAndGraduate(100e18, 0.01e18, 0.01e18, 0, 50e18);

        vm.prank(creator);
        vm.expectRevert(ClassicalCurveSale.Graduated.selector);
        sale.setLpRecipient(token, alice);
    }

    // ── SetCreator Revert Tests ──────────────────────────────────

    function test_SetCreator_Revert_Unauthorized() public {
        address token = _launch(1000e18, 0.01e18, 0.01e18, 0, 0, 0, 0);

        vm.prank(alice);
        vm.expectRevert(ClassicalCurveSale.Unauthorized.selector);
        sale.setCreator(token, alice);
    }

    function test_SetCreator_Revert_ZeroAddress() public {
        address token = _launch(1000e18, 0.01e18, 0.01e18, 0, 0, 0, 0);

        vm.prank(creator);
        vm.expectRevert(ClassicalCurveSale.InvalidParams.selector);
        sale.setCreator(token, address(0));
    }

    // ── Graduate Tests ───────────────────────────────────────────

    function test_Graduate_SeedsZAMM() public {
        address token = _launch(100e18, 0.01e18, 0.01e18, 0, 0, 50e18, 0);

        // Buy entire cap
        vm.prank(alice);
        sale.buy{value: 10 ether}(token, 100e18, 100e18);
        assertTrue(sale.graduable(token));

        uint256 liquidity = sale.graduate(token);
        assertGt(liquidity, 0);

        // Verify state
        (,,,,,,,,,,,,, bool seeded) = sale.curves(token);
        assertTrue(seeded);

        // Not graduable anymore
        assertFalse(sale.graduable(token));

        // Pool registered
        (, uint256 poolId) = sale.poolKeyOf(token);
        assertEq(sale.poolToken(poolId), token);
    }

    function test_Graduate_BurnsUnsold() public {
        // Graduate via ETH target with unsold tokens
        address token = _launch(1000e18, 0.01e18, 0.01e18, 0, 5e18, 500e18, 0);

        vm.prank(alice);
        sale.buy{value: 5 ether}(token, 500e18, 500e18);
        assertTrue(sale.graduable(token));

        uint256 deadBefore = ERC20(token).balanceOf(address(0xdead));
        sale.graduate(token);

        // 500 unsold tokens should be burned to 0xdead
        uint256 burned = ERC20(token).balanceOf(address(0xdead)) - deadBefore;
        assertEq(burned, 500e18);
    }

    function test_Graduate_NoLPTokens_ReturnsFundsToCreator() public {
        // No LP tokens — ETH goes to creator
        address token = _launch(100e18, 0.01e18, 0.01e18, 0, 0, 0, 0);

        vm.prank(alice);
        sale.buy{value: 10 ether}(token, 100e18, 100e18);

        uint256 creatorBefore = creator.balance;
        (,,,,,,,, uint256 raisedETH,,,,,) = sale.curves(token);

        uint256 liq = sale.graduate(token);
        assertEq(liq, 0);
        assertEq(creator.balance - creatorBefore, raisedETH);
    }

    function test_Graduate_Revert_NotGraduable() public {
        address token = _launch(1000e18, 0.01e18, 0.01e18, 0, 0, 0, 0);

        vm.expectRevert(ClassicalCurveSale.NotGraduable.selector);
        sale.graduate(token);
    }

    function test_Graduate_Revert_AlreadySeeded() public {
        address token = _launchAndGraduate(100e18, 0.01e18, 0.01e18, 0, 50e18);

        vm.expectRevert(ClassicalCurveSale.NotGraduable.selector);
        sale.graduate(token);
    }

    function test_Graduate_Revert_NotConfigured() public {
        vm.expectRevert(ClassicalCurveSale.NotConfigured.selector);
        sale.graduate(address(0xdead));
    }

    // ── BeforeAction Tests ───────────────────────────────────────

    function test_BeforeAction_ReturnsPoolFee() public {
        address token = _launchAndGraduate(100e18, 0.01e18, 0.01e18, 0, 50e18);
        (, uint256 poolId) = sale.poolKeyOf(token);

        // Call from ZAMM address
        vm.prank(address(ZAMM));
        uint256 fee = sale.beforeAction(IZAMM.swapExactIn.selector, poolId, alice, "");
        assertEq(fee, 25); // DEFAULT_POOL_FEE
    }

    function test_BeforeAction_CustomPoolFee() public {
        // Launch with custom pool fee
        address token = sale.launch(
            creator,
            "C",
            "C",
            "",
            150e18,
            bytes32(uint256(55)),
            100e18,
            0.01e18,
            0.01e18,
            0,
            0,
            50e18,
            address(0),
            100, // 1% pool fee
            0,
            0,
            0,
            NO_FEE,
            0,
            0
        );

        vm.prank(alice);
        sale.buy{value: 10 ether}(token, 100e18, 100e18);
        sale.graduate(token);

        (, uint256 poolId) = sale.poolKeyOf(token);
        vm.prank(address(ZAMM));
        uint256 fee = sale.beforeAction(IZAMM.swapExactIn.selector, poolId, alice, "");
        assertEq(fee, 100);
    }

    function test_BeforeAction_LP_PostSeed_Allowed() public {
        address token = _launchAndGraduate(100e18, 0.01e18, 0.01e18, 0, 50e18);
        (, uint256 poolId) = sale.poolKeyOf(token);

        // LP operations (non-swap selector) should return 0 fee
        vm.prank(address(ZAMM));
        uint256 fee = sale.beforeAction(IZAMM.addLiquidity.selector, poolId, alice, "");
        assertEq(fee, 0);
    }

    function test_BeforeAction_LP_PreSeed_Blocked() public {
        // Unregistered pool → LP should be blocked
        vm.prank(address(ZAMM));
        vm.expectRevert(ClassicalCurveSale.NotConfigured.selector);
        sale.beforeAction(IZAMM.addLiquidity.selector, 12345, alice, "");
    }

    function test_BeforeAction_Swap_UnregisteredPool_Blocked() public {
        vm.prank(address(ZAMM));
        vm.expectRevert(ClassicalCurveSale.NotConfigured.selector);
        sale.beforeAction(IZAMM.swapExactIn.selector, 12345, alice, "");
    }

    function test_BeforeAction_CreatorFee_BlocksDirectSwap() public {
        // Launch with creator fee
        ClassicalCurveSale.CreatorFee memory cf =
            ClassicalCurveSale.CreatorFee(feeBeneficiary, 500, 300, true, false);
        address token = sale.launch(
            creator,
            "F",
            "F",
            "",
            150e18,
            bytes32(uint256(66)),
            100e18,
            0.01e18,
            0.01e18,
            0,
            0,
            50e18,
            address(0),
            0,
            0,
            0,
            0,
            cf,
            0,
            0
        );

        vm.prank(alice);
        sale.buy{value: 10 ether}(token, 100e18, 100e18);
        sale.graduate(token);

        (, uint256 poolId) = sale.poolKeyOf(token);

        // swap selector should be blocked
        vm.prank(address(ZAMM));
        vm.expectRevert(ClassicalCurveSale.Unauthorized.selector);
        sale.beforeAction(IZAMM.swap.selector, poolId, alice, "");

        // swapExactIn from non-sale sender should be blocked
        vm.prank(address(ZAMM));
        vm.expectRevert(ClassicalCurveSale.Unauthorized.selector);
        sale.beforeAction(IZAMM.swapExactIn.selector, poolId, alice, "");

        // swapExactIn from the sale contract itself should pass
        vm.prank(address(ZAMM));
        uint256 fee = sale.beforeAction(IZAMM.swapExactIn.selector, poolId, address(sale), "");
        assertEq(fee, 25); // default pool fee
    }

    // ── Routed Swap Tests ────────────────────────────────────────

    function test_SwapExactIn_BuyToken_FeeOnInput() public {
        ClassicalCurveSale.CreatorFee memory cf =
            ClassicalCurveSale.CreatorFee(feeBeneficiary, 500, 500, true, true);
        address token = sale.launch(
            creator,
            "S",
            "S",
            "",
            150e18,
            bytes32(uint256(88)),
            100e18,
            0.01e18,
            0.01e18,
            0,
            0,
            50e18,
            address(0),
            0,
            0,
            0,
            0,
            cf,
            0,
            0
        );

        vm.prank(alice);
        sale.buy{value: 10 ether}(token, 100e18, 100e18);
        sale.graduate(token);

        (IZAMM.PoolKey memory key,) = sale.poolKeyOf(token);

        // Buy token (ETH → token) with fee on input
        uint256 feeBenBefore = feeBeneficiary.balance;
        vm.prank(bob);
        uint256 amountOut =
            sale.swapExactIn{value: 1 ether}(key, 1 ether, 0, true, bob, block.timestamp);

        assertGt(amountOut, 0);
        assertGt(ERC20(token).balanceOf(bob), 0);
        // Beneficiary got 5% of 1 ETH = 0.05 ETH
        assertEq(feeBeneficiary.balance - feeBenBefore, 0.05 ether);
    }

    function test_SwapExactIn_SellToken_FeeOnInput() public {
        ClassicalCurveSale.CreatorFee memory cf =
            ClassicalCurveSale.CreatorFee(feeBeneficiary, 500, 500, true, true);
        address token = sale.launch(
            creator,
            "S",
            "S",
            "",
            150e18,
            bytes32(uint256(89)),
            100e18,
            0.01e18,
            0.01e18,
            0,
            0,
            50e18,
            address(0),
            0,
            0,
            0,
            0,
            cf,
            0,
            0
        );

        // Buy all, graduate, then buy some on ZAMM to have tokens
        vm.prank(alice);
        sale.buy{value: 10 ether}(token, 100e18, 100e18);
        sale.graduate(token);

        (IZAMM.PoolKey memory key,) = sale.poolKeyOf(token);

        // Buy some tokens first via routed swap
        vm.prank(bob);
        sale.swapExactIn{value: 0.5 ether}(key, 0.5 ether, 0, true, bob, block.timestamp);
        uint256 bobTokens = ERC20(token).balanceOf(bob);
        assertGt(bobTokens, 0);

        // Sell tokens (token → ETH) with fee on input
        uint256 sellAmount = bobTokens / 2;
        vm.startPrank(bob);
        ERC20(token).approve(address(sale), sellAmount);
        uint256 bobEthBefore = bob.balance;
        uint256 feeBenTokenBefore = ERC20(token).balanceOf(feeBeneficiary);
        sale.swapExactIn(key, sellAmount, 0, false, bob, block.timestamp);
        vm.stopPrank();

        assertGt(bob.balance, bobEthBefore);
        // Beneficiary got 5% of tokens as fee
        uint256 feeBenTokenGot = ERC20(token).balanceOf(feeBeneficiary) - feeBenTokenBefore;
        assertEq(feeBenTokenGot, (sellAmount * 500) / 10_000);
    }

    function test_SwapExactIn_NoCreatorFee_DirectRoute() public {
        // No creator fee — swaps go through but no tax taken
        address token = _launchAndGraduate(100e18, 0.01e18, 0.01e18, 0, 50e18);

        (IZAMM.PoolKey memory key,) = sale.poolKeyOf(token);

        vm.prank(bob);
        uint256 amountOut =
            sale.swapExactIn{value: 0.1 ether}(key, 0.1 ether, 0, true, bob, block.timestamp);
        assertGt(amountOut, 0);
        assertGt(ERC20(token).balanceOf(bob), 0);
    }

    function test_SwapExactIn_Revert_SellWithETH() public {
        address token = _launchAndGraduate(100e18, 0.01e18, 0.01e18, 0, 50e18);
        (IZAMM.PoolKey memory key,) = sale.poolKeyOf(token);

        vm.prank(bob);
        vm.expectRevert(ClassicalCurveSale.InvalidParams.selector);
        sale.swapExactIn{value: 1 ether}(key, 1e18, 0, false, bob, block.timestamp);
    }

    function test_SwapExactOut_BuyToken_FeeOnOutput() public {
        ClassicalCurveSale.CreatorFee memory cf =
            ClassicalCurveSale.CreatorFee(feeBeneficiary, 500, 500, false, false);
        address token = sale.launch(
            creator,
            "S",
            "S",
            "",
            150e18,
            bytes32(uint256(90)),
            100e18,
            0.01e18,
            0.01e18,
            0,
            0,
            50e18,
            address(0),
            0,
            0,
            0,
            0,
            cf,
            0,
            0
        );

        vm.prank(alice);
        sale.buy{value: 10 ether}(token, 100e18, 100e18);
        sale.graduate(token);

        (IZAMM.PoolKey memory key,) = sale.poolKeyOf(token);

        // Buy exact amount of tokens, fee deducted from output
        uint256 wantTokens = 1e18;
        uint256 feeBenTokenBefore = ERC20(token).balanceOf(feeBeneficiary);
        vm.prank(bob);
        sale.swapExactOut{value: 5 ether}(key, wantTokens, 5 ether, true, bob, block.timestamp);

        assertEq(ERC20(token).balanceOf(bob), wantTokens);
        // Beneficiary gets the tax (gross - net)
        uint256 feeBenTokenGot = ERC20(token).balanceOf(feeBeneficiary) - feeBenTokenBefore;
        assertGt(feeBenTokenGot, 0);
    }

    function test_SwapExactOut_SellToken_FeeOnOutput() public {
        ClassicalCurveSale.CreatorFee memory cf =
            ClassicalCurveSale.CreatorFee(feeBeneficiary, 500, 500, false, false);
        address token = sale.launch(
            creator,
            "S",
            "S",
            "",
            150e18,
            bytes32(uint256(91)),
            100e18,
            0.01e18,
            0.01e18,
            0,
            0,
            50e18,
            address(0),
            0,
            0,
            0,
            0,
            cf,
            0,
            0
        );

        vm.prank(alice);
        sale.buy{value: 10 ether}(token, 100e18, 100e18);
        sale.graduate(token);

        (IZAMM.PoolKey memory key,) = sale.poolKeyOf(token);

        // Buy some tokens first
        vm.prank(bob);
        sale.swapExactIn{value: 0.5 ether}(key, 0.5 ether, 0, true, bob, block.timestamp);
        uint256 bobTokens = ERC20(token).balanceOf(bob);

        // Sell for exact ETH output
        uint256 wantETH = 0.01 ether;
        vm.startPrank(bob);
        ERC20(token).approve(address(sale), bobTokens);
        uint256 bobEthBefore = bob.balance;
        uint256 feeBenBefore = feeBeneficiary.balance;
        sale.swapExactOut(key, wantETH, bobTokens, false, bob, block.timestamp);
        vm.stopPrank();

        assertEq(bob.balance - bobEthBefore, wantETH);
        assertGt(feeBeneficiary.balance - feeBenBefore, 0); // beneficiary got ETH tax
    }

    function test_SwapExactOut_Revert_SellWithETH() public {
        address token = _launchAndGraduate(100e18, 0.01e18, 0.01e18, 0, 50e18);
        (IZAMM.PoolKey memory key,) = sale.poolKeyOf(token);

        vm.prank(bob);
        vm.expectRevert(ClassicalCurveSale.InvalidParams.selector);
        sale.swapExactOut{value: 1 ether}(key, 0.01 ether, 1e18, false, bob, block.timestamp);
    }

    // ── Slippage on Routed Swaps ─────────────────────────────────

    function test_SwapExactIn_FeeOnOutput_SlippageRevert() public {
        ClassicalCurveSale.CreatorFee memory cf =
            ClassicalCurveSale.CreatorFee(feeBeneficiary, 1000, 1000, false, false); // 10% output fee
        address token = sale.launch(
            creator,
            "S",
            "S",
            "",
            150e18,
            bytes32(uint256(92)),
            100e18,
            0.01e18,
            0.01e18,
            0,
            0,
            50e18,
            address(0),
            0,
            0,
            0,
            0,
            cf,
            0,
            0
        );

        vm.prank(alice);
        sale.buy{value: 10 ether}(token, 100e18, 100e18);
        sale.graduate(token);

        (IZAMM.PoolKey memory key,) = sale.poolKeyOf(token);

        // Set unreasonably high minOut
        vm.prank(bob);
        vm.expectRevert(ClassicalCurveSale.Slippage.selector);
        sale.swapExactIn{value: 0.01 ether}(
            key, 0.01 ether, type(uint256).max, true, bob, block.timestamp
        );
    }

    // ── Full Lifecycle Test ──────────────────────────────────────

    function test_FullLifecycle() public {
        // 1. Launch with LP tokens, vesting, and creator fee
        ClassicalCurveSale.CreatorFee memory cf =
            ClassicalCurveSale.CreatorFee(feeBeneficiary, 300, 300, true, true);
        address token = sale.launch(
            creator,
            "LIFE",
            "LIFE",
            "https://example.com",
            2000e18,
            bytes32(uint256(42)),
            1000e18,
            0.005e18,
            0.02e18,
            100, // 1% curve fee
            0,
            500e18,
            alice, // LP tokens to alice
            50, // 0.5% pool fee
            0,
            0,
            0,
            cf,
            uint40(7 days),
            uint40(30 days) // vesting
        );

        // 2. Users buy on curve
        vm.prank(alice);
        sale.buy{value: 50 ether}(token, 500e18, 0);

        vm.prank(bob);
        sale.buyExactIn{value: 50 ether}(token, 0);

        // Verify raisedETH <= balance (contract may hold a bit more due to buyExactIn fee rounding)
        (,,,,,,,, uint256 raisedETH,,,,,) = sale.curves(token);
        assertGe(address(sale).balance, raisedETH);

        // 3. Buy rest to graduate
        uint256 remaining;
        (,, uint256 sold,,,,,,,,,,,) = sale.curves(token);
        remaining = 1000e18 - sold;
        if (remaining > 0) {
            uint256 cost = sale.quote(token, remaining);
            uint256 fee = (cost * 100) / 10_000;
            vm.prank(bob);
            sale.buy{value: cost + fee}(token, remaining, 0);
        }

        assertTrue(sale.graduable(token));

        // 4. Graduate
        uint256 liq = sale.graduate(token);
        assertGt(liq, 0);

        // 5. Post-graduation: routed swaps
        (IZAMM.PoolKey memory key,) = sale.poolKeyOf(token);
        address swapper = address(0xBEEF);
        vm.deal(swapper, 10 ether);

        vm.prank(swapper);
        uint256 tokensOut =
            sale.swapExactIn{value: 0.1 ether}(key, 0.1 ether, 0, true, swapper, block.timestamp);
        assertGt(tokensOut, 0);
        assertGt(feeBeneficiary.balance, 0); // creator fee taken

        // 6. Vesting claim after cliff + partial linear
        vm.warp(block.timestamp + 7 days + 15 days); // cliff + half linear
        vm.prank(creator);
        sale.claimVested(token);
        assertGt(ERC20(token).balanceOf(creator), 0);
        assertLt(ERC20(token).balanceOf(creator), 500e18); // partial
    }

    // ── Fuzz Tests (fork) ────────────────────────────────────────

    function test_Fuzz_Graduate_VaryingLPRatio(uint256 lpPct) public {
        // Fuzz LP token allocation as a percentage of cap
        lpPct = bound(lpPct, 1, 200); // 1% to 200% of cap
        uint256 cap = 100e18;
        uint256 lpTokens = cap * lpPct / 100;

        address token = _launch(cap, 0.01e18, 0.01e18, 0, 0, lpTokens, 0);

        // Buy full cap
        uint256 cost = sale.quote(token, cap);
        vm.prank(alice);
        sale.buy{value: cost}(token, cap, 0);

        assertTrue(sale.graduable(token));

        uint256 liq = sale.graduate(token);
        assertGt(liq, 0, "should produce liquidity");

        (,,,,,,,,,,,,, bool seeded) = sale.curves(token);
        assertTrue(seeded);
    }

    function test_Fuzz_Graduate_VaryingETHTarget(uint256 targetPct) public {
        // Fuzz graduation target as percentage of max ETH
        uint256 cap = 100e18;
        uint256 lpTokens = 50e18;

        // First compute max ETH
        address probe = _launch(cap, 0.01e18, 0.01e18, 0, 0, lpTokens, 0);
        uint256 maxETH = sale.quote(probe, cap);

        // Graduate via target
        targetPct = bound(targetPct, 10, 100); // 10% to 100% of max
        uint256 target = maxETH * targetPct / 100;

        address token = sale.launch(
            creator,
            "F",
            "F",
            "",
            cap + lpTokens,
            bytes32(uint256(targetPct + 1000)),
            cap,
            0.01e18,
            0.01e18,
            0,
            target,
            lpTokens,
            address(0),
            0,
            0,
            0,
            0,
            NO_FEE,
            0,
            0
        );

        // Buy until graduated
        vm.prank(alice);
        sale.buy{value: maxETH}(token, cap, 0);

        if (sale.graduable(token)) {
            uint256 liq = sale.graduate(token);
            assertGt(liq, 0);
        }
    }

    function test_Fuzz_SwapExactIn_BuyVaryingAmounts(uint256 ethIn) public {
        address token = _launchAndGraduate(100e18, 0.01e18, 0.01e18, 0, 50e18);
        (IZAMM.PoolKey memory key,) = sale.poolKeyOf(token);

        ethIn = bound(ethIn, 0.001 ether, 0.5 ether);
        vm.deal(bob, ethIn);
        vm.prank(bob);
        uint256 out = sale.swapExactIn{value: ethIn}(key, ethIn, 0, true, bob, block.timestamp);
        assertGt(out, 0);
        assertEq(ERC20(token).balanceOf(bob), out);
    }
}
