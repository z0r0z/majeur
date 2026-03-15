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

        // Buy 1 more — should fail (allowance exhausted)
        vm.prank(bob);
        vm.expectRevert(); // underflow in allowance -= amount
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
