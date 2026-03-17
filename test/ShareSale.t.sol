// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Moloch, Shares, Loot} from "../src/Moloch.sol";
import {SafeSummoner, Call} from "../src/peripheral/SafeSummoner.sol";
import {ShareSale} from "../src/peripheral/ShareSale.sol";

contract ShareSaleTest is Test {
    SafeSummoner internal safe;
    ShareSale internal sale;

    address internal alice = address(0xA11CE);
    address internal bob = address(0x0B0B);

    function setUp() public {
        vm.createSelectFork("main");
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        safe = new SafeSummoner();
        sale = new ShareSale();
    }

    // ── Helpers ──────────────────────────────────────────────────

    function _deployDAO(bytes32 salt) internal returns (address dao) {
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        // Predict addresses for init calls
        dao = safe.predictDAO(salt, h, s);

        // Init calls: setAllowance + configure ShareSale for minting shares
        // token = address(dao) → _payout mints shares
        Call[] memory extra = new Call[](2);
        extra[0] = Call(
            dao,
            0,
            abi.encodeCall(
                Moloch.setAllowance,
                (address(sale), address(uint160(uint256(uint160(dao)))), 1000e18)
            )
        );
        extra[1] = Call(
            address(sale),
            0,
            abi.encodeCall(
                sale.configure,
                (address(uint160(uint256(uint160(dao)))), address(0), 1e18, uint40(0))
            )
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        address deployed = safe.safeSummon(
            "SaleDAO", "SALE", "", 1000, true, address(0), salt, h, s, new uint256[](0), c, extra
        );
        assertEq(deployed, dao);
    }

    // ── Tests ────────────────────────────────────────────────────

    function test_BuySharesWithETH() public {
        address dao = _deployDAO(bytes32(uint256(1)));
        Moloch m = Moloch(payable(dao));
        address sharesAddr = address(m.shares());

        uint256 buyAmount = 10e18;
        uint256 cost = 10e18; // price=1e18: 10 shares * 1 ETH/share = 10 ETH

        uint256 bobSharesBefore = Shares(sharesAddr).balanceOf(bob);
        uint256 daoBefore = dao.balance;

        vm.prank(bob);
        sale.buy{value: cost}(dao, buyAmount);

        assertEq(Shares(sharesAddr).balanceOf(bob) - bobSharesBefore, buyAmount);
        assertEq(dao.balance - daoBefore, cost);
    }

    function test_BuySharesWithRefund() public {
        address dao = _deployDAO(bytes32(uint256(2)));
        Moloch m = Moloch(payable(dao));
        address sharesAddr = address(m.shares());

        uint256 buyAmount = 5e18;
        uint256 cost = 5e18; // 5 shares * 1 ETH/share = 5 ETH
        uint256 overpay = 1 ether;

        uint256 bobBalBefore = bob.balance;

        vm.prank(bob);
        sale.buy{value: cost + overpay}(dao, buyAmount);

        // Bob should get refund
        assertEq(bob.balance, bobBalBefore - cost);
        assertEq(Shares(sharesAddr).balanceOf(bob), buyAmount);
    }

    function test_RevertIf_NotConfigured() public {
        vm.prank(bob);
        vm.expectRevert(ShareSale.NotConfigured.selector);
        sale.buy{value: 1 ether}(address(0xdead), 1e18);
    }

    function test_RevertIf_ZeroAmount() public {
        address dao = _deployDAO(bytes32(uint256(3)));
        vm.prank(bob);
        vm.expectRevert(ShareSale.ZeroAmount.selector);
        sale.buy{value: 1 ether}(dao, 0);
    }

    function test_RevertIf_InsufficientPayment() public {
        address dao = _deployDAO(bytes32(uint256(4)));
        uint256 cost = 10e18; // 10 shares * 1 ETH/share
        vm.prank(bob);
        vm.expectRevert(ShareSale.InsufficientPayment.selector);
        sale.buy{value: cost - 1}(dao, 10e18);
    }

    function test_BuyLootWithETH() public {
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        bytes32 salt = bytes32(uint256(5));
        address dao = safe.predictDAO(salt, h, s);

        // Configure for loot minting (token = address(1007))
        Call[] memory extra = new Call[](2);
        extra[0] = Call(
            dao, 0, abi.encodeCall(Moloch.setAllowance, (address(sale), address(1007), 500e18))
        );
        extra[1] = Call(
            address(sale),
            0,
            abi.encodeCall(sale.configure, (address(1007), address(0), 1e18, uint40(0)))
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        address deployed = safe.safeSummon(
            "LootDAO", "LOOT", "", 1000, true, address(0), salt, h, s, new uint256[](0), c, extra
        );

        Moloch m = Moloch(payable(deployed));
        address lootAddr = address(m.loot());

        uint256 buyAmount = 10e18;
        uint256 cost = 10e18; // 10 loot * 1 ETH/loot

        vm.prank(bob);
        sale.buy{value: cost}(deployed, buyAmount);

        assertEq(Loot(lootAddr).balanceOf(bob), buyAmount);
    }

    function test_AllowanceCapEnforced() public {
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        bytes32 salt = bytes32(uint256(6));
        address dao = safe.predictDAO(salt, h, s);

        // Small cap: only 5e18 shares
        Call[] memory extra = new Call[](2);
        extra[0] = Call(dao, 0, abi.encodeCall(Moloch.setAllowance, (address(sale), dao, 5e18)));
        extra[1] = Call(
            address(sale), 0, abi.encodeCall(sale.configure, (dao, address(0), 1e18, uint40(0)))
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        safe.safeSummon(
            "CapDAO", "CAP", "", 1000, true, address(0), salt, h, s, new uint256[](0), c, extra
        );

        // Buy 5e18 — should succeed (cost = 5e18 * 1e18 / 1e18 = 5 ETH)
        vm.prank(bob);
        sale.buy{value: 5e18}(dao, 5e18);

        // Buy 1 more — should revert ZeroAmount (allowance exhausted, caps to 0)
        vm.prank(bob);
        vm.expectRevert(ShareSale.ZeroAmount.selector);
        sale.buy{value: 1e18}(dao, 1e18);
    }

    function test_RevertIf_Expired() public {
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        bytes32 salt = bytes32(uint256(7));
        address dao = safe.predictDAO(salt, h, s);

        uint40 deadline = uint40(block.timestamp + 1 days);

        Call[] memory extra = new Call[](2);
        extra[0] = Call(dao, 0, abi.encodeCall(Moloch.setAllowance, (address(sale), dao, 100e18)));
        extra[1] = Call(
            address(sale), 0, abi.encodeCall(sale.configure, (dao, address(0), 1e18, deadline))
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        safe.safeSummon(
            "DeadlineDAO", "DL", "", 1000, true, address(0), salt, h, s, new uint256[](0), c, extra
        );

        // Buy before deadline — should work
        vm.prank(bob);
        sale.buy{value: 1e18}(dao, 1e18);

        // Warp past deadline
        vm.warp(deadline + 1);

        // Buy after deadline — should revert
        vm.prank(bob);
        vm.expectRevert(ShareSale.Expired.selector);
        sale.buy{value: 1e18}(dao, 1e18);
    }

    function test_DeadlineZero_NeverExpires() public {
        address dao = _deployDAO(bytes32(uint256(8))); // uses deadline=0

        // Warp far into the future
        vm.warp(block.timestamp + 365 days);

        // Should still work
        vm.prank(bob);
        sale.buy{value: 1e18}(dao, 1e18);
    }

    function test_SaleInitCallsHelper() public view {
        address dao = address(0xDA0);
        (address t1, bytes memory d1, address t2, bytes memory d2) =
            sale.saleInitCalls(dao, dao, 100e18, address(0), 1e15, 0);

        assertEq(t1, dao);
        assertEq(t2, address(sale));
        assertTrue(d1.length > 0);
        assertTrue(d2.length > 0);
    }

    // ── Configure Reverts ─────────────────────────────────────────

    function test_RevertIf_ConfigureZeroPrice() public {
        vm.expectRevert(ShareSale.ZeroPrice.selector);
        sale.configure(address(0xDA0), address(0), 0, uint40(0));
    }

    // ── ERC20 PayToken ────────────────────────────────────────────

    function test_BuySharesWithERC20() public {
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        bytes32 salt = bytes32(uint256(20));
        address dao = safe.predictDAO(salt, h, s);

        MockERC20 payToken = new MockERC20("Pay", "PAY", 18);
        payToken.mint(bob, 1000e18);

        // Configure: minting shares, paid with ERC20
        Call[] memory extra = new Call[](2);
        extra[0] = Call(dao, 0, abi.encodeCall(Moloch.setAllowance, (address(sale), dao, 1000e18)));
        extra[1] = Call(
            address(sale),
            0,
            abi.encodeCall(sale.configure, (dao, address(payToken), 1e18, uint40(0)))
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        safe.safeSummon(
            "ERC20PayDAO",
            "EPAY",
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

        address sharesAddr = address(Moloch(payable(dao)).shares());

        uint256 buyAmount = 10e18;
        uint256 cost = 10e18; // 10 shares * 1 token/share

        vm.startPrank(bob);
        payToken.approve(address(sale), cost);
        sale.buy(dao, buyAmount);
        vm.stopPrank();

        assertEq(Shares(sharesAddr).balanceOf(bob), buyAmount);
        assertEq(payToken.balanceOf(dao), cost);
    }

    function test_RevertIf_UnexpectedETH_ERC20Sale() public {
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        bytes32 salt = bytes32(uint256(21));
        address dao = safe.predictDAO(salt, h, s);

        MockERC20 payToken = new MockERC20("Pay", "PAY", 18);

        Call[] memory extra = new Call[](2);
        extra[0] = Call(dao, 0, abi.encodeCall(Moloch.setAllowance, (address(sale), dao, 100e18)));
        extra[1] = Call(
            address(sale),
            0,
            abi.encodeCall(sale.configure, (dao, address(payToken), 1e18, uint40(0)))
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        safe.safeSummon(
            "NoETHDAO", "NOETH", "", 1000, true, address(0), salt, h, s, new uint256[](0), c, extra
        );

        // Sending ETH to an ERC20-priced sale should revert
        vm.prank(bob);
        vm.expectRevert(ShareSale.UnexpectedETH.selector);
        sale.buy{value: 1 ether}(dao, 1e18);
    }

    // ── SaleInitCalls for loot ────────────────────────────────────

    // ── Exact-out capping ────────────────────────────────────────

    function test_BuyCapsToRemaining() public {
        address dao = _deployDAO(bytes32(uint256(30)));
        Moloch m = Moloch(payable(dao));
        address sharesAddr = address(m.shares());

        // Allowance is 1000e18, buy 90e18 first
        vm.prank(bob);
        sale.buy{value: 90e18}(dao, 90e18);

        // Try to buy 920e18 but only 910e18 remains — caps to 910e18, refunds 10 ETH
        vm.deal(bob, 1000 ether);
        uint256 bobBalBefore = bob.balance;
        uint256 bobSharesBefore = Shares(sharesAddr).balanceOf(bob);

        vm.prank(bob);
        sale.buy{value: 920e18}(dao, 920e18);

        assertEq(Shares(sharesAddr).balanceOf(bob) - bobSharesBefore, 910e18);
        assertEq(bobBalBefore - bob.balance, 910e18);
    }

    function test_BuyMaxUint_BuysRemaining() public {
        address dao = _deployDAO(bytes32(uint256(31)));
        Moloch m = Moloch(payable(dao));
        address sharesAddr = address(m.shares());

        // Buy 90e18 first
        vm.prank(bob);
        sale.buy{value: 90e18}(dao, 90e18);

        // Buy remaining with type(uint256).max
        vm.deal(bob, 1000 ether);
        uint256 bobBalBefore = bob.balance;
        vm.prank(bob);
        sale.buy{value: 920e18}(dao, type(uint256).max);

        // 910e18 remained
        assertEq(Shares(sharesAddr).balanceOf(bob), 1000e18);
        assertEq(bobBalBefore - bob.balance, 910e18);
    }

    // ── Exact-in (ETH) ──────────────────────────────────────────

    function test_BuyExactIn() public {
        address dao = _deployDAO(bytes32(uint256(32)));
        Moloch m = Moloch(payable(dao));
        address sharesAddr = address(m.shares());

        // Price is 1e18 (1 ETH per share), send 7 ETH → 7 shares
        uint256 bobBalBefore = bob.balance;
        vm.prank(bob);
        sale.buyExactIn{value: 7 ether}(dao);

        assertEq(Shares(sharesAddr).balanceOf(bob), 7e18);
        assertEq(bobBalBefore - bob.balance, 7 ether);
    }

    function test_BuyExactIn_CapsToRemaining() public {
        address dao = _deployDAO(bytes32(uint256(33)));
        Moloch m = Moloch(payable(dao));
        address sharesAddr = address(m.shares());

        // Buy 90e18 first
        vm.prank(bob);
        sale.buy{value: 90e18}(dao, 90e18);

        // Send 920 ETH but only 910e18 shares remain → buy 910, refund 10 ETH
        vm.deal(bob, 1000 ether);
        uint256 bobBalBefore = bob.balance;
        vm.prank(bob);
        sale.buyExactIn{value: 920 ether}(dao);

        assertEq(Shares(sharesAddr).balanceOf(bob), 1000e18);
        assertEq(bobBalBefore - bob.balance, 910 ether);
    }

    function test_BuyExactIn_RevertIf_ERC20Sale() public {
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        bytes32 salt = bytes32(uint256(34));
        address dao = safe.predictDAO(salt, h, s);

        MockERC20 payToken = new MockERC20("Pay", "PAY", 18);

        Call[] memory extra = new Call[](2);
        extra[0] = Call(dao, 0, abi.encodeCall(Moloch.setAllowance, (address(sale), dao, 100e18)));
        extra[1] = Call(
            address(sale),
            0,
            abi.encodeCall(sale.configure, (dao, address(payToken), 1e18, uint40(0)))
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        safe.safeSummon(
            "ERC20DAO", "ERC", "", 1000, true, address(0), salt, h, s, new uint256[](0), c, extra
        );

        vm.prank(bob);
        vm.expectRevert(ShareSale.UnexpectedETH.selector);
        sale.buyExactIn{value: 1 ether}(dao);
    }

    function test_BuyExactIn_RevertIf_ZeroValue() public {
        address dao = _deployDAO(bytes32(uint256(35)));
        vm.prank(bob);
        vm.expectRevert(ShareSale.ZeroAmount.selector);
        sale.buyExactIn(dao);
    }

    function test_BuyExactIn_RevertIf_SoldOut() public {
        address dao = _deployDAO(bytes32(uint256(36)));

        // Buy all 1000e18
        vm.deal(bob, 1100 ether);
        vm.prank(bob);
        sale.buy{value: 1000e18}(dao, type(uint256).max);

        // Exact-in should revert — nothing left
        vm.prank(bob);
        vm.expectRevert(ShareSale.ZeroAmount.selector);
        sale.buyExactIn{value: 1 ether}(dao);
    }

    // ── Round-up pricing: no dust ─────────────────────────────

    function test_NoDust_SmallAmountStillCosts() public {
        // With price = 1e16 (0.01 ETH/share), buying 1 wei of shares
        // should cost 1 wei (rounded up from 0), not revert.
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        bytes32 salt = bytes32(uint256(40));
        address dao = safe.predictDAO(salt, h, s);

        Call[] memory extra = new Call[](2);
        extra[0] = Call(dao, 0, abi.encodeCall(Moloch.setAllowance, (address(sale), dao, 100e18)));
        extra[1] = Call(
            address(sale),
            0,
            abi.encodeCall(sale.configure, (dao, address(0), 1e16, uint40(0))) // 0.01 ETH/share
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        safe.safeSummon(
            "DustDAO", "DUST", "", 1000, true, address(0), salt, h, s, new uint256[](0), c, extra
        );

        address sharesAddr = address(Moloch(payable(dao)).shares());

        // Buy 1 wei of shares — should cost 1 wei (rounded up), not revert
        vm.prank(bob);
        sale.buy{value: 1}(dao, 1);

        assertEq(Shares(sharesAddr).balanceOf(bob), 1);
    }

    function test_NoDust_FullAllowanceDrainable() public {
        // With price = 1e16 (0.01 ETH/share) and cap = 99 wei of shares,
        // the full allowance should be spendable without dust remaining.
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        bytes32 salt = bytes32(uint256(41));
        address dao = safe.predictDAO(salt, h, s);

        uint256 cap = 99; // 99 wei of shares — would have been unspendable pre-roundup

        Call[] memory extra = new Call[](2);
        extra[0] = Call(dao, 0, abi.encodeCall(Moloch.setAllowance, (address(sale), dao, cap)));
        extra[1] = Call(
            address(sale),
            0,
            abi.encodeCall(sale.configure, (dao, address(0), 1e16, uint40(0))) // 0.01 ETH/share
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        safe.safeSummon(
            "FullDAO", "FULL", "", 1000, true, address(0), salt, h, s, new uint256[](0), c, extra
        );

        address sharesAddr = address(Moloch(payable(dao)).shares());

        // Buy all 99 wei — cost rounds up to 1 wei
        vm.prank(bob);
        sale.buy{value: 1}(dao, cap);

        assertEq(Shares(sharesAddr).balanceOf(bob), cap);
        // Allowance should be fully spent
        assertEq(Moloch(payable(dao)).allowance(dao, address(sale)), 0);
    }

    function test_NoDust_BuyExactIn_SmallValue() public {
        // buyExactIn with small msg.value and fractional price should work
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        bytes32 salt = bytes32(uint256(42));
        address dao = safe.predictDAO(salt, h, s);

        Call[] memory extra = new Call[](2);
        extra[0] = Call(dao, 0, abi.encodeCall(Moloch.setAllowance, (address(sale), dao, 100e18)));
        extra[1] = Call(
            address(sale),
            0,
            abi.encodeCall(sale.configure, (dao, address(0), 1e16, uint40(0))) // 0.01 ETH/share
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        safe.safeSummon(
            "ExactDAO", "EXCT", "", 1000, true, address(0), salt, h, s, new uint256[](0), c, extra
        );

        address sharesAddr = address(Moloch(payable(dao)).shares());

        // Send 1 wei of ETH — should buy 100 wei of shares (1 * 1e18 / 1e16 = 100)
        // cost = ceil(100 * 1e16 / 1e18) = ceil(1) = 1 wei
        vm.prank(bob);
        sale.buyExactIn{value: 1}(dao);

        assertEq(Shares(sharesAddr).balanceOf(bob), 100);
        // No refund — cost equals msg.value exactly
    }

    function test_RoundUp_BuyerPaysAtMostOneWeiExtra() public {
        address dao = _deployDAO(bytes32(uint256(43))); // price = 1e18
        Moloch m = Moloch(payable(dao));
        address sharesAddr = address(m.shares());

        // With price=1e18, cost = ceil(amount * 1e18 / 1e18) = amount exactly
        // No rounding occurs — buyer pays exact cost
        uint256 buyAmount = 7e18;
        uint256 bobBalBefore = bob.balance;

        vm.prank(bob);
        sale.buy{value: 7e18}(dao, buyAmount);

        assertEq(Shares(sharesAddr).balanceOf(bob), buyAmount);
        assertEq(bobBalBefore - bob.balance, 7e18); // exact, no extra
    }

    function test_SaleInitCallsHelper_Loot() public view {
        address dao = address(0xDA0);
        (address t1, bytes memory d1, address t2, bytes memory d2) =
            sale.saleInitCalls(dao, address(1007), 500e18, address(0), 1e15, 0);

        assertEq(t1, dao);
        assertEq(t2, address(sale));
        assertTrue(d1.length > 0);
        assertTrue(d2.length > 0);
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
