// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Moloch} from "../src/Moloch.sol";
import {SafeSummoner, Call} from "../src/peripheral/SafeSummoner.sol";
import {TapVest} from "../src/peripheral/TapVest.sol";

contract TapVestTest is Test {
    SafeSummoner internal safe;
    TapVest internal tap;

    address internal alice = address(0xA11CE);
    address internal beneficiary = address(0xBEEF);

    function setUp() public {
        vm.createSelectFork("main");
        safe = new SafeSummoner();
        tap = new TapVest();
    }

    // ── Helpers ──────────────────────────────────────────────────

    /// @dev Deploy a DAO with ETH tap: 1 ETH/day to beneficiary, 100 ETH budget.
    function _deployWithTap(bytes32 salt, uint128 rate, uint256 budget)
        internal
        returns (address dao)
    {
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        dao = safe.predictDAO(salt, h, s);

        // initCalls: setAllowance + configure Tap
        Call[] memory extra = new Call[](2);
        extra[0] =
            Call(dao, 0, abi.encodeCall(Moloch.setAllowance, (address(tap), address(0), budget)));
        extra[1] =
            Call(address(tap), 0, abi.encodeCall(tap.configure, (address(0), beneficiary, rate)));

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        address deployed = safe.safeSummon(
            "TapDAO", "TAP", "", 1000, true, address(0), salt, h, s, new uint256[](0), c, extra
        );
        assertEq(deployed, dao);

        // Fund the DAO with ETH
        vm.deal(dao, 100 ether);
    }

    // ── Tests ────────────────────────────────────────────────────

    function test_ClaimAfterTime() public {
        uint128 rate = 1e18 / uint128(1 days); // ~1 ETH/day in wei/sec
        address dao = _deployWithTap(bytes32(uint256(1)), rate, 100e18);

        // Warp 1 day
        vm.warp(block.timestamp + 1 days);

        uint256 benBefore = beneficiary.balance;
        tap.claim(dao);
        uint256 claimed = beneficiary.balance - benBefore;

        // Should be ~1 ETH (rate * 1 day)
        assertApproxEqAbs(claimed, 1e18, 1e15); // within 0.001 ETH tolerance
    }

    function test_ClaimableView() public {
        uint128 rate = 1e18 / uint128(1 days);
        address dao = _deployWithTap(bytes32(uint256(2)), rate, 100e18);

        assertEq(tap.claimable(dao), 0); // nothing accrued yet

        vm.warp(block.timestamp + 1 days);
        uint256 c = tap.claimable(dao);
        assertApproxEqAbs(c, 1e18, 1e15);
    }

    function test_PendingView() public {
        uint128 rate = 1e18 / uint128(1 days);
        address dao = _deployWithTap(bytes32(uint256(3)), rate, 100e18);

        vm.warp(block.timestamp + 10 days);
        uint256 p = tap.pending(dao);
        assertApproxEqAbs(p, 10e18, 1e15);
    }

    function test_ClaimCappedByAllowance() public {
        uint128 rate = 1e18 / uint128(1 days);
        // Only 2 ETH budget
        address dao = _deployWithTap(bytes32(uint256(4)), rate, 2e18);

        // Warp 10 days — owed = ~10 ETH but allowance = 2 ETH
        vm.warp(block.timestamp + 10 days);

        uint256 c = tap.claimable(dao);
        // Rounded down to whole seconds — within 1 second of rate
        assertApproxEqAbs(c, 2e18, rate);

        uint256 benBefore = beneficiary.balance;
        tap.claim(dao);
        assertApproxEqAbs(beneficiary.balance - benBefore, 2e18, rate);

        // Second claim should fail — allowance exhausted
        vm.warp(block.timestamp + 1 days);
        vm.expectRevert(TapVest.NothingToClaim.selector);
        tap.claim(dao);
    }

    function test_ClaimCappedByBalance() public {
        uint128 rate = 1e18 / uint128(1 days);
        address dao = _deployWithTap(bytes32(uint256(5)), rate, 100e18);

        // Drain DAO balance to 0.5 ETH
        vm.deal(dao, 0.5e18);

        vm.warp(block.timestamp + 10 days);
        uint256 c = tap.claimable(dao);
        // Rounded down to whole seconds — slightly less than 0.5 ETH
        assertApproxEqAbs(c, 0.5e18, rate); // within 1 second of rate

        uint256 benBefore = beneficiary.balance;
        tap.claim(dao);
        uint256 firstClaimed = beneficiary.balance - benBefore;
        assertApproxEqAbs(firstClaimed, 0.5e18, rate);

        // Refund DAO — beneficiary should be able to claim the remainder
        vm.deal(dao, 100 ether);
        uint256 remaining = tap.claimable(dao);
        assertApproxEqAbs(remaining, 10e18 - firstClaimed, rate);

        uint256 benBefore2 = beneficiary.balance;
        tap.claim(dao);
        // Total across both claims should equal ~10 ETH (no overpayment)
        uint256 totalClaimed = firstClaimed + (beneficiary.balance - benBefore2);
        assertApproxEqAbs(totalClaimed, 10e18, 1e15);
    }

    function test_MultipleClaims() public {
        uint128 rate = 1e18 / uint128(1 days);
        address dao = _deployWithTap(bytes32(uint256(6)), rate, 100e18);

        // Claim after 1 day
        vm.warp(block.timestamp + 1 days);
        uint256 benBefore = beneficiary.balance;
        tap.claim(dao);
        uint256 first = beneficiary.balance - benBefore;

        // Claim after another 2 days
        vm.warp(block.timestamp + 2 days);
        uint256 benMid = beneficiary.balance;
        tap.claim(dao);
        uint256 second = beneficiary.balance - benMid;

        assertApproxEqAbs(first, 1e18, 1e15);
        assertApproxEqAbs(second, 2e18, 1e15);
    }

    function test_PermissionlessClaim() public {
        uint128 rate = 1e18 / uint128(1 days);
        address dao = _deployWithTap(bytes32(uint256(7)), rate, 100e18);

        vm.warp(block.timestamp + 1 days);

        // Anyone can call claim — funds go to beneficiary
        address random = address(0xCAFE);
        uint256 randomBefore = random.balance;
        uint256 benBefore = beneficiary.balance;
        vm.prank(random);
        tap.claim(dao);

        assertTrue(beneficiary.balance > benBefore); // beneficiary got funds
        assertEq(random.balance, randomBefore); // caller balance unchanged
    }

    function test_RevertIf_NotConfigured() public {
        vm.expectRevert(TapVest.NotConfigured.selector);
        tap.claim(address(0xdead));
    }

    function test_RevertIf_NothingToClaim() public {
        uint128 rate = 1e18 / uint128(1 days);
        address dao = _deployWithTap(bytes32(uint256(8)), rate, 100e18);

        // No time elapsed
        vm.expectRevert(TapVest.NothingToClaim.selector);
        tap.claim(dao);
    }

    // ── Governance ───────────────────────────────────────────────

    function test_SetBeneficiary() public {
        uint128 rate = 1e18 / uint128(1 days);
        address dao = _deployWithTap(bytes32(uint256(9)), rate, 100e18);

        address newBen = address(0xFACE);

        // Only DAO can call setBeneficiary
        vm.prank(dao);
        tap.setBeneficiary(newBen);

        vm.warp(block.timestamp + 1 days);
        uint256 newBenBefore = newBen.balance;
        uint256 oldBenBefore = beneficiary.balance;
        tap.claim(dao);

        assertTrue(newBen.balance > newBenBefore); // new beneficiary got funds
        assertEq(beneficiary.balance, oldBenBefore); // old beneficiary unchanged
    }

    function test_SetRate() public {
        uint128 rate = 1e18 / uint128(1 days);
        address dao = _deployWithTap(bytes32(uint256(10)), rate, 100e18);

        // Capture warp targets before any vm.warp to avoid block.timestamp re-evaluation
        uint256 day1 = block.timestamp + 1 days;
        uint256 day2 = day1 + 1 days;

        // Warp 1 day, don't claim
        vm.warp(day1);

        // DAO doubles the rate — non-retroactive, unclaimed at old rate is forfeited
        uint128 newRate = 2e18 / uint128(1 days);
        vm.prank(dao);
        tap.setRate(newRate);

        // Old accrual is forfeited. Warp another day at new rate.
        vm.warp(day2);
        uint256 benBefore = beneficiary.balance;
        tap.claim(dao);
        uint256 claimed = beneficiary.balance - benBefore;

        // Should be ~2 ETH (1 day at 2 ETH/day), not 3 ETH
        assertApproxEqAbs(claimed, 2e18, 1e15);
    }

    function test_FreezeRate() public {
        uint128 rate = 1e18 / uint128(1 days);
        address dao = _deployWithTap(bytes32(uint256(11)), rate, 100e18);

        // Freeze
        vm.prank(dao);
        tap.setRate(0);

        vm.warp(block.timestamp + 10 days);
        assertEq(tap.claimable(dao), 0);
    }

    function test_TapInitCallsHelper() public view {
        address dao = address(0xDA0);
        (address t1, bytes memory d1, address t2, bytes memory d2) =
            tap.tapInitCalls(dao, address(0), 100e18, beneficiary, 1e15);

        assertEq(t1, dao);
        assertEq(t2, address(tap));
        assertTrue(d1.length > 0);
        assertTrue(d2.length > 0);
    }

    // ── Configure Reverts ─────────────────────────────────────────

    function test_RevertIf_ConfigureZeroRate() public {
        vm.expectRevert(TapVest.ZeroRate.selector);
        tap.configure(address(0), beneficiary, 0);
    }

    function test_RevertIf_ConfigureZeroBeneficiary() public {
        vm.expectRevert();
        tap.configure(address(0), address(0), 1e15);
    }

    // ── Governance Access Control ─────────────────────────────────

    function test_RevertIf_SetBeneficiaryNotDAO() public {
        uint128 rate = 1e18 / uint128(1 days);
        _deployWithTap(bytes32(uint256(20)), rate, 100e18);

        vm.prank(alice);
        vm.expectRevert(TapVest.NotConfigured.selector);
        tap.setBeneficiary(address(0xFACE));
    }

    function test_RevertIf_SetBeneficiaryToZero() public {
        uint128 rate = 1e18 / uint128(1 days);
        address dao = _deployWithTap(bytes32(uint256(21)), rate, 100e18);

        vm.prank(dao);
        vm.expectRevert();
        tap.setBeneficiary(address(0));
    }

    function test_SetBeneficiaryWhileFrozen() public {
        uint128 rate = 1e18 / uint128(1 days);
        address dao = _deployWithTap(bytes32(uint256(23)), rate, 100e18);

        // Freeze the tap
        vm.prank(dao);
        tap.setRate(0);

        // Should still be able to change beneficiary while frozen
        address newBen = address(0xFACE);
        vm.prank(dao);
        tap.setBeneficiary(newBen);

        (, address ben,,) = tap.taps(dao);
        assertEq(ben, newBen);
    }

    function test_RevertIf_SetRateNotDAO() public {
        uint128 rate = 1e18 / uint128(1 days);
        _deployWithTap(bytes32(uint256(22)), rate, 100e18);

        vm.prank(alice);
        vm.expectRevert(TapVest.NotConfigured.selector);
        tap.setRate(2e15);
    }

    // ── ERC20 Token Tap ───────────────────────────────────────────

    function test_ClaimERC20() public {
        address[] memory h = new address[](1);
        h[0] = alice;
        uint256[] memory s = new uint256[](1);
        s[0] = 100e18;

        bytes32 salt = bytes32(uint256(30));
        address dao = safe.predictDAO(salt, h, s);

        MockERC20 token = new MockERC20("Vesting", "VEST", 18);
        token.mint(dao, 100e18);

        uint128 rate = 1e18 / uint128(1 days);

        Call[] memory extra = new Call[](2);
        extra[0] = Call(
            dao, 0, abi.encodeCall(Moloch.setAllowance, (address(tap), address(token), 100e18))
        );
        extra[1] = Call(
            address(tap), 0, abi.encodeCall(tap.configure, (address(token), beneficiary, rate))
        );

        SafeSummoner.SafeConfig memory c;
        c.proposalThreshold = 1e18;
        c.proposalTTL = 7 days;

        safe.safeSummon(
            "ERC20TapDAO",
            "ETAP",
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

        vm.warp(block.timestamp + 1 days);

        uint256 benBefore = token.balanceOf(beneficiary);
        tap.claim(dao);
        uint256 claimed = token.balanceOf(beneficiary) - benBefore;

        assertApproxEqAbs(claimed, 1e18, 1e15);
    }

    // ── Pending View for unconfigured ─────────────────────────────

    function test_PendingView_NotConfigured() public view {
        assertEq(tap.pending(address(0xdead)), 0);
    }

    function test_ClaimableView_NotConfigured() public view {
        assertEq(tap.claimable(address(0xdead)), 0);
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
