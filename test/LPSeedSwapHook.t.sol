// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Moloch, Shares, Loot} from "../src/Moloch.sol";
import {SafeSummoner, Call} from "../src/peripheral/SafeSummoner.sol";
import {ShareSale} from "../src/peripheral/ShareSale.sol";
import {LPSeedSwapHook, IZAMM} from "../src/peripheral/LPSeedSwapHook.sol";

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
        // 1. Mint shares to DAO (for LP seeding)
        // 2. setAllowance(lpSeed, address(0), amtA)  -- ETH side
        // 3. setAllowance(lpSeed, sharesAddr, amtB)   -- shares side
        // 4. lpSeed.configure(...)
        Call[] memory extra = new Call[](4);

        // Mint shares to DAO for seeding
        extra[0] = Call(sharesAddr, 0, abi.encodeCall(Shares.mintFromMoloch, (dao, amtB)));

        // ETH allowance
        extra[1] =
            Call(dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), address(0), amtA)));

        // Shares allowance
        extra[2] =
            Call(dao, 0, abi.encodeCall(Moloch.setAllowance, (address(lpSeed), sharesAddr, amtB)));

        // Configure LPSeedSwapHook
        extra[3] = Call(
            address(lpSeed),
            0,
            abi.encodeCall(
                lpSeed.configure,
                (address(0), amtA, sharesAddr, amtB, deadline, shareSaleAddr, minSupply)
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
                lpSeed.configure,
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
            uint40 deadline,
            address shareSaleGate,
            uint128 minSupply,
            bool seeded
        ) = lpSeed.seeds(dao);

        assertEq(tokenA, address(0));
        assertEq(tokenB, sharesAddr);
        assertEq(amountA, 1e18);
        assertEq(amountB, 1000e18);
        assertEq(feeBps, 0);
        assertEq(deadline, 0);
        assertEq(shareSaleGate, address(0));
        assertEq(minSupply, 0);
        assertFalse(seeded);
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

        // DAO has 100e18 shares (minted for seed) + 100e18 from init = way above minSupply
        uint256 daoBal = Shares(sharesAddr).balanceOf(dao);
        assertTrue(daoBal > 50e18);
        assertFalse(lpSeed.seedable(dao));
    }

    function test_Seedable_MinSupplyMet() public {
        // Use a small amount so DAO balance will be near zero after distribution
        (address dao, address sharesAddr) =
            _deployWithSeed(bytes32(uint256(31)), 1e18, 100e18, 0, address(0), 200e18);

        // DAO has 100e18 (seed mint) + alice's don't count (she holds them).
        // DAO's own balance = 100e18 for seed. minSupply = 200e18 so already met.
        uint256 daoBal = Shares(sharesAddr).balanceOf(dao);
        assertTrue(daoBal <= 200e18);
        assertTrue(lpSeed.seedable(dao));
    }

    // ── Cancel ───────────────────────────────────────────────────

    function test_Cancel() public {
        (address dao,) = _deployWithSeed(bytes32(uint256(40)), 1e18, 1000e18, 0, address(0), 0);

        vm.prank(dao);
        lpSeed.cancel();

        (,, uint128 amtA,,,,,, bool seeded) = lpSeed.seeds(dao);
        assertEq(amtA, 0); // config cleared
        assertFalse(seeded);
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
                lpSeed.configure,
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

        // Only deadline met
        vm.warp(deadline + 1);
        assertFalse(lpSeed.seedable(dao)); // sale still has allowance

        // Buy all shares to exhaust sale
        vm.prank(bob);
        shareSale.buy{value: 5e18}(dao, 5e18);

        // Both conditions met
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
                lpSeed.configure, (address(usdc), usdcAmt, sharesAddr, sharesAmt, 0, address(0), 0)
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

        // Verify seeded flag
        (,,,,,,,, bool seeded) = lpSeed.seeds(dao);
        assertTrue(seeded);

        // Verify cannot seed again
        vm.expectRevert(LPSeedSwapHook.AlreadySeeded.selector);
        lpSeed.seed(dao);
    }

    // ── Init Call Helper ─────────────────────────────────────────

    function test_SeedInitCallsHelper() public view {
        address dao = address(0xDA0);
        (address t1, bytes memory d1, address t2, bytes memory d2, address t3, bytes memory d3) =
            lpSeed.seedInitCalls(dao, address(0), 1e18, address(1), 1000e18, 0, address(0), 0);

        assertEq(t1, dao); // setAllowance tokenA
        assertEq(t2, dao); // setAllowance tokenB
        assertEq(t3, address(lpSeed)); // configure
        assertTrue(d1.length > 0);
        assertTrue(d2.length > 0);
        assertTrue(d3.length > 0);
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
}
