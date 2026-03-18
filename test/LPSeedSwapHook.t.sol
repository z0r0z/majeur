// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Moloch, Shares, Loot} from "../src/Moloch.sol";
import {SafeSummoner, Call, ILPSeedSwapHook} from "../src/peripheral/SafeSummoner.sol";
import {ShareSale} from "../src/peripheral/ShareSale.sol";
import {LPSeedSwapHook, IZAMM} from "../src/peripheral/LPSeedSwapHook.sol";

/// @dev Minimal mock ERC20 with configurable decimals.
contract MockERC20_6d {
    string public name = "Mock USDC";
    string public symbol = "MUSDC";
    uint8 public decimals = 6;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

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

/// @dev Minimal mock ERC20 for the "other side" of the LP pair.
contract MockERC20 {
    string public name = "Mock";
    string public symbol = "MCK";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

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

contract LPSeedSwapHookTest is Test {
    SafeSummoner internal safe;
    LPSeedSwapHook internal lpSeed;
    ShareSale internal shareSale;
    MockERC20 internal usdc;
    MockERC20_6d internal usdc6;

    address internal alice = address(0xA11CE);
    address internal bob = address(0x0B0B);

    function setUp() public {
        vm.createSelectFork("main");
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        safe = new SafeSummoner();
        lpSeed = new LPSeedSwapHook();
        shareSale = new ShareSale();
        usdc = new MockERC20();
        usdc6 = new MockERC20_6d();
    }

    // ── Helpers ──────────────────────────────────────────────────

    /// @dev Deploy a DAO with LPSeedSwapHook configured for ETH + shares pair.
    function _deployWithSeed(
        bytes32 salt,
        uint128 amtA,
        uint128 amtB,
        uint40 deadline,
        address shareSaleAddr,
        uint128 minSupply
    ) internal returns (address dao, address sharesAddr) {
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        dao = safe.predictDAO(salt, h, s);
        sharesAddr = safe.predictShares(dao);

        // Build extra initCalls:
        // 1. setAllowance(lpSeed, address(0), amtA)  -- ETH side (regular transfer)
        // 2. setAllowance(lpSeed, dao, amtB)          -- shares mint sentinel
        // 3. lpSeed.configure(...) with mintTokenB = dao (mint-on-spend)
        Call[] memory extra = new Call[](3);

        // ETH allowance (regular transfer path)
        extra[0] =
            Call(dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), address(0), amtA)));

        // Shares allowance on Moloch mint sentinel (address(dao) = mint shares on spend)
        extra[1] = Call(dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), dao, amtB)));

        // Configure LPSeedSwapHook with mintTokenB = dao (shares mint sentinel)
        extra[2] = Call(
            address(lpSeed),
            0,
            abi.encodeWithSignature(
                "configure(address,uint128,address,uint128,uint16,uint40,address,uint128,address,address)",
                address(0),
                amtA,
                sharesAddr,
                amtB,
                uint16(0),
                deadline,
                shareSaleAddr,
                minSupply,
                address(0),
                dao
            )
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        address deployed = safe.safeSummon(
            "SeedDAO", "SEED", "", 1000, true, address(0), salt, h, s, new uint256[](0), c, extra
        );
        assertEq(deployed, dao);

        // Fund DAO with ETH for LP
        vm.deal(dao, uint256(amtA) + 10 ether);
    }

    /// @dev Deploy a DAO with ShareSale + LPSeedSwapHook (sale completion gate).
    function _deployWithSaleAndSeed(
        bytes32 salt,
        uint256 saleCap,
        uint128 seedAmtA,
        uint128 seedAmtB
    ) internal returns (address dao, address sharesAddr) {
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        dao = safe.predictDAO(salt, h, s);
        sharesAddr = safe.predictShares(dao);

        // 6 initCalls: ShareSale setup (2) + mint shares for seed (1) + LPSeedSwapHook setup (3)
        Call[] memory extra = new Call[](6);

        // ShareSale: setAllowance + configure
        extra[0] =
            Call(dao, 0, abi.encodeCall(Moloch.setAllowance, (address(shareSale), dao, saleCap)));
        extra[1] = Call(
            address(shareSale),
            0,
            abi.encodeCall(shareSale.configure, (dao, address(0), 1e18, uint40(0)))
        );

        // Mint shares to DAO for LP seeding
        extra[2] = Call(sharesAddr, 0, abi.encodeCall(Shares.mintFromMoloch, (dao, seedAmtB)));

        // LPSeedSwapHook: setAllowance(ETH) + setAllowance(shares) + configure
        extra[3] = Call(
            dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), address(0), seedAmtA))
        );
        extra[4] = Call(
            dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), sharesAddr, seedAmtB))
        );
        extra[5] = Call(
            address(lpSeed),
            0,
            abi.encodeCall(
                ILPSeedSwapHook.configure,
                (
                    address(0),
                    seedAmtA,
                    sharesAddr,
                    seedAmtB,
                    0, // no deadline gate
                    address(shareSale), // sale completion gate
                    0 // no minSupply gate
                )
            )
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        address deployed = safe.safeSummon(
            "SaleSeedDAO",
            "SSEED",
            "",
            1000,
            true,
            address(0),
            salt,
            h,
            s,
            new uint256[](0),
            c,
            extra
        );
        assertEq(deployed, dao);

        vm.deal(dao, uint256(seedAmtA) + 100 ether);
    }

    // ── Configuration Tests ─────────────────────────────────────

    function test_Configure() public {
        (address dao, address sharesAddr) =
            _deployWithSeed(bytes32(uint256(1)), 1e18, 1000e18, 0, address(0), 0);

        (
            address tokenA,
            address tokenB,
            uint128 amountA,
            uint128 amountB,
            uint16 feeBps,
            uint16 launchBps,
            uint40 deadline,
            uint40 decayPeriod,
            address shareSaleGate,
            uint128 minSupply,,
            uint40 seeded,,
        ) = lpSeed.seeds(dao);

        assertEq(tokenA, address(0));
        assertEq(tokenB, sharesAddr);
        assertEq(amountA, 1e18);
        assertEq(amountB, 1000e18);
        assertEq(feeBps, 0);
        assertEq(launchBps, 0);
        assertEq(deadline, 0);
        assertEq(decayPeriod, 0);
        assertEq(shareSaleGate, address(0));
        assertEq(minSupply, 0);
        assertEq(seeded, 0);
    }

    function test_RevertIf_ConfigureZeroAmounts() public {
        vm.prank(alice);
        vm.expectRevert(LPSeedSwapHook.InvalidParams.selector);
        lpSeed.configure(address(0), 0, address(1), 100, 0, address(0), 0);
    }

    function test_RevertIf_ConfigureZeroTokenB() public {
        vm.prank(alice);
        vm.expectRevert(LPSeedSwapHook.InvalidParams.selector);
        lpSeed.configure(address(0), 100, address(0), 100, 0, address(0), 0);
    }

    function test_RevertIf_ConfigureSameTokens() public {
        vm.prank(alice);
        vm.expectRevert(LPSeedSwapHook.InvalidParams.selector);
        lpSeed.configure(address(1), 100, address(1), 100, 0, address(0), 0);
    }

    // ── Gating: Deadline ─────────────────────────────────────────

    function test_Seedable_DeadlineNotReached() public {
        uint40 deadline = uint40(block.timestamp + 7 days);
        (address dao,) =
            _deployWithSeed(bytes32(uint256(10)), 1e18, 1000e18, deadline, address(0), 0);

        assertFalse(lpSeed.seedable(dao));
    }

    function test_Seedable_DeadlinePassed() public {
        uint40 deadline = uint40(block.timestamp + 7 days);
        (address dao,) =
            _deployWithSeed(bytes32(uint256(11)), 1e18, 1000e18, deadline, address(0), 0);

        vm.warp(deadline + 1);
        assertTrue(lpSeed.seedable(dao));
    }

    function test_RevertIf_SeedBeforeDeadline() public {
        uint40 deadline = uint40(block.timestamp + 7 days);
        (address dao,) =
            _deployWithSeed(bytes32(uint256(12)), 1e18, 1000e18, deadline, address(0), 0);

        vm.expectRevert(LPSeedSwapHook.NotReady.selector);
        lpSeed.seed(dao);
    }

    // ── Gating: ShareSale Completion ─────────────────────────────

    function test_Seedable_SaleNotComplete() public {
        (address dao,) = _deployWithSaleAndSeed(bytes32(uint256(20)), 10e18, 1e18, 1000e18);

        // Sale still has allowance remaining
        assertFalse(lpSeed.seedable(dao));
    }

    function test_Seedable_SaleComplete() public {
        (address dao,) = _deployWithSaleAndSeed(bytes32(uint256(21)), 10e18, 1e18, 1000e18);

        // Buy all 10e18 shares to exhaust allowance
        vm.prank(bob);
        shareSale.buy{value: 10e18}(dao, 10e18);

        // Sale allowance now 0
        assertTrue(lpSeed.seedable(dao));
    }

    function test_RevertIf_SeedBeforeSaleComplete() public {
        (address dao,) = _deployWithSaleAndSeed(bytes32(uint256(22)), 10e18, 1e18, 1000e18);

        vm.expectRevert(LPSeedSwapHook.NotReady.selector);
        lpSeed.seed(dao);
    }

    // ── Gating: MinSupply ────────────────────────────────────────

    function test_Seedable_MinSupplyNotMet() public {
        (address dao, address sharesAddr) =
            _deployWithSeed(bytes32(uint256(30)), 1e18, 100e18, 0, address(0), 50e18);

        // Mint extra shares to DAO to exceed minSupply threshold
        vm.prank(dao);
        Shares(sharesAddr).mintFromMoloch(dao, 100e18);

        uint256 daoBal = Shares(sharesAddr).balanceOf(dao);
        assertTrue(daoBal > 50e18);
        assertFalse(lpSeed.seedable(dao));
    }

    function test_Seedable_MinSupplyMet() public {
        (address dao, address sharesAddr) =
            _deployWithSeed(bytes32(uint256(31)), 1e18, 100e18, 0, address(0), 200e18);

        // With allowance-based minting, DAO has no pre-minted shares.
        // DAO balance = 0, which is <= minSupply (200e18), so seedable.
        uint256 daoBal = Shares(sharesAddr).balanceOf(dao);
        assertTrue(daoBal <= 200e18);
        assertTrue(lpSeed.seedable(dao));
    }

    // ── Cancel ───────────────────────────────────────────────────

    function test_Cancel() public {
        (address dao,) = _deployWithSeed(bytes32(uint256(40)), 1e18, 1000e18, 0, address(0), 0);

        vm.prank(dao);
        lpSeed.cancel();

        (,, uint128 amtA,,,,,,,,, uint40 seeded,,) = lpSeed.seeds(dao);
        assertEq(amtA, 0); // config cleared
        assertEq(seeded, 0);
    }

    function test_RevertIf_CancelNotConfigured() public {
        vm.prank(address(0xdead));
        vm.expectRevert(LPSeedSwapHook.NotConfigured.selector);
        lpSeed.cancel();
    }

    function test_Seedable_AfterCancel() public {
        (address dao,) = _deployWithSeed(bytes32(uint256(41)), 1e18, 1000e18, 0, address(0), 0);

        vm.prank(dao);
        lpSeed.cancel();

        assertFalse(lpSeed.seedable(dao));
    }

    // ── Seed: Not Configured / Already Seeded ────────────────────

    function test_RevertIf_SeedNotConfigured() public {
        vm.expectRevert(LPSeedSwapHook.NotConfigured.selector);
        lpSeed.seed(address(0xdead));
    }

    // ── Combined Gates ───────────────────────────────────────────

    function test_Seedable_CombinedDeadlineAndSale() public {
        // Deploy with both deadline and sale gates
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        bytes32 salt = bytes32(uint256(50));
        address dao = safe.predictDAO(salt, h, s);
        address sharesAddr = safe.predictShares(dao);

        uint40 deadline = uint40(block.timestamp + 7 days);

        Call[] memory extra = new Call[](6);

        // ShareSale setup
        extra[0] =
            Call(dao, 0, abi.encodeCall(Moloch.setAllowance, (address(shareSale), dao, 5e18)));
        extra[1] = Call(
            address(shareSale),
            0,
            abi.encodeCall(shareSale.configure, (dao, address(0), 1e18, uint40(0)))
        );

        // Mint shares for seed
        extra[2] = Call(sharesAddr, 0, abi.encodeCall(Shares.mintFromMoloch, (dao, 100e18)));

        // LPSeedSwapHook setup
        extra[3] =
            Call(dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), address(0), 1e18)));
        extra[4] = Call(
            dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), sharesAddr, 100e18))
        );
        extra[5] = Call(
            address(lpSeed),
            0,
            abi.encodeCall(
                ILPSeedSwapHook.configure,
                (address(0), 1e18, sharesAddr, 100e18, deadline, address(shareSale), 0)
            )
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        safe.safeSummon(
            "ComboDAO", "COMBO", "", 1000, true, address(0), salt, h, s, new uint256[](0), c, extra
        );
        vm.deal(dao, 10 ether);

        // Neither condition met
        assertFalse(lpSeed.seedable(dao));

        // Sale complete before deadline — still blocked by deadline
        vm.prank(bob);
        shareSale.buy{value: 5e18}(dao, 5e18);
        assertFalse(lpSeed.seedable(dao)); // deadline not reached

        // After deadline — seedable (sale done + deadline passed)
        vm.warp(deadline + 1);
        assertTrue(lpSeed.seedable(dao));
    }

    // ── Seed: Actual LP (via ZAMM on fork) ───────────────────────

    function test_Seed_ERC20Pair() public {
        // Deploy DAO with ERC20 (usdc) + shares LP seed (no gates)
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        bytes32 salt = bytes32(uint256(60));
        address dao = safe.predictDAO(salt, h, s);
        address sharesAddr = safe.predictShares(dao);

        uint128 usdcAmt = 1000e18; // mock has 18 decimals
        uint128 sharesAmt = 1000e18;

        Call[] memory extra = new Call[](4);

        // Mint shares to DAO
        extra[0] = Call(sharesAddr, 0, abi.encodeCall(Shares.mintFromMoloch, (dao, sharesAmt)));

        // setAllowance for USDC
        extra[1] = Call(
            dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), address(usdc), usdcAmt))
        );

        // setAllowance for shares
        extra[2] = Call(
            dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), sharesAddr, sharesAmt))
        );

        // Configure LPSeedSwapHook
        extra[3] = Call(
            address(lpSeed),
            0,
            abi.encodeCall(
                ILPSeedSwapHook.configure,
                (address(usdc), usdcAmt, sharesAddr, sharesAmt, 0, address(0), 0)
            )
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        address deployed = safe.safeSummon(
            "LPTestDAO", "LPTST", "", 1000, true, address(0), salt, h, s, new uint256[](0), c, extra
        );
        assertEq(deployed, dao);

        // Fund DAO with USDC via mint
        usdc.mint(dao, usdcAmt);

        assertTrue(lpSeed.seedable(dao));

        // Seed LP
        lpSeed.seed(dao);

        // Verify seeded timestamp
        (,,,,,,,,,,, uint40 seeded,,) = lpSeed.seeds(dao);
        assertTrue(seeded != 0);

        // Verify cannot seed again
        vm.expectRevert(LPSeedSwapHook.AlreadySeeded.selector);
        lpSeed.seed(dao);
    }

    // ── Init Call Helper ─────────────────────────────────────────

    function test_SeedInitCallsHelper() public view {
        address dao = address(0xDA0);
        address sharesAddr = address(0x54A8E);
        // mintTokenB = dao → shares mint sentinel for allowance-based minting
        (address[3] memory targets, bytes[3] memory data) = lpSeed.seedInitCalls(
            dao, address(0), 1e18, sharesAddr, 1000e18, 0, 0, address(0), 0, address(0), dao
        );

        assertEq(targets[0], dao); // setAllowance tokenA (ETH)
        assertEq(targets[1], dao); // setAllowance tokenB (shares mint sentinel)
        assertEq(targets[2], address(lpSeed)); // configure
        assertTrue(data[0].length > 0);
        assertTrue(data[1].length > 0);
        assertTrue(data[2].length > 0);
    }

    // ── Seedable: Not configured ─────────────────────────────────

    function test_Seedable_NotConfigured() public view {
        assertFalse(lpSeed.seedable(address(0xdead)));
    }

    // ── Hook: hookFeeOrHook ──────────────────────────────────────

    function test_HookFeeOrHook() public view {
        uint256 val = lpSeed.hookFeeOrHook();
        // Should encode address with FLAG_BEFORE
        assertEq(val & uint256(uint160(address(lpSeed))), uint256(uint160(address(lpSeed))));
        assertTrue(val > 10_000); // hook mode, not fee mode
    }

    // ── setFee ────────────────────────────────────────────────────

    function test_SetFee() public {
        (address dao,) = _deployWithSeed(bytes32(uint256(70)), 1e18, 1000e18, 0, address(0), 0);

        vm.prank(dao);
        lpSeed.setFee(50); // 50 bps = 0.5%

        (,,,, uint16 feeBps,,,,,,,,,) = lpSeed.seeds(dao);
        assertEq(feeBps, 50);
    }

    function test_SetFee_ToZero() public {
        (address dao,) = _deployWithSeed(bytes32(uint256(71)), 1e18, 1000e18, 0, address(0), 0);

        vm.prank(dao);
        lpSeed.setFee(50);

        vm.prank(dao);
        lpSeed.setFee(0); // reset to default

        (,,,, uint16 feeBps,,,,,,,,,) = lpSeed.seeds(dao);
        assertEq(feeBps, 0);
    }

    function test_RevertIf_SetFeeAboveMax() public {
        (address dao,) = _deployWithSeed(bytes32(uint256(72)), 1e18, 1000e18, 0, address(0), 0);

        vm.prank(dao);
        vm.expectRevert(LPSeedSwapHook.InvalidParams.selector);
        lpSeed.setFee(10_001);
    }

    function test_RevertIf_SetFeeNotConfigured() public {
        vm.prank(address(0xdead));
        vm.expectRevert(LPSeedSwapHook.NotConfigured.selector);
        lpSeed.setFee(50);
    }

    function test_RevertIf_SetFeeNotDAO() public {
        _deployWithSeed(bytes32(uint256(73)), 1e18, 1000e18, 0, address(0), 0);

        vm.prank(bob);
        vm.expectRevert(LPSeedSwapHook.NotConfigured.selector);
        lpSeed.setFee(50);
    }

    // ── Configure with custom fee ──────────────────────────────────

    function test_Configure_WithFee() public {
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        bytes32 salt = bytes32(uint256(100));
        address dao = safe.predictDAO(salt, h, s);
        address sharesAddr = safe.predictShares(dao);

        Call[] memory extra = new Call[](4);
        extra[0] = Call(sharesAddr, 0, abi.encodeCall(Shares.mintFromMoloch, (dao, 100e18)));
        extra[1] =
            Call(dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), address(0), 1e18)));
        extra[2] = Call(
            dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), sharesAddr, 100e18))
        );
        // Use the 8-param configure with feeBps=100 (1%)
        extra[3] = Call(
            address(lpSeed),
            0,
            abi.encodeWithSignature(
                "configure(address,uint128,address,uint128,uint16,uint40,address,uint128)",
                address(0),
                uint128(1e18),
                sharesAddr,
                uint128(100e18),
                uint16(100),
                uint40(0),
                address(0),
                uint128(0)
            )
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        safe.safeSummon(
            "FeeDAO", "FEE", "", 1000, true, address(0), salt, h, s, new uint256[](0), c, extra
        );

        (,,,, uint16 feeBps,,,,,,,,,) = lpSeed.seeds(dao);
        assertEq(feeBps, 100);
    }

    function test_RevertIf_Configure_FeeAboveMax() public {
        vm.prank(alice);
        vm.expectRevert(LPSeedSwapHook.InvalidParams.selector);
        lpSeed.configure(address(0), 1e18, address(1), 1e18, 10_001, 0, address(0), 0);
    }

    // ── Sale deadline bypass (dust mitigation) ────────────────────

    function test_Seedable_SaleNoDealine_WithDust_Blocked() public {
        (address dao,) = _deployWithSaleAndSeed(bytes32(uint256(110)), 10e18, 1e18, 1000e18);

        // Buy 9e18 out of 10e18 — 1e18 dust remains
        vm.prank(bob);
        shareSale.buy{value: 9e18}(dao, 9e18);

        // Sale has no deadline (0) AND LPSeed has no deadline (0) — dust blocks seeding
        assertFalse(lpSeed.seedable(dao));
    }

    function test_Seedable_SaleNoDeadline_WithDust_LPSeedDeadlineBypass() public {
        // Deploy with sale gate (no sale deadline) + LPSeed deadline as backstop
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        bytes32 salt = bytes32(uint256(112));
        address dao = safe.predictDAO(salt, h, s);
        address sharesAddr = safe.predictShares(dao);

        uint40 lpDeadline = uint40(block.timestamp + 14 days);

        Call[] memory extra = new Call[](6);

        // ShareSale with NO deadline
        extra[0] =
            Call(dao, 0, abi.encodeCall(Moloch.setAllowance, (address(shareSale), dao, 10e18)));
        extra[1] = Call(
            address(shareSale),
            0,
            abi.encodeCall(shareSale.configure, (dao, address(0), 1e18, uint40(0)))
        );

        // Mint shares for seed
        extra[2] = Call(sharesAddr, 0, abi.encodeCall(Shares.mintFromMoloch, (dao, 100e18)));

        // LPSeedSwapHook with shareSale gate + LPSeed deadline as backstop
        extra[3] =
            Call(dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), address(0), 1e18)));
        extra[4] = Call(
            dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), sharesAddr, 100e18))
        );
        extra[5] = Call(
            address(lpSeed),
            0,
            abi.encodeCall(
                ILPSeedSwapHook.configure,
                (address(0), 1e18, sharesAddr, 100e18, lpDeadline, address(shareSale), 0)
            )
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        safe.safeSummon(
            "DustFixDAO", "DFIX", "", 1000, true, address(0), salt, h, s, new uint256[](0), c, extra
        );
        vm.deal(dao, 10 ether);

        // Buy 9e18, leaving 1e18 dust. Sale has no deadline.
        vm.prank(bob);
        shareSale.buy{value: 9e18}(dao, 9e18);

        // Before LPSeed deadline — blocked
        assertFalse(lpSeed.seedable(dao));

        // After LPSeed deadline — bypasses sale dust
        vm.warp(lpDeadline + 1);
        assertTrue(lpSeed.seedable(dao));
    }

    function test_Seedable_SaleDeadlinePassed_WithDust_Bypass() public {
        // Deploy with both sale gate and explicit sale deadline
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        bytes32 salt = bytes32(uint256(111));
        address dao = safe.predictDAO(salt, h, s);
        address sharesAddr = safe.predictShares(dao);

        uint40 saleDeadline = uint40(block.timestamp + 7 days);

        Call[] memory extra = new Call[](6);

        // ShareSale with deadline
        extra[0] =
            Call(dao, 0, abi.encodeCall(Moloch.setAllowance, (address(shareSale), dao, 10e18)));
        extra[1] = Call(
            address(shareSale),
            0,
            abi.encodeCall(shareSale.configure, (dao, address(0), 1e18, saleDeadline))
        );

        // Mint shares for seed
        extra[2] = Call(sharesAddr, 0, abi.encodeCall(Shares.mintFromMoloch, (dao, 100e18)));

        // LPSeedSwapHook setup with shareSale gate
        extra[3] =
            Call(dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), address(0), 1e18)));
        extra[4] = Call(
            dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), sharesAddr, 100e18))
        );
        extra[5] = Call(
            address(lpSeed),
            0,
            abi.encodeCall(
                ILPSeedSwapHook.configure,
                (address(0), 1e18, sharesAddr, 100e18, 0, address(shareSale), 0)
            )
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        safe.safeSummon(
            "DustDAO", "DUST", "", 1000, true, address(0), salt, h, s, new uint256[](0), c, extra
        );
        vm.deal(dao, 10 ether);

        // Buy 9e18, leaving 1e18 dust
        vm.prank(bob);
        shareSale.buy{value: 9e18}(dao, 9e18);

        // Before sale deadline — dust blocks
        assertFalse(lpSeed.seedable(dao));

        // After sale deadline — dust bypassed
        vm.warp(saleDeadline + 1);
        assertTrue(lpSeed.seedable(dao));
    }

    // ── Launch Fee Decay ────────────────────────────────────────────

    function test_SetLaunchFee() public {
        (address dao,) = _deployWithSeed(bytes32(uint256(120)), 1e18, 1000e18, 0, address(0), 0);

        vm.prank(dao);
        lpSeed.setLaunchFee(500, 1 days);

        (,,,,, uint16 launchBps,, uint40 decayPeriod,,,,,,) = lpSeed.seeds(dao);
        assertEq(launchBps, 500);
        assertEq(decayPeriod, uint40(1 days));
    }

    function test_RevertIf_SetLaunchFeeNotConfigured() public {
        vm.prank(address(0xdead));
        vm.expectRevert(LPSeedSwapHook.NotConfigured.selector);
        lpSeed.setLaunchFee(500, 1 days);
    }

    function test_RevertIf_SetLaunchFeeAfterSeed() public {
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        bytes32 salt = bytes32(uint256(121));
        address dao = safe.predictDAO(salt, h, s);
        address sharesAddr = safe.predictShares(dao);

        Call[] memory extra = new Call[](4);
        extra[0] = Call(sharesAddr, 0, abi.encodeCall(Shares.mintFromMoloch, (dao, 1000e18)));
        extra[1] = Call(
            dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), address(usdc), 1000e18))
        );
        extra[2] = Call(
            dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), sharesAddr, 1000e18))
        );
        extra[3] = Call(
            address(lpSeed),
            0,
            abi.encodeCall(
                ILPSeedSwapHook.configure,
                (address(usdc), 1000e18, sharesAddr, 1000e18, 0, address(0), 0)
            )
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        safe.safeSummon(
            "LaunchDAO", "LNCH", "", 1000, true, address(0), salt, h, s, new uint256[](0), c, extra
        );

        usdc.mint(dao, 1000e18);
        lpSeed.seed(dao);

        // Can't set launch fee after seeding
        vm.prank(dao);
        vm.expectRevert(LPSeedSwapHook.AlreadySeeded.selector);
        lpSeed.setLaunchFee(500, 1 days);
    }

    function test_RevertIf_SetLaunchFeeAboveMax() public {
        (address dao,) = _deployWithSeed(bytes32(uint256(122)), 1e18, 1000e18, 0, address(0), 0);

        vm.prank(dao);
        vm.expectRevert(LPSeedSwapHook.InvalidParams.selector);
        lpSeed.setLaunchFee(10_001, 1 days);
    }

    function test_LaunchFeeInitCallHelper() public view {
        (address target, uint256 value, bytes memory data) = lpSeed.launchFeeInitCall(500, 1 days);

        assertEq(target, address(lpSeed));
        assertEq(value, 0);
        assertTrue(data.length > 0);
    }

    function test_LaunchFeeInitCallHelper_Encoding() public view {
        (,, bytes memory data) = lpSeed.launchFeeInitCall(500, 1 days);

        // Should encode setLaunchFee(500, 86400)
        bytes memory expected = abi.encodeCall(lpSeed.setLaunchFee, (500, 1 days));
        assertEq(keccak256(data), keccak256(expected));
    }

    // ── DAO Fee ─────────────────────────────────────────────────────

    function test_SetDaoFee() public {
        (address dao,) = _deployWithSeed(bytes32(uint256(130)), 1e18, 1000e18, 0, address(0), 0);

        vm.prank(dao);
        lpSeed.setDaoFee(address(0xBEEF), 100, 200, false, false);

        (address ben, uint16 buyBps, uint16 sellBps, bool buyOnInput, bool sellOnInput) =
            lpSeed.daoFees(dao);
        assertEq(ben, address(0xBEEF));
        assertEq(buyBps, 100);
        assertEq(sellBps, 200);
        assertFalse(buyOnInput);
        assertFalse(sellOnInput);
    }

    function test_SetDaoFee_AlwaysETH() public {
        (address dao,) = _deployWithSeed(bytes32(uint256(132)), 1e18, 1000e18, 0, address(0), 0);

        // Fee always in ETH (token0): buy=input(ETH), sell=output(ETH)
        vm.prank(dao);
        lpSeed.setDaoFee(address(0xBEEF), 100, 100, true, false);

        (, uint16 buyBps, uint16 sellBps, bool buyOnInput, bool sellOnInput) = lpSeed.daoFees(dao);
        assertEq(buyBps, 100);
        assertEq(sellBps, 100);
        assertTrue(buyOnInput); // buy: fee on input = ETH
        assertFalse(sellOnInput); // sell: fee on output = ETH
    }

    function test_SetDaoFee_Directional() public {
        (address dao,) = _deployWithSeed(bytes32(uint256(134)), 1e18, 1000e18, 0, address(0), 0);

        // Buy fee only, no sell fee
        vm.prank(dao);
        lpSeed.setDaoFee(address(0xBEEF), 50, 0, true, false);

        (, uint16 buyBps, uint16 sellBps,,) = lpSeed.daoFees(dao);
        assertEq(buyBps, 50);
        assertEq(sellBps, 0);
    }

    function test_SetBeneficiary() public {
        (address dao,) = _deployWithSeed(bytes32(uint256(133)), 1e18, 1000e18, 0, address(0), 0);

        vm.prank(dao);
        lpSeed.setDaoFee(address(0xBEEF), 100, 100, false, false);

        vm.prank(dao);
        lpSeed.setBeneficiary(address(0xFACE));

        (address ben, uint16 buyBps,,,) = lpSeed.daoFees(dao);
        assertEq(ben, address(0xFACE));
        assertEq(buyBps, 100);
    }

    function test_RevertIf_SetDaoFeeNotConfigured() public {
        vm.prank(address(0xdead));
        vm.expectRevert(LPSeedSwapHook.NotConfigured.selector);
        lpSeed.setDaoFee(address(0xBEEF), 100, 100, false, false);
    }

    function test_RevertIf_SetDaoFeeAboveMax() public {
        (address dao,) = _deployWithSeed(bytes32(uint256(131)), 1e18, 1000e18, 0, address(0), 0);

        vm.prank(dao);
        vm.expectRevert(LPSeedSwapHook.InvalidParams.selector);
        lpSeed.setDaoFee(address(0xBEEF), 10_001, 0, false, false);
    }

    function test_DaoFeeInitCallHelper() public view {
        (address target, uint256 value, bytes memory data) =
            lpSeed.daoFeeInitCall(address(0xBEEF), 100, 200, true, false);

        assertEq(target, address(lpSeed));
        assertEq(value, 0);
        bytes memory expected =
            abi.encodeCall(lpSeed.setDaoFee, (address(0xBEEF), 100, 200, true, false));
        assertEq(keccak256(data), keccak256(expected));
    }

    // ── View Helpers ──────────────────────────────────────────────

    function test_PoolKeyOf() public {
        (address dao, address sharesAddr) =
            _deployWithSeed(bytes32(uint256(140)), 1e18, 1000e18, 0, address(0), 0);

        (IZAMM.PoolKey memory key, uint256 poolId) = lpSeed.poolKeyOf(dao);

        // ETH is address(0) → always token0
        assertEq(key.token0, address(0));
        assertEq(key.token1, sharesAddr);
        assertEq(key.feeOrHook, lpSeed.hookFeeOrHook());
        assertTrue(poolId != 0);

        // poolId matches what poolDAO was set to
        assertEq(lpSeed.poolDAO(poolId), dao);
    }

    function test_RevertIf_PoolKeyOfNotConfigured() public {
        vm.expectRevert(LPSeedSwapHook.NotConfigured.selector);
        lpSeed.poolKeyOf(address(0xdead));
    }

    function test_EffectiveFee_Default() public {
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        bytes32 salt = bytes32(uint256(142));
        address dao = safe.predictDAO(salt, h, s);
        address sharesAddr = safe.predictShares(dao);

        Call[] memory extra = new Call[](4);
        extra[0] = Call(sharesAddr, 0, abi.encodeCall(Shares.mintFromMoloch, (dao, 1000e18)));
        extra[1] = Call(
            dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), address(usdc), 1000e18))
        );
        extra[2] = Call(
            dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), sharesAddr, 1000e18))
        );
        extra[3] = Call(
            address(lpSeed),
            0,
            abi.encodeCall(
                ILPSeedSwapHook.configure,
                (address(usdc), 1000e18, sharesAddr, 1000e18, 0, address(0), 0)
            )
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        safe.safeSummon(
            "ViewDAO", "VIEW", "", 1000, true, address(0), salt, h, s, new uint256[](0), c, extra
        );
        usdc.mint(dao, 1000e18);

        // Before seeding: 0
        assertEq(lpSeed.effectiveFee(dao), 0);

        lpSeed.seed(dao);

        // After seeding with feeBps=0: returns DEFAULT (30)
        assertEq(lpSeed.effectiveFee(dao), 30);
    }

    function test_QuoteSwap() public {
        (address dao, address sharesAddr) =
            _deployWithSeed(bytes32(uint256(143)), 1e18, 1000e18, 0, address(0), 0);

        // No DAO fee — returns pool key, zero fees, zero beneficiary
        (IZAMM.PoolKey memory key, uint256 poolFee, uint256 daoFee, bool onInput, address ben) =
            lpSeed.quoteSwap(dao, true);
        assertEq(key.token0, address(0)); // ETH
        assertEq(key.token1, sharesAddr);
        assertEq(poolFee, 0); // not seeded
        assertEq(daoFee, 0);
        assertEq(ben, address(0));

        // Set DAO fee and quote buy direction
        vm.prank(dao);
        lpSeed.setDaoFee(address(0xBEEF), 100, 200, true, false);

        (key, poolFee, daoFee, onInput, ben) = lpSeed.quoteSwap(dao, true);
        assertEq(key.token0, address(0));
        assertEq(daoFee, 100); // buyBps
        assertTrue(onInput); // buyOnInput
        assertEq(ben, address(0xBEEF));

        // Quote sell direction
        (, poolFee, daoFee, onInput, ben) = lpSeed.quoteSwap(dao, false);
        assertEq(daoFee, 200); // sellBps
        assertFalse(onInput); // sellOnInput
    }

    // ── Quoter: ExactIn / ExactOut ──────────────────────────────

    /// @dev Helper: deploy DAO, seed ERC20+shares LP, return (dao, sharesAddr, poolKey)
    function _deployAndSeedERC20(bytes32 salt, uint128 usdcAmt, uint128 sharesAmt)
        internal
        returns (address dao, address sharesAddr)
    {
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        dao = safe.predictDAO(salt, h, s);
        sharesAddr = safe.predictShares(dao);

        Call[] memory extra = new Call[](4);
        extra[0] = Call(sharesAddr, 0, abi.encodeCall(Shares.mintFromMoloch, (dao, sharesAmt)));
        extra[1] = Call(
            dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), address(usdc), usdcAmt))
        );
        extra[2] = Call(
            dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), sharesAddr, sharesAmt))
        );
        extra[3] = Call(
            address(lpSeed),
            0,
            abi.encodeCall(
                ILPSeedSwapHook.configure,
                (address(usdc), usdcAmt, sharesAddr, sharesAmt, 0, address(0), 0)
            )
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        safe.safeSummon(
            "QuoteDAO", "QTE", "", 1000, true, address(0), salt, h, s, new uint256[](0), c, extra
        );
        usdc.mint(dao, usdcAmt);
        lpSeed.seed(dao);
    }

    function test_QuoteExactIn_NoDaoFee() public {
        (address dao,) = _deployAndSeedERC20(bytes32(uint256(150)), 1000e18, 1000e18);

        (uint256 amountOut, uint256 daoTax) = lpSeed.quoteExactIn(dao, 10e18, true);

        // With 30 bps pool fee, 1000/1000 reserves, 10e18 in:
        // amountInWithFee = 10e18 * 9970 = 99.7e21
        // numerator = 99.7e21 * 1000e18
        // denominator = 1000e18 * 10000 + 99.7e21
        // Expected ~9.87e18
        assertTrue(amountOut > 9.8e18 && amountOut < 10e18);
        assertEq(daoTax, 0);
    }

    function test_QuoteExactIn_WithDaoFee_OnInput() public {
        (address dao,) = _deployAndSeedERC20(bytes32(uint256(151)), 1000e18, 1000e18);

        // Quote without DAO fee first
        (uint256 noFeeOut,) = lpSeed.quoteExactIn(dao, 9.9e18, true);

        // Set 1% DAO fee on buy input
        vm.prank(dao);
        lpSeed.setDaoFee(address(0xBEEF), 100, 100, true, true);

        (uint256 amountOut, uint256 daoTax) = lpSeed.quoteExactIn(dao, 10e18, true);

        // 1% tax on input: daoTax = 0.1e18, net input = 9.9e18
        assertEq(daoTax, 0.1e18);
        assertTrue(amountOut > 0);
        // Should match a no-fee quote with 9.9e18 input (since 10e18 - 1% = 9.9e18)
        assertEq(amountOut, noFeeOut);
    }

    function test_QuoteExactIn_WithDaoFee_OnOutput() public {
        (address dao,) = _deployAndSeedERC20(bytes32(uint256(152)), 1000e18, 1000e18);

        // Set 2% DAO fee on buy output
        vm.prank(dao);
        lpSeed.setDaoFee(address(0xBEEF), 200, 200, false, false);

        (uint256 amountOut, uint256 daoTax) = lpSeed.quoteExactIn(dao, 10e18, true);

        // Full 10e18 goes to ZAMM, then 2% of output is taxed
        assertTrue(daoTax > 0);
        assertTrue(amountOut > 0);
        // daoTax should be ~2% of (amountOut + daoTax)
        uint256 gross = amountOut + daoTax;
        assertEq(daoTax, (gross * 200) / 10_000);
    }

    function test_QuoteExactOut_NoDaoFee() public {
        (address dao,) = _deployAndSeedERC20(bytes32(uint256(153)), 1000e18, 1000e18);

        (uint256 amountIn, uint256 daoTax) = lpSeed.quoteExactOut(dao, 10e18, true);

        // To get 10e18 out of 1000/1000 pool with 30 bps:
        // amountIn = ceil(1000e18 * 10e18 * 10000 / (990e18 * 9970))
        assertTrue(amountIn > 10e18); // must pay more than output due to fees + price impact
        assertEq(daoTax, 0);
    }

    function test_QuoteExactOut_WithDaoFee_OnInput() public {
        (address dao,) = _deployAndSeedERC20(bytes32(uint256(154)), 1000e18, 1000e18);

        // 1% DAO fee on input
        vm.prank(dao);
        lpSeed.setDaoFee(address(0xBEEF), 100, 100, true, true);

        (uint256 amountIn, uint256 daoTax) = lpSeed.quoteExactOut(dao, 10e18, true);

        // amountIn includes DAO tax
        assertTrue(daoTax > 0);
        assertTrue(amountIn > daoTax);

        // daoTax / (amountIn - daoTax) should equal 100/9900
        uint256 net = amountIn - daoTax;
        assertEq(daoTax, (net * 100) / (10_000 - 100));
    }

    function test_QuoteExactOut_WithDaoFee_OnOutput() public {
        (address dao,) = _deployAndSeedERC20(bytes32(uint256(155)), 1000e18, 1000e18);

        // 2% DAO fee on output
        vm.prank(dao);
        lpSeed.setDaoFee(address(0xBEEF), 200, 200, false, false);

        (uint256 amountIn, uint256 daoTax) = lpSeed.quoteExactOut(dao, 10e18, true);

        // Need gross output = ceil(10e18 * 10000 / 9800)
        uint256 desiredOut = 10e18;
        uint256 expectedGross = (desiredOut * 10_000 + 9_799) / 9_800;
        assertEq(daoTax, expectedGross - 10e18);
        assertTrue(amountIn > 0);
    }

    function test_QuoteExactIn_Symmetry() public {
        // Quote exactIn, then use the output as input to quoteExactOut — should round-trip
        (address dao,) = _deployAndSeedERC20(bytes32(uint256(156)), 1000e18, 1000e18);

        uint256 inputAmt = 5e18;
        (uint256 amountOut,) = lpSeed.quoteExactIn(dao, inputAmt, true);
        (uint256 roundTrip,) = lpSeed.quoteExactOut(dao, amountOut, true);

        // Due to rounding, roundTrip should be == inputAmt or inputAmt + 1
        assertTrue(roundTrip >= inputAmt && roundTrip <= inputAmt + 1);
    }

    // ── Hook Access Control ───────────────────────────────────────

    function test_RevertIf_BeforeActionNotZAMM() public {
        vm.prank(alice);
        vm.expectRevert(LPSeedSwapHook.Unauthorized.selector);
        lpSeed.beforeAction(bytes4(0), 0, alice, "");
    }

    // ── Configure: Overwrite ──────────────────────────────────────

    function test_Configure_Overwrite() public {
        (address dao, address sharesAddr) =
            _deployWithSeed(bytes32(uint256(80)), 1e18, 100e18, 0, address(0), 0);

        // Reconfigure with different amounts
        vm.prank(dao);
        lpSeed.configure(address(0), 2e18, sharesAddr, 200e18, 0, address(0), 0);

        (,, uint128 amtA, uint128 amtB,,,,,,,,,,) = lpSeed.seeds(dao);
        assertEq(amtA, 2e18);
        assertEq(amtB, 200e18);
    }

    // ── Seedable: Already seeded ──────────────────────────────────

    function test_Seedable_AlreadySeeded() public {
        // Use the ERC20 pair test setup
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        bytes32 salt = bytes32(uint256(90));
        address dao = safe.predictDAO(salt, h, s);
        address sharesAddr = safe.predictShares(dao);

        uint128 usdcAmt = 1000e18;
        uint128 sharesAmt = 1000e18;

        Call[] memory extra = new Call[](4);
        extra[0] = Call(sharesAddr, 0, abi.encodeCall(Shares.mintFromMoloch, (dao, sharesAmt)));
        extra[1] = Call(
            dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), address(usdc), usdcAmt))
        );
        extra[2] = Call(
            dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), sharesAddr, sharesAmt))
        );
        extra[3] = Call(
            address(lpSeed),
            0,
            abi.encodeCall(
                ILPSeedSwapHook.configure,
                (address(usdc), usdcAmt, sharesAddr, sharesAmt, 0, address(0), 0)
            )
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        safe.safeSummon(
            "SeedOnceDAO",
            "ONCE",
            "",
            1000,
            true,
            address(0),
            salt,
            h,
            s,
            new uint256[](0),
            c,
            extra
        );

        usdc.mint(dao, usdcAmt);
        lpSeed.seed(dao);

        // After seeding, seedable returns false
        assertFalse(lpSeed.seedable(dao));
    }

    // ── Cancel: Already seeded ────────────────────────────────────

    // ── Configure: Blocked after seeding ─────────────────────────

    function test_RevertIf_ConfigureAfterSeeded() public {
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        bytes32 salt = bytes32(uint256(95));
        address dao = safe.predictDAO(salt, h, s);
        address sharesAddr = safe.predictShares(dao);

        uint128 usdcAmt = 1000e18;
        uint128 sharesAmt = 1000e18;

        Call[] memory extra = new Call[](4);
        extra[0] = Call(sharesAddr, 0, abi.encodeCall(Shares.mintFromMoloch, (dao, sharesAmt)));
        extra[1] = Call(
            dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), address(usdc), usdcAmt))
        );
        extra[2] = Call(
            dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), sharesAddr, sharesAmt))
        );
        extra[3] = Call(
            address(lpSeed),
            0,
            abi.encodeCall(
                ILPSeedSwapHook.configure,
                (address(usdc), usdcAmt, sharesAddr, sharesAmt, 0, address(0), 0)
            )
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        safe.safeSummon(
            "ReconfDAO", "RECF", "", 1000, true, address(0), salt, h, s, new uint256[](0), c, extra
        );

        usdc.mint(dao, usdcAmt);
        lpSeed.seed(dao);

        // Reconfigure after seeding should revert — prevents bricking the pool
        vm.prank(dao);
        vm.expectRevert(LPSeedSwapHook.AlreadySeeded.selector);
        lpSeed.configure(address(usdc), 500e18, sharesAddr, 500e18, 0, address(0), 0);
    }

    // ── setBeneficiary: Blocked when rates are zero ──────────────

    function test_RevertIf_SetBeneficiaryNoRates() public {
        (address dao,) = _deployWithSeed(bytes32(uint256(135)), 1e18, 1000e18, 0, address(0), 0);

        // No daoFee configured — rates are zero
        vm.prank(dao);
        vm.expectRevert(LPSeedSwapHook.InvalidParams.selector);
        lpSeed.setBeneficiary(address(0xBEEF));
    }

    function test_SetBeneficiary_AllowZeroWithoutRates() public {
        (address dao,) = _deployWithSeed(bytes32(uint256(136)), 1e18, 1000e18, 0, address(0), 0);

        // Setting to address(0) should always work (disables routing)
        vm.prank(dao);
        lpSeed.setBeneficiary(address(0));
    }

    function test_RevertIf_CancelAlreadySeeded() public {
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        bytes32 salt = bytes32(uint256(91));
        address dao = safe.predictDAO(salt, h, s);
        address sharesAddr = safe.predictShares(dao);

        uint128 usdcAmt = 1000e18;
        uint128 sharesAmt = 1000e18;

        Call[] memory extra = new Call[](4);
        extra[0] = Call(sharesAddr, 0, abi.encodeCall(Shares.mintFromMoloch, (dao, sharesAmt)));
        extra[1] = Call(
            dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), address(usdc), usdcAmt))
        );
        extra[2] = Call(
            dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), sharesAddr, sharesAmt))
        );
        extra[3] = Call(
            address(lpSeed),
            0,
            abi.encodeCall(
                ILPSeedSwapHook.configure,
                (address(usdc), usdcAmt, sharesAddr, sharesAmt, 0, address(0), 0)
            )
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        safe.safeSummon(
            "CancelSeeded",
            "CNCL",
            "",
            1000,
            true,
            address(0),
            salt,
            h,
            s,
            new uint256[](0),
            c,
            extra
        );

        usdc.mint(dao, usdcAmt);
        lpSeed.seed(dao);

        // Cancel after seeding should revert — prevents bricking the pool
        vm.prank(dao);
        vm.expectRevert(LPSeedSwapHook.AlreadySeeded.selector);
        lpSeed.cancel();
    }

    // ── Seed: Mint-on-spend sentinel path (ETH + shares) ─────────

    function test_Seed_MintSentinel_ETHShares() public {
        // Deploy via _deployWithSeed which uses mintTokenB = dao sentinel
        (address dao, address sharesAddr) =
            _deployWithSeed(bytes32(uint256(200)), 1e18, 1000e18, 0, address(0), 0);

        // Verify mintTokenB is set to dao (shares mint sentinel)
        (,,,,,,,,,,,, address mintTokenA, address mintTokenB) = lpSeed.seeds(dao);
        assertEq(mintTokenA, address(0)); // ETH side: no sentinel
        assertEq(mintTokenB, dao); // shares side: mint sentinel

        // DAO has no pre-minted shares — they'll be minted on spend
        assertEq(Shares(sharesAddr).balanceOf(dao), 0);

        // Seed should work via mint-on-spend
        assertTrue(lpSeed.seedable(dao));
        uint256 liq = lpSeed.seed(dao);
        assertTrue(liq > 0);

        // Verify seeded
        (,,,,,,,,,,, uint40 seeded,,) = lpSeed.seeds(dao);
        assertTrue(seeded != 0);

        // Shares were minted and deposited into LP — DAO should not hold them
        // (they went into the ZAMM pool)
        assertEq(Shares(sharesAddr).balanceOf(address(lpSeed)), 0); // no leftover on hook

        // Cannot seed again
        vm.expectRevert(LPSeedSwapHook.AlreadySeeded.selector);
        lpSeed.seed(dao);
    }

    function test_Seed_MintSentinel_WithSaleGate() public {
        // Deploy with sale + LP seed where seed uses mint sentinel
        (address dao, address sharesAddr) =
            _deployWithSeed(bytes32(uint256(201)), 1e18, 500e18, 0, address(0), 0);

        // Verify the mint sentinel path works after manual sale gate scenario
        assertTrue(lpSeed.seedable(dao));

        uint256 sharesBefore = Shares(sharesAddr).totalSupply();
        lpSeed.seed(dao);
        uint256 sharesAfter = Shares(sharesAddr).totalSupply();

        // Shares supply should have increased by ~500e18 (minted via sentinel)
        assertTrue(sharesAfter > sharesBefore);
        // The minted amount should be at least the seed amount
        assertTrue(sharesAfter - sharesBefore >= 500e18);
    }

    // ── Arb-Clamp: 6-Decimal Pay Token ──────────────────────────

    function test_Seed_ArbClamp_6DecimalPayToken() public {
        // Verify arb-protection clamping is decimal-agnostic.
        // ShareSale price = 10e6 means "10 USDC6-wei per 1e18 share-wei" → $10/share.
        // With 100e6 USDC6 in treasury, maxShares = 100e6 * 1e18 / 10e6 = 10e18.
        // Configure seed with 1000e18 shares — clamp should reduce to 10e18.

        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        bytes32 salt = bytes32(uint256(300));
        address dao = safe.predictDAO(salt, h, s);
        address sharesAddr = safe.predictShares(dao);

        uint256 salePrice = 10e6; // $10/share in 6-decimal USDC
        uint256 saleCap = 10e18; // 10 shares for sale
        uint128 usdcAmt = 100e6; // 100 USDC (6 decimals) for LP
        uint128 sharesAmt = 1000e18; // intentionally high — clamp should reduce

        // 8 initCalls: ShareSale(2) + mint shares(1) + LPSeed(4) + approve USDC allowance(1)
        Call[] memory extra = new Call[](8);

        // ShareSale: setAllowance for shares + configure with USDC6 pay token
        extra[0] =
            Call(dao, 0, abi.encodeCall(Moloch.setAllowance, (address(shareSale), dao, saleCap)));
        extra[1] = Call(
            address(shareSale),
            0,
            abi.encodeCall(shareSale.configure, (dao, address(usdc6), salePrice, uint40(0)))
        );

        // Mint shares to DAO for LP seeding
        extra[2] = Call(sharesAddr, 0, abi.encodeCall(Shares.mintFromMoloch, (dao, sharesAmt)));

        // LPSeedSwapHook: setAllowance(USDC6) + setAllowance(shares) + configure
        extra[3] = Call(
            dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), address(usdc6), usdcAmt))
        );
        extra[4] = Call(
            dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), sharesAddr, sharesAmt))
        );
        extra[5] = Call(
            address(lpSeed),
            0,
            abi.encodeCall(
                ILPSeedSwapHook.configure,
                (
                    address(usdc6),
                    usdcAmt,
                    sharesAddr,
                    sharesAmt,
                    0, // no deadline gate
                    address(shareSale), // sale completion gate
                    0 // no minSupply gate
                )
            )
        );

        // Approve USDC6 transfers: DAO approves lpSeed (for spendAllowance pull)
        extra[6] = Call(
            address(usdc6), 0, abi.encodeCall(MockERC20_6d.approve, (address(lpSeed), usdcAmt))
        );

        // Also approve shareSale to pull USDC6 from bob (done outside initCalls)
        // Approve shares transfer from DAO to lpSeed
        extra[7] = Call(
            sharesAddr, 0, abi.encodeCall(Shares.approve, (address(lpSeed), sharesAmt))
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        address deployed = safe.safeSummon(
            "ArbClamp6d", "AC6D", "", 1000, true, address(0), salt, h, s, new uint256[](0), c, extra
        );
        assertEq(deployed, dao);

        // Fund DAO with USDC6
        usdc6.mint(dao, usdcAmt);

        // Complete the sale: bob buys all 10e18 shares with USDC6
        // cost = 10e18 * 10e6 / 1e18 = 100e6 (rounds up)
        usdc6.mint(bob, 100e6);
        vm.prank(bob);
        usdc6.approve(address(shareSale), 100e6);
        vm.prank(bob);
        shareSale.buy(dao, 10e18);

        // Sale exhausted — seedable
        assertTrue(lpSeed.seedable(dao));

        // Record shares balance before seed
        uint256 daoSharesBefore = Shares(sharesAddr).balanceOf(dao);

        // Seed — arb clamp should kick in
        lpSeed.seed(dao);

        // Verify seeded
        (,,,,,,,,,,, uint40 seeded,,) = lpSeed.seeds(dao);
        assertTrue(seeded != 0);

        // Expected maxShares = usdcAmt * 1e18 / salePrice = 100e6 * 1e18 / 10e6 = 10e18
        uint256 expectedMaxShares = uint256(usdcAmt) * 1e18 / salePrice;
        assertEq(expectedMaxShares, 10e18);

        // DAO should have excess shares returned (1000e18 - 10e18 = 990e18 unclaimed)
        // The shares that went into LP should be clamped to ~10e18
        uint256 daoSharesAfter = Shares(sharesAddr).balanceOf(dao);
        // DAO started with sharesAmt (1000e18), LP consumed expectedMaxShares (10e18)
        // Remaining = 1000e18 - 10e18 = 990e18
        assertEq(daoSharesAfter, daoSharesBefore - expectedMaxShares);
    }
}
