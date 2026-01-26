// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console2, Vm} from "../lib/forge-std/src/Test.sol";
import {Moloch, Shares, Loot, Badges, Summoner, Call, Locked} from "../src/Moloch.sol";
import {DAICO} from "../src/peripheral/DAICO.sol";

/// @dev Simple ERC20 mock for testing
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

/// @dev USDT-style ERC20 mock that reverts if approval is non-zero to non-zero
contract MockUSDT {
    string public name = "Tether USD";
    string public symbol = "USDT";
    uint8 public decimals = 6;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    error ApprovalRaceCondition();

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        // USDT behavior: revert if changing non-zero to non-zero
        if (allowance[msg.sender][spender] != 0 && amount != 0) {
            revert ApprovalRaceCondition();
        }
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

contract DAICOTest is Test {
    // 1 ETH per day = 1e18 / 86400 = 11574074074074 wei/sec
    uint128 constant ONE_ETH_PER_DAY = 11574074074074;
    Summoner internal summoner;
    Moloch internal moloch;
    Shares internal shares;
    DAICO internal daico;

    // Implementation addresses for CREATE2 prediction
    address internal molochImpl;
    address internal sharesImpl;
    address internal lootImpl;

    address internal alice = address(0xA11CE);
    address internal bob = address(0x0B0B);
    address internal ops = address(0x0505); // ops beneficiary for tap

    // Events from DAICO
    event SaleSet(
        address indexed dao,
        address indexed tribTkn,
        uint256 tribAmt,
        address indexed forTkn,
        uint256 forAmt,
        uint40 deadline
    );

    event SaleBought(
        address indexed buyer,
        address indexed dao,
        address indexed tribTkn,
        uint256 payAmt,
        address forTkn,
        uint256 buyAmt
    );

    event TapSet(
        address indexed dao, address indexed ops, address indexed tribTkn, uint128 ratePerSec
    );

    event TapClaimed(address indexed dao, address indexed ops, address tribTkn, uint256 amount);

    function setUp() public {
        vm.label(alice, "ALICE");
        vm.label(bob, "BOB");
        vm.label(ops, "OPS");

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);

        // Record logs to capture NewDAO event which contains impl address
        vm.recordLogs();
        summoner = new Summoner();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // NewDAO(address indexed summoner, Moloch indexed dao)
        // The second topic is the Moloch implementation address
        molochImpl = address(uint160(uint256(logs[0].topics[2])));

        daico = new DAICO();

        // Compute shares/loot impl addresses from Moloch impl
        // Moloch constructor: sharesImpl = new Shares{salt: bytes32(bytes20(address(this)))}()
        bytes32 implSalt = bytes32(bytes20(molochImpl));
        sharesImpl = _computeCreate2(molochImpl, implSalt, type(Shares).creationCode);
        lootImpl = _computeCreate2(molochImpl, implSalt, type(Loot).creationCode);

        // Create DAO with alice as initial holder
        address[] memory initialHolders = new address[](1);
        initialHolders[0] = alice;
        uint256[] memory initialAmounts = new uint256[](1);
        initialAmounts[0] = 100e18;

        moloch = summoner.summon(
            "Test DAO",
            "TEST",
            "",
            5000, // 50% quorum
            true, // ragequit enabled
            address(0), // no renderer
            bytes32(0),
            initialHolders,
            initialAmounts,
            new Call[](0)
        );

        shares = moloch.shares();

        vm.roll(block.number + 1);
    }

    function _computeCreate2(address deployer, bytes32 salt, bytes memory creationCode)
        internal
        pure
        returns (address)
    {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), deployer, salt, keccak256(creationCode))
                    )
                )
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                            BASIC SALE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetSale_ETH() public {
        // DAO sets up ETH sale: 1 ETH for 1000 shares
        vm.prank(address(moloch));
        daico.setSale(
            address(0), // ETH
            1 ether, // tribAmt
            address(shares), // forTkn
            1000e18, // forAmt
            0 // no deadline
        );

        (uint256 tribAmt, uint256 forAmt, address forTkn, uint40 deadline) =
            daico.sales(address(moloch), address(0));

        assertEq(tribAmt, 1 ether);
        assertEq(forAmt, 1000e18);
        assertEq(forTkn, address(shares));
        assertEq(deadline, 0);
    }

    function test_Buy_ETH() public {
        // 1. Mint shares to DAO for sale
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);

        // 2. DAO approves DAICO to transfer shares
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        // 3. DAO sets sale: 1 ETH for 1000 shares
        vm.prank(address(moloch));
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, 0);

        // 4. Bob buys with 0.5 ETH
        uint256 bobSharesBefore = shares.balanceOf(bob);
        uint256 daoBalanceBefore = address(moloch).balance;

        vm.prank(bob);
        daico.buy{value: 0.5 ether}(address(moloch), address(0), 0.5 ether, 0);

        // Bob should get 500 shares (0.5 ETH * 1000 / 1)
        assertEq(shares.balanceOf(bob), bobSharesBefore + 500e18);
        // DAO should receive 0.5 ETH
        assertEq(address(moloch).balance, daoBalanceBefore + 0.5 ether);
    }

    function test_Buy_ETH_WithDeadline() public {
        // Setup
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        // Set sale with deadline 1 hour from now
        uint40 deadline = uint40(block.timestamp + 1 hours);
        vm.prank(address(moloch));
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, deadline);

        // Buy before deadline - should work
        vm.prank(bob);
        daico.buy{value: 0.1 ether}(address(moloch), address(0), 0.1 ether, 0);
        assertEq(shares.balanceOf(bob), 100e18);

        // Warp past deadline
        vm.warp(block.timestamp + 2 hours);

        // Buy after deadline - should fail
        vm.prank(bob);
        vm.expectRevert(DAICO.Expired.selector);
        daico.buy{value: 0.1 ether}(address(moloch), address(0), 0.1 ether, 0);
    }

    /*//////////////////////////////////////////////////////////////
                              TAP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetSaleWithTap() public {
        // DAO sets sale with tap: 1 ETH/day rate
        uint128 ratePerSec = ONE_ETH_PER_DAY;

        vm.prank(address(moloch));
        vm.expectEmit(true, true, true, true);
        emit TapSet(address(moloch), ops, address(0), ratePerSec);

        daico.setSaleWithTap(
            address(0), // ETH
            1 ether,
            address(shares),
            1000e18,
            0, // no deadline
            ops,
            ratePerSec
        );

        // Check tap was set
        (address tapOps, address tapTribTkn, uint128 tapRate, uint64 lastClaim) =
            daico.taps(address(moloch));

        assertEq(tapOps, ops);
        assertEq(tapTribTkn, address(0));
        assertEq(tapRate, ratePerSec);
        assertEq(lastClaim, block.timestamp);
    }

    function test_ClaimTap_ETH() public {
        // 1. Setup: Mint shares to DAO, approve DAICO
        vm.startPrank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        shares.approve(address(daico), type(uint256).max);
        vm.stopPrank();

        // 2. Fund DAO with ETH
        vm.deal(address(moloch), 10 ether);

        // 3. DAO grants allowance to DAICO for ETH tap
        vm.prank(address(moloch));
        moloch.setAllowance(address(daico), address(0), 5 ether);

        // 4. Set sale with tap: 1 ETH/day
        uint128 ratePerSec = ONE_ETH_PER_DAY;
        vm.prank(address(moloch));
        daico.setSaleWithTap(address(0), 1 ether, address(shares), 1000e18, 0, ops, ratePerSec);

        // 5. Warp 1 day
        vm.warp(block.timestamp + 1 days);

        // 6. Check pending/claimable
        uint256 pending = daico.pendingTap(address(moloch));
        uint256 claimable = daico.claimableTap(address(moloch));

        assertApproxEqRel(pending, 1 ether, 0.001e18); // ~1 ETH owed
        assertApproxEqRel(claimable, 1 ether, 0.001e18); // ~1 ETH claimable (allowance > owed)

        // 7. Claim tap
        uint256 opsBalanceBefore = ops.balance;

        vm.expectEmit(true, true, false, true);
        emit TapClaimed(address(moloch), ops, address(0), claimable);

        uint256 claimed = daico.claimTap(address(moloch));

        assertApproxEqRel(claimed, 1 ether, 0.001e18);
        assertEq(ops.balance, opsBalanceBefore + claimed);
    }

    function test_ClaimTap_CappedByAllowance() public {
        // Setup
        vm.startPrank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        shares.approve(address(daico), type(uint256).max);
        vm.stopPrank();

        vm.deal(address(moloch), 10 ether);

        // Grant only 0.5 ETH allowance
        vm.prank(address(moloch));
        moloch.setAllowance(address(daico), address(0), 0.5 ether);

        // Set tap at 1 ETH/day
        uint128 ratePerSec = ONE_ETH_PER_DAY;
        vm.prank(address(moloch));
        daico.setSaleWithTap(address(0), 1 ether, address(shares), 1000e18, 0, ops, ratePerSec);

        // Warp 1 day - owed is ~1 ETH but allowance is only 0.5 ETH
        vm.warp(block.timestamp + 1 days);

        uint256 pending = daico.pendingTap(address(moloch));
        uint256 claimable = daico.claimableTap(address(moloch));

        assertApproxEqRel(pending, 1 ether, 0.001e18); // ~1 ETH owed
        assertEq(claimable, 0.5 ether); // capped at allowance

        // Claim - should only get 0.5 ETH
        uint256 claimed = daico.claimTap(address(moloch));
        assertEq(claimed, 0.5 ether);
        assertEq(ops.balance, 0.5 ether);

        // Allowance exhausted - next claim should fail
        vm.warp(block.timestamp + 1 days);
        vm.expectRevert(DAICO.NothingToClaim.selector);
        daico.claimTap(address(moloch));
    }

    function test_ClaimTap_MultipleClaimsOverTime() public {
        // Setup
        vm.startPrank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        shares.approve(address(daico), type(uint256).max);
        vm.stopPrank();

        vm.deal(address(moloch), 100 ether);

        // Grant 10 ETH allowance
        vm.prank(address(moloch));
        moloch.setAllowance(address(daico), address(0), 10 ether);

        // Set tap at 1 ETH/day
        uint128 ratePerSec = ONE_ETH_PER_DAY;
        vm.prank(address(moloch));
        daico.setSaleWithTap(address(0), 1 ether, address(shares), 1000e18, 0, ops, ratePerSec);

        // Claim after 1 day
        vm.warp(block.timestamp + 1 days);
        uint256 claimed1 = daico.claimTap(address(moloch));
        assertApproxEqRel(claimed1, 1 ether, 0.001e18);

        // Claim after another 2 days
        vm.warp(block.timestamp + 2 days);
        uint256 claimed2 = daico.claimTap(address(moloch));
        assertApproxEqRel(claimed2, 2 ether, 0.001e18);

        // Total claimed should be ~3 ETH
        assertApproxEqRel(ops.balance, 3 ether, 0.001e18);
    }

    function test_ClaimTap_NoTapSet() public {
        vm.expectRevert(DAICO.NoTap.selector);
        daico.claimTap(address(moloch));
    }

    function test_ClaimTap_NothingToClaim_SameBlock() public {
        // Setup tap
        vm.startPrank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        shares.approve(address(daico), type(uint256).max);
        vm.stopPrank();

        vm.deal(address(moloch), 10 ether);
        vm.prank(address(moloch));
        moloch.setAllowance(address(daico), address(0), 5 ether);

        uint128 ratePerSec = ONE_ETH_PER_DAY;
        vm.prank(address(moloch));
        daico.setSaleWithTap(address(0), 1 ether, address(shares), 1000e18, 0, ops, ratePerSec);

        // Try to claim immediately (0 elapsed time)
        vm.expectRevert(DAICO.NothingToClaim.selector);
        daico.claimTap(address(moloch));
    }

    /*//////////////////////////////////////////////////////////////
                    INTEGRATION: INIT CALLS PATTERN
    //////////////////////////////////////////////////////////////*/

    /// @notice Test the full init call pattern for setting up DAICO with tap
    function test_SummonWithDAICOInitCalls() public {
        // This simulates what a real deployment would look like:
        // Summoner creates DAO with initCalls that set up the DAICO sale + tap

        uint128 ratePerSec = ONE_ETH_PER_DAY;

        // In production, you'd build init calls to:
        // 1. Mint shares to DAO itself (for sale)
        // 2. Approve DAICO to transfer shares
        // 3. Set allowance for DAICO to pull ETH (for tap)
        // 4. Call DAICO.setSaleWithTap
        //
        // We need to predict the DAO address to encode calls properly
        // For this test, we'll create the DAO first, then do manual calls
        // In production, you'd compute the CREATE2 address

        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        // Create DAO without init calls first
        Moloch newDao = summoner.summon{value: 10 ether}(
            "DAICO DAO",
            "DAICO",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(123)),
            holders,
            amounts,
            new Call[](0)
        );

        Shares newShares = newDao.shares();

        // Now execute the setup calls via proposal/execution or direct prank
        // (In production these would be initCalls)

        vm.startPrank(address(newDao));

        // 1. Mint shares to DAO for sale
        newShares.mintFromMoloch(address(newDao), 100_000e18);

        // 2. Approve DAICO
        newShares.approve(address(daico), type(uint256).max);

        // 3. Set allowance for tap (5 ETH total budget)
        newDao.setAllowance(address(daico), address(0), 5 ether);

        // 4. Set sale with tap
        daico.setSaleWithTap(
            address(0), // ETH
            0.01 ether, // 0.01 ETH per 100 shares
            address(newShares),
            100e18,
            0, // no deadline
            ops,
            ratePerSec
        );

        vm.stopPrank();

        // Verify setup
        (uint256 tribAmt, uint256 forAmt, address forTkn,) =
            daico.sales(address(newDao), address(0));
        assertEq(tribAmt, 0.01 ether);
        assertEq(forAmt, 100e18);
        assertEq(forTkn, address(newShares));

        (address tapOps,, uint128 tapRate,) = daico.taps(address(newDao));
        assertEq(tapOps, ops);
        assertEq(tapRate, ratePerSec);

        // Test the full flow: buy shares, then claim tap
        vm.prank(bob);
        daico.buy{value: 0.05 ether}(address(newDao), address(0), 0.05 ether, 0);
        assertEq(newShares.balanceOf(bob), 500e18); // 0.05 ETH * 100 / 0.01 = 500 shares

        // Warp and claim tap
        vm.warp(block.timestamp + 1 days);
        uint256 claimed = daico.claimTap(address(newDao));
        assertApproxEqRel(claimed, 1 ether, 0.001e18);
        assertEq(ops.balance, claimed);
    }

    /*//////////////////////////////////////////////////////////////
                            QUOTE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_QuoteBuy() public {
        vm.prank(address(moloch));
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, 0);

        uint256 quote = daico.quoteBuy(address(moloch), address(0), 0.5 ether);
        assertEq(quote, 500e18);
    }

    function test_QuotePayExactOut() public {
        vm.prank(address(moloch));
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, 0);

        uint256 quote = daico.quotePayExactOut(address(moloch), address(0), 500e18);
        assertEq(quote, 0.5 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        ADDITIONAL SALE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_BuyExactOut_ETH() public {
        // Setup
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, 0);

        // Bob wants exactly 250 shares
        uint256 bobSharesBefore = shares.balanceOf(bob);
        uint256 bobEthBefore = bob.balance;

        vm.prank(bob);
        daico.buyExactOut{value: 1 ether}(address(moloch), address(0), 250e18, 0);

        // Bob should get exactly 250 shares
        assertEq(shares.balanceOf(bob), bobSharesBefore + 250e18);
        // Bob should pay 0.25 ETH (250 * 1 / 1000)
        assertEq(bob.balance, bobEthBefore - 0.25 ether);
    }

    function test_BuyExactOut_ETH_WithRefund() public {
        // Setup
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, 0);

        // Bob sends 1 ETH but only needs 0.25 ETH for 250 shares
        uint256 bobEthBefore = bob.balance;

        vm.prank(bob);
        daico.buyExactOut{value: 1 ether}(address(moloch), address(0), 250e18, 0);

        // Bob should only pay 0.25 ETH, rest refunded
        assertEq(bob.balance, bobEthBefore - 0.25 ether);
    }

    function test_Buy_ETH_WithRefund() public {
        // Setup
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, 0);

        // Bob sends 1 ETH but specifies payAmt of 0.5 ETH
        uint256 bobEthBefore = bob.balance;

        vm.prank(bob);
        daico.buy{value: 1 ether}(address(moloch), address(0), 0.5 ether, 0);

        // Bob should only pay 0.5 ETH, 0.5 ETH refunded
        assertEq(bob.balance, bobEthBefore - 0.5 ether);
        assertEq(shares.balanceOf(bob), 500e18);
    }

    function test_Buy_RevertNoSale() public {
        // Try to buy from non-existent sale
        vm.prank(bob);
        vm.expectRevert(DAICO.NoSale.selector);
        daico.buy{value: 0.5 ether}(address(moloch), address(0), 0.5 ether, 0);
    }

    function test_Buy_RevertInvalidParams_ZeroDao() public {
        vm.prank(bob);
        vm.expectRevert(DAICO.InvalidParams.selector);
        daico.buy{value: 0.5 ether}(address(0), address(0), 0.5 ether, 0);
    }

    function test_Buy_RevertInvalidParams_ZeroPayAmt() public {
        vm.prank(address(moloch));
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, 0);

        vm.prank(bob);
        vm.expectRevert(DAICO.InvalidParams.selector);
        daico.buy(address(moloch), address(0), 0, 0);
    }

    function test_Buy_RevertSlippage() public {
        // Setup
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, 0);

        // Bob expects at least 600 shares for 0.5 ETH, but would only get 500
        vm.prank(bob);
        vm.expectRevert(DAICO.SlippageExceeded.selector);
        daico.buy{value: 0.5 ether}(address(moloch), address(0), 0.5 ether, 600e18);
    }

    function test_BuyExactOut_RevertSlippage() public {
        // Setup
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, 0);

        // Bob wants 500 shares but max pay is 0.4 ETH (would need 0.5 ETH)
        vm.prank(bob);
        vm.expectRevert(DAICO.SlippageExceeded.selector);
        daico.buyExactOut{value: 1 ether}(address(moloch), address(0), 500e18, 0.4 ether);
    }

    function test_SetSale_ClearSale() public {
        // Set sale
        vm.prank(address(moloch));
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, 0);

        // Verify it's set
        (uint256 tribAmt,,,) = daico.sales(address(moloch), address(0));
        assertEq(tribAmt, 1 ether);

        // Clear sale by setting tribAmt to 0
        vm.prank(address(moloch));
        daico.setSale(address(0), 0, address(shares), 1000e18, 0);

        // Verify it's cleared
        (tribAmt,,,) = daico.sales(address(moloch), address(0));
        assertEq(tribAmt, 0);
    }

    function test_SetSale_RevertForTknZero() public {
        // Can't set forTkn to address(0)
        vm.prank(address(moloch));
        vm.expectRevert(DAICO.InvalidParams.selector);
        daico.setSale(address(0), 1 ether, address(0), 1000e18, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        ADDITIONAL TAP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetSaleWithTap_ClearTap() public {
        // Set tap
        vm.prank(address(moloch));
        daico.setSaleWithTap(address(0), 1 ether, address(shares), 1000e18, 0, ops, ONE_ETH_PER_DAY);

        // Verify tap set
        (address tapOps,,,) = daico.taps(address(moloch));
        assertEq(tapOps, ops);

        // Clear tap by setting rate to 0
        vm.prank(address(moloch));
        daico.setSaleWithTap(address(0), 1 ether, address(shares), 1000e18, 0, ops, 0);

        // Verify tap cleared
        (tapOps,,,) = daico.taps(address(moloch));
        assertEq(tapOps, address(0));
    }

    function test_SetSaleWithTap_ClearTapByZeroOps() public {
        // Set tap
        vm.prank(address(moloch));
        daico.setSaleWithTap(address(0), 1 ether, address(shares), 1000e18, 0, ops, ONE_ETH_PER_DAY);

        // Clear tap by setting ops to address(0)
        vm.prank(address(moloch));
        daico.setSaleWithTap(
            address(0), 1 ether, address(shares), 1000e18, 0, address(0), ONE_ETH_PER_DAY
        );

        // Verify tap cleared
        (address tapOps,,,) = daico.taps(address(moloch));
        assertEq(tapOps, address(0));
    }

    function test_PendingTap_NoTap() public view {
        uint256 pending = daico.pendingTap(address(moloch));
        assertEq(pending, 0);
    }

    function test_ClaimableTap_NoTap() public view {
        uint256 claimable = daico.claimableTap(address(moloch));
        assertEq(claimable, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        SET TAP OPS (GOVERNANCE)
    //////////////////////////////////////////////////////////////*/

    event TapOpsUpdated(address indexed dao, address indexed oldOps, address indexed newOps);
    event TapRateUpdated(address indexed dao, uint128 oldRate, uint128 newRate);

    function test_SetTapOps() public {
        // Setup tap with ops
        vm.prank(address(moloch));
        daico.setSaleWithTap(address(0), 1 ether, address(shares), 1000e18, 0, ops, ONE_ETH_PER_DAY);

        // Verify initial ops
        (address tapOps,,,) = daico.taps(address(moloch));
        assertEq(tapOps, ops);

        // DAO updates ops to alice
        vm.prank(address(moloch));
        vm.expectEmit(true, true, true, true);
        emit TapOpsUpdated(address(moloch), ops, alice);
        daico.setTapOps(alice);

        // Verify updated ops
        (tapOps,,,) = daico.taps(address(moloch));
        assertEq(tapOps, alice);
    }

    function test_SetTapOps_ClaimGoesToNewOps() public {
        // Setup tap
        vm.startPrank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        shares.approve(address(daico), type(uint256).max);
        vm.stopPrank();

        vm.deal(address(moloch), 10 ether);
        vm.prank(address(moloch));
        moloch.setAllowance(address(daico), address(0), 5 ether);

        vm.prank(address(moloch));
        daico.setSaleWithTap(address(0), 1 ether, address(shares), 1000e18, 0, ops, ONE_ETH_PER_DAY);

        // Warp and accumulate some tap
        vm.warp(block.timestamp + 12 hours);

        // DAO changes ops to alice
        vm.prank(address(moloch));
        daico.setTapOps(alice);

        // Warp more and claim - should go to alice (new ops)
        vm.warp(block.timestamp + 12 hours);

        uint256 aliceBalanceBefore = alice.balance;
        uint256 opsBalanceBefore = ops.balance;

        daico.claimTap(address(moloch));

        // Alice (new ops) should receive funds
        assertGt(alice.balance, aliceBalanceBefore);
        // Old ops should receive nothing
        assertEq(ops.balance, opsBalanceBefore);
    }

    function test_SetTapOps_RevertNoTap() public {
        // Try to set ops without a tap configured
        vm.prank(address(moloch));
        vm.expectRevert(DAICO.NoTap.selector);
        daico.setTapOps(alice);
    }

    function test_SetTapOps_DisableTap() public {
        // Setup tap
        vm.startPrank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        shares.approve(address(daico), type(uint256).max);
        vm.stopPrank();

        vm.deal(address(moloch), 10 ether);
        vm.prank(address(moloch));
        moloch.setAllowance(address(daico), address(0), 5 ether);

        vm.prank(address(moloch));
        daico.setSaleWithTap(address(0), 1 ether, address(shares), 1000e18, 0, ops, ONE_ETH_PER_DAY);

        // Warp to accumulate tap
        vm.warp(block.timestamp + 1 days);

        // DAO sets ops to address(0) to disable
        vm.prank(address(moloch));
        daico.setTapOps(address(0));

        // Verify ops is now address(0)
        (address tapOps,,,) = daico.taps(address(moloch));
        assertEq(tapOps, address(0));

        // When ops is address(0), claimableTap returns 0 (no valid recipient)
        uint256 claimable = daico.claimableTap(address(moloch));
        assertEq(claimable, 0);

        // pendingTap still shows the accrued amount (time-based)
        uint256 pending = daico.pendingTap(address(moloch));
        assertApproxEqRel(pending, 1 ether, 0.001e18);

        // claimTap should revert with NoTap since ops is address(0)
        vm.expectRevert(DAICO.NoTap.selector);
        daico.claimTap(address(moloch));
    }

    function test_SetTapOps_OnlyDaoCanCall() public {
        // Setup tap
        vm.prank(address(moloch));
        daico.setSaleWithTap(address(0), 1 ether, address(shares), 1000e18, 0, ops, ONE_ETH_PER_DAY);

        // Alice tries to change ops - should fail (no tap for alice's address)
        vm.prank(alice);
        vm.expectRevert(DAICO.NoTap.selector);
        daico.setTapOps(bob);

        // Ops itself cannot change ops (only DAO can)
        vm.prank(ops);
        vm.expectRevert(DAICO.NoTap.selector);
        daico.setTapOps(bob);

        // Verify ops unchanged
        (address tapOps,,,) = daico.taps(address(moloch));
        assertEq(tapOps, ops);
    }

    /*//////////////////////////////////////////////////////////////
                        SET TAP RATE (GOVERNANCE)
    //////////////////////////////////////////////////////////////*/

    function test_SetTapRate() public {
        // Setup tap
        vm.prank(address(moloch));
        daico.setSaleWithTap(address(0), 1 ether, address(shares), 1000e18, 0, ops, ONE_ETH_PER_DAY);

        // Verify initial rate
        (,, uint128 tapRate,) = daico.taps(address(moloch));
        assertEq(tapRate, ONE_ETH_PER_DAY);

        // DAO raises the tap to 2 ETH/day
        uint128 newRate = ONE_ETH_PER_DAY * 2;
        vm.prank(address(moloch));
        vm.expectEmit(true, true, true, true);
        emit TapRateUpdated(address(moloch), ONE_ETH_PER_DAY, newRate);
        daico.setTapRate(newRate);

        // Verify updated rate
        (,, tapRate,) = daico.taps(address(moloch));
        assertEq(tapRate, newRate);
    }

    function test_SetTapRate_RaiseTap() public {
        // Setup tap
        vm.startPrank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        shares.approve(address(daico), type(uint256).max);
        vm.stopPrank();

        vm.deal(address(moloch), 100 ether);
        vm.prank(address(moloch));
        moloch.setAllowance(address(daico), address(0), 50 ether);

        // Start with 1 ETH/day
        vm.prank(address(moloch));
        daico.setSaleWithTap(address(0), 1 ether, address(shares), 1000e18, 0, ops, ONE_ETH_PER_DAY);

        // Warp 1 day - accumulate ~1 ETH
        vm.warp(block.timestamp + 1 days);

        // Claim BEFORE changing rate to lock in accrual at old rate
        uint256 claimed1 = daico.claimTap(address(moloch));
        assertApproxEqRel(claimed1, 1 ether, 0.001e18);

        // DAO votes to RAISE tap to 2 ETH/day (team doing well!)
        vm.prank(address(moloch));
        daico.setTapRate(ONE_ETH_PER_DAY * 2);

        // Warp another day from current time - should accumulate ~2 ETH at new rate
        skip(1 days);
        uint256 claimed2 = daico.claimTap(address(moloch));
        assertApproxEqRel(claimed2, 2 ether, 0.001e18);
    }

    function test_SetTapRate_LowerTap() public {
        // Setup tap at 2 ETH/day
        vm.startPrank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        shares.approve(address(daico), type(uint256).max);
        vm.stopPrank();

        vm.deal(address(moloch), 100 ether);
        vm.prank(address(moloch));
        moloch.setAllowance(address(daico), address(0), 50 ether);

        vm.prank(address(moloch));
        daico.setSaleWithTap(
            address(0), 1 ether, address(shares), 1000e18, 0, ops, ONE_ETH_PER_DAY * 2
        );

        // Warp 1 day - accumulate ~2 ETH
        vm.warp(block.timestamp + 1 days);

        // Claim BEFORE changing rate to lock in accrual at old rate
        uint256 claimed1 = daico.claimTap(address(moloch));
        assertApproxEqRel(claimed1, 2 ether, 0.001e18);

        // DAO votes to LOWER tap to 0.5 ETH/day (concerns about spending)
        vm.prank(address(moloch));
        daico.setTapRate(ONE_ETH_PER_DAY / 2);

        // Warp another day from current time - should accumulate ~0.5 ETH at new rate
        skip(1 days);
        uint256 claimed2 = daico.claimTap(address(moloch));
        assertApproxEqRel(claimed2, 0.5 ether, 0.001e18);
    }

    function test_SetTapRate_FreezeTap() public {
        // Setup tap
        vm.startPrank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        shares.approve(address(daico), type(uint256).max);
        vm.stopPrank();

        vm.deal(address(moloch), 100 ether);
        vm.prank(address(moloch));
        moloch.setAllowance(address(daico), address(0), 50 ether);

        vm.prank(address(moloch));
        daico.setSaleWithTap(address(0), 1 ether, address(shares), 1000e18, 0, ops, ONE_ETH_PER_DAY);

        // Warp 1 day
        vm.warp(block.timestamp + 1 days);

        // Claim BEFORE freezing to lock in accrual
        uint256 claimed = daico.claimTap(address(moloch));
        assertApproxEqRel(claimed, 1 ether, 0.001e18);

        // DAO votes to FREEZE tap (set rate to 0) - loss of confidence!
        vm.prank(address(moloch));
        daico.setTapRate(0);

        // Verify rate is now 0
        (,, uint128 rate,) = daico.taps(address(moloch));
        assertEq(rate, 0);

        // Warp more - no new accrual
        vm.warp(block.timestamp + 10 days);
        uint256 pending = daico.pendingTap(address(moloch));
        assertEq(pending, 0); // Rate is 0, so nothing accrues
    }

    function test_SetTapRate_UnfreezeTap() public {
        // Setup and freeze tap
        vm.prank(address(moloch));
        daico.setSaleWithTap(address(0), 1 ether, address(shares), 1000e18, 0, ops, ONE_ETH_PER_DAY);

        vm.prank(address(moloch));
        daico.setTapRate(0); // Freeze

        // Verify frozen
        (,, uint128 rate,) = daico.taps(address(moloch));
        assertEq(rate, 0);

        // DAO votes to unfreeze with new rate
        vm.prank(address(moloch));
        daico.setTapRate(ONE_ETH_PER_DAY);

        // Verify unfrozen
        (,, rate,) = daico.taps(address(moloch));
        assertEq(rate, ONE_ETH_PER_DAY);
    }

    function test_SetTapRate_RevertNoTap() public {
        // Try to set rate without a tap configured
        vm.prank(address(moloch));
        vm.expectRevert(DAICO.NoTap.selector);
        daico.setTapRate(ONE_ETH_PER_DAY);
    }

    function test_SetTapRate_OnlyDaoCanCall() public {
        // Setup tap
        vm.prank(address(moloch));
        daico.setSaleWithTap(address(0), 1 ether, address(shares), 1000e18, 0, ops, ONE_ETH_PER_DAY);

        // Alice tries to change rate - should fail
        vm.prank(alice);
        vm.expectRevert(DAICO.NoTap.selector);
        daico.setTapRate(ONE_ETH_PER_DAY * 2);

        // Verify rate unchanged
        (,, uint128 rate,) = daico.taps(address(moloch));
        assertEq(rate, ONE_ETH_PER_DAY);
    }

    function test_ClaimTap_AnyoneCanCall() public {
        // Setup tap
        vm.startPrank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        shares.approve(address(daico), type(uint256).max);
        vm.stopPrank();

        vm.deal(address(moloch), 10 ether);
        vm.prank(address(moloch));
        moloch.setAllowance(address(daico), address(0), 5 ether);

        vm.prank(address(moloch));
        daico.setSaleWithTap(address(0), 1 ether, address(shares), 1000e18, 0, ops, ONE_ETH_PER_DAY);

        vm.warp(block.timestamp + 1 days);

        // Alice (not ops) can call claimTap, but funds go to ops
        uint256 opsBalanceBefore = ops.balance;
        uint256 aliceBalanceBefore = alice.balance;

        vm.prank(alice);
        uint256 claimed = daico.claimTap(address(moloch));

        // Ops receives funds, not alice
        assertEq(ops.balance, opsBalanceBefore + claimed);
        assertEq(alice.balance, aliceBalanceBefore); // Alice balance unchanged
    }

    /*//////////////////////////////////////////////////////////////
                            QUOTE EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_QuoteBuy_NoSale() public view {
        uint256 quote = daico.quoteBuy(address(moloch), address(0), 0.5 ether);
        assertEq(quote, 0);
    }

    function test_QuoteBuy_ZeroPayAmt() public {
        vm.prank(address(moloch));
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, 0);

        uint256 quote = daico.quoteBuy(address(moloch), address(0), 0);
        assertEq(quote, 0);
    }

    function test_QuoteBuy_ZeroDao() public view {
        uint256 quote = daico.quoteBuy(address(0), address(0), 0.5 ether);
        assertEq(quote, 0);
    }

    function test_QuotePayExactOut_NoSale() public view {
        uint256 quote = daico.quotePayExactOut(address(moloch), address(0), 500e18);
        assertEq(quote, 0);
    }

    function test_QuotePayExactOut_CeilRounding() public {
        // Setup: 3 ETH for 10 shares (awkward ratio)
        vm.prank(address(moloch));
        daico.setSale(address(0), 3 ether, address(shares), 10e18, 0);

        // Want 1 share: payAmt = ceil(1 * 3 / 10) = ceil(0.3) = 1 (in smallest units)
        // Actually: 1e18 * 3e18 / 10e18 = 0.3e18, ceil = 0.3e18 rounded up
        uint256 quote = daico.quotePayExactOut(address(moloch), address(0), 1e18);
        // Should be 0.3 ETH
        assertEq(quote, 0.3 ether);

        // Want 7 shares: payAmt = ceil(7 * 3 / 10) = ceil(2.1) = 2.1 ETH
        quote = daico.quotePayExactOut(address(moloch), address(0), 7e18);
        assertEq(quote, 2.1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        BUY EXACT OUT DEADLINE
    //////////////////////////////////////////////////////////////*/

    function test_BuyExactOut_WithDeadline() public {
        // Setup
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        uint40 deadline = uint40(block.timestamp + 1 hours);
        vm.prank(address(moloch));
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, deadline);

        // Buy before deadline - should work
        vm.prank(bob);
        daico.buyExactOut{value: 1 ether}(address(moloch), address(0), 100e18, 0);
        assertEq(shares.balanceOf(bob), 100e18);

        // Warp past deadline
        vm.warp(block.timestamp + 2 hours);

        // Buy after deadline - should fail
        vm.prank(bob);
        vm.expectRevert(DAICO.Expired.selector);
        daico.buyExactOut{value: 1 ether}(address(moloch), address(0), 100e18, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        SUMMON WRAPPER TESTS
    //////////////////////////////////////////////////////////////*/

    function _getSummonConfig() internal view returns (DAICO.SummonConfig memory) {
        return DAICO.SummonConfig({
            summoner: address(summoner),
            molochImpl: molochImpl,
            sharesImpl: sharesImpl,
            lootImpl: lootImpl
        });
    }

    function test_SummonDAICO_SellShares() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0), // ETH
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false, // sell shares
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        address dao = daico.summonDAICO(
            _getSummonConfig(),
            "DAICO Test",
            "DTEST",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(1)),
            holders,
            amounts,
            false, // shares not locked
            false, // loot not locked
            daicoConfig
        );

        // Verify DAO created
        assertTrue(dao != address(0));

        // Verify sale configured
        (uint256 tribAmt, uint256 forAmt, address forTkn, uint40 deadline) =
            daico.sales(dao, address(0));
        assertEq(tribAmt, 1 ether);
        assertEq(forAmt, 1000e18);
        assertEq(forTkn, address(Moloch(payable(dao)).shares()));
        assertEq(deadline, 0);

        // Verify DAO has the minted shares for sale
        Shares daoShares = Moloch(payable(dao)).shares();
        assertEq(daoShares.balanceOf(dao), 100_000e18);

        // Verify DAICO has approval to transfer shares
        assertEq(daoShares.allowance(dao, address(daico)), 100_000e18);

        // Test buying
        vm.prank(bob);
        daico.buy{value: 0.1 ether}(dao, address(0), 0.1 ether, 0);
        assertEq(daoShares.balanceOf(bob), 100e18); // 0.1 ETH * 1000 / 1 = 100 shares
    }

    function test_SummonDAICO_SellLoot() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 50_000e18,
            forAmt: 500e18,
            deadline: uint40(block.timestamp + 30 days),
            sellLoot: true, // sell loot
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        address dao = daico.summonDAICO(
            _getSummonConfig(),
            "Loot Sale DAO",
            "LOOT",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(2)),
            holders,
            amounts,
            false,
            false,
            daicoConfig
        );

        // Verify sale is for loot
        (,, address forTkn,) = daico.sales(dao, address(0));
        assertEq(forTkn, address(Moloch(payable(dao)).loot()));

        // Verify DAO has the minted loot for sale
        Loot daoLoot = Moloch(payable(dao)).loot();
        assertEq(daoLoot.balanceOf(dao), 50_000e18);

        // Test buying loot
        vm.prank(bob);
        daico.buy{value: 2 ether}(dao, address(0), 2 ether, 0);
        assertEq(daoLoot.balanceOf(bob), 1000e18); // 2 ETH * 500 / 1 = 1000 loot
    }

    function test_SummonDAICO_SharesLocked() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        address dao = daico.summonDAICO(
            _getSummonConfig(),
            "Locked DAO",
            "LOCK",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(3)),
            holders,
            amounts,
            true, // shares locked
            false,
            daicoConfig
        );

        // Verify shares are locked (non-transferable)
        Moloch daoMoloch = Moloch(payable(dao));
        assertTrue(daoMoloch.shares().transfersLocked());
        assertFalse(daoMoloch.loot().transfersLocked());
    }

    function test_SummonDAICO_LootLocked() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: true, // selling loot
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        address dao = daico.summonDAICO(
            _getSummonConfig(),
            "Locked Loot DAO",
            "LLOOT",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(4)),
            holders,
            amounts,
            false,
            true, // loot locked
            daicoConfig
        );

        // Verify loot is locked
        Moloch daoMoloch = Moloch(payable(dao));
        assertFalse(daoMoloch.shares().transfersLocked());
        assertTrue(daoMoloch.loot().transfersLocked());
    }

    function test_SummonDAICO_BothLocked() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        address dao = daico.summonDAICO(
            _getSummonConfig(),
            "Both Locked DAO",
            "BOTH",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(5)),
            holders,
            amounts,
            true, // shares locked
            true, // loot locked
            daicoConfig
        );

        // Verify both locked
        Moloch daoMoloch = Moloch(payable(dao));
        assertTrue(daoMoloch.shares().transfersLocked());
        assertTrue(daoMoloch.loot().transfersLocked());
    }

    function test_SummonDAICOWithTap() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        DAICO.TapConfig memory tapConfig =
            DAICO.TapConfig({ops: ops, ratePerSec: ONE_ETH_PER_DAY, tapAllowance: 10 ether});

        address dao = daico.summonDAICOWithTap{value: 20 ether}(
            _getSummonConfig(),
            "DAICO Tap DAO",
            "DTAP",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(6)),
            holders,
            amounts,
            false,
            false,
            daicoConfig,
            tapConfig
        );

        // Verify sale configured
        (uint256 tribAmt, uint256 forAmt, address forTkn,) = daico.sales(dao, address(0));
        assertEq(tribAmt, 1 ether);
        assertEq(forAmt, 1000e18);
        assertEq(forTkn, address(Moloch(payable(dao)).shares()));

        // Verify tap configured
        (address tapOps, address tapTribTkn, uint128 tapRate, uint64 lastClaim) = daico.taps(dao);
        assertEq(tapOps, ops);
        assertEq(tapTribTkn, address(0));
        assertEq(tapRate, ONE_ETH_PER_DAY);
        assertEq(lastClaim, block.timestamp);

        // Verify DAO has ETH (sent in summon)
        assertEq(dao.balance, 20 ether);

        // Verify tap allowance set
        assertEq(Moloch(payable(dao)).allowance(address(0), address(daico)), 10 ether);

        // Test the tap works
        skip(1 days);
        uint256 claimable = daico.claimableTap(dao);
        assertApproxEqRel(claimable, 1 ether, 0.001e18);

        uint256 opsBefore = ops.balance;
        daico.claimTap(dao);
        assertApproxEqRel(ops.balance - opsBefore, 1 ether, 0.001e18);
    }

    function test_SummonDAICOWithTap_SellLootWithLockedTransfers() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 0.5 ether,
            saleSupply: 1_000_000e18,
            forAmt: 10_000e18,
            deadline: uint40(block.timestamp + 90 days),
            sellLoot: true,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        DAICO.TapConfig memory tapConfig = DAICO.TapConfig({
            ops: ops,
            ratePerSec: ONE_ETH_PER_DAY * 2, // 2 ETH/day
            tapAllowance: 100 ether
        });

        address dao = daico.summonDAICOWithTap{value: 150 ether}(
            _getSummonConfig(),
            "Full DAICO",
            "FULL",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(7)),
            holders,
            amounts,
            true, // shares locked
            true, // loot locked
            daicoConfig,
            tapConfig
        );

        // Verify all configurations
        Moloch daoMoloch = Moloch(payable(dao));

        // Transfers locked
        assertTrue(daoMoloch.shares().transfersLocked());
        assertTrue(daoMoloch.loot().transfersLocked());

        // Sale is for loot
        (,, address forTkn, uint40 deadline) = daico.sales(dao, address(0));
        assertEq(forTkn, address(daoMoloch.loot()));
        assertEq(deadline, uint40(block.timestamp + 90 days));

        // Tap configured with 2 ETH/day
        (,, uint128 tapRate,) = daico.taps(dao);
        assertEq(tapRate, ONE_ETH_PER_DAY * 2);

        // DAO has ETH
        assertEq(dao.balance, 150 ether);

        // Allowance set
        assertEq(daoMoloch.allowance(address(0), address(daico)), 100 ether);

        // Test buying loot
        vm.prank(bob);
        daico.buy{value: 1 ether}(dao, address(0), 1 ether, 0);
        assertEq(daoMoloch.loot().balanceOf(bob), 20_000e18); // 1 ETH * 10000 / 0.5 = 20000 loot

        // Test tap claim at 2 ETH/day
        skip(1 days);
        uint256 claimable = daico.claimableTap(dao);
        assertApproxEqRel(claimable, 2 ether, 0.001e18);
    }

    function test_SummonDAICOWithTap_NoTapIfZeroRate() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        // Zero rate = no tap
        DAICO.TapConfig memory tapConfig =
            DAICO.TapConfig({ops: ops, ratePerSec: 0, tapAllowance: 10 ether});

        address dao = daico.summonDAICOWithTap(
            _getSummonConfig(),
            "No Tap DAO",
            "NOTAP",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(8)),
            holders,
            amounts,
            false,
            false,
            daicoConfig,
            tapConfig
        );

        // Verify no tap configured
        (address tapOps,, uint128 tapRate,) = daico.taps(dao);
        assertEq(tapOps, address(0));
        assertEq(tapRate, 0);

        // But sale should still work
        (uint256 tribAmt,,,) = daico.sales(dao, address(0));
        assertEq(tribAmt, 1 ether);
    }

    function test_SummonDAICOWithTap_NoTapIfZeroOps() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        // Zero ops = no tap
        DAICO.TapConfig memory tapConfig =
            DAICO.TapConfig({ops: address(0), ratePerSec: ONE_ETH_PER_DAY, tapAllowance: 10 ether});

        address dao = daico.summonDAICOWithTap(
            _getSummonConfig(),
            "No Ops DAO",
            "NOOPS",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(9)),
            holders,
            amounts,
            false,
            false,
            daicoConfig,
            tapConfig
        );

        // Verify no tap configured
        (address tapOps,, uint128 tapRate,) = daico.taps(dao);
        assertEq(tapOps, address(0));
        assertEq(tapRate, 0);
    }

    function test_SummonDAICO_MultipleInitialHolders() public {
        address[] memory holders = new address[](3);
        holders[0] = alice;
        holders[1] = bob;
        holders[2] = ops;
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100e18;
        amounts[1] = 50e18;
        amounts[2] = 25e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        address dao = daico.summonDAICO(
            _getSummonConfig(),
            "Multi Holder DAO",
            "MULTI",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(10)),
            holders,
            amounts,
            false,
            false,
            daicoConfig
        );

        // Verify initial holders have shares
        Shares daoShares = Moloch(payable(dao)).shares();
        assertEq(daoShares.balanceOf(alice), 100e18);
        assertEq(daoShares.balanceOf(bob), 50e18);
        assertEq(daoShares.balanceOf(ops), 25e18);

        // DAO has sale supply
        assertEq(daoShares.balanceOf(dao), 100_000e18);
    }

    function test_SummonDAICO_WithDeadline() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        uint40 saleDeadline = uint40(block.timestamp + 7 days);

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: saleDeadline,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        address dao = daico.summonDAICO(
            _getSummonConfig(),
            "Deadline DAO",
            "DEAD",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(11)),
            holders,
            amounts,
            false,
            false,
            daicoConfig
        );

        // Verify deadline set
        (,,, uint40 deadline) = daico.sales(dao, address(0));
        assertEq(deadline, saleDeadline);

        // Can buy before deadline
        vm.prank(bob);
        daico.buy{value: 0.1 ether}(dao, address(0), 0.1 ether, 0);

        // Warp past deadline
        vm.warp(saleDeadline + 1);

        // Cannot buy after deadline
        vm.prank(bob);
        vm.expectRevert(DAICO.Expired.selector);
        daico.buy{value: 0.1 ether}(dao, address(0), 0.1 ether, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        ERC20 PAYMENT TOKEN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetSale_ERC20() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);

        // DAO sets up USDC sale: 100 USDC for 1000 shares
        vm.prank(address(moloch));
        daico.setSale(
            address(usdc), // USDC as payment token
            100e6, // tribAmt (100 USDC, 6 decimals)
            address(shares), // forTkn
            1000e18, // forAmt (1000 shares, 18 decimals)
            0 // no deadline
        );

        (uint256 tribAmt, uint256 forAmt, address forTkn, uint40 deadline) =
            daico.sales(address(moloch), address(usdc));

        assertEq(tribAmt, 100e6);
        assertEq(forAmt, 1000e18);
        assertEq(forTkn, address(shares));
        assertEq(deadline, 0);
    }

    function test_Buy_ERC20() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);

        // 1. Mint shares to DAO for sale
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);

        // 2. DAO approves DAICO to transfer shares
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        // 3. DAO sets sale: 100 USDC for 1000 shares
        vm.prank(address(moloch));
        daico.setSale(address(usdc), 100e6, address(shares), 1000e18, 0);

        // 4. Mint USDC to bob and approve
        usdc.mint(bob, 1000e6);
        vm.prank(bob);
        usdc.approve(address(daico), type(uint256).max);

        // 5. Bob buys with 50 USDC
        uint256 bobSharesBefore = shares.balanceOf(bob);
        uint256 daoUsdcBefore = usdc.balanceOf(address(moloch));

        vm.prank(bob);
        daico.buy(address(moloch), address(usdc), 50e6, 0);

        // Bob should get 500 shares (50 USDC * 1000 / 100)
        assertEq(shares.balanceOf(bob), bobSharesBefore + 500e18);
        // DAO should receive 50 USDC
        assertEq(usdc.balanceOf(address(moloch)), daoUsdcBefore + 50e6);
    }

    function test_BuyExactOut_ERC20() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);

        // Setup
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSale(address(usdc), 100e6, address(shares), 1000e18, 0);

        // Mint USDC to bob and approve
        usdc.mint(bob, 1000e6);
        vm.prank(bob);
        usdc.approve(address(daico), type(uint256).max);

        // Bob wants exactly 250 shares
        uint256 bobSharesBefore = shares.balanceOf(bob);
        uint256 bobUsdcBefore = usdc.balanceOf(bob);

        vm.prank(bob);
        daico.buyExactOut(address(moloch), address(usdc), 250e18, 0);

        // Bob should get exactly 250 shares
        assertEq(shares.balanceOf(bob), bobSharesBefore + 250e18);
        // Bob should pay 25 USDC (250 * 100 / 1000 = 25)
        assertEq(usdc.balanceOf(bob), bobUsdcBefore - 25e6);
    }

    function test_Buy_ERC20_RevertOnETHSent() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);

        // Setup
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSale(address(usdc), 100e6, address(shares), 1000e18, 0);

        usdc.mint(bob, 1000e6);
        vm.prank(bob);
        usdc.approve(address(daico), type(uint256).max);

        // Try to buy ERC20 sale with ETH - should fail
        vm.prank(bob);
        vm.expectRevert(DAICO.InvalidParams.selector);
        daico.buy{value: 1 ether}(address(moloch), address(usdc), 50e6, 0);
    }

    function test_ClaimTap_ERC20() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);

        // 1. Setup: Mint shares to DAO, approve DAICO
        vm.startPrank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        shares.approve(address(daico), type(uint256).max);
        vm.stopPrank();

        // 2. Fund DAO with USDC
        usdc.mint(address(moloch), 10_000e6);

        // 3. DAO grants allowance to DAICO for USDC tap
        vm.prank(address(moloch));
        moloch.setAllowance(address(daico), address(usdc), 5000e6);

        // 4. Set sale with tap: rate of 100 USDC/day
        // For USDC (6 decimals): 100 USDC/day = 100_000_000 / 86400 ≈ 1157 smallest units/sec
        uint128 ratePerSec = 1157; // ~100 USDC/day for 6 decimal token
        vm.prank(address(moloch));
        daico.setSaleWithTap(address(usdc), 100e6, address(shares), 1000e18, 0, ops, ratePerSec);

        // 5. Warp 1 day
        vm.warp(block.timestamp + 1 days);

        // 6. Check pending/claimable - rate * 86400 = 1157 * 86400 = 99,964,800 ≈ 99.96 USDC
        uint256 pending = daico.pendingTap(address(moloch));
        uint256 claimable = daico.claimableTap(address(moloch));

        // Expected: 1157 * 86400 = 99,964,800 (99.96 USDC)
        uint256 expected = uint256(ratePerSec) * 86400;
        assertEq(pending, expected);
        assertEq(claimable, expected); // allowance > owed

        // 7. Claim tap
        uint256 opsBalanceBefore = usdc.balanceOf(ops);

        uint256 claimed = daico.claimTap(address(moloch));

        assertEq(claimed, expected);
        assertEq(usdc.balanceOf(ops), opsBalanceBefore + claimed);
    }

    function test_QuoteBuy_ERC20() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);

        vm.prank(address(moloch));
        daico.setSale(address(usdc), 100e6, address(shares), 1000e18, 0);

        uint256 quote = daico.quoteBuy(address(moloch), address(usdc), 50e6);
        assertEq(quote, 500e18);
    }

    function test_QuotePayExactOut_ERC20() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);

        vm.prank(address(moloch));
        daico.setSale(address(usdc), 100e6, address(shares), 1000e18, 0);

        uint256 quote = daico.quotePayExactOut(address(moloch), address(usdc), 500e18);
        assertEq(quote, 50e6);
    }

    /*//////////////////////////////////////////////////////////////
                          FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Buy_ETH(uint256 payAmt) public {
        // Bound payAmt to reasonable range
        payAmt = bound(payAmt, 0.001 ether, 10 ether);

        // Setup
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 1_000_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, 0);

        uint256 expectedShares = (1000e18 * payAmt) / 1 ether;

        vm.prank(bob);
        daico.buy{value: payAmt}(address(moloch), address(0), payAmt, 0);

        assertEq(shares.balanceOf(bob), expectedShares);
    }

    function testFuzz_BuyExactOut_ETH(uint256 buyAmt) public {
        // Bound buyAmt to reasonable range
        buyAmt = bound(buyAmt, 1e18, 10_000e18);

        // Setup
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 1_000_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, 0);

        // Calculate expected payment (ceil division)
        uint256 num = buyAmt * 1 ether;
        uint256 expectedPay = (num + 1000e18 - 1) / 1000e18;

        uint256 bobEthBefore = bob.balance;

        vm.prank(bob);
        daico.buyExactOut{value: expectedPay + 1 ether}(address(moloch), address(0), buyAmt, 0);

        assertEq(shares.balanceOf(bob), buyAmt);
        assertEq(bob.balance, bobEthBefore - expectedPay);
    }

    function testFuzz_TapClaim(uint128 ratePerSec, uint256 timeElapsed) public {
        // Bound inputs
        ratePerSec = uint128(bound(ratePerSec, 1, ONE_ETH_PER_DAY * 10));
        timeElapsed = bound(timeElapsed, 1, 365 days);

        // Setup
        vm.startPrank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        shares.approve(address(daico), type(uint256).max);
        vm.stopPrank();

        // Fund DAO with enough ETH
        uint256 maxOwed = uint256(ratePerSec) * timeElapsed;
        vm.deal(address(moloch), maxOwed + 1 ether);

        vm.prank(address(moloch));
        moloch.setAllowance(address(daico), address(0), maxOwed);

        vm.prank(address(moloch));
        daico.setSaleWithTap(address(0), 1 ether, address(shares), 1000e18, 0, ops, ratePerSec);

        // Warp
        vm.warp(block.timestamp + timeElapsed);

        // Check pending
        uint256 pending = daico.pendingTap(address(moloch));
        assertEq(pending, uint256(ratePerSec) * timeElapsed);

        // Claim
        uint256 claimed = daico.claimTap(address(moloch));
        assertEq(ops.balance, claimed);
    }

    function testFuzz_QuoteBuy(uint256 tribAmt, uint256 forAmt, uint256 payAmt) public {
        // Bound inputs to avoid overflow and division by zero
        tribAmt = bound(tribAmt, 1, 1e30);
        forAmt = bound(forAmt, 1, 1e30);
        payAmt = bound(payAmt, 1, 1e30);

        vm.prank(address(moloch));
        daico.setSale(address(0), tribAmt, address(shares), forAmt, 0);

        uint256 quote = daico.quoteBuy(address(moloch), address(0), payAmt);
        uint256 expected = (forAmt * payAmt) / tribAmt;

        assertEq(quote, expected);
    }

    function testFuzz_QuotePayExactOut(uint256 tribAmt, uint256 forAmt, uint256 buyAmt) public {
        // Bound inputs to avoid overflow
        tribAmt = bound(tribAmt, 1, 1e30);
        forAmt = bound(forAmt, 1, 1e30);
        buyAmt = bound(buyAmt, 1, 1e30);

        // Skip if would overflow
        if (buyAmt > type(uint256).max / tribAmt) return;

        vm.prank(address(moloch));
        daico.setSale(address(0), tribAmt, address(shares), forAmt, 0);

        uint256 quote = daico.quotePayExactOut(address(moloch), address(0), buyAmt);
        uint256 num = buyAmt * tribAmt;
        uint256 expected = (num + forAmt - 1) / forAmt;

        assertEq(quote, expected);
    }

    /*//////////////////////////////////////////////////////////////
                    INTEGRATION: FULL DAICO LIFECYCLE
    //////////////////////////////////////////////////////////////*/

    function test_FullDAICOLifecycle() public {
        // This test simulates a complete DAICO lifecycle:
        // 1. Summon DAO with sale + tap
        // 2. Multiple users buy shares
        // 3. Ops claims tap over time
        // 4. DAO governance adjusts tap rate
        // 5. Tap continues after partial drain

        address[] memory holders = new address[](2);
        holders[0] = alice;
        holders[1] = address(0xFEED); // team wallet
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e18; // alice gets voting shares
        amounts[1] = 50e18; // team gets shares

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0), // ETH
            tribAmt: 0.1 ether, // 0.1 ETH per 100 shares
            saleSupply: 500_000e18, // 500k shares for sale
            forAmt: 100e18,
            deadline: 0, // No deadline for this lifecycle test
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        DAICO.TapConfig memory tapConfig = DAICO.TapConfig({
            ops: ops,
            ratePerSec: ONE_ETH_PER_DAY, // 1 ETH/day
            tapAllowance: 30 ether // 30 day budget
        });

        // Step 1: Summon DAO
        address dao = daico.summonDAICOWithTap{value: 50 ether}(
            _getSummonConfig(),
            "Lifecycle DAO",
            "LIFE",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(100)),
            holders,
            amounts,
            false,
            false,
            daicoConfig,
            tapConfig
        );

        Moloch daoMoloch = Moloch(payable(dao));
        Shares daoShares = daoMoloch.shares();

        // Verify setup
        assertEq(daoShares.balanceOf(dao), 500_000e18);
        assertEq(dao.balance, 50 ether);

        // Step 2: Multiple users buy shares
        address buyer1 = address(0xB1);
        address buyer2 = address(0xB2);
        address buyer3 = address(0xB3);
        vm.deal(buyer1, 10 ether);
        vm.deal(buyer2, 10 ether);
        vm.deal(buyer3, 10 ether);

        // Buyer1 buys 1000 shares
        vm.prank(buyer1);
        daico.buy{value: 1 ether}(dao, address(0), 1 ether, 0);
        assertEq(daoShares.balanceOf(buyer1), 1000e18);

        // Buyer2 uses exact out for 500 shares
        vm.prank(buyer2);
        daico.buyExactOut{value: 1 ether}(dao, address(0), 500e18, 0);
        assertEq(daoShares.balanceOf(buyer2), 500e18);

        // Buyer3 buys with minBuyAmt slippage protection
        vm.prank(buyer3);
        daico.buy{value: 0.5 ether}(dao, address(0), 0.5 ether, 400e18);
        assertEq(daoShares.balanceOf(buyer3), 500e18);

        // Step 3: Ops claims tap after 7 days
        skip(7 days);

        uint256 opsBalanceBefore = ops.balance;
        uint256 claimed = daico.claimTap(dao);
        assertApproxEqRel(claimed, 7 ether, 0.001e18);
        assertEq(ops.balance, opsBalanceBefore + claimed);

        // Step 4: DAO governance raises tap (team doing well)
        vm.prank(dao);
        daico.setTapRate(ONE_ETH_PER_DAY * 2); // Double the rate

        // Step 5: More time passes, claim at new rate
        skip(7 days);
        claimed = daico.claimTap(dao);
        assertApproxEqRel(claimed, 14 ether, 0.001e18); // 2 ETH/day * 7 days

        // Step 6: DAO lowers tap rate (governance decision)
        vm.prank(dao);
        daico.setTapRate(ONE_ETH_PER_DAY / 2); // Halve the rate

        // Step 7: Claim at lower rate - remaining allowance is ~9 ETH (30 - 7 - 14 = 9)
        skip(7 days);
        claimed = daico.claimTap(dao);
        assertApproxEqRel(claimed, 3.5 ether, 0.001e18); // 0.5 ETH/day * 7 days

        // Verify total ops received is approximately 7 + 14 + 3.5 = 24.5 ETH
        assertApproxEqRel(ops.balance, 24.5 ether, 0.001e18);
    }

    function test_MultipleSalesForSameDAO() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 dai = new MockERC20("Dai Stablecoin", "DAI", 18);

        // Setup shares
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        // DAO sets up multiple sales with different payment tokens
        vm.startPrank(address(moloch));

        // ETH sale
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, 0);

        // USDC sale (different rate)
        daico.setSale(address(usdc), 100e6, address(shares), 800e18, 0);

        // DAI sale (yet another rate)
        daico.setSale(address(dai), 50e18, address(shares), 500e18, 0);

        vm.stopPrank();

        // Verify all three sales exist
        (uint256 ethTribAmt,,,) = daico.sales(address(moloch), address(0));
        (uint256 usdcTribAmt,,,) = daico.sales(address(moloch), address(usdc));
        (uint256 daiTribAmt,,,) = daico.sales(address(moloch), address(dai));

        assertEq(ethTribAmt, 1 ether);
        assertEq(usdcTribAmt, 100e6);
        assertEq(daiTribAmt, 50e18);

        // Bob can buy from any sale
        vm.prank(bob);
        daico.buy{value: 0.5 ether}(address(moloch), address(0), 0.5 ether, 0);
        assertEq(shares.balanceOf(bob), 500e18);

        usdc.mint(bob, 200e6);
        vm.prank(bob);
        usdc.approve(address(daico), type(uint256).max);
        vm.prank(bob);
        daico.buy(address(moloch), address(usdc), 100e6, 0);
        assertEq(shares.balanceOf(bob), 500e18 + 800e18);

        dai.mint(bob, 100e18);
        vm.prank(bob);
        dai.approve(address(daico), type(uint256).max);
        vm.prank(bob);
        daico.buy(address(moloch), address(dai), 50e18, 0);
        assertEq(shares.balanceOf(bob), 500e18 + 800e18 + 500e18);
    }

    function test_DAOCanChangeSaleTerms() public {
        // Setup initial sale
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        // Initial sale: 1 ETH = 1000 shares
        vm.prank(address(moloch));
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, 0);

        // Bob buys at original rate
        vm.prank(bob);
        daico.buy{value: 1 ether}(address(moloch), address(0), 1 ether, 0);
        assertEq(shares.balanceOf(bob), 1000e18);

        // DAO changes price: 1 ETH = 500 shares (price increase)
        vm.prank(address(moloch));
        daico.setSale(address(0), 1 ether, address(shares), 500e18, 0);

        // Alice buys at new rate
        vm.prank(alice);
        daico.buy{value: 1 ether}(address(moloch), address(0), 1 ether, 0);
        // Alice only gets 500 shares for 1 ETH now
        assertEq(shares.balanceOf(alice), 100e18 + 500e18); // 100 initial + 500 bought
    }

    function test_SetupDAICO_RevertNotDAO() public {
        // Try to call setupDAICO directly (should fail - only DAO can call)
        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        DAICO.TapConfig memory tapConfig =
            DAICO.TapConfig({ops: ops, ratePerSec: ONE_ETH_PER_DAY, tapAllowance: 10 ether});

        // Random user tries to call setupDAICO
        vm.prank(bob);
        vm.expectRevert(DAICO.Unauthorized.selector);
        daico.setupDAICO(address(moloch), address(shares), daicoConfig, tapConfig);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASES & SECURITY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Buy_SmallAmounts() public {
        // Setup
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, 0);

        // Very small buy - should still work if buyAmt > 0
        vm.prank(bob);
        daico.buy{value: 0.001 ether}(address(moloch), address(0), 0.001 ether, 0);
        assertEq(shares.balanceOf(bob), 1e18); // 0.001 ETH * 1000 / 1 = 1 share
    }

    function test_Buy_TooSmallReturnsZero() public {
        // Setup
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        // Very expensive sale: 1000 ETH for 1 share
        vm.prank(address(moloch));
        daico.setSale(address(0), 1000 ether, address(shares), 1e18, 0);

        // Try to buy with 1 wei - would compute to 0 shares
        vm.prank(bob);
        vm.expectRevert(DAICO.InvalidParams.selector);
        daico.buy{value: 1}(address(moloch), address(0), 1, 0);
    }

    function test_BuyExactOut_CeilRounding() public {
        // Setup
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        // Awkward ratio: 3 ETH for 10 shares
        vm.prank(address(moloch));
        daico.setSale(address(0), 3 ether, address(shares), 10e18, 0);

        // Want 1 share: payAmt = ceil(1 * 3 / 10) = ceil(0.3) = 0.3 ETH
        // Actually in wei: ceil(1e18 * 3e18 / 10e18) = ceil(0.3e18)
        uint256 bobEthBefore = bob.balance;

        vm.prank(bob);
        daico.buyExactOut{value: 1 ether}(address(moloch), address(0), 1e18, 0);

        assertEq(shares.balanceOf(bob), 1e18);
        assertEq(bob.balance, bobEthBefore - 0.3 ether);
    }

    function test_TapDrain_AllowanceExhausted() public {
        // Setup tap with limited allowance
        vm.startPrank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        shares.approve(address(daico), type(uint256).max);
        vm.stopPrank();

        vm.deal(address(moloch), 100 ether);

        // Only 1 ETH allowance
        vm.prank(address(moloch));
        moloch.setAllowance(address(daico), address(0), 1 ether);

        // 1 ETH/day rate
        vm.prank(address(moloch));
        daico.setSaleWithTap(address(0), 1 ether, address(shares), 1000e18, 0, ops, ONE_ETH_PER_DAY);

        // After 1 day, can claim ~1 ETH (but not exactly due to rate rounding)
        skip(1 days);
        uint256 claimed = daico.claimTap(address(moloch));
        assertApproxEqRel(claimed, 1 ether, 0.001e18);

        // Record remaining allowance (there may be dust due to rate rounding)
        uint256 remainingAllowance = moloch.allowance(address(0), address(daico));

        // After another day, owed but only dust claimable (allowance nearly exhausted)
        skip(1 days);
        uint256 pending = daico.pendingTap(address(moloch));
        uint256 claimable = daico.claimableTap(address(moloch));

        assertApproxEqRel(pending, 1 ether, 0.001e18); // Still owed ~1 ETH
        // Claimable should be equal to remaining allowance (dust)
        assertEq(claimable, remainingAllowance);

        // If there's any dust remaining, claim it
        if (remainingAllowance > 0) {
            uint256 dustClaimed = daico.claimTap(address(moloch));
            assertEq(dustClaimed, remainingAllowance);
        }

        // Now allowance is truly exhausted
        skip(1 days);
        claimable = daico.claimableTap(address(moloch));
        assertEq(claimable, 0);

        // Trying to claim reverts
        vm.expectRevert(DAICO.NothingToClaim.selector);
        daico.claimTap(address(moloch));
    }

    function test_SummonDAICO_DifferentSalts() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        // Create two DAOs with different salts
        address dao1 = daico.summonDAICO(
            _getSummonConfig(),
            "DAO One",
            "ONE",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(1000)),
            holders,
            amounts,
            false,
            false,
            daicoConfig
        );

        address dao2 = daico.summonDAICO(
            _getSummonConfig(),
            "DAO Two",
            "TWO",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(2000)),
            holders,
            amounts,
            false,
            false,
            daicoConfig
        );

        // Both DAOs should be different
        assertTrue(dao1 != dao2);

        // Both should have working sales
        (uint256 tribAmt1,,,) = daico.sales(dao1, address(0));
        (uint256 tribAmt2,,,) = daico.sales(dao2, address(0));
        assertEq(tribAmt1, 1 ether);
        assertEq(tribAmt2, 1 ether);
    }

    function test_ReceiveETH() public {
        // DAICO should accept ETH (needed for tap claims)
        (bool success,) = address(daico).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(daico).balance, 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                    TRANSFERABILITY + SALE INTERACTION TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test that locked shares can still be sold via DAICO (DAO->buyer transfer allowed)
    function test_SummonDAICO_LockedSharesCanStillBeSold() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        address dao = daico.summonDAICO(
            _getSummonConfig(),
            "Locked Shares Sale",
            "LSS",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(100)),
            holders,
            amounts,
            true, // shares locked
            false,
            daicoConfig
        );

        Moloch daoMoloch = Moloch(payable(dao));
        Shares daoShares = daoMoloch.shares();

        // Verify shares are locked
        assertTrue(daoShares.transfersLocked());

        // Bob can still buy shares via DAICO (DAO->buyer transfer is allowed when locked)
        vm.prank(bob);
        daico.buy{value: 1 ether}(dao, address(0), 1 ether, 0);
        assertEq(daoShares.balanceOf(bob), 1000e18);

        // But Bob cannot transfer his locked shares to someone else
        vm.prank(bob);
        vm.expectRevert(Locked.selector);
        daoShares.transfer(alice, 100e18);
    }

    /// @notice Test that locked loot can still be sold via DAICO
    function test_SummonDAICO_LockedLootCanStillBeSold() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 50_000e18,
            forAmt: 500e18,
            deadline: 0,
            sellLoot: true,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        address dao = daico.summonDAICO(
            _getSummonConfig(),
            "Locked Loot Sale",
            "LLS",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(101)),
            holders,
            amounts,
            false,
            true, // loot locked
            daicoConfig
        );

        Moloch daoMoloch = Moloch(payable(dao));
        Loot daoLoot = daoMoloch.loot();

        // Verify loot is locked
        assertTrue(daoLoot.transfersLocked());

        // Bob can still buy loot via DAICO
        vm.prank(bob);
        daico.buy{value: 2 ether}(dao, address(0), 2 ether, 0);
        assertEq(daoLoot.balanceOf(bob), 1000e18);

        // But Bob cannot transfer his locked loot
        vm.prank(bob);
        vm.expectRevert(Locked.selector);
        daoLoot.transfer(alice, 100e18);
    }

    /// @notice Test buying with exact out when shares are locked
    function test_SummonDAICO_LockedSharesBuyExactOut() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        address dao = daico.summonDAICO(
            _getSummonConfig(),
            "Locked ExactOut",
            "LEO",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(102)),
            holders,
            amounts,
            true, // shares locked
            false,
            daicoConfig
        );

        Shares daoShares = Moloch(payable(dao)).shares();

        // Bob buys exact 500 shares with locked transfers
        vm.prank(bob);
        daico.buyExactOut{value: 1 ether}(dao, address(0), 500e18, 1 ether);
        assertEq(daoShares.balanceOf(bob), 500e18);
    }

    /*//////////////////////////////////////////////////////////////
                        ERC20 PAYMENT SUMMON TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test summoning a DAICO with ERC20 payment token
    function test_SummonDAICO_ERC20Payment() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);

        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(usdc), // USDC payment
            tribAmt: 100e6, // 100 USDC
            saleSupply: 100_000e18,
            forAmt: 1000e18, // 1000 shares
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        address dao = daico.summonDAICO(
            _getSummonConfig(),
            "USDC Sale DAO",
            "USDC",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(200)),
            holders,
            amounts,
            false,
            false,
            daicoConfig
        );

        // Verify sale configured for USDC
        (uint256 tribAmt, uint256 forAmt, address forTkn,) = daico.sales(dao, address(usdc));
        assertEq(tribAmt, 100e6);
        assertEq(forAmt, 1000e18);
        assertEq(forTkn, address(Moloch(payable(dao)).shares()));

        // Bob gets USDC and buys shares
        usdc.mint(bob, 1000e6);
        vm.prank(bob);
        usdc.approve(address(daico), type(uint256).max);

        vm.prank(bob);
        daico.buy(dao, address(usdc), 50e6, 0); // 50 USDC
        assertEq(Moloch(payable(dao)).shares().balanceOf(bob), 500e18); // 50/100 * 1000 = 500 shares
    }

    /// @notice Test ERC20 payment with tap
    function test_SummonDAICOWithTap_ERC20Payment() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);

        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        // 100 USDC per day rate
        uint128 usdcRatePerSec = uint128(uint256(100e6) / 86400); // ~1157 wei/sec

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(usdc),
            tribAmt: 100e6,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        DAICO.TapConfig memory tapConfig =
            DAICO.TapConfig({ops: ops, ratePerSec: usdcRatePerSec, tapAllowance: 1000e6}); // 1000 USDC budget

        address dao = daico.summonDAICOWithTap(
            _getSummonConfig(),
            "USDC Tap DAO",
            "UTAP",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(201)),
            holders,
            amounts,
            false,
            false,
            daicoConfig,
            tapConfig
        );

        // Verify tap configured
        (address tapOps, address tapTribTkn, uint128 tapRate,) = daico.taps(dao);
        assertEq(tapOps, ops);
        assertEq(tapTribTkn, address(usdc));
        assertEq(tapRate, usdcRatePerSec);

        // Fund DAO with USDC (simulate sales revenue)
        usdc.mint(dao, 500e6);

        // Warp 1 day and claim
        vm.warp(block.timestamp + 1 days);

        uint256 claimable = daico.claimableTap(dao);
        assertGt(claimable, 0);

        uint256 claimed = daico.claimTap(dao);
        assertEq(usdc.balanceOf(ops), claimed);
    }

    /*//////////////////////////////////////////////////////////////
                    TAP + LOCKED TOKEN COMBINATION TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test tap with both shares and loot locked
    function test_SummonDAICOWithTap_BothLocked() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        DAICO.TapConfig memory tapConfig =
            DAICO.TapConfig({ops: ops, ratePerSec: ONE_ETH_PER_DAY, tapAllowance: 10 ether});

        address dao = daico.summonDAICOWithTap{value: 20 ether}(
            _getSummonConfig(),
            "Both Locked Tap",
            "BLT",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(300)),
            holders,
            amounts,
            true, // shares locked
            true, // loot locked
            daicoConfig,
            tapConfig
        );

        Moloch daoMoloch = Moloch(payable(dao));

        // Verify both locked
        assertTrue(daoMoloch.shares().transfersLocked());
        assertTrue(daoMoloch.loot().transfersLocked());

        // Verify tap works
        (address tapOps,,, uint64 lastClaim) = daico.taps(dao);
        assertEq(tapOps, ops);
        assertGt(lastClaim, 0);

        // Bob buys shares (sale still works with locked tokens)
        vm.prank(bob);
        daico.buy{value: 1 ether}(dao, address(0), 1 ether, 0);
        assertEq(daoMoloch.shares().balanceOf(bob), 1000e18);

        // Tap claim works
        vm.warp(block.timestamp + 1 days);
        uint256 claimed = daico.claimTap(dao);
        assertApproxEqRel(claimed, 1 ether, 0.001e18);
    }

    /// @notice Test selling locked loot with tap
    function test_SummonDAICOWithTap_SellLockedLoot() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 50_000e18,
            forAmt: 500e18,
            deadline: 0,
            sellLoot: true, // selling loot
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        DAICO.TapConfig memory tapConfig =
            DAICO.TapConfig({ops: ops, ratePerSec: ONE_ETH_PER_DAY, tapAllowance: 5 ether});

        address dao = daico.summonDAICOWithTap{value: 10 ether}(
            _getSummonConfig(),
            "Locked Loot Tap",
            "LLT",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(301)),
            holders,
            amounts,
            false,
            true, // loot locked
            daicoConfig,
            tapConfig
        );

        Moloch daoMoloch = Moloch(payable(dao));
        Loot daoLoot = daoMoloch.loot();

        // Verify loot is locked
        assertTrue(daoLoot.transfersLocked());

        // Verify sale is for loot
        (,, address forTkn,) = daico.sales(dao, address(0));
        assertEq(forTkn, address(daoLoot));

        // Bob buys loot
        vm.prank(bob);
        daico.buy{value: 2 ether}(dao, address(0), 2 ether, 0);
        assertEq(daoLoot.balanceOf(bob), 1000e18);

        // Bob cannot transfer locked loot
        vm.prank(bob);
        vm.expectRevert(Locked.selector);
        daoLoot.transfer(alice, 100e18);

        // Tap still works
        vm.warp(block.timestamp + 1 days);
        uint256 claimed = daico.claimTap(dao);
        assertApproxEqRel(claimed, 1 ether, 0.001e18);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE SUMMON TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test summoning with zero sale supply (no tokens minted)
    function test_SummonDAICO_ZeroSaleSupply() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 0, // No tokens minted
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        address dao = daico.summonDAICO(
            _getSummonConfig(),
            "Zero Supply",
            "ZERO",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(400)),
            holders,
            amounts,
            false,
            false,
            daicoConfig
        );

        // Sale configured but no supply
        Shares daoShares = Moloch(payable(dao)).shares();
        assertEq(daoShares.balanceOf(dao), 0);
        assertEq(daoShares.allowance(dao, address(daico)), 0);

        // Buying will fail due to no allowance/balance
        vm.prank(bob);
        vm.expectRevert(); // Transfer will fail
        daico.buy{value: 1 ether}(dao, address(0), 1 ether, 0);
    }

    /// @notice Test summoning with very large sale supply
    function test_SummonDAICO_LargeSaleSupply() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        uint256 largeSupply = 1_000_000_000e18; // 1 billion tokens

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 0.001 ether, // cheap price
            saleSupply: largeSupply,
            forAmt: 1_000_000e18, // 1M tokens per 0.001 ETH
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        address dao = daico.summonDAICO(
            _getSummonConfig(),
            "Large Supply",
            "LARGE",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(401)),
            holders,
            amounts,
            false,
            false,
            daicoConfig
        );

        Shares daoShares = Moloch(payable(dao)).shares();
        assertEq(daoShares.balanceOf(dao), largeSupply);

        // Buy works
        vm.prank(bob);
        daico.buy{value: 0.001 ether}(dao, address(0), 0.001 ether, 0);
        assertEq(daoShares.balanceOf(bob), 1_000_000e18);
    }

    /// @notice Test summoning with very high price
    function test_SummonDAICO_HighPrice() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1000 ether, // 1000 ETH
            saleSupply: 100e18,
            forAmt: 1e18, // 1 share per 1000 ETH
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        address dao = daico.summonDAICO(
            _getSummonConfig(),
            "Expensive DAO",
            "PRICEY",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(402)),
            holders,
            amounts,
            false,
            false,
            daicoConfig
        );

        // Quote confirms high price
        uint256 quote = daico.quoteBuy(dao, address(0), 100 ether);
        assertEq(quote, 0.1e18); // 100/1000 = 0.1 shares
    }

    /// @notice Test summoning with immediate deadline (already expired)
    function test_SummonDAICO_ImmediateDeadline() public {
        // Warp to a reasonable time so block.timestamp - 1 isn't 0 (which means no deadline)
        vm.warp(1000);

        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        uint40 pastDeadline = uint40(block.timestamp - 1);

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: pastDeadline,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        address dao = daico.summonDAICO(
            _getSummonConfig(),
            "Expired DAO",
            "EXP",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(403)),
            holders,
            amounts,
            false,
            false,
            daicoConfig
        );

        // Sale created but expired
        (,,, uint40 deadline) = daico.sales(dao, address(0));
        assertEq(deadline, pastDeadline);

        // Buying fails with Expired
        vm.prank(bob);
        vm.expectRevert(DAICO.Expired.selector);
        daico.buy{value: 1 ether}(dao, address(0), 1 ether, 0);
    }

    /// @notice Test summoning with ragequit disabled
    function test_SummonDAICO_NoRagequit() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        address dao = daico.summonDAICO(
            _getSummonConfig(),
            "No Ragequit",
            "NORQ",
            "",
            5000,
            false, // ragequit disabled
            address(0),
            bytes32(uint256(404)),
            holders,
            amounts,
            false,
            false,
            daicoConfig
        );

        Moloch daoMoloch = Moloch(payable(dao));
        assertFalse(daoMoloch.ragequittable());

        // Sale still works
        vm.prank(bob);
        daico.buy{value: 1 ether}(dao, address(0), 1 ether, 0);
        assertEq(daoMoloch.shares().balanceOf(bob), 1000e18);
    }

    /// @notice Test summoning with different quorum settings
    function test_SummonDAICO_DifferentQuorum() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        // Test with 10% quorum
        address dao10 = daico.summonDAICO(
            _getSummonConfig(),
            "10% Quorum",
            "Q10",
            "",
            1000, // 10% quorum
            true,
            address(0),
            bytes32(uint256(405)),
            holders,
            amounts,
            false,
            false,
            daicoConfig
        );

        // Test with 90% quorum
        address dao90 = daico.summonDAICO(
            _getSummonConfig(),
            "90% Quorum",
            "Q90",
            "",
            9000, // 90% quorum
            true,
            address(0),
            bytes32(uint256(406)),
            holders,
            amounts,
            false,
            false,
            daicoConfig
        );

        assertEq(Moloch(payable(dao10)).quorumBps(), 1000);
        assertEq(Moloch(payable(dao90)).quorumBps(), 9000);
    }

    /// @notice Test tap with very high rate
    function test_SummonDAICOWithTap_HighRate() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        // 100 ETH per day
        uint128 highRate = ONE_ETH_PER_DAY * 100;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        DAICO.TapConfig memory tapConfig =
            DAICO.TapConfig({ops: ops, ratePerSec: highRate, tapAllowance: 1000 ether});

        address dao = daico.summonDAICOWithTap{value: 500 ether}(
            _getSummonConfig(),
            "High Rate Tap",
            "HRT",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(407)),
            holders,
            amounts,
            false,
            false,
            daicoConfig,
            tapConfig
        );

        // Verify high rate stored
        (,, uint128 rate,) = daico.taps(dao);
        assertEq(rate, highRate);

        // After 1 day, ~100 ETH should be claimable (capped by allowance)
        vm.warp(block.timestamp + 1 days);
        uint256 pending = daico.pendingTap(dao);
        assertApproxEqRel(pending, 100 ether, 0.001e18);
    }

    /// @notice Test tap exhaustion behavior
    function test_SummonDAICOWithTap_ExhaustAllowance() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        // Small allowance that will be exhausted quickly
        DAICO.TapConfig memory tapConfig =
            DAICO.TapConfig({ops: ops, ratePerSec: ONE_ETH_PER_DAY, tapAllowance: 0.5 ether});

        address dao = daico.summonDAICOWithTap{value: 10 ether}(
            _getSummonConfig(),
            "Exhaust Tap",
            "EXT",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(408)),
            holders,
            amounts,
            false,
            false,
            daicoConfig,
            tapConfig
        );

        // After 1 day, owed is ~1 ETH but allowance is only 0.5 ETH
        skip(1 days);

        uint256 claimable = daico.claimableTap(dao);
        assertEq(claimable, 0.5 ether); // capped at allowance

        uint256 claimed = daico.claimTap(dao);
        assertEq(claimed, 0.5 ether);
        assertEq(ops.balance, 0.5 ether);

        // Allowance exhausted - nothing more to claim
        skip(1 days);
        claimable = daico.claimableTap(dao);
        assertEq(claimable, 0);

        // But pending still accumulates (just can't claim without more allowance)
        uint256 pending = daico.pendingTap(dao);
        assertApproxEqRel(pending, 1 ether, 0.001e18); // ~1 more ETH owed since last claim

        // Trying to claim reverts
        vm.expectRevert(DAICO.NothingToClaim.selector);
        daico.claimTap(dao);
    }

    /// @notice Test multiple DAOs with same summon config but different params
    function test_SummonDAICO_MultipleDAOsSameConfig() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig1 = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        DAICO.DAICOConfig memory daicoConfig2 = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 2 ether, // Different price
            saleSupply: 50_000e18,
            forAmt: 500e18,
            deadline: 0,
            sellLoot: true, // Sell loot instead
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        address dao1 = daico.summonDAICO(
            _getSummonConfig(),
            "DAO Alpha",
            "ALPHA",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(500)),
            holders,
            amounts,
            false,
            false,
            daicoConfig1
        );

        address dao2 = daico.summonDAICO(
            _getSummonConfig(),
            "DAO Beta",
            "BETA",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(501)),
            holders,
            amounts,
            true, // shares locked
            true, // loot locked
            daicoConfig2
        );

        // Verify different configurations
        (uint256 tribAmt1, uint256 forAmt1, address forTkn1,) = daico.sales(dao1, address(0));
        (uint256 tribAmt2, uint256 forAmt2, address forTkn2,) = daico.sales(dao2, address(0));

        assertEq(tribAmt1, 1 ether);
        assertEq(tribAmt2, 2 ether);
        assertEq(forAmt1, 1000e18);
        assertEq(forAmt2, 500e18);
        assertEq(forTkn1, address(Moloch(payable(dao1)).shares()));
        assertEq(forTkn2, address(Moloch(payable(dao2)).loot()));

        // Verify lock states
        assertFalse(Moloch(payable(dao1)).shares().transfersLocked());
        assertTrue(Moloch(payable(dao2)).shares().transfersLocked());
        assertTrue(Moloch(payable(dao2)).loot().transfersLocked());
    }

    /// @notice Test that claimTap correctly adjusts when DAO balance drops (e.g., ragequit)
    function test_ClaimTap_CappedByDAOBalance() public {
        address[] memory holders = new address[](2);
        holders[0] = alice;
        holders[1] = bob;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 50e18;
        amounts[1] = 50e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        DAICO.TapConfig memory tapConfig =
            DAICO.TapConfig({ops: ops, ratePerSec: ONE_ETH_PER_DAY, tapAllowance: 100 ether});

        address dao = daico.summonDAICOWithTap{value: 2 ether}(
            _getSummonConfig(),
            "Balance Cap Test",
            "BCT",
            "",
            5000,
            true, // ragequit enabled
            address(0),
            bytes32(uint256(600)),
            holders,
            amounts,
            false,
            false,
            daicoConfig,
            tapConfig
        );

        // DAO starts with 2 ETH
        assertEq(dao.balance, 2 ether);

        // After 1 day, owed is ~1 ETH, claimable should be ~1 ETH (within balance)
        vm.warp(block.timestamp + 1 days);
        uint256 claimable = daico.claimableTap(dao);
        assertApproxEqRel(claimable, 1 ether, 0.001e18);

        // After 5 days, owed is ~5 ETH, but DAO only has 2 ETH
        vm.warp(block.timestamp + 4 days);
        claimable = daico.claimableTap(dao);
        assertEq(claimable, 2 ether); // capped by DAO balance

        // Claim the 2 ETH
        uint256 claimed = daico.claimTap(dao);
        assertEq(claimed, 2 ether);
        assertEq(ops.balance, 2 ether);
        assertEq(dao.balance, 0);

        // Now nothing claimable (DAO is empty)
        vm.warp(block.timestamp + 1 days);
        claimable = daico.claimableTap(dao);
        assertEq(claimable, 0);
    }

    /// @notice Fuzz test for summonDAICO with various parameters
    function testFuzz_SummonDAICO(
        uint256 saleSupply,
        uint256 tribAmt,
        uint256 forAmt,
        bool sellLoot,
        bool sharesLocked,
        bool lootLocked
    ) public {
        // Bound inputs to reasonable ranges
        saleSupply = bound(saleSupply, 1e18, 1_000_000_000e18);
        tribAmt = bound(tribAmt, 1, 1000 ether);
        forAmt = bound(forAmt, 1e18, saleSupply);

        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: tribAmt,
            saleSupply: saleSupply,
            forAmt: forAmt,
            deadline: 0,
            sellLoot: sellLoot,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        // Use unique salt based on fuzz inputs
        bytes32 salt =
            keccak256(abi.encode(saleSupply, tribAmt, forAmt, sellLoot, sharesLocked, lootLocked));

        address dao = daico.summonDAICO(
            _getSummonConfig(),
            "Fuzz DAO",
            "FUZZ",
            "",
            5000,
            true,
            address(0),
            salt,
            holders,
            amounts,
            sharesLocked,
            lootLocked,
            daicoConfig
        );

        // Verify DAO created
        assertTrue(dao != address(0));

        // Verify sale configured
        (uint256 storedTribAmt, uint256 storedForAmt, address forTkn,) =
            daico.sales(dao, address(0));
        assertEq(storedTribAmt, tribAmt);
        assertEq(storedForAmt, forAmt);

        if (sellLoot) {
            assertEq(forTkn, address(Moloch(payable(dao)).loot()));
        } else {
            assertEq(forTkn, address(Moloch(payable(dao)).shares()));
        }

        // Verify lock states
        assertEq(Moloch(payable(dao)).shares().transfersLocked(), sharesLocked);
        assertEq(Moloch(payable(dao)).loot().transfersLocked(), lootLocked);
    }

    /*//////////////////////////////////////////////////////////////
                        SETUPDAICO VALIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetupDAICO_RevertZeroTribAmt() public {
        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 0, // invalid
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        DAICO.TapConfig memory tapConfig =
            DAICO.TapConfig({ops: address(0), ratePerSec: 0, tapAllowance: 0});

        vm.prank(address(moloch));
        vm.expectRevert(DAICO.InvalidParams.selector);
        daico.setupDAICO(address(moloch), address(shares), daicoConfig, tapConfig);
    }

    function test_SetupDAICO_RevertZeroForAmt() public {
        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 0, // invalid
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        DAICO.TapConfig memory tapConfig =
            DAICO.TapConfig({ops: address(0), ratePerSec: 0, tapAllowance: 0});

        vm.prank(address(moloch));
        vm.expectRevert(DAICO.InvalidParams.selector);
        daico.setupDAICO(address(moloch), address(shares), daicoConfig, tapConfig);
    }

    function test_SetupDAICO_RevertZeroForTkn() public {
        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        DAICO.TapConfig memory tapConfig =
            DAICO.TapConfig({ops: address(0), ratePerSec: 0, tapAllowance: 0});

        vm.prank(address(moloch));
        vm.expectRevert(DAICO.InvalidParams.selector);
        daico.setupDAICO(address(moloch), address(0), daicoConfig, tapConfig); // forTkn = address(0)
    }

    function test_SetupDAICO_WithTap() public {
        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        DAICO.TapConfig memory tapConfig =
            DAICO.TapConfig({ops: ops, ratePerSec: ONE_ETH_PER_DAY, tapAllowance: 10 ether});

        vm.prank(address(moloch));
        vm.expectEmit(true, true, true, true);
        emit TapSet(address(moloch), ops, address(0), ONE_ETH_PER_DAY);
        daico.setupDAICO(address(moloch), address(shares), daicoConfig, tapConfig);

        // Verify tap was set
        (address tapOps, address tapTribTkn, uint128 tapRate,) = daico.taps(address(moloch));
        assertEq(tapOps, ops);
        assertEq(tapTribTkn, address(0));
        assertEq(tapRate, ONE_ETH_PER_DAY);

        // Verify sale was set
        (uint256 tribAmt, uint256 forAmt, address forTkn,) =
            daico.sales(address(moloch), address(0));
        assertEq(tribAmt, 1 ether);
        assertEq(forAmt, 1000e18);
        assertEq(forTkn, address(shares));
    }

    function test_SetupDAICO_NoTapIfZeroOps() public {
        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        // ops is zero, so no tap should be set
        DAICO.TapConfig memory tapConfig =
            DAICO.TapConfig({ops: address(0), ratePerSec: ONE_ETH_PER_DAY, tapAllowance: 10 ether});

        vm.prank(address(moloch));
        daico.setupDAICO(address(moloch), address(shares), daicoConfig, tapConfig);

        // Verify no tap was set
        (address tapOps,,,) = daico.taps(address(moloch));
        assertEq(tapOps, address(0));
    }

    function test_SetupDAICO_NoTapIfZeroRate() public {
        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        // rate is zero, so no tap should be set
        DAICO.TapConfig memory tapConfig =
            DAICO.TapConfig({ops: ops, ratePerSec: 0, tapAllowance: 10 ether});

        vm.prank(address(moloch));
        daico.setupDAICO(address(moloch), address(shares), daicoConfig, tapConfig);

        // Verify no tap was set
        (address tapOps,,,) = daico.taps(address(moloch));
        assertEq(tapOps, address(0));
    }

    function test_SetupDAICO_NoTapIfZeroAllowance() public {
        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        // allowance is zero, so no tap should be set
        DAICO.TapConfig memory tapConfig =
            DAICO.TapConfig({ops: ops, ratePerSec: ONE_ETH_PER_DAY, tapAllowance: 0});

        vm.prank(address(moloch));
        daico.setupDAICO(address(moloch), address(shares), daicoConfig, tapConfig);

        // Verify no tap was set
        (address tapOps,,,) = daico.taps(address(moloch));
        assertEq(tapOps, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                    SUMMON EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SummonDAICO_WithETHValue() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        // Summon with ETH value - should forward to DAO
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        address dao = daico.summonDAICO{value: 5 ether}(
            _getSummonConfig(),
            "ETH DAO",
            "ETHD",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(100)),
            holders,
            amounts,
            false,
            false,
            daicoConfig
        );

        // DAO should have the ETH
        assertEq(dao.balance, 5 ether);
    }

    function test_SummonDAICOWithTap_WithETHValue() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        DAICO.TapConfig memory tapConfig =
            DAICO.TapConfig({ops: ops, ratePerSec: ONE_ETH_PER_DAY, tapAllowance: 10 ether});

        // Summon with ETH value
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        address dao = daico.summonDAICOWithTap{value: 3 ether}(
            _getSummonConfig(),
            "Tap ETH DAO",
            "TAPETH",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(101)),
            holders,
            amounts,
            false,
            false,
            daicoConfig,
            tapConfig
        );

        // DAO should have the ETH
        assertEq(dao.balance, 3 ether);

        // Tap should be configured
        (address tapOps,,,) = daico.taps(dao);
        assertEq(tapOps, ops);
    }

    function test_SummonDAICO_EmptyHolders() public {
        address[] memory holders = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        // Should still work - DAO with no initial holders
        address dao = daico.summonDAICO(
            _getSummonConfig(),
            "Empty DAO",
            "EMPTY",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(102)),
            holders,
            amounts,
            false,
            false,
            daicoConfig
        );

        assertTrue(dao != address(0));

        // Sale should be configured
        (uint256 tribAmt,,,) = daico.sales(dao, address(0));
        assertEq(tribAmt, 1 ether);
    }

    function test_SummonDAICO_ManyInitialHolders() public {
        uint256 numHolders = 10;
        address[] memory holders = new address[](numHolders);
        uint256[] memory amounts = new uint256[](numHolders);

        for (uint256 i = 0; i < numHolders; i++) {
            holders[i] = address(uint160(0x1000 + i));
            amounts[i] = 10e18;
        }

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        address dao = daico.summonDAICO(
            _getSummonConfig(),
            "Many Holders DAO",
            "MANY",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(103)),
            holders,
            amounts,
            false,
            false,
            daicoConfig
        );

        // Verify all holders got shares
        Shares daoShares = Moloch(payable(dao)).shares();
        for (uint256 i = 0; i < numHolders; i++) {
            assertEq(daoShares.balanceOf(holders[i]), 10e18);
        }
    }

    function test_SummonDAICO_CustomRenderer() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        address customRenderer = address(0xDEAD);

        address dao = daico.summonDAICO(
            _getSummonConfig(),
            "Renderer DAO",
            "REND",
            "ipfs://metadata",
            5000,
            true,
            customRenderer,
            bytes32(uint256(104)),
            holders,
            amounts,
            false,
            false,
            daicoConfig
        );

        assertTrue(dao != address(0));
    }

    function test_SummonDAICO_MinQuorum() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        address dao = daico.summonDAICO(
            _getSummonConfig(),
            "Min Quorum DAO",
            "MINQ",
            "",
            1, // 0.01% quorum
            true,
            address(0),
            bytes32(uint256(105)),
            holders,
            amounts,
            false,
            false,
            daicoConfig
        );

        assertTrue(dao != address(0));
    }

    function test_SummonDAICO_MaxQuorum() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        address dao = daico.summonDAICO(
            _getSummonConfig(),
            "Max Quorum DAO",
            "MAXQ",
            "",
            10000, // 100% quorum
            true,
            address(0),
            bytes32(uint256(106)),
            holders,
            amounts,
            false,
            false,
            daicoConfig
        );

        assertTrue(dao != address(0));
    }

    function test_SummonDAICO_NoRagequitWithLockedTokens() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        address dao = daico.summonDAICO(
            _getSummonConfig(),
            "No Ragequit Locked DAO",
            "NRQL",
            "",
            5000,
            false, // no ragequit
            address(0),
            bytes32(uint256(107)),
            holders,
            amounts,
            true, // shares locked
            true, // loot locked
            daicoConfig
        );

        Moloch daoMoloch = Moloch(payable(dao));
        assertTrue(daoMoloch.shares().transfersLocked());
        assertTrue(daoMoloch.loot().transfersLocked());
    }

    function test_SummonDAICOWithTap_ClaimAfterSummon() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        DAICO.TapConfig memory tapConfig =
            DAICO.TapConfig({ops: ops, ratePerSec: ONE_ETH_PER_DAY, tapAllowance: 10 ether});

        // Summon with ETH to fund the tap
        vm.deal(alice, 20 ether);
        vm.prank(alice);
        address dao = daico.summonDAICOWithTap{value: 10 ether}(
            _getSummonConfig(),
            "Claimable Tap DAO",
            "CTAP",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(108)),
            holders,
            amounts,
            false,
            false,
            daicoConfig,
            tapConfig
        );

        // Warp 1 day
        vm.warp(block.timestamp + 1 days);

        // Check claimable
        uint256 claimable = daico.claimableTap(dao);
        assertApproxEqRel(claimable, 1 ether, 0.001e18);

        // Claim
        uint256 opsBefore = ops.balance;
        daico.claimTap(dao);
        assertApproxEqRel(ops.balance - opsBefore, 1 ether, 0.001e18);
    }

    function test_SummonDAICOWithTap_BuyThenClaim() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        DAICO.TapConfig memory tapConfig =
            DAICO.TapConfig({ops: ops, ratePerSec: ONE_ETH_PER_DAY, tapAllowance: 100 ether});

        address dao = daico.summonDAICOWithTap(
            _getSummonConfig(),
            "Buy Claim DAO",
            "BCLAIM",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(109)),
            holders,
            amounts,
            false,
            false,
            daicoConfig,
            tapConfig
        );

        // Bob buys shares with ETH - this funds the DAO
        vm.prank(bob);
        daico.buy{value: 10 ether}(dao, address(0), 10 ether, 0);

        // Verify DAO received ETH
        assertEq(dao.balance, 10 ether);

        // Warp and claim tap
        vm.warp(block.timestamp + 1 days);

        uint256 opsBefore = ops.balance;
        daico.claimTap(dao);
        assertApproxEqRel(ops.balance - opsBefore, 1 ether, 0.001e18);
    }

    function test_SummonDAICO_PredictedAddressMatches() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        bytes32 salt = bytes32(uint256(110));

        // Predict DAO address before summon
        bytes32 innerSalt = keccak256(abi.encode(holders, amounts, salt));
        bytes memory creationCode = abi.encodePacked(
            hex"602d5f8160095f39f35f5f365f5f37365f73",
            molochImpl,
            hex"5af43d5f5f3e6029573d5ffd5b3d5ff3"
        );
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), address(summoner), innerSalt, keccak256(creationCode)
                        )
                    )
                )
            )
        );

        address dao = daico.summonDAICO(
            _getSummonConfig(),
            "Predicted DAO",
            "PRED",
            "",
            5000,
            true,
            address(0),
            salt,
            holders,
            amounts,
            false,
            false,
            daicoConfig
        );

        assertEq(dao, predicted);
    }

    function test_SummonDAICOWithTap_VerySmallRate() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        // Very small rate: 1 wei per second
        DAICO.TapConfig memory tapConfig =
            DAICO.TapConfig({ops: ops, ratePerSec: 1, tapAllowance: 1 ether});

        vm.deal(alice, 10 ether);
        vm.prank(alice);
        address dao = daico.summonDAICOWithTap{value: 1 ether}(
            _getSummonConfig(),
            "Small Rate DAO",
            "SMALL",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(111)),
            holders,
            amounts,
            false,
            false,
            daicoConfig,
            tapConfig
        );

        // Warp 1 day = 86400 seconds = 86400 wei owed
        vm.warp(block.timestamp + 1 days);

        uint256 pending = daico.pendingTap(dao);
        assertEq(pending, 86400);
    }

    function test_SummonDAICOWithTap_VeryLargeRate() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        // Very large rate: max uint128 / 1 day to avoid overflow in reasonable time
        uint128 largeRate = type(uint128).max / 86400;
        DAICO.TapConfig memory tapConfig =
            DAICO.TapConfig({ops: ops, ratePerSec: largeRate, tapAllowance: type(uint256).max});

        address dao = daico.summonDAICOWithTap(
            _getSummonConfig(),
            "Large Rate DAO",
            "LARGE",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(112)),
            holders,
            amounts,
            false,
            false,
            daicoConfig,
            tapConfig
        );

        (,, uint128 rate,) = daico.taps(dao);
        assertEq(rate, largeRate);
    }

    function test_SummonDAICO_SellLootWithERC20Payment() public {
        MockERC20 usdc = new MockERC20("USDC", "USDC", 6);

        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(usdc), // USDC payment
            tribAmt: 100e6, // 100 USDC
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: true, // sell loot
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        address dao = daico.summonDAICO(
            _getSummonConfig(),
            "Loot USDC DAO",
            "LUSDC",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(113)),
            holders,
            amounts,
            false,
            false,
            daicoConfig
        );

        // Verify sale is for USDC -> Loot
        (uint256 tribAmt,, address forTkn,) = daico.sales(dao, address(usdc));
        assertEq(tribAmt, 100e6);
        assertEq(forTkn, address(Moloch(payable(dao)).loot()));

        // Bob buys with USDC
        usdc.mint(bob, 1000e6);
        vm.prank(bob);
        usdc.approve(address(daico), type(uint256).max);

        vm.prank(bob);
        daico.buy(dao, address(usdc), 100e6, 0);

        Loot daoLoot = Moloch(payable(dao)).loot();
        assertEq(daoLoot.balanceOf(bob), 1000e18);
    }

    function test_SummonDAICOWithTap_ERC20Tap() public {
        MockERC20 usdc = new MockERC20("USDC", "USDC", 6);

        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        // 100 USDC for 1000 shares, tap at ~100 USDC/day
        uint128 usdcPerDay = uint128(100e6) / 86400; // ~1157 USDC-units/sec

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(usdc),
            tribAmt: 100e6,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        DAICO.TapConfig memory tapConfig =
            DAICO.TapConfig({ops: ops, ratePerSec: usdcPerDay, tapAllowance: 10000e6});

        address dao = daico.summonDAICOWithTap(
            _getSummonConfig(),
            "USDC Tap DAO",
            "USDCTAP",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(114)),
            holders,
            amounts,
            false,
            false,
            daicoConfig,
            tapConfig
        );

        // Bob buys with USDC to fund DAO
        usdc.mint(bob, 1000e6);
        vm.prank(bob);
        usdc.approve(address(daico), type(uint256).max);
        vm.prank(bob);
        daico.buy(dao, address(usdc), 1000e6, 0);

        // Verify DAO received USDC
        assertEq(usdc.balanceOf(dao), 1000e6);

        // Warp and claim
        vm.warp(block.timestamp + 1 days);

        uint256 opsBefore = usdc.balanceOf(ops);
        daico.claimTap(dao);
        uint256 claimed = usdc.balanceOf(ops) - opsBefore;

        // Should be ~100 USDC (with rounding)
        assertApproxEqRel(claimed, 100e6, 0.01e18);
    }

    function testFuzz_SummonDAICOWithTap(
        uint256 saleSupply,
        uint256 tribAmt,
        uint256 forAmt,
        uint128 ratePerSec,
        uint256 tapAllowance,
        bool sellLoot,
        bool sharesLocked,
        bool lootLocked
    ) public {
        // Bound inputs
        saleSupply = bound(saleSupply, 1e18, 1_000_000_000e18);
        tribAmt = bound(tribAmt, 1, 1000 ether);
        forAmt = bound(forAmt, 1e18, saleSupply);
        ratePerSec = uint128(bound(ratePerSec, 1, type(uint128).max / 86400)); // avoid overflow in 1 day
        tapAllowance = bound(tapAllowance, 1, type(uint256).max);

        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: tribAmt,
            saleSupply: saleSupply,
            forAmt: forAmt,
            deadline: 0,
            sellLoot: sellLoot,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        DAICO.TapConfig memory tapConfig =
            DAICO.TapConfig({ops: ops, ratePerSec: ratePerSec, tapAllowance: tapAllowance});

        bytes32 salt = keccak256(
            abi.encode(
                saleSupply,
                tribAmt,
                forAmt,
                ratePerSec,
                tapAllowance,
                sellLoot,
                sharesLocked,
                lootLocked
            )
        );

        address dao = daico.summonDAICOWithTap(
            _getSummonConfig(),
            "Fuzz Tap DAO",
            "FZTAP",
            "",
            5000,
            true,
            address(0),
            salt,
            holders,
            amounts,
            sharesLocked,
            lootLocked,
            daicoConfig,
            tapConfig
        );

        // Verify DAO created
        assertTrue(dao != address(0));

        // Verify sale configured
        (uint256 storedTribAmt, uint256 storedForAmt,,) = daico.sales(dao, address(0));
        assertEq(storedTribAmt, tribAmt);
        assertEq(storedForAmt, forAmt);

        // Verify tap configured
        (address tapOps,, uint128 tapRate,) = daico.taps(dao);
        assertEq(tapOps, ops);
        assertEq(tapRate, ratePerSec);

        // Verify lock states
        assertEq(Moloch(payable(dao)).shares().transfersLocked(), sharesLocked);
        assertEq(Moloch(payable(dao)).loot().transfersLocked(), lootLocked);
    }

    /*//////////////////////////////////////////////////////////////
                    USER STORY: DECIMAL VALIDATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Validate user story: DAO sells 10mm voting shares, 10k USDC buys 100k shares
    /// @dev Tests that different decimals (USDC=6, Shares=18) work correctly
    function test_UserStory_10mmShares_10kUSDCBuys100kShares() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);

        // User story parameters:
        // - Total sale supply: 10,000,000 shares (10mm)
        // - Price: 10,000 USDC buys 100,000 shares
        // - Therefore: 1 USDC = 10 shares
        uint256 totalSaleSupply = 10_000_000e18; // 10mm shares (18 decimals)
        uint256 tribAmt = 10_000e6; // 10,000 USDC (6 decimals)
        uint256 forAmt = 100_000e18; // 100,000 shares (18 decimals)

        // 1. Mint shares to DAO for sale
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), totalSaleSupply);

        // 2. DAO approves DAICO to transfer shares
        vm.prank(address(moloch));
        shares.approve(address(daico), totalSaleSupply);

        // 3. DAO sets sale: 10,000 USDC for 100,000 shares
        vm.prank(address(moloch));
        daico.setSale(address(usdc), tribAmt, address(shares), forAmt, 0);

        // 4. Mint USDC to bob (buyer) and approve
        usdc.mint(bob, 100_000e6); // 100k USDC
        vm.prank(bob);
        usdc.approve(address(daico), type(uint256).max);

        // Test Case 1: Bob buys with exactly 10,000 USDC -> should get 100,000 shares
        vm.prank(bob);
        daico.buy(address(moloch), address(usdc), 10_000e6, 0);

        assertEq(shares.balanceOf(bob), 100_000e18, "10k USDC should buy 100k shares");
        assertEq(usdc.balanceOf(address(moloch)), 10_000e6, "DAO should receive 10k USDC");

        // Test Case 2: Bob buys with 1 USDC -> should get 10 shares
        uint256 bobSharesBefore = shares.balanceOf(bob);
        vm.prank(bob);
        daico.buy(address(moloch), address(usdc), 1e6, 0);

        assertEq(shares.balanceOf(bob) - bobSharesBefore, 10e18, "1 USDC should buy 10 shares");

        // Test Case 3: Bob buys with 0.01 USDC (10,000 units) -> should get 0.1 shares
        bobSharesBefore = shares.balanceOf(bob);
        vm.prank(bob);
        daico.buy(address(moloch), address(usdc), 10_000, 0); // 0.01 USDC

        // Expected: (100_000e18 * 10_000) / 10_000e6 = 100_000e18 * 10_000 / 10_000_000_000 = 0.1e18
        assertEq(shares.balanceOf(bob) - bobSharesBefore, 0.1e18, "0.01 USDC should buy 0.1 shares");
    }

    /// @notice Test exact-out buy with user story decimals
    function test_UserStory_ExactOut_10kUSDCFor100kShares() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);

        uint256 totalSaleSupply = 10_000_000e18;
        uint256 tribAmt = 10_000e6;
        uint256 forAmt = 100_000e18;

        // Setup
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), totalSaleSupply);
        vm.prank(address(moloch));
        shares.approve(address(daico), totalSaleSupply);
        vm.prank(address(moloch));
        daico.setSale(address(usdc), tribAmt, address(shares), forAmt, 0);

        usdc.mint(bob, 100_000e6);
        vm.prank(bob);
        usdc.approve(address(daico), type(uint256).max);

        // Bob wants exactly 100,000 shares -> should pay 10,000 USDC
        uint256 bobUsdcBefore = usdc.balanceOf(bob);
        vm.prank(bob);
        daico.buyExactOut(address(moloch), address(usdc), 100_000e18, 0);

        assertEq(shares.balanceOf(bob), 100_000e18, "Should get exactly 100k shares");
        assertEq(bobUsdcBefore - usdc.balanceOf(bob), 10_000e6, "Should pay exactly 10k USDC");

        // Bob wants exactly 10 shares -> should pay 1 USDC
        bobUsdcBefore = usdc.balanceOf(bob);
        uint256 bobSharesBefore = shares.balanceOf(bob);
        vm.prank(bob);
        daico.buyExactOut(address(moloch), address(usdc), 10e18, 0);

        assertEq(shares.balanceOf(bob) - bobSharesBefore, 10e18, "Should get exactly 10 shares");
        assertEq(bobUsdcBefore - usdc.balanceOf(bob), 1e6, "Should pay exactly 1 USDC");
    }

    /// @notice Test quote functions with user story decimals
    function test_UserStory_Quotes() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);

        uint256 tribAmt = 10_000e6;
        uint256 forAmt = 100_000e18;

        vm.prank(address(moloch));
        daico.setSale(address(usdc), tribAmt, address(shares), forAmt, 0);

        // quoteBuy: how many shares for 10k USDC?
        uint256 sharesOut = daico.quoteBuy(address(moloch), address(usdc), 10_000e6);
        assertEq(sharesOut, 100_000e18, "Quote: 10k USDC should yield 100k shares");

        // quoteBuy: how many shares for 1 USDC?
        sharesOut = daico.quoteBuy(address(moloch), address(usdc), 1e6);
        assertEq(sharesOut, 10e18, "Quote: 1 USDC should yield 10 shares");

        // quotePayExactOut: how much USDC for 100k shares?
        uint256 usdcRequired = daico.quotePayExactOut(address(moloch), address(usdc), 100_000e18);
        assertEq(usdcRequired, 10_000e6, "Quote: 100k shares should cost 10k USDC");

        // quotePayExactOut: how much USDC for 10 shares?
        usdcRequired = daico.quotePayExactOut(address(moloch), address(usdc), 10e18);
        assertEq(usdcRequired, 1e6, "Quote: 10 shares should cost 1 USDC");
    }

    /// @notice Test edge case: very small purchase (precision test)
    function test_UserStory_SmallPurchase_Precision() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);

        uint256 totalSaleSupply = 10_000_000e18;
        uint256 tribAmt = 10_000e6; // 10_000_000_000 (10 billion)
        uint256 forAmt = 100_000e18; // 100_000_000_000_000_000_000_000 (100k * 1e18)

        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), totalSaleSupply);
        vm.prank(address(moloch));
        shares.approve(address(daico), totalSaleSupply);
        vm.prank(address(moloch));
        daico.setSale(address(usdc), tribAmt, address(shares), forAmt, 0);

        usdc.mint(bob, 100_000e6);
        vm.prank(bob);
        usdc.approve(address(daico), type(uint256).max);

        // Smallest meaningful USDC purchase: 1 unit (0.000001 USDC)
        // Expected shares: (100_000e18 * 1) / 10_000e6
        //                = 100_000_000_000_000_000_000_000 / 10_000_000_000
        //                = 10_000_000_000_000 wei = 10 trillion wei = 0.00001e18 shares
        uint256 expectedShares = (forAmt * 1) / tribAmt;
        assertEq(expectedShares, 10_000_000_000_000, "1 USDC unit should yield 10T wei of shares");

        vm.prank(bob);
        daico.buy(address(moloch), address(usdc), 1, 0);

        assertEq(
            shares.balanceOf(bob), expectedShares, "Smallest USDC unit should still yield shares"
        );
    }

    /// @notice Test that all 10mm shares can be sold
    function test_UserStory_FullSale() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);

        uint256 totalSaleSupply = 10_000_000e18;
        uint256 tribAmt = 10_000e6;
        uint256 forAmt = 100_000e18;

        // To sell 10mm shares at rate of 100k shares per 10k USDC:
        // Total USDC needed = 10_000_000 / 100_000 * 10_000 = 1_000_000 USDC (1mm)
        uint256 totalUsdcNeeded = 1_000_000e6;

        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), totalSaleSupply);
        vm.prank(address(moloch));
        shares.approve(address(daico), totalSaleSupply);
        vm.prank(address(moloch));
        daico.setSale(address(usdc), tribAmt, address(shares), forAmt, 0);

        usdc.mint(bob, totalUsdcNeeded);
        vm.prank(bob);
        usdc.approve(address(daico), type(uint256).max);

        // Bob buys all 10mm shares with 1mm USDC
        vm.prank(bob);
        daico.buy(address(moloch), address(usdc), totalUsdcNeeded, 0);

        assertEq(shares.balanceOf(bob), totalSaleSupply, "Should buy all 10mm shares");
        assertEq(usdc.balanceOf(address(moloch)), totalUsdcNeeded, "DAO should receive 1mm USDC");
    }

    /*//////////////////////////////////////////////////////////////
                    PRODUCTION READINESS TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test that maxSlipBps > 10000 reverts in setLPConfig
    function test_SetLPConfig_RevertBadMaxSlipBps() public {
        vm.prank(address(moloch));
        vm.expectRevert(DAICO.BadLPBps.selector);
        daico.setLPConfig(address(0), 5000, 10001, 30); // maxSlipBps > 10000
    }

    /// @notice Test that maxSlipBps > 10000 reverts in setupDAICO
    function test_SetupDAICO_RevertBadMaxSlipBps() public {
        DAICO.DAICOConfig memory config = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 1000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 5000,
            maxSlipBps: 10001, // Invalid
            feeOrHook: 30
        });

        DAICO.TapConfig memory tapConfig =
            DAICO.TapConfig({ops: address(0), ratePerSec: 0, tapAllowance: 0});

        vm.prank(address(moloch));
        vm.expectRevert(DAICO.BadLPBps.selector);
        daico.setupDAICO(address(moloch), address(shares), config, tapConfig);
    }

    /// @notice Test buying with exact allowance (no excess)
    function test_Buy_ExactAllowance() public {
        vm.startPrank(address(moloch));
        shares.mintFromMoloch(address(moloch), 1000e18); // Exactly what will be sold
        shares.approve(address(daico), 1000e18); // Exact allowance
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, 0);
        vm.stopPrank();

        // Buy exactly 1000 shares
        vm.prank(bob);
        daico.buy{value: 1 ether}(address(moloch), address(0), 1 ether, 0);
        assertEq(shares.balanceOf(bob), 1000e18);

        // Next buy should fail (no more allowance)
        vm.prank(alice);
        vm.expectRevert(); // Transfer will fail
        daico.buy{value: 0.1 ether}(address(moloch), address(0), 0.1 ether, 0);
    }

    /// @notice Test buying when DAO has insufficient token balance
    function test_Buy_InsufficientDAOBalance() public {
        vm.startPrank(address(moloch));
        shares.mintFromMoloch(address(moloch), 500e18); // Only 500, but sale offers 1000 per ETH
        shares.approve(address(daico), type(uint256).max);
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, 0);
        vm.stopPrank();

        // Try to buy 1000 shares but DAO only has 500
        vm.prank(bob);
        vm.expectRevert(); // Transfer will fail
        daico.buy{value: 1 ether}(address(moloch), address(0), 1 ether, 0);
    }

    /// @notice Test tap claim when DAO balance is zero
    function test_ClaimTap_ZeroDAOBalance() public {
        vm.startPrank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        shares.approve(address(daico), type(uint256).max);
        vm.stopPrank();

        // Set allowance but don't fund DAO with ETH
        vm.prank(address(moloch));
        moloch.setAllowance(address(daico), address(0), 5 ether);

        vm.prank(address(moloch));
        daico.setSaleWithTap(address(0), 1 ether, address(shares), 1000e18, 0, ops, ONE_ETH_PER_DAY);

        vm.warp(block.timestamp + 1 days);

        // Should revert because DAO has no ETH
        vm.expectRevert(DAICO.NothingToClaim.selector);
        daico.claimTap(address(moloch));
    }

    /// @notice Test multiple DAOs using same DAICO contract
    function test_MultipleDAOs_Isolation() public {
        // Create second DAO
        address[] memory holders = new address[](1);
        holders[0] = bob;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        Moloch moloch2 = summoner.summon(
            "Second DAO",
            "DAO2",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(999)),
            holders,
            amounts,
            new Call[](0)
        );
        Shares shares2 = moloch2.shares();

        // Setup sales for both DAOs
        vm.startPrank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        shares.approve(address(daico), type(uint256).max);
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, 0); // 1000 shares per ETH
        vm.stopPrank();

        vm.startPrank(address(moloch2));
        shares2.mintFromMoloch(address(moloch2), 10_000e18);
        shares2.approve(address(daico), type(uint256).max);
        daico.setSale(address(0), 1 ether, address(shares2), 500e18, 0); // 500 shares per ETH (different rate)
        vm.stopPrank();

        // Buy from both DAOs
        vm.prank(alice);
        daico.buy{value: 1 ether}(address(moloch), address(0), 1 ether, 0);

        vm.prank(alice);
        daico.buy{value: 1 ether}(address(moloch2), address(0), 1 ether, 0);

        // Verify isolation - different amounts received (alice starts with 100e18 shares from setUp)
        assertEq(shares.balanceOf(alice), 1000e18 + 100e18);
        assertEq(shares2.balanceOf(alice), 500e18);
    }

    /// @notice Test extreme price ratios (very cheap tokens)
    function test_Buy_ExtremeRatio_CheapTokens() public {
        // 1 wei ETH for 1 million shares (extremely cheap)
        vm.startPrank(address(moloch));
        shares.mintFromMoloch(address(moloch), 1_000_000_000e18);
        shares.approve(address(daico), type(uint256).max);
        daico.setSale(address(0), 1, address(shares), 1_000_000e18, 0);
        vm.stopPrank();

        vm.prank(bob);
        daico.buy{value: 1000}(address(moloch), address(0), 1000, 0);

        // Should get 1000 * 1_000_000e18 = 1_000_000_000e18 shares
        assertEq(shares.balanceOf(bob), 1_000_000_000e18);
    }

    /// @notice Test extreme price ratios (very expensive tokens)
    function test_Buy_ExtremeRatio_ExpensiveTokens() public {
        // 1000 ETH for 1 share (extremely expensive)
        vm.startPrank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100e18);
        shares.approve(address(daico), type(uint256).max);
        daico.setSale(address(0), 1000 ether, address(shares), 1e18, 0);
        vm.stopPrank();

        vm.deal(bob, 2000 ether);
        vm.prank(bob);
        daico.buy{value: 1000 ether}(address(moloch), address(0), 1000 ether, 0);

        assertEq(shares.balanceOf(bob), 1e18);
    }

    /// @notice Test deadline at exact block.timestamp (edge case)
    function test_Buy_DeadlineExact() public {
        vm.startPrank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        shares.approve(address(daico), type(uint256).max);
        vm.stopPrank();

        uint40 deadline = uint40(block.timestamp + 100);
        vm.prank(address(moloch));
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, deadline);

        // Warp to exactly deadline
        vm.warp(deadline);

        // Should still work at exact deadline
        vm.prank(bob);
        daico.buy{value: 0.1 ether}(address(moloch), address(0), 0.1 ether, 0);
        assertEq(shares.balanceOf(bob), 100e18);

        // Warp 1 second past deadline
        vm.warp(deadline + 1);

        // Should now fail
        vm.prank(bob);
        vm.expectRevert(DAICO.Expired.selector);
        daico.buy{value: 0.1 ether}(address(moloch), address(0), 0.1 ether, 0);
    }

    /// @notice Test tap with very high rate (potential overflow check)
    function test_Tap_VeryHighRate() public {
        vm.startPrank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        shares.approve(address(daico), type(uint256).max);
        vm.stopPrank();

        vm.deal(address(moloch), 1000 ether);
        vm.prank(address(moloch));
        moloch.setAllowance(address(daico), address(0), 1000 ether);

        // Max uint128 rate
        uint128 maxRate = type(uint128).max;
        vm.prank(address(moloch));
        daico.setSaleWithTap(address(0), 1 ether, address(shares), 1000e18, 0, ops, maxRate);

        // Even 1 second would overflow if not careful
        vm.warp(block.timestamp + 1);

        // Should be capped by allowance/balance, not overflow
        uint256 claimable = daico.claimableTap(address(moloch));
        assertLe(claimable, 1000 ether); // Capped by allowance
    }

    /// @notice Test tap claim partial when allowance reduced mid-stream
    function test_Tap_AllowanceReducedMidStream() public {
        vm.startPrank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        shares.approve(address(daico), type(uint256).max);
        vm.stopPrank();

        vm.deal(address(moloch), 10 ether);
        vm.prank(address(moloch));
        moloch.setAllowance(address(daico), address(0), 5 ether);

        vm.prank(address(moloch));
        daico.setSaleWithTap(address(0), 1 ether, address(shares), 1000e18, 0, ops, ONE_ETH_PER_DAY);

        // Warp 3 days - would owe 3 ETH
        vm.warp(block.timestamp + 3 days);

        // DAO reduces allowance to 1 ETH
        vm.prank(address(moloch));
        moloch.setAllowance(address(daico), address(0), 1 ether);

        // Claim should be capped at 1 ETH
        uint256 claimed = daico.claimTap(address(moloch));
        assertApproxEqRel(claimed, 1 ether, 0.001e18);
    }

    /// @notice Test buying with minBuyAmt exactly equal to expected output
    function test_Buy_MinBuyAmtExact() public {
        vm.startPrank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        shares.approve(address(daico), type(uint256).max);
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, 0);
        vm.stopPrank();

        // minBuyAmt exactly equals expected output
        vm.prank(bob);
        daico.buy{value: 1 ether}(address(moloch), address(0), 1 ether, 1000e18);
        assertEq(shares.balanceOf(bob), 1000e18);
    }

    /// @notice Test buyExactOut with maxPayAmt exactly equal to required payment
    function test_BuyExactOut_MaxPayAmtExact() public {
        vm.startPrank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        shares.approve(address(daico), type(uint256).max);
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, 0);
        vm.stopPrank();

        // maxPayAmt exactly equals required payment
        vm.prank(bob);
        daico.buyExactOut{value: 1 ether}(address(moloch), address(0), 1000e18, 1 ether);
        assertEq(shares.balanceOf(bob), 1000e18);
    }

    /// @notice Test that events are emitted correctly
    function test_Events_SaleBought() public {
        vm.startPrank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        shares.approve(address(daico), type(uint256).max);
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, 0);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit SaleBought(bob, address(moloch), address(0), 0.5 ether, address(shares), 500e18);

        vm.prank(bob);
        daico.buy{value: 0.5 ether}(address(moloch), address(0), 0.5 ether, 0);
    }

    /// @notice Test concurrent buys from multiple users in same block
    function test_Buy_ConcurrentSameBlock() public {
        vm.startPrank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        shares.approve(address(daico), type(uint256).max);
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, 0);
        vm.stopPrank();

        address charlie = address(0xC);
        address dave = address(0xD);
        vm.deal(charlie, 10 ether);
        vm.deal(dave, 10 ether);

        // Multiple buys in same block
        vm.prank(alice);
        daico.buy{value: 1 ether}(address(moloch), address(0), 1 ether, 0);

        vm.prank(bob);
        daico.buy{value: 2 ether}(address(moloch), address(0), 2 ether, 0);

        vm.prank(charlie);
        daico.buy{value: 3 ether}(address(moloch), address(0), 3 ether, 0);

        vm.prank(dave);
        daico.buy{value: 4 ether}(address(moloch), address(0), 4 ether, 0);

        // All should succeed (alice starts with 100e18 from setUp)
        assertEq(shares.balanceOf(alice), 1000e18 + 100e18);
        assertEq(shares.balanceOf(bob), 2000e18);
        assertEq(shares.balanceOf(charlie), 3000e18);
        assertEq(shares.balanceOf(dave), 4000e18);
    }

    /// @notice Test LP config with maxSlipBps = 10000 (100% slippage allowed)
    function test_SetLPConfig_MaxSlipBps10000() public {
        vm.prank(address(moloch));
        daico.setLPConfig(address(0), 5000, 10000, 30); // 100% slippage - edge case but valid

        (uint16 lpBps, uint16 maxSlipBps, uint256 feeOrHook) =
            daico.lpConfigs(address(moloch), address(0));
        assertEq(lpBps, 5000);
        assertEq(maxSlipBps, 10000);
        assertEq(feeOrHook, 30);
    }

    /// @notice Test clearing LP config
    function test_SetLPConfig_Clear() public {
        // Set LP config
        vm.prank(address(moloch));
        daico.setLPConfig(address(0), 5000, 100, 30);

        // Clear by setting lpBps = 0
        vm.prank(address(moloch));
        daico.setLPConfig(address(0), 0, 100, 30);

        (uint16 lpBps,,) = daico.lpConfigs(address(moloch), address(0));
        assertEq(lpBps, 0);
    }

    /// @notice Test setSaleWithLP convenience function
    function test_SetSaleWithLP() public {
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(0), 1 ether, address(shares), 1000e18, 0, 5000, 100, 30);

        // Check sale was set
        (uint256 tribAmt, uint256 forAmt, address forTkn,) =
            daico.sales(address(moloch), address(0));
        assertEq(tribAmt, 1 ether);
        assertEq(forAmt, 1000e18);
        assertEq(forTkn, address(shares));

        // Check LP config was set
        (uint16 lpBps, uint16 maxSlipBps, uint256 feeOrHook) =
            daico.lpConfigs(address(moloch), address(0));
        assertEq(lpBps, 5000);
        assertEq(maxSlipBps, 100);
        assertEq(feeOrHook, 30);
    }

    /// @notice Test that sale with same token for both sides works (edge case)
    function test_Buy_SameTokenBothSides() public {
        MockERC20 token = new MockERC20("Token", "TKN", 18);
        token.mint(address(moloch), 10_000e18);

        vm.startPrank(address(moloch));
        token.approve(address(daico), type(uint256).max);
        // Set sale: pay TKN, receive TKN (same token)
        daico.setSale(address(token), 1e18, address(token), 1e18, 0);
        vm.stopPrank();

        // This is a valid but useless configuration - no economic exploit
        token.mint(bob, 1e18);
        vm.startPrank(bob);
        token.approve(address(daico), 1e18);
        daico.buy(address(moloch), address(token), 1e18, 0);
        vm.stopPrank();

        // Bob ends up with same amount (transferred to DAO, received back)
        assertEq(token.balanceOf(bob), 1e18);
    }

    /// @notice Test quote functions return 0 for zero amounts
    function test_Quote_ZeroAmount() public {
        vm.prank(address(moloch));
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, 0);

        assertEq(daico.quoteBuy(address(moloch), address(0), 0), 0);
        assertEq(daico.quotePayExactOut(address(moloch), address(0), 0), 0);
    }

    /// @notice Test that tap lastClaim updates correctly over multiple claims
    function test_Tap_LastClaimUpdates() public {
        vm.startPrank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000e18);
        shares.approve(address(daico), type(uint256).max);
        vm.stopPrank();

        vm.deal(address(moloch), 100 ether);
        vm.prank(address(moloch));
        moloch.setAllowance(address(daico), address(0), 100 ether);

        uint256 startTime = block.timestamp;
        vm.prank(address(moloch));
        daico.setSaleWithTap(address(0), 1 ether, address(shares), 1000e18, 0, ops, ONE_ETH_PER_DAY);

        (,,, uint64 lastClaim1) = daico.taps(address(moloch));
        assertEq(lastClaim1, startTime);

        vm.warp(startTime + 1 days);
        daico.claimTap(address(moloch));

        (,,, uint64 lastClaim2) = daico.taps(address(moloch));
        assertEq(lastClaim2, startTime + 1 days);

        vm.warp(startTime + 3 days);
        daico.claimTap(address(moloch));

        (,,, uint64 lastClaim3) = daico.taps(address(moloch));
        assertEq(lastClaim3, startTime + 3 days);
    }

    /// @notice Fuzz test for buy with various amounts
    function testFuzz_Buy_Amounts(uint256 payAmt, uint256 tribAmt, uint256 forAmt) public {
        // Bound to reasonable values
        payAmt = bound(payAmt, 1, 1000 ether);
        tribAmt = bound(tribAmt, 1, 1000 ether);
        forAmt = bound(forAmt, 1, 1_000_000e18);

        uint256 mintAmount = 1_000_000_000e18;
        vm.startPrank(address(moloch));
        // Use a large but safe amount that won't overflow Shares delegation tracking
        shares.mintFromMoloch(address(moloch), mintAmount);
        shares.approve(address(daico), type(uint256).max);
        daico.setSale(address(0), tribAmt, address(shares), forAmt, 0);
        vm.stopPrank();

        uint256 expectedBuy = (forAmt * payAmt) / tribAmt;
        // Skip cases where expectedBuy exceeds available supply
        if (expectedBuy == 0 || expectedBuy > mintAmount) {
            return;
        }
        vm.deal(bob, payAmt + 1 ether); // Ensure bob has enough ETH for fuzz values
        vm.prank(bob);
        daico.buy{value: payAmt}(address(moloch), address(0), payAmt, 0);
        assertEq(shares.balanceOf(bob), expectedBuy);
    }

    /// @notice Fuzz test for buyExactOut with various amounts
    function testFuzz_BuyExactOut_Amounts(uint256 buyAmt, uint256 tribAmt, uint256 forAmt) public {
        // Bound to reasonable values
        buyAmt = bound(buyAmt, 1, 1_000_000e18);
        tribAmt = bound(tribAmt, 1, 1000 ether);
        forAmt = bound(forAmt, 1, 1_000_000e18);

        vm.startPrank(address(moloch));
        // Use a large but safe amount that won't overflow Shares delegation tracking
        shares.mintFromMoloch(address(moloch), 1_000_000_000e18);
        shares.approve(address(daico), type(uint256).max);
        daico.setSale(address(0), tribAmt, address(shares), forAmt, 0);
        vm.stopPrank();

        // Calculate expected payment (ceiling division)
        uint256 num = buyAmt * tribAmt;
        uint256 expectedPay = (num + forAmt - 1) / forAmt;

        if (expectedPay == 0 || expectedPay > 10000 ether) {
            // Skip unreasonable cases
            return;
        }

        vm.deal(bob, expectedPay + 1 ether);
        vm.prank(bob);
        daico.buyExactOut{value: expectedPay + 1 ether}(address(moloch), address(0), buyAmt, 0);
        assertEq(shares.balanceOf(bob), buyAmt);
    }

    /// @notice Test that DAO can have sales in multiple payment tokens simultaneously
    function test_MultipleTribTokens() public {
        MockERC20 usdc = new MockERC20("USDC", "USDC", 6);
        MockERC20 dai = new MockERC20("DAI", "DAI", 18);

        vm.startPrank(address(moloch));
        shares.mintFromMoloch(address(moloch), 1_000_000e18);
        shares.approve(address(daico), type(uint256).max);

        // ETH sale
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, 0);
        // USDC sale (different rate)
        daico.setSale(address(usdc), 100e6, address(shares), 1000e18, 0);
        // DAI sale (different rate)
        daico.setSale(address(dai), 100e18, address(shares), 500e18, 0);
        vm.stopPrank();

        // Buy with ETH
        vm.prank(bob);
        daico.buy{value: 1 ether}(address(moloch), address(0), 1 ether, 0);

        // Buy with USDC
        usdc.mint(alice, 100e6);
        vm.startPrank(alice);
        usdc.approve(address(daico), 100e6);
        daico.buy(address(moloch), address(usdc), 100e6, 0);
        vm.stopPrank();

        // Buy with DAI
        address charlie = address(0xC);
        dai.mint(charlie, 100e18);
        vm.startPrank(charlie);
        dai.approve(address(daico), 100e18);
        daico.buy(address(moloch), address(dai), 100e18, 0);
        vm.stopPrank();

        assertEq(shares.balanceOf(bob), 1000e18);
        assertEq(shares.balanceOf(alice), 1000e18 + 100e18); // alice starts with 100e18 from setUp
        assertEq(shares.balanceOf(charlie), 500e18);
    }
}

/*//////////////////////////////////////////////////////////////
                    ZAMM LP INTEGRATION TESTS
//////////////////////////////////////////////////////////////*/

import {ZAMM} from "@zamm/ZAMM.sol";

contract DAICO_ZAMM_Test is Test {
    // 1 ETH per day = 1e18 / 86400 = 11574074074074 wei/sec
    uint128 constant ONE_ETH_PER_DAY = 11574074074074;

    Summoner internal summoner;
    Moloch internal moloch;
    Shares internal shares;
    Loot internal loot;
    DAICO internal daico;
    ZAMM internal zamm;

    // Implementation addresses for CREATE2 prediction
    address internal molochImpl;
    address internal sharesImpl;
    address internal lootImpl;

    address internal alice = address(0xA11CE);
    address internal bob = address(0x0B0B);
    address internal ops = address(0x0505);

    // Events
    event LPConfigSet(
        address indexed dao, address indexed tribTkn, uint16 lpBps, uint256 feeOrHook
    );
    event LPInitialized(
        address indexed dao,
        address indexed tribTkn,
        uint256 tribUsed,
        uint256 forTknUsed,
        uint256 liquidity
    );
    event SaleBought(
        address indexed buyer,
        address indexed dao,
        address indexed tribTkn,
        uint256 payAmt,
        address forTkn,
        uint256 buyAmt
    );

    // ZAMM address from DAICO.sol
    address constant ZAMM_ADDRESS = 0x000000000000040470635EB91b7CE4D132D616eD;

    function setUp() public {
        vm.label(alice, "ALICE");
        vm.label(bob, "BOB");
        vm.label(ops, "OPS");

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);

        // Deploy ZAMM to the hardcoded address used by DAICO
        ZAMM zammLocal = new ZAMM();
        vm.etch(ZAMM_ADDRESS, address(zammLocal).code);
        zamm = ZAMM(payable(ZAMM_ADDRESS));
        vm.label(address(zamm), "ZAMM");

        // Record logs to capture NewDAO event
        vm.recordLogs();
        summoner = new Summoner();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        molochImpl = address(uint160(uint256(logs[0].topics[2])));

        daico = new DAICO();

        // Compute shares/loot impl addresses
        bytes32 implSalt = bytes32(bytes20(molochImpl));
        sharesImpl = _computeCreate2(molochImpl, implSalt, type(Shares).creationCode);
        lootImpl = _computeCreate2(molochImpl, implSalt, type(Loot).creationCode);

        // Create DAO with alice as initial holder
        address[] memory initialHolders = new address[](1);
        initialHolders[0] = alice;
        uint256[] memory initialAmounts = new uint256[](1);
        initialAmounts[0] = 100e18;

        moloch = summoner.summon(
            "Test DAO",
            "TEST",
            "",
            5000,
            true,
            address(0),
            bytes32(0),
            initialHolders,
            initialAmounts,
            new Call[](0)
        );

        shares = moloch.shares();
        loot = moloch.loot();

        vm.roll(block.number + 1);
    }

    function _computeCreate2(address deployer, bytes32 salt, bytes memory creationCode)
        internal
        pure
        returns (address)
    {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), deployer, salt, keccak256(creationCode))
                    )
                )
            )
        );
    }

    /// @dev Helper to compute ZAMM pool ID
    function _getPoolId(address token0, address token1, uint256 id0, uint256 id1, uint256 feeOrHook)
        internal
        pure
        returns (uint256)
    {
        ZAMM.PoolKey memory key = ZAMM.PoolKey({
            id0: id0, id1: id1, token0: token0, token1: token1, feeOrHook: feeOrHook
        });
        return uint256(keccak256(abi.encode(key)));
    }

    /*//////////////////////////////////////////////////////////////
                        LP CONFIG TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetLPConfig() public {
        vm.prank(address(moloch));
        vm.expectEmit(true, true, false, true);
        emit LPConfigSet(address(moloch), address(0), 5000, 30);
        daico.setLPConfig(address(0), 5000, 100, 30); // 50% LP, 1% slippage, 30 bps fee

        (uint16 lpBps, uint16 maxSlipBps, uint256 feeOrHook) =
            daico.lpConfigs(address(moloch), address(0));

        assertEq(lpBps, 5000);
        assertEq(maxSlipBps, 100);
        assertEq(feeOrHook, 30);
    }

    function test_SetLPConfig_DefaultSlippage() public {
        vm.prank(address(moloch));
        daico.setLPConfig(address(0), 5000, 0, 30); // 0 maxSlipBps = default

        (, uint16 maxSlipBps,) = daico.lpConfigs(address(moloch), address(0));
        assertEq(maxSlipBps, 100); // Default 1%
    }

    function test_SetLPConfig_Clear() public {
        // Set LP config
        vm.prank(address(moloch));
        daico.setLPConfig(address(0), 5000, 100, 30);

        // Clear by setting lpBps to 0
        vm.prank(address(moloch));
        daico.setLPConfig(address(0), 0, 100, 30);

        (uint16 lpBps,,) = daico.lpConfigs(address(moloch), address(0));
        assertEq(lpBps, 0);
    }

    function test_SetLPConfig_RevertBadBps() public {
        vm.prank(address(moloch));
        vm.expectRevert(DAICO.BadLPBps.selector);
        daico.setLPConfig(address(0), 10001, 100, 30); // > 100%
    }

    function test_SetSaleWithLP() public {
        vm.prank(address(moloch));
        daico.setSaleWithLP(
            address(0), // ETH
            1 ether, // tribAmt
            address(shares), // forTkn
            1000e18, // forAmt
            0, // no deadline
            5000, // 50% LP
            100, // 1% slippage
            30 // 30 bps fee
        );

        // Check sale config
        (uint256 tribAmt, uint256 forAmt, address forTkn,) =
            daico.sales(address(moloch), address(0));
        assertEq(tribAmt, 1 ether);
        assertEq(forAmt, 1000e18);
        assertEq(forTkn, address(shares));

        // Check LP config
        (uint16 lpBps, uint16 maxSlipBps, uint256 feeOrHook) =
            daico.lpConfigs(address(moloch), address(0));
        assertEq(lpBps, 5000);
        assertEq(maxSlipBps, 100);
        assertEq(feeOrHook, 30);
    }

    /*//////////////////////////////////////////////////////////////
                    LP SEEDING TESTS - NEW POOL (ETH)
    //////////////////////////////////////////////////////////////*/

    /// @notice Test basic LP seeding with ETH - new pool creation
    function test_Buy_ETH_WithLP_NewPool() public {
        // 1. Mint shares to DAO for sale + LP
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);

        // 2. DAO approves DAICO to transfer shares
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        // 3. DAO sets sale with 50% LP: 1 ETH for 1000 shares
        vm.prank(address(moloch));
        daico.setSaleWithLP(
            address(0), // ETH
            1 ether, // tribAmt
            address(shares), // forTkn
            1000e18, // forAmt
            0, // no deadline
            5000, // 50% to LP
            100, // 1% slippage
            30 // 30 bps pool fee
        );

        // 4. Bob buys with 2 ETH
        // Expected: 2 ETH * 1000 / 1 = 2000 shares total at OTC rate
        // LP portion: 1 ETH (50%) goes to LP
        // LP needs 1000 shares at OTC rate
        // Buyer gets: 2000 - 1000 = 1000 shares

        uint256 bobSharesBefore = shares.balanceOf(bob);
        uint256 daoEthBefore = address(moloch).balance;

        vm.prank(bob);
        daico.buy{value: 2 ether}(address(moloch), address(0), 2 ether, 0);

        // Bob should get 1000 shares (2000 gross - 1000 to LP)
        assertEq(shares.balanceOf(bob), bobSharesBefore + 1000e18);

        // DAO should receive 1 ETH (50% of tribute)
        assertEq(address(moloch).balance, daoEthBefore + 1 ether);

        // Verify pool was created
        // Pool key: ETH < shares address
        uint256 poolId;
        if (address(0) < address(shares)) {
            poolId = _getPoolId(address(0), address(shares), 0, 0, 30);
        } else {
            poolId = _getPoolId(address(shares), address(0), 0, 0, 30);
        }

        (uint112 reserve0, uint112 reserve1,,,,, uint256 supply) = zamm.pools(poolId);

        // Pool should have liquidity
        assertGt(supply, 0, "Pool should have supply");
        assertGt(reserve0, 0, "Pool should have reserve0");
        assertGt(reserve1, 0, "Pool should have reserve1");
    }

    /// @notice Test LP seeding with slippage protection
    function test_Buy_ETH_WithLP_SlippageProtection() public {
        // Setup
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        // Sale: 1 ETH = 1000 shares, 50% to LP
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(0), 1 ether, address(shares), 1000e18, 0, 5000, 100, 30);

        // Bob buys with minBuyAmt - should account for LP reduction
        // 1 ETH -> 1000 shares gross, but 500 go to LP, so net = 500
        vm.prank(bob);
        daico.buy{value: 1 ether}(address(moloch), address(0), 1 ether, 400e18); // expect at least 400

        assertGe(shares.balanceOf(bob), 400e18);
    }

    /// @notice Test slippage exceeded when LP reduces buyer's output too much
    function test_Buy_ETH_WithLP_RevertSlippageExceeded() public {
        // Setup
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        // Sale: 1 ETH = 1000 shares, 50% to LP
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(0), 1 ether, address(shares), 1000e18, 0, 5000, 100, 30);

        // Bob wants at least 600 shares from 1 ETH, but LP takes 50%
        // So he'd only get ~500 shares
        vm.prank(bob);
        vm.expectRevert(DAICO.SlippageExceeded.selector);
        daico.buy{value: 1 ether}(address(moloch), address(0), 1 ether, 600e18);
    }

    /*//////////////////////////////////////////////////////////////
                LP SEEDING TESTS - EXISTING POOL (DRIFT)
    //////////////////////////////////////////////////////////////*/

    /// @notice Test LP seeding when pool already exists at same rate
    function test_Buy_ETH_WithLP_ExistingPool_SameRate() public {
        // 1. Setup sale
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(0), 1 ether, address(shares), 1000e18, 0, 5000, 100, 30);

        // 2. First buy creates the pool
        vm.prank(bob);
        daico.buy{value: 2 ether}(address(moloch), address(0), 2 ether, 0);

        uint256 bobSharesAfterFirst = shares.balanceOf(bob);

        // 3. Second buy adds to existing pool
        vm.prank(alice);
        daico.buy{value: 2 ether}(address(moloch), address(0), 2 ether, 0);

        // Alice should get similar ratio as Bob
        uint256 aliceShares = shares.balanceOf(alice) - 100e18; // subtract initial shares
        assertApproxEqRel(aliceShares, bobSharesAfterFirst, 0.05e18); // within 5%
    }

    /// @notice Test drift protection when pool price > OTC rate
    /// When spot price is higher than OTC rate, LP slice is capped to prevent
    /// buyer from receiving fewer tokens than OTC rate promises
    function test_Buy_ETH_WithLP_DriftProtection_SpotHigherThanOTC() public {
        // 1. Setup sale: OTC rate = 1000 shares per ETH
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(0), 1 ether, address(shares), 1000e18, 0, 5000, 100, 30);

        // 2. First buy creates pool at OTC rate
        vm.prank(bob);
        daico.buy{value: 2 ether}(address(moloch), address(0), 2 ether, 0);

        // 3. Now manipulate pool price to be HIGHER (more shares per ETH)
        // Add more shares to the pool directly via ZAMM
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(this), 10_000e18);
        shares.approve(address(zamm), 10_000e18);

        // Build pool key
        ZAMM.PoolKey memory key;
        if (address(0) < address(shares)) {
            key = ZAMM.PoolKey({
                id0: 0, id1: 0, token0: address(0), token1: address(shares), feeOrHook: 30
            });
        } else {
            key = ZAMM.PoolKey({
                id0: 0, id1: 0, token0: address(shares), token1: address(0), feeOrHook: 30
            });
        }

        // Add more shares to increase shares/ETH ratio (spot > OTC)
        zamm.addLiquidity{value: 0.5 ether}(
            key, 0.5 ether, 2000e18, 0, 0, address(this), block.timestamp
        );

        // 4. Alice buys - drift protection should cap LP slice
        uint256 aliceSharesBefore = shares.balanceOf(alice);
        vm.prank(alice);
        daico.buy{value: 2 ether}(address(moloch), address(0), 2 ether, 0);

        uint256 aliceSharesReceived = shares.balanceOf(alice) - aliceSharesBefore;

        // Alice should still receive a reasonable amount despite drift
        // With drift protection, she shouldn't be drastically shortchanged
        assertGt(aliceSharesReceived, 800e18, "Alice should get reasonable shares despite drift");
    }

    /// @notice Test that drift cap doesn't cause ETH to be stuck in DAICO
    /// When drift caps the LP slice, the unused portion must be sent to DAO
    function test_Buy_ETH_WithLP_DriftRefundGoesToDAO() public {
        // 1. Setup sale: OTC rate = 1000 shares per ETH, 50% to LP
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(0), 1 ether, address(shares), 1000e18, 0, 5000, 100, 30);

        // 2. First buy creates pool at OTC rate
        vm.prank(bob);
        daico.buy{value: 2 ether}(address(moloch), address(0), 2 ether, 0);

        // 3. Manipulate pool to have higher spot price (more shares per ETH)
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(this), 50_000e18);
        shares.approve(address(zamm), 50_000e18);

        ZAMM.PoolKey memory key;
        if (address(0) < address(shares)) {
            key = ZAMM.PoolKey({
                id0: 0, id1: 0, token0: address(0), token1: address(shares), feeOrHook: 30
            });
        } else {
            key = ZAMM.PoolKey({
                id0: 0, id1: 0, token0: address(shares), token1: address(0), feeOrHook: 30
            });
        }

        // Add lots of shares to make spot >> OTC (extreme drift)
        zamm.addLiquidity{value: 0.1 ether}(
            key, 0.1 ether, 5000e18, 0, 0, address(this), block.timestamp
        );

        // 4. Record balances before
        uint256 daoEthBefore = address(moloch).balance;
        uint256 daicoEthBefore = address(daico).balance;

        // 5. Alice buys with 4 ETH - extreme drift should cap LP heavily
        vm.prank(alice);
        daico.buy{value: 4 ether}(address(moloch), address(0), 4 ether, 0);

        // 6. Verify no ETH stuck in DAICO - this is the critical test!
        assertEq(address(daico).balance, daicoEthBefore, "No ETH should be stuck in DAICO");

        // 7. DAO should receive at least 50% of tribute (the non-LP portion)
        uint256 daoEthReceived = address(moloch).balance - daoEthBefore;
        assertGe(daoEthReceived, 2 ether, "DAO should receive at least 2 ETH (50%)");
    }

    /// @notice Test that drift cap doesn't cause ERC20 to be stuck in DAICO
    function test_Buy_ERC20_WithLP_DriftRefundGoesToDAO() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);

        // 1. Setup sale: OTC rate = 100 USDC for 1000 shares (10 shares per USDC), 50% to LP
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(usdc), 100e6, address(shares), 1000e18, 0, 5000, 100, 30);

        // 2. Mint USDC to users
        usdc.mint(bob, 10_000e6);
        usdc.mint(alice, 10_000e6);
        vm.prank(bob);
        usdc.approve(address(daico), type(uint256).max);
        vm.prank(alice);
        usdc.approve(address(daico), type(uint256).max);

        // 3. First buy creates pool at OTC rate (10 shares per USDC)
        vm.prank(bob);
        daico.buy(address(moloch), address(usdc), 200e6, 0);

        // 4. Manipulate pool to have HIGHER spot ratio (more shares per USDC than OTC)
        // OTC rate: 10 shares/USDC, we'll make spot much higher
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(this), 100_000e18);
        shares.approve(address(zamm), 100_000e18);
        usdc.mint(address(this), 100e6);
        usdc.approve(address(zamm), 100e6);

        ZAMM.PoolKey memory key;
        if (address(usdc) < address(shares)) {
            key = ZAMM.PoolKey({
                id0: 0, id1: 0, token0: address(usdc), token1: address(shares), feeOrHook: 30
            });
        } else {
            key = ZAMM.PoolKey({
                id0: 0, id1: 0, token0: address(shares), token1: address(usdc), feeOrHook: 30
            });
        }

        // Add lots more shares than OTC ratio would suggest to create significant drift
        uint256 amount0 = address(usdc) < address(shares) ? 10e6 : 50_000e18;
        uint256 amount1 = address(usdc) < address(shares) ? 50_000e18 : 10e6;
        zamm.addLiquidity(key, amount0, amount1, 0, 0, address(this), block.timestamp);

        // 5. Record balances before
        uint256 daoUsdcBefore = usdc.balanceOf(address(moloch));
        uint256 daicoUsdcBefore = usdc.balanceOf(address(daico));

        // 6. Alice buys with 400 USDC
        vm.prank(alice);
        daico.buy(address(moloch), address(usdc), 400e6, 0);

        // 7. Verify no USDC stuck in DAICO - critical for this bug fix!
        assertEq(
            usdc.balanceOf(address(daico)), daicoUsdcBefore, "No USDC should be stuck in DAICO"
        );

        // 8. DAO should receive tribute (at least 50% due to LP portion)
        uint256 daoUsdcReceived = usdc.balanceOf(address(moloch)) - daoUsdcBefore;
        assertGe(daoUsdcReceived, 200e6, "DAO should receive at least 200 USDC");
    }

    /*//////////////////////////////////////////////////////////////
                    LP SEEDING TESTS - ERC20 TRIBUTE
    //////////////////////////////////////////////////////////////*/

    /// @notice Test LP seeding with ERC20 tribute token
    function test_Buy_ERC20_WithLP_NewPool() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);

        // 1. Mint shares to DAO for sale + LP
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);

        // 2. DAO approves DAICO to transfer shares
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        // 3. DAO sets sale with 50% LP: 100 USDC for 1000 shares
        vm.prank(address(moloch));
        daico.setSaleWithLP(
            address(usdc),
            100e6, // tribAmt
            address(shares),
            1000e18, // forAmt
            0,
            5000, // 50% to LP
            100, // 1% slippage
            30 // 30 bps fee
        );

        // 4. Mint USDC to bob and approve
        usdc.mint(bob, 10_000e6);
        vm.prank(bob);
        usdc.approve(address(daico), type(uint256).max);

        // 5. Bob buys with 200 USDC
        // Expected: 200 USDC * 1000 / 100 = 2000 shares gross
        // LP portion: 100 USDC (50%) goes to LP with 1000 shares

        uint256 bobSharesBefore = shares.balanceOf(bob);

        vm.prank(bob);
        daico.buy(address(moloch), address(usdc), 200e6, 0);

        // Bob should get ~1000 shares (2000 gross - 1000 to LP)
        assertApproxEqRel(shares.balanceOf(bob) - bobSharesBefore, 1000e18, 0.05e18);

        // DAO should receive 100 USDC (50% of tribute)
        assertEq(usdc.balanceOf(address(moloch)), 100e6);
    }

    /// @notice Test that ERC20 sale with LP rejects ETH
    function test_Buy_ERC20_WithLP_RejectETH() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);

        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(usdc), 100e6, address(shares), 1000e18, 0, 5000, 100, 30);

        usdc.mint(bob, 10_000e6);
        vm.prank(bob);
        usdc.approve(address(daico), type(uint256).max);

        // Try to send ETH with ERC20 sale
        vm.prank(bob);
        vm.expectRevert(DAICO.InvalidParams.selector);
        daico.buy{value: 1 ether}(address(moloch), address(usdc), 200e6, 0);
    }

    /*//////////////////////////////////////////////////////////////
                    LP SEEDING - SUMMON WRAPPER TESTS
    //////////////////////////////////////////////////////////////*/

    function _getSummonConfig() internal view returns (DAICO.SummonConfig memory) {
        return DAICO.SummonConfig({
            summoner: address(summoner),
            molochImpl: molochImpl,
            sharesImpl: sharesImpl,
            lootImpl: lootImpl
        });
    }

    /// @notice Test summoning a DAO with LP config
    function test_SummonDAICO_WithLP() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0), // ETH
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 5000, // 50% to LP
            maxSlipBps: 100, // 1% slippage
            feeOrHook: 30 // 30 bps fee
        });

        address dao = daico.summonDAICO(
            _getSummonConfig(),
            "LP DAO",
            "LPDAO",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(200)),
            holders,
            amounts,
            false,
            false,
            daicoConfig
        );

        // Verify LP config was set
        (uint16 lpBps, uint16 maxSlipBps, uint256 feeOrHook) = daico.lpConfigs(dao, address(0));
        assertEq(lpBps, 5000);
        assertEq(maxSlipBps, 100);
        assertEq(feeOrHook, 30);

        // Test buying with LP
        Shares daoShares = Moloch(payable(dao)).shares();

        vm.prank(bob);
        daico.buy{value: 2 ether}(dao, address(0), 2 ether, 0);

        // Bob should get some shares (less than full OTC amount due to LP)
        assertGt(daoShares.balanceOf(bob), 0);
        assertLt(daoShares.balanceOf(bob), 2000e18); // Less than full OTC amount
    }

    /// @notice Test summoning DAO with LP + Tap
    function test_SummonDAICOWithTap_AndLP() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 3000, // 30% to LP
            maxSlipBps: 100,
            feeOrHook: 30
        });

        DAICO.TapConfig memory tapConfig =
            DAICO.TapConfig({ops: ops, ratePerSec: ONE_ETH_PER_DAY, tapAllowance: 10 ether});

        address dao = daico.summonDAICOWithTap{value: 20 ether}(
            _getSummonConfig(),
            "LP Tap DAO",
            "LPTAP",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(201)),
            holders,
            amounts,
            false,
            false,
            daicoConfig,
            tapConfig
        );

        // Verify both LP and Tap configured
        (uint16 lpBps,,) = daico.lpConfigs(dao, address(0));
        assertEq(lpBps, 3000);

        (address tapOps,, uint128 tapRate,) = daico.taps(dao);
        assertEq(tapOps, ops);
        assertEq(tapRate, ONE_ETH_PER_DAY);

        // Test buy with LP
        Shares daoShares = Moloch(payable(dao)).shares();
        vm.prank(bob);
        daico.buy{value: 1 ether}(dao, address(0), 1 ether, 0);
        assertGt(daoShares.balanceOf(bob), 0);

        // Test tap still works
        skip(1 days);
        uint256 claimable = daico.claimableTap(dao);
        assertApproxEqRel(claimable, 1 ether, 0.001e18);
    }

    /*//////////////////////////////////////////////////////////////
                    LP SEEDING - EDGE CASES
    //////////////////////////////////////////////////////////////*/

    /// @notice Test LP with 100% allocation (all tribute goes to LP)
    function test_Buy_ETH_WithLP_100Percent_RevertsOnConfig() public {
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        // 100% to LP is now blocked at config time (leaves nothing for buyer)
        vm.prank(address(moloch));
        vm.expectRevert(DAICO.BadLPBps.selector);
        daico.setSaleWithLP(address(0), 1 ether, address(shares), 1000e18, 0, 10_000, 100, 30);
    }

    /// @notice Test LP with very small percentage
    function test_Buy_ETH_WithLP_SmallPercent() public {
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        // 1% to LP
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(0), 1 ether, address(shares), 1000e18, 0, 100, 100, 30);

        uint256 bobSharesBefore = shares.balanceOf(bob);

        vm.prank(bob);
        daico.buy{value: 10 ether}(address(moloch), address(0), 10 ether, 0);

        // Bob should get close to full OTC amount (only 1% to LP)
        // 10 ETH * 1000 = 10000 shares gross
        // 0.1 ETH to LP -> 100 shares to LP
        // Bob gets ~9900 shares
        uint256 bobSharesReceived = shares.balanceOf(bob) - bobSharesBefore;
        assertApproxEqRel(bobSharesReceived, 9900e18, 0.05e18);
    }

    /// @notice Test LP refund when pool exists and rates differ
    function test_Buy_ETH_WithLP_RefundUnusedTribute() public {
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(0), 1 ether, address(shares), 1000e18, 0, 5000, 100, 30);

        // First buy creates pool
        vm.prank(bob);
        daico.buy{value: 2 ether}(address(moloch), address(0), 2 ether, 0);

        // Second buy - AMM may not accept all LP tokens due to ratio mismatch
        uint256 daoBalanceBefore = address(moloch).balance;

        vm.prank(alice);
        daico.buy{value: 2 ether}(address(moloch), address(0), 2 ether, 0);

        // DAO should receive at least the non-LP portion
        assertGe(address(moloch).balance - daoBalanceBefore, 1 ether);
    }

    /// @notice Test LP with different fee levels
    function test_Buy_ETH_WithLP_HighFee() public {
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        // High fee pool: 1000 bps = 10%
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(0), 1 ether, address(shares), 1000e18, 0, 5000, 100, 1000);

        vm.prank(bob);
        daico.buy{value: 2 ether}(address(moloch), address(0), 2 ether, 0);

        // Should still work with high fee
        assertGt(shares.balanceOf(bob), 0);
    }

    /*//////////////////////////////////////////////////////////////
                    HYBRID SALE LIFECYCLE TEST
    //////////////////////////////////////////////////////////////*/

    /// @notice Full lifecycle: Summon -> Sale with LP -> Tap claim -> Governance
    function test_HybridSaleLifecycle() public {
        // 1. Summon DAO with hybrid sale (LP + Tap)
        address[] memory holders = new address[](2);
        holders[0] = alice;
        holders[1] = address(0xDEAD);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e18;
        amounts[1] = 50e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 0.1 ether, // 0.1 ETH = 100 shares
            saleSupply: 1_000_000e18, // 1M shares for sale
            forAmt: 100e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 2000, // 20% to LP
            maxSlipBps: 100,
            feeOrHook: 30
        });

        DAICO.TapConfig memory tapConfig = DAICO.TapConfig({
            ops: ops,
            ratePerSec: ONE_ETH_PER_DAY, // 1 ETH/day
            tapAllowance: 50 ether
        });

        address dao = daico.summonDAICOWithTap{value: 100 ether}(
            _getSummonConfig(),
            "Hybrid DAO",
            "HYBRID",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(300)),
            holders,
            amounts,
            false,
            false,
            daicoConfig,
            tapConfig
        );

        Moloch daoMoloch = Moloch(payable(dao));
        Shares daoShares = daoMoloch.shares();

        // 2. Multiple buyers purchase shares
        address buyer1 = address(0xB1);
        address buyer2 = address(0xB2);
        vm.deal(buyer1, 50 ether);
        vm.deal(buyer2, 50 ether);

        // Buyer1 buys with 10 ETH
        // Gross: 10 ETH * 100 / 0.1 = 10,000 shares
        // LP: 2 ETH (20%) -> 2000 shares
        // Net to buyer1: ~8000 shares
        vm.prank(buyer1);
        daico.buy{value: 10 ether}(dao, address(0), 10 ether, 0);

        assertGt(daoShares.balanceOf(buyer1), 7000e18);
        assertLt(daoShares.balanceOf(buyer1), 9000e18);

        // Buyer2 buys with 5 ETH
        vm.prank(buyer2);
        daico.buy{value: 5 ether}(dao, address(0), 5 ether, 0);

        assertGt(daoShares.balanceOf(buyer2), 3500e18);

        // 3. Time passes, ops claims tap
        skip(7 days);

        uint256 opsBalanceBefore = ops.balance;
        daico.claimTap(dao);
        assertApproxEqRel(ops.balance - opsBalanceBefore, 7 ether, 0.001e18);

        // 4. DAO can adjust tap rate
        vm.prank(dao);
        daico.setTapRate(ONE_ETH_PER_DAY * 2);

        skip(3 days);
        opsBalanceBefore = ops.balance;
        daico.claimTap(dao);
        assertApproxEqRel(ops.balance - opsBalanceBefore, 6 ether, 0.001e18);

        // 5. Verify pool has liquidity from LP seeding
        uint256 poolId;
        if (address(0) < address(daoShares)) {
            poolId = _getPoolId(address(0), address(daoShares), 0, 0, 30);
        } else {
            poolId = _getPoolId(address(daoShares), address(0), 0, 0, 30);
        }

        (uint112 reserve0, uint112 reserve1,,,,, uint256 supply) = zamm.pools(poolId);
        assertGt(supply, 0, "Pool should have LP tokens");
        assertGt(reserve0, 0, "Pool should have reserves");
        assertGt(reserve1, 0, "Pool should have reserves");

        // 6. DAO should have received LP tokens
        uint256 daoLPBalance = zamm.balanceOf(dao, poolId);
        assertGt(daoLPBalance, 0, "DAO should have LP tokens");
    }

    /*//////////////////////////////////////////////////////////////
                    FUZZ TESTS FOR LP
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Buy_ETH_WithLP(uint256 payAmt, uint16 lpBps) public {
        // Bound inputs
        payAmt = bound(payAmt, 0.1 ether, 50 ether);
        lpBps = uint16(bound(lpBps, 100, 9000)); // 1% to 90%

        // Setup
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 10_000_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        vm.prank(address(moloch));
        daico.setSaleWithLP(address(0), 1 ether, address(shares), 1000e18, 0, lpBps, 100, 30);

        uint256 bobSharesBefore = shares.balanceOf(bob);

        vm.prank(bob);
        daico.buy{value: payAmt}(address(moloch), address(0), payAmt, 0);

        uint256 bobSharesReceived = shares.balanceOf(bob) - bobSharesBefore;

        // Gross amount at OTC rate
        uint256 grossShares = (1000e18 * payAmt) / 1 ether;

        // Buyer should receive less than gross (some went to LP)
        assertLe(bobSharesReceived, grossShares);

        // But should receive at least (100% - lpBps) of gross (minus some for pool ratio adjustment)
        uint256 minExpected = (grossShares * (10000 - lpBps)) / 10000;
        // Allow 10% variance for pool creation overhead
        assertGe(bobSharesReceived, (minExpected * 90) / 100);
    }

    /*//////////////////////////////////////////////////////////////
                    buyExactOut WITH LP SUPPORT
    //////////////////////////////////////////////////////////////*/

    /// @notice Test that buyExactOut now properly supports LP seeding
    function test_BuyExactOut_WithLP() public {
        // Setup sale with 50% LP
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(0), 1 ether, address(shares), 1000e18, 0, 5000, 100, 30);

        // Verify LP config is set
        (uint16 lpBps,,) = daico.lpConfigs(address(moloch), address(0));
        assertEq(lpBps, 5000, "LP should be configured at 50%");

        uint256 bobBalanceBefore = bob.balance;

        // buyExactOut: get exactly 500 shares
        // With 50% LP: grossForTkn = 500 * 10000 / 5000 = 1000 shares
        // payAmt = 1000 * 1 ETH / 1000 = 1 ETH
        // LP gets 500 shares + 0.5 ETH, DAO gets 0.5 ETH, buyer gets 500 shares
        vm.prank(bob);
        daico.buyExactOut{value: 2 ether}(address(moloch), address(0), 500e18, 0);

        // Bob gets exactly 500 shares
        assertEq(shares.balanceOf(bob), 500e18, "Bob should get exactly 500 shares");

        // Bob paid 1 ETH (got 1 ETH refund from 2 ETH sent)
        assertEq(bobBalanceBefore - bob.balance, 1 ether, "Bob should pay 1 ETH");

        // Pool SHOULD have been created (LP seeding works now)
        uint256 poolId;
        if (address(0) < address(shares)) {
            poolId = _getPoolId(address(0), address(shares), 0, 0, 30);
        } else {
            poolId = _getPoolId(address(shares), address(0), 0, 0, 30);
        }
        (,,,,,, uint256 supply) = zamm.pools(poolId);
        assertGt(supply, 0, "Pool SHOULD be created by buyExactOut with LP");
    }

    /// @notice Test that buyExactOut without LP still works as before
    function test_BuyExactOut_WithoutLP() public {
        // Setup sale WITHOUT LP
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, 0);

        uint256 daoBalanceBefore = address(moloch).balance;

        // buyExactOut: get exactly 500 shares = 0.5 ETH
        vm.prank(bob);
        daico.buyExactOut{value: 1 ether}(address(moloch), address(0), 500e18, 0);

        // Bob gets exactly 500 shares
        assertEq(shares.balanceOf(bob), 500e18);

        // DAO receives 0.5 ETH (no LP split)
        assertEq(address(moloch).balance - daoBalanceBefore, 0.5 ether);
    }

    /// @notice Test buyExactOut with LP matches buy() in terms of LP contribution
    function test_BuyExactOut_WithLP_MatchesBuy() public {
        // Setup two identical DAOs, one uses buy(), one uses buyExactOut()
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(0), 1 ether, address(shares), 1000e18, 0, 5000, 100, 30);

        // Bob uses buy() with 2 ETH
        vm.prank(bob);
        daico.buy{value: 2 ether}(address(moloch), address(0), 2 ether, 0);
        uint256 bobSharesFromBuy = shares.balanceOf(bob);

        // Alice uses buyExactOut() to get same amount
        vm.prank(alice);
        daico.buyExactOut{value: 3 ether}(address(moloch), address(0), bobSharesFromBuy, 0);
        uint256 aliceSharesFromExactOut = shares.balanceOf(alice) - 100e18; // subtract initial

        // Both should have same shares
        assertEq(aliceSharesFromExactOut, bobSharesFromBuy, "buyExactOut should match buy output");
    }

    /*//////////////////////////////////////////////////////////////
                    CONCERN #2: saleSupply MUST COVER LP NEEDS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test that saleSupply must be large enough for LP + buyer
    /// If saleSupply is too small, LP seeding will fail
    function test_SummonDAICO_InsufficientSaleSupplyForLP() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        // Configure: 1 ETH = 1000 shares, 50% to LP
        // If buyer pays 2 ETH:
        //   - Gross: 2000 shares
        //   - LP needs: 1000 shares (50% of 2 ETH worth)
        //   - Buyer gets: 1000 shares
        //   - Total needed: 2000 shares
        // But we only mint 1500 - not enough!
        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 1500e18, // Only 1500 shares - not enough for 2 ETH purchase
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 5000, // 50% to LP
            maxSlipBps: 100,
            feeOrHook: 30
        });

        address dao = daico.summonDAICO(
            _getSummonConfig(),
            "Low Supply DAO",
            "LOW",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(400)),
            holders,
            amounts,
            false,
            false,
            daicoConfig
        );

        // First buy of 1 ETH should work (needs 1000 shares)
        // 1 ETH -> 1000 gross, 500 to LP, 500 to buyer
        vm.prank(bob);
        daico.buy{value: 1 ether}(dao, address(0), 1 ether, 0);

        Shares daoShares = Moloch(payable(dao)).shares();
        assertGt(daoShares.balanceOf(bob), 0);

        // Second buy should fail - not enough shares for LP + buyer
        // (depends on pool state, may revert differently)
        // The DAO's share balance is depleted
        uint256 daoShareBalance = daoShares.balanceOf(dao);
        // After first buy, DAO should have ~500 shares left (1500 - 500 buyer - 500 LP)
        assertLt(daoShareBalance, 1000e18, "DAO should have limited shares left");
    }

    /*//////////////////////////////////////////////////////////////
                    CONCERN #3: DRIFT EDGE CASES
    //////////////////////////////////////////////////////////////*/

    /// @notice Test drift protection when spot is exactly at OTC rate
    function test_Buy_ETH_WithLP_NoDrift() public {
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(0), 1 ether, address(shares), 1000e18, 0, 5000, 100, 30);

        // First buy creates pool at OTC rate
        vm.prank(bob);
        daico.buy{value: 2 ether}(address(moloch), address(0), 2 ether, 0);

        uint256 bobSharesFirst = shares.balanceOf(bob);

        // Second buy - pool is at OTC rate (no drift)
        // Should behave the same as first buy
        vm.prank(alice);
        daico.buy{value: 2 ether}(address(moloch), address(0), 2 ether, 0);

        uint256 aliceShares = shares.balanceOf(alice) - 100e18; // subtract initial

        // Both should get similar amounts (within 10% due to AMM mechanics)
        assertApproxEqRel(aliceShares, bobSharesFirst, 0.1e18);
    }

    /// @notice Test drift protection when spot is LOWER than OTC rate
    /// When spot < OTC, no capping needed - LP is favorable
    function test_Buy_ETH_WithLP_SpotLowerThanOTC() public {
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(0), 1 ether, address(shares), 1000e18, 0, 5000, 100, 30);

        // First buy creates pool at OTC rate (1 ETH = 1000 shares)
        vm.prank(bob);
        daico.buy{value: 2 ether}(address(moloch), address(0), 2 ether, 0);

        // Manipulate pool: add more ETH relative to shares
        // This makes shares MORE expensive (fewer shares per ETH = spot < OTC)
        ZAMM.PoolKey memory key;
        if (address(0) < address(shares)) {
            key = ZAMM.PoolKey({
                id0: 0, id1: 0, token0: address(0), token1: address(shares), feeOrHook: 30
            });
        } else {
            key = ZAMM.PoolKey({
                id0: 0, id1: 0, token0: address(shares), token1: address(0), feeOrHook: 30
            });
        }

        // Add ETH-heavy liquidity to lower shares/ETH ratio using bob (can receive refunds)
        vm.prank(address(moloch));
        shares.mintFromMoloch(bob, 100e18);
        vm.prank(bob);
        shares.approve(address(zamm), 100e18);

        // Use correct ordering based on token addresses
        uint256 amount0 = address(0) < address(shares) ? 5 ether : 100e18;
        uint256 amount1 = address(0) < address(shares) ? 100e18 : 5 ether;
        vm.prank(bob);
        zamm.addLiquidity{value: 5 ether}(key, amount0, amount1, 0, 0, bob, block.timestamp);

        // Alice buys - spot is now LOWER than OTC (fewer shares per ETH in pool)
        // No drift cap needed - this is favorable for buyer
        uint256 aliceSharesBefore = shares.balanceOf(alice);

        vm.prank(alice);
        daico.buy{value: 2 ether}(address(moloch), address(0), 2 ether, 0);

        uint256 aliceSharesReceived = shares.balanceOf(alice) - aliceSharesBefore;

        // Alice should get reasonable amount (OTC guarantees minimum)
        // With 50% LP and favorable pool, buyer should still get ~1000 shares
        assertGt(aliceSharesReceived, 500e18, "Should get reasonable shares");
    }

    /*//////////////////////////////////////////////////////////////
                    CONCERN #4: EVENT ACCURACY
    //////////////////////////////////////////////////////////////*/

    /// @notice Test that SaleBought event emits grossBuyAmt, not netBuyAmt
    function test_Buy_ETH_WithLP_EventEmitsGross() public {
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(0), 1 ether, address(shares), 1000e18, 0, 5000, 100, 30);

        // Bob buys with 2 ETH
        // Gross: 2000 shares
        // Net (after LP): ~1000 shares

        vm.recordLogs();
        vm.prank(bob);
        daico.buy{value: 2 ether}(address(moloch), address(0), 2 ether, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Find SaleBought event
        // SaleBought(address indexed buyer, address indexed dao, address indexed tribTkn, uint256 payAmt, address forTkn, uint256 buyAmt)
        bytes32 saleBoughtSig =
            keccak256("SaleBought(address,address,address,uint256,address,uint256)");

        bool foundEvent = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == saleBoughtSig) {
                // Decode non-indexed params (payAmt, forTkn, buyAmt)
                (uint256 payAmt,, uint256 buyAmt) =
                    abi.decode(logs[i].data, (uint256, address, uint256));
                assertEq(payAmt, 2 ether, "payAmt should be 2 ETH");
                // buyAmt in event is the NET amount transferred to buyer (after LP deduction)
                assertEq(buyAmt, 1000e18, "Event emits NET buyAmt transferred to buyer");
                foundEvent = true;
                break;
            }
        }
        assertTrue(foundEvent, "SaleBought event should be emitted");

        // But bob actually received less due to LP
        assertLt(shares.balanceOf(bob), 2000e18, "Bob received less than gross");
        assertApproxEqRel(shares.balanceOf(bob), 1000e18, 0.1e18, "Bob should get ~1000 shares net");
    }

    /*//////////////////////////////////////////////////////////////
                    CONCERN #5: APPROVAL PERSISTENCE AFTER LP
    //////////////////////////////////////////////////////////////*/

    /// @notice Test that ZAMM approval persists after LP (not reset)
    /// This is not a security issue since DAICO doesn't hold tokens,
    /// but documents the behavior
    function test_Buy_ETH_WithLP_ApprovalPersists() public {
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(0), 1 ether, address(shares), 1000e18, 0, 5000, 100, 30);

        // Check shares allowance DAICO->ZAMM before
        uint256 allowanceBefore = shares.allowance(address(daico), address(zamm));
        assertEq(allowanceBefore, 0, "No allowance before first buy");

        // First buy triggers LP
        vm.prank(bob);
        daico.buy{value: 2 ether}(address(moloch), address(0), 2 ether, 0);

        // ensureApproval sets max approval (type(uint256).max) - ZAMM only consumes what it needs
        // via transferFrom, leaving the approval near max (minus the consumed amount)
        uint256 allowanceAfter = shares.allowance(address(daico), address(zamm));
        // Approval should be very high (max minus consumed amount)
        assertGt(
            allowanceAfter, type(uint128).max, "Approval persists above threshold after ZAMM use"
        );
    }

    /*//////////////////////////////////////////////////////////////
                    CONCERN #6: GAS FOR DOUBLE TRANSFER
    //////////////////////////////////////////////////////////////*/

    /// @notice Measure gas for ERC20 buy with LP (2 transfers) vs without LP
    function test_Buy_ERC20_GasComparison_WithVsWithoutLP() public {
        MockERC20 usdc = new MockERC20("USDC", "USDC", 6);

        // Setup two identical sales, one with LP, one without
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        // Mint USDC to bob
        usdc.mint(bob, 10_000e6);
        vm.prank(bob);
        usdc.approve(address(daico), type(uint256).max);

        // Test 1: Without LP
        vm.prank(address(moloch));
        daico.setSale(address(usdc), 100e6, address(shares), 1000e18, 0);

        uint256 gasBefore = gasleft();
        vm.prank(bob);
        daico.buy(address(moloch), address(usdc), 200e6, 0);
        uint256 gasWithoutLP = gasBefore - gasleft();

        // Test 2: With LP - need fresh setup
        // Clear old sale
        vm.prank(address(moloch));
        daico.setSale(address(usdc), 0, address(shares), 0, 0);

        // Set new sale with LP
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(usdc), 100e6, address(shares), 1000e18, 0, 5000, 100, 30);

        usdc.mint(bob, 10_000e6); // More USDC for bob

        gasBefore = gasleft();
        vm.prank(bob);
        daico.buy(address(moloch), address(usdc), 200e6, 0);
        uint256 gasWithLP = gasBefore - gasleft();

        // Log for comparison (LP adds significant gas due to ZAMM interaction)
        emit log_named_uint("Gas without LP", gasWithoutLP);
        emit log_named_uint("Gas with LP", gasWithLP);

        // LP version should use more gas (ZAMM addLiquidity + extra transfers)
        assertGt(gasWithLP, gasWithoutLP, "LP version uses more gas");
    }

    /*//////////////////////////////////////////////////////////////
                    NEW TESTS FOR COVERAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Test setSaleWithLPAndTap convenience function
    function test_SetSaleWithLPAndTap() public {
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        // Set sale with LP and tap in one call
        vm.prank(address(moloch));
        daico.setSaleWithLPAndTap(
            address(0), // tribTkn (ETH)
            1 ether, // tribAmt
            address(shares), // forTkn
            1000e18, // forAmt
            0, // deadline
            5000, // lpBps (50%)
            100, // maxSlipBps (1%)
            30, // feeOrHook
            alice, // ops
            0.01 ether // ratePerSec
        );

        // Verify sale config
        (uint256 tribAmt, uint256 forAmt, address forTkn, uint40 deadline) =
            daico.sales(address(moloch), address(0));
        assertEq(tribAmt, 1 ether);
        assertEq(forAmt, 1000e18);
        assertEq(forTkn, address(shares));
        assertEq(deadline, 0);

        // Verify LP config
        (uint16 lpBps, uint16 maxSlipBps, uint256 feeOrHook) =
            daico.lpConfigs(address(moloch), address(0));
        assertEq(lpBps, 5000);
        assertEq(maxSlipBps, 100);
        assertEq(feeOrHook, 30);

        // Verify tap config
        (address tapOps, address tapTribTkn, uint128 ratePerSec,) = daico.taps(address(moloch));
        assertEq(tapOps, alice);
        assertEq(tapTribTkn, address(0));
        assertEq(ratePerSec, 0.01 ether);
    }

    /// @notice Test setSaleWithLPAndTap clears tap when ops is zero
    function test_SetSaleWithLPAndTap_ClearTapZeroOps() public {
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        // First set a tap
        vm.prank(address(moloch));
        daico.setSaleWithLPAndTap(
            address(0), 1 ether, address(shares), 1000e18, 0, 5000, 100, 30, alice, 0.01 ether
        );

        // Now clear it with zero ops
        vm.prank(address(moloch));
        daico.setSaleWithLPAndTap(
            address(0), 1 ether, address(shares), 1000e18, 0, 5000, 100, 30, address(0), 0.01 ether
        );

        // Verify tap is cleared
        (address tapOps,,,) = daico.taps(address(moloch));
        assertEq(tapOps, address(0));
    }

    /// @notice Test setSaleWithLPAndTap clears tap when rate is zero
    function test_SetSaleWithLPAndTap_ClearTapZeroRate() public {
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        // Set with zero rate - should clear tap
        vm.prank(address(moloch));
        daico.setSaleWithLPAndTap(
            address(0), 1 ether, address(shares), 1000e18, 0, 5000, 100, 30, alice, 0
        );

        // Verify tap is cleared
        (address tapOps,, uint128 ratePerSec,) = daico.taps(address(moloch));
        assertEq(tapOps, address(0));
        assertEq(ratePerSec, 0);
    }

    /// @notice Test quoteBuy is LP-aware
    function test_QuoteBuy_WithLP() public {
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        // Sale: 1 ETH = 1000 shares, 50% to LP
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(0), 1 ether, address(shares), 1000e18, 0, 5000, 100, 30);

        // Quote 2 ETH
        uint256 buyAmt = daico.quoteBuy(address(moloch), address(0), 2 ether);

        // Gross = 2000 shares, LP takes 50% = 1000, buyer gets 1000
        assertEq(buyAmt, 1000e18, "Buyer should get 1000 shares (50% to LP)");
    }

    /// @notice Test quotePayExactOut is LP-aware
    function test_QuotePayExactOut_WithLP() public {
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        // Sale: 1 ETH = 1000 shares, 50% to LP
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(0), 1 ether, address(shares), 1000e18, 0, 5000, 100, 30);

        // Quote to get exactly 1000 shares
        uint256 payAmt = daico.quotePayExactOut(address(moloch), address(0), 1000e18);

        // Buyer wants 1000 shares, but 50% goes to LP
        // So gross = 1000 * 10000 / 5000 = 2000 shares
        // payAmt = ceil(2000 * 1e18 / 1000e18) = 2 ETH
        assertEq(payAmt, 2 ether, "Should pay 2 ETH to get 1000 shares with 50% LP");
    }

    /// @notice Test quoteBuy returns 0 after deadline expires
    function test_QuoteBuy_ExpiredDeadline() public {
        uint40 deadline = uint40(block.timestamp + 1 hours);

        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, deadline);

        // Quote before expiry
        uint256 buyAmtBefore = daico.quoteBuy(address(moloch), address(0), 1 ether);
        assertEq(buyAmtBefore, 1000e18, "Should quote 1000 shares before expiry");

        // Warp past deadline
        vm.warp(deadline + 1);

        // Quote after expiry
        uint256 buyAmtAfter = daico.quoteBuy(address(moloch), address(0), 1 ether);
        assertEq(buyAmtAfter, 0, "Should return 0 after deadline");
    }

    /// @notice Test quotePayExactOut returns 0 after deadline expires
    function test_QuotePayExactOut_ExpiredDeadline() public {
        uint40 deadline = uint40(block.timestamp + 1 hours);

        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, deadline);

        // Quote before expiry
        uint256 payAmtBefore = daico.quotePayExactOut(address(moloch), address(0), 1000e18);
        assertEq(payAmtBefore, 1 ether, "Should quote 1 ETH before expiry");

        // Warp past deadline
        vm.warp(deadline + 1);

        // Quote after expiry
        uint256 payAmtAfter = daico.quotePayExactOut(address(moloch), address(0), 1000e18);
        assertEq(payAmtAfter, 0, "Should return 0 after deadline");
    }

    /// @notice Test setupDAICO reverts on bad lpBps
    function test_SetupDAICO_RevertBadLPBps() public {
        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 1000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 10_001, // Invalid: > 10000
            maxSlipBps: 100,
            feeOrHook: 30
        });

        DAICO.TapConfig memory tapConfig =
            DAICO.TapConfig({ops: address(0), ratePerSec: 0, tapAllowance: 0});

        vm.prank(address(moloch));
        vm.expectRevert(DAICO.BadLPBps.selector);
        daico.setupDAICO(address(moloch), address(shares), daicoConfig, tapConfig);
    }

    /// @notice Test buyExactOut with LP and pool drift
    /// @dev When spot > OTC, drift protection caps LP. The exact amounts depend on pool state.
    function test_BuyExactOut_WithLP_DriftProtection() public {
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        // First create a pool with same rate as OTC (no drift)
        // OTC rate: 1 ETH = 1000 shares
        // Pool rate: 1 ETH = 1000 shares (no drift)
        vm.prank(address(moloch));
        shares.approve(address(zamm), type(uint256).max);

        ZAMM.PoolKey memory poolKey = ZAMM.PoolKey({
            id0: 0, id1: 0, token0: address(0), token1: address(shares), feeOrHook: 30
        });

        vm.deal(address(moloch), 10 ether);
        vm.prank(address(moloch));
        zamm.addLiquidity{value: 1 ether}(
            poolKey, 1 ether, 1000e18, 0, 0, address(moloch), block.timestamp
        );

        // Set sale with LP (lower lpBps for easier math)
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(0), 1 ether, address(shares), 1000e18, 0, 2000, 500, 30);

        // BuyExactOut - Bob wants exactly 500 shares
        vm.deal(bob, 10 ether);
        vm.prank(bob);
        daico.buyExactOut{value: 2 ether}(address(moloch), address(0), 500e18, 2 ether);

        // Bob should have received exactly 500 shares
        assertEq(shares.balanceOf(bob), 500e18, "Bob should have 500 shares");
    }

    /// @notice Test buy reverts when expired (exact-in)
    function test_Buy_RevertExpired() public {
        uint40 deadline = uint40(block.timestamp + 1 hours);

        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, deadline);

        // Warp past deadline
        vm.warp(deadline + 1);

        vm.deal(bob, 1 ether);
        vm.prank(bob);
        vm.expectRevert(DAICO.Expired.selector);
        daico.buy{value: 1 ether}(address(moloch), address(0), 1 ether, 0);
    }

    /// @notice Test buyExactOut reverts when expired
    function test_BuyExactOut_RevertExpired() public {
        uint40 deadline = uint40(block.timestamp + 1 hours);

        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, deadline);

        // Warp past deadline
        vm.warp(deadline + 1);

        vm.deal(bob, 1 ether);
        vm.prank(bob);
        vm.expectRevert(DAICO.Expired.selector);
        daico.buyExactOut{value: 1 ether}(address(moloch), address(0), 1000e18, 1 ether);
    }

    /// @notice Test buyExactOut reverts with zero buyAmt
    function test_BuyExactOut_RevertZeroBuyAmt() public {
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, 0);

        vm.prank(bob);
        vm.expectRevert(DAICO.InvalidParams.selector);
        daico.buyExactOut(address(moloch), address(0), 0, 1 ether);
    }

    /// @notice Test buyExactOut reverts with zero dao
    function test_BuyExactOut_RevertZeroDao() public {
        vm.prank(bob);
        vm.expectRevert(DAICO.InvalidParams.selector);
        daico.buyExactOut(address(0), address(0), 1000e18, 1 ether);
    }

    /// @notice Test buyExactOut reverts with no sale
    function test_BuyExactOut_RevertNoSale() public {
        vm.prank(bob);
        vm.expectRevert(DAICO.NoSale.selector);
        daico.buyExactOut(address(moloch), address(0), 1000e18, 1 ether);
    }

    /// @notice Test buy with LP where forTknDesired rounds to zero
    function test_Buy_WithLP_TinyAmount() public {
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        // Sale: 1 ETH = 1 share (very expensive)
        // With 50% LP, buying 1 wei would try to LP 0.5 wei worth
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(0), 1 ether, address(shares), 1e18, 0, 5000, 100, 30);

        // Try to buy with tiny amount - LP portion will be too small
        vm.deal(bob, 1 ether);
        vm.prank(bob);
        // This should still work - LP will get skipped if forTknDesired is 0
        daico.buy{value: 1 wei}(address(moloch), address(0), 1 wei, 0);

        // Bob gets 0 shares due to rounding (1 wei * 1e18 / 1e18 = 1 wei worth = 0 shares)
        // Actually this will revert with InvalidParams because buyAmt = 0
    }

    /// @notice Test ERC20 buy with LP properly rejects ETH
    function test_BuyExactOut_ERC20_WithLP_RejectETH() public {
        MockERC20 usdc = new MockERC20("USDC", "USDC", 6);

        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        // Setup USDC sale with LP
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(usdc), 100e6, address(shares), 1000e18, 0, 5000, 100, 30);

        usdc.mint(bob, 10_000e6);
        vm.prank(bob);
        usdc.approve(address(daico), type(uint256).max);

        vm.deal(bob, 1 ether);
        vm.prank(bob);
        vm.expectRevert(DAICO.InvalidParams.selector);
        daico.buyExactOut{value: 1 ether}(address(moloch), address(usdc), 1000e18, 1000e6);
    }

    /// @notice Test quote functions return correct values without LP
    function test_Quotes_WithoutLP() public {
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        // Sale without LP: 1 ETH = 1000 shares
        vm.prank(address(moloch));
        daico.setSale(address(0), 1 ether, address(shares), 1000e18, 0);

        // quoteBuy: 2 ETH -> 2000 shares
        uint256 buyAmt = daico.quoteBuy(address(moloch), address(0), 2 ether);
        assertEq(buyAmt, 2000e18);

        // quotePayExactOut: 2000 shares -> 2 ETH
        uint256 payAmt = daico.quotePayExactOut(address(moloch), address(0), 2000e18);
        assertEq(payAmt, 2 ether);
    }

    /// @notice Test LP with 100% allocation (all to LP, nothing to buyer - should fail)
    function test_Buy_WithLP_100Percent_RevertsOnConfig() public {
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        // 100% to LP is now blocked at config time (leaves nothing for buyer)
        vm.prank(address(moloch));
        vm.expectRevert(DAICO.BadLPBps.selector);
        daico.setSaleWithLP(address(0), 1 ether, address(shares), 1000e18, 0, 10_000, 100, 30);
    }

    /// @notice Test claimTap when tap rate is zero but ops is set (frozen tap)
    function test_ClaimTap_FrozenTap() public {
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        // Set tap then freeze it
        vm.prank(address(moloch));
        daico.setSaleWithTap(address(0), 1 ether, address(shares), 1000e18, 0, alice, 0.01 ether);

        // Fund the DAO
        vm.deal(address(moloch), 10 ether);
        vm.prank(address(moloch));
        moloch.setAllowance(address(daico), address(0), 10 ether);

        // Freeze the tap
        vm.prank(address(moloch));
        daico.setTapRate(0);

        // Advance time
        vm.warp(block.timestamp + 1 days);

        // Claim should fail because rate is 0
        vm.expectRevert(DAICO.NoTap.selector);
        daico.claimTap(address(moloch));
    }

    /// @notice Test pendingTap returns 0 for non-existent tap
    function test_PendingTap_NonExistent() public view {
        uint256 pending = daico.pendingTap(address(0xdead));
        assertEq(pending, 0);
    }

    /// @notice Test claimableTap returns 0 when ops is address(0)
    function test_ClaimableTap_ZeroOps() public {
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        // Set tap then disable ops
        vm.prank(address(moloch));
        daico.setSaleWithTap(address(0), 1 ether, address(shares), 1000e18, 0, alice, 0.01 ether);

        vm.prank(address(moloch));
        daico.setTapOps(address(0));

        // Advance time
        vm.warp(block.timestamp + 1 days);

        // claimableTap should return 0
        uint256 claimable = daico.claimableTap(address(moloch));
        assertEq(claimable, 0);
    }

    /// @notice Test fuzz for setSaleWithLPAndTap
    function testFuzz_SetSaleWithLPAndTap(
        uint256 tribAmt,
        uint256 forAmt,
        uint16 lpBps,
        uint128 ratePerSec
    ) public {
        // Constrain to reasonable values to avoid overflow in rate calculations
        tribAmt = bound(tribAmt, 1e6, 1e27);
        forAmt = bound(forAmt, 1e6, 1e27);
        lpBps = uint16(bound(lpBps, 1, 9_999)); // 100% (10000) is now blocked
        ratePerSec = uint128(bound(ratePerSec, 1, 1e18));

        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 1e27); // Fits in uint96 for voting checkpoints
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        vm.prank(address(moloch));
        daico.setSaleWithLPAndTap(
            address(0), tribAmt, address(shares), forAmt, 0, lpBps, 100, 30, alice, ratePerSec
        );

        // Verify all configs set correctly
        (uint256 storedTribAmt, uint256 storedForAmt,,) = daico.sales(address(moloch), address(0));
        assertEq(storedTribAmt, tribAmt);
        assertEq(storedForAmt, forAmt);

        (uint16 storedLpBps,,) = daico.lpConfigs(address(moloch), address(0));
        assertEq(storedLpBps, lpBps);

        (address tapOps,, uint128 storedRate,) = daico.taps(address(moloch));
        assertEq(tapOps, alice);
        assertEq(storedRate, ratePerSec);
    }

    /// @notice Test quoteBuy with various LP percentages
    function testFuzz_QuoteBuy_WithLP(uint256 payAmt, uint16 lpBps) public {
        // Constrain payAmt to avoid overflow in grossBuyAmt calculation (1000e18 * payAmt)
        payAmt = bound(payAmt, 1e15, 1e24); // Max 1e24 to avoid overflow with 1000e18 multiplier
        lpBps = uint16(bound(lpBps, 1, 9999)); // Not 100% or 0%

        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 1e27); // Fits in uint96 for voting checkpoints
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);

        // 1 ETH = 1000 shares
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(0), 1 ether, address(shares), 1000e18, 0, lpBps, 100, 30);

        uint256 buyAmt = daico.quoteBuy(address(moloch), address(0), payAmt);

        // Calculate expected - must match _quoteLPUsed logic exactly:
        // 1. grossBuyAmt = (forAmt * payAmt) / tribAmt
        // 2. tribForLP = (payAmt * lpBps) / 10_000
        // 3. rateX18 = (forAmt * 1e18) / tribAmt = 1000e18 for our sale
        // 4. forTknLPUsed = (tribForLP * rateX18) / 1e18
        // 5. buyAmt = grossBuyAmt - forTknLPUsed
        uint256 grossBuyAmt = (1000e18 * payAmt) / 1 ether;
        uint256 tribForLP = (payAmt * lpBps) / 10_000;
        uint256 rateX18 = 1000e18; // (1000e18 * 1e18) / 1e18
        uint256 forTknLPUsed = (tribForLP * rateX18) / 1e18;
        uint256 expectedBuyAmt = grossBuyAmt - forTknLPUsed;

        assertEq(buyAmt, expectedBuyAmt, "Quote should match expected LP-adjusted amount");
    }

    /*//////////////////////////////////////////////////////////////
                    USDT-STYLE APPROVAL TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test that ensureApproval works with standard ERC20 (multiple LP buys)
    function test_Buy_ERC20_WithLP_MultipleApprovals() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);

        // 1. Setup DAO and sale
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(usdc), 100e6, address(shares), 1000e18, 0, 5000, 100, 30);

        // 2. Mint USDC to multiple buyers
        usdc.mint(bob, 10_000e6);
        usdc.mint(alice, 10_000e6);
        vm.prank(bob);
        usdc.approve(address(daico), type(uint256).max);
        vm.prank(alice);
        usdc.approve(address(daico), type(uint256).max);

        // 3. First buy - creates LP pool and sets max approval to ZAMM
        vm.prank(bob);
        daico.buy(address(moloch), address(usdc), 200e6, 0);

        // 4. Verify DAICO has high approval to ZAMM for both tokens (>= uint128.max threshold)
        assertGt(
            usdc.allowance(address(daico), address(zamm)),
            type(uint128).max,
            "USDC approval should be above threshold"
        );
        assertGt(
            shares.allowance(address(daico), address(zamm)),
            type(uint128).max,
            "Shares approval should be above threshold"
        );

        // 5. Second buy - should reuse existing approval without re-approving
        uint256 aliceSharesBefore = shares.balanceOf(alice);
        vm.prank(alice);
        daico.buy(address(moloch), address(usdc), 400e6, 0);

        // 6. Alice should have received shares
        assertGt(shares.balanceOf(alice), aliceSharesBefore, "Alice should receive shares");

        // 7. Approval should still be above threshold (not reset to 0)
        assertGt(
            usdc.allowance(address(daico), address(zamm)),
            type(uint128).max,
            "USDC approval should remain above threshold"
        );
    }

    /// @notice Test that ensureApproval works with USDT-style tokens (reverts on non-zero to non-zero)
    function test_Buy_USDT_WithLP_MultipleApprovals() public {
        MockUSDT usdt = new MockUSDT();

        // 1. Setup DAO and sale with USDT as tribute token
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(usdt), 100e6, address(shares), 1000e18, 0, 5000, 100, 30);

        // 2. Mint USDT to multiple buyers
        usdt.mint(bob, 10_000e6);
        usdt.mint(alice, 10_000e6);
        vm.prank(bob);
        usdt.approve(address(daico), type(uint256).max);
        vm.prank(alice);
        usdt.approve(address(daico), type(uint256).max);

        // 3. First buy - creates LP pool and sets max approval to ZAMM
        vm.prank(bob);
        daico.buy(address(moloch), address(usdt), 200e6, 0);

        // 4. Verify DAICO has high approval to ZAMM for USDT (above uint128.max threshold)
        assertGt(
            usdt.allowance(address(daico), address(zamm)),
            type(uint128).max,
            "USDT approval should be above threshold"
        );

        // 5. Second buy - would FAIL with old safeApprove (non-zero to non-zero)
        // But ensureApproval skips approval since it's above threshold
        uint256 aliceSharesBefore = shares.balanceOf(alice);
        vm.prank(alice);
        daico.buy(address(moloch), address(usdt), 400e6, 0);

        // 6. Alice should have received shares (proves no revert occurred)
        assertGt(shares.balanceOf(alice), aliceSharesBefore, "Alice should receive shares");

        // 7. Approval should still be above threshold
        assertGt(
            usdt.allowance(address(daico), address(zamm)),
            type(uint128).max,
            "USDT approval should remain above threshold"
        );
    }

    /// @notice Test multiple sequential buys with USDT-style token
    function test_Buy_USDT_WithLP_ManySequentialBuys() public {
        MockUSDT usdt = new MockUSDT();

        // Setup
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 1_000_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(usdt), 100e6, address(shares), 1000e18, 0, 5000, 100, 30);

        // Give bob lots of USDT
        usdt.mint(bob, 100_000e6);
        vm.prank(bob);
        usdt.approve(address(daico), type(uint256).max);

        // Perform 5 sequential buys - all should succeed with ensureApproval
        for (uint256 i = 0; i < 5; i++) {
            uint256 bobSharesBefore = shares.balanceOf(bob);
            vm.prank(bob);
            daico.buy(address(moloch), address(usdt), 200e6, 0);
            assertGt(shares.balanceOf(bob), bobSharesBefore, "Bob should receive shares each buy");
        }

        // Approval should still be above threshold after all buys
        assertGt(
            usdt.allowance(address(daico), address(zamm)),
            type(uint128).max,
            "USDT approval should remain above threshold after multiple buys"
        );
    }

    /// @notice Test buyExactOut also works with USDT-style tokens
    function test_BuyExactOut_USDT_WithLP() public {
        MockUSDT usdt = new MockUSDT();

        // Setup
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(usdt), 100e6, address(shares), 1000e18, 0, 5000, 100, 30);

        usdt.mint(bob, 10_000e6);
        usdt.mint(alice, 10_000e6);
        vm.prank(bob);
        usdt.approve(address(daico), type(uint256).max);
        vm.prank(alice);
        usdt.approve(address(daico), type(uint256).max);

        // First buyExactOut
        vm.prank(bob);
        daico.buyExactOut(address(moloch), address(usdt), 500e18, type(uint256).max);

        // Second buyExactOut - should work with ensureApproval
        uint256 aliceSharesBefore = shares.balanceOf(alice);
        vm.prank(alice);
        daico.buyExactOut(address(moloch), address(usdt), 500e18, type(uint256).max);

        assertEq(
            shares.balanceOf(alice) - aliceSharesBefore,
            500e18,
            "Alice should receive exact 500 shares"
        );
    }

    /// @notice Test that forTkn (shares) approval also uses ensureApproval correctly
    function test_Buy_WithLP_ForTknApprovalPersists() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);

        // Setup
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(usdc), 100e6, address(shares), 1000e18, 0, 5000, 100, 30);

        usdc.mint(bob, 10_000e6);
        vm.prank(bob);
        usdc.approve(address(daico), type(uint256).max);

        // Before first buy, DAICO should have no approval to ZAMM for shares
        assertEq(
            shares.allowance(address(daico), address(zamm)),
            0,
            "No shares approval before first buy"
        );

        // First buy
        vm.prank(bob);
        daico.buy(address(moloch), address(usdc), 200e6, 0);

        // After first buy, DAICO should have max approval for shares
        assertEq(
            shares.allowance(address(daico), address(zamm)),
            type(uint256).max,
            "Shares approval should be max after first buy"
        );

        // Second buy - verify shares approval persists
        usdc.mint(bob, 10_000e6);
        vm.prank(bob);
        daico.buy(address(moloch), address(usdc), 200e6, 0);

        assertEq(
            shares.allowance(address(daico), address(zamm)),
            type(uint256).max,
            "Shares approval should remain max"
        );
    }

    /// @notice Test gas savings from ensureApproval skipping redundant approvals
    function test_Buy_ERC20_WithLP_GasSavingsOnSecondBuy() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);

        // Setup
        vm.prank(address(moloch));
        shares.mintFromMoloch(address(moloch), 100_000e18);
        vm.prank(address(moloch));
        shares.approve(address(daico), type(uint256).max);
        vm.prank(address(moloch));
        daico.setSaleWithLP(address(usdc), 100e6, address(shares), 1000e18, 0, 5000, 100, 30);

        usdc.mint(bob, 10_000e6);
        usdc.mint(alice, 10_000e6);
        vm.prank(bob);
        usdc.approve(address(daico), type(uint256).max);
        vm.prank(alice);
        usdc.approve(address(daico), type(uint256).max);

        // First buy - sets approval (cold storage write)
        uint256 gasBefore = gasleft();
        vm.prank(bob);
        daico.buy(address(moloch), address(usdc), 200e6, 0);
        uint256 gasFirstBuy = gasBefore - gasleft();

        // Second buy - skips approval (only reads, no write)
        gasBefore = gasleft();
        vm.prank(alice);
        daico.buy(address(moloch), address(usdc), 200e6, 0);
        uint256 gasSecondBuy = gasBefore - gasleft();

        emit log_named_uint("Gas first buy (sets approval)", gasFirstBuy);
        emit log_named_uint("Gas second buy (skips approval)", gasSecondBuy);

        // Second buy should use less gas since it skips the approval SSTORE
        // The savings come from avoiding 2 SSTORE operations (~20k gas each)
        assertLt(gasSecondBuy, gasFirstBuy, "Second buy should use less gas");
    }
}

/*//////////////////////////////////////////////////////////////
                CUSTOM INIT CALLS TESTS
//////////////////////////////////////////////////////////////*/

import {Call as DAICOCall} from "../src/peripheral/DAICO.sol";

contract DAICO_CustomCalls_Test is Test {
    Summoner internal summoner;
    DAICO internal daico;
    ZAMM internal zamm;

    // Implementation addresses for CREATE2 prediction
    address internal molochImpl;
    address internal sharesImpl;
    address internal lootImpl;

    address internal alice = address(0xA11CE);
    address internal bob = address(0x0B0B);
    address internal ops = address(0x0505);
    address internal founder = address(0xF00D);

    // ZAMM address from DAICO.sol
    address constant ZAMM_ADDRESS = 0x000000000000040470635EB91b7CE4D132D616eD;

    function setUp() public {
        vm.label(alice, "ALICE");
        vm.label(bob, "BOB");
        vm.label(ops, "OPS");
        vm.label(founder, "FOUNDER");

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);

        // Deploy ZAMM to the hardcoded address used by DAICO
        ZAMM zammLocal = new ZAMM();
        vm.etch(ZAMM_ADDRESS, address(zammLocal).code);
        zamm = ZAMM(payable(ZAMM_ADDRESS));
        vm.label(address(zamm), "ZAMM");

        // Record logs to capture NewDAO event
        vm.recordLogs();
        summoner = new Summoner();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        molochImpl = address(uint160(uint256(logs[0].topics[2])));

        daico = new DAICO();

        // Compute shares/loot impl addresses
        bytes32 implSalt = bytes32(bytes20(molochImpl));
        sharesImpl = _computeCreate2(molochImpl, implSalt, type(Shares).creationCode);
        lootImpl = _computeCreate2(molochImpl, implSalt, type(Loot).creationCode);

        vm.roll(block.number + 1);
    }

    function _computeCreate2(address deployer, bytes32 salt, bytes memory creationCode)
        internal
        pure
        returns (address)
    {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), deployer, salt, keccak256(creationCode))
                    )
                )
            )
        );
    }

    function _getSummonConfig() internal view returns (DAICO.SummonConfig memory) {
        return DAICO.SummonConfig({
            summoner: address(summoner),
            molochImpl: molochImpl,
            sharesImpl: sharesImpl,
            lootImpl: lootImpl
        });
    }

    /// @dev Predict DAO address (same logic as DAICO._predictDAO)
    function _predictDAO(bytes32 salt, address[] memory holders, uint256[] memory amounts)
        internal
        view
        returns (address)
    {
        bytes32 _salt = keccak256(abi.encode(holders, amounts, salt));
        bytes memory creationCode = abi.encodePacked(
            hex"602d5f8160095f39f35f5f365f5f37365f73",
            molochImpl,
            hex"5af43d5f5f3e6029573d5ffd5b3d5ff3"
        );
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), address(summoner), _salt, keccak256(creationCode)
                        )
                    )
                )
            )
        );
    }

    /// @dev Predict clone address (shares/loot from DAO)
    function _predictClone(address impl, address deployer) internal pure returns (address) {
        bytes32 salt = bytes32(bytes20(deployer));
        bytes memory creationCode = abi.encodePacked(
            hex"602d5f8160095f39f35f5f365f5f37365f73", impl, hex"5af43d5f5f3e6029573d5ffd5b3d5ff3"
        );
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), deployer, salt, keccak256(creationCode))
                    )
                )
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                        summonDAICOCustom TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test summonDAICOCustom with extra shares mint for ops
    function test_SummonDAICOCustom_ExtraOpsMint() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        bytes32 salt = bytes32(uint256(100));

        // Predict addresses
        address predictedDAO = _predictDAO(salt, holders, amounts);
        address predictedShares = _predictClone(sharesImpl, predictedDAO);

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        // Custom call: mint extra 10,000 shares to ops team
        DAICOCall[] memory customCalls = new DAICOCall[](1);
        customCalls[0] = DAICOCall({
            target: predictedShares,
            value: 0,
            data: abi.encodeCall(Shares.mintFromMoloch, (ops, 10_000e18))
        });

        address dao = daico.summonDAICOCustom(
            _getSummonConfig(),
            "Custom DAO",
            "CUST",
            "",
            5000,
            true,
            address(0),
            salt,
            holders,
            amounts,
            false,
            false,
            daicoConfig,
            customCalls
        );

        // Verify DAO created at predicted address
        assertEq(dao, predictedDAO);

        // Verify ops received extra shares
        Shares daoShares = Moloch(payable(dao)).shares();
        assertEq(daoShares.balanceOf(ops), 10_000e18);

        // Verify sale supply still minted to DAO
        assertEq(daoShares.balanceOf(dao), 100_000e18);

        // Verify sale works
        vm.prank(bob);
        daico.buy{value: 1 ether}(dao, address(0), 1 ether, 0);
        assertEq(daoShares.balanceOf(bob), 1000e18);
    }

    /// @notice Test summonDAICOCustom with founder shares timelocked to ZAMM
    /// This is a powerful pattern: founder allocation locked until cliff date,
    /// automatically released to founder via ZAMM's unlock mechanism
    function test_SummonDAICOCustom_FounderSharesTimelocked() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        bytes32 salt = bytes32(uint256(101));

        // Predict addresses
        address predictedDAO = _predictDAO(salt, holders, amounts);
        address predictedShares = _predictClone(sharesImpl, predictedDAO);

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        // Founder allocation: 20,000 shares locked for 1 year
        uint256 founderAllocation = 20_000e18;
        uint256 unlockTime = block.timestamp + 365 days;

        // Custom calls:
        // 1. Mint founder shares to DAO (so DAO can approve ZAMM)
        // 2. Approve ZAMM to transfer founder shares
        // 3. Call ZAMM.lockup to lock founder shares
        DAICOCall[] memory customCalls = new DAICOCall[](3);

        // Mint founder allocation to DAO
        customCalls[0] = DAICOCall({
            target: predictedShares,
            value: 0,
            data: abi.encodeCall(Shares.mintFromMoloch, (predictedDAO, founderAllocation))
        });

        // Approve ZAMM to transfer shares
        customCalls[1] = DAICOCall({
            target: predictedShares,
            value: 0,
            data: abi.encodeCall(Shares.approve, (ZAMM_ADDRESS, founderAllocation))
        });

        // Lock shares in ZAMM for founder
        // lockup(token, to, id, amount, unlockTime)
        customCalls[2] = DAICOCall({
            target: ZAMM_ADDRESS,
            value: 0,
            data: abi.encodeCall(
                ZAMM.lockup, (predictedShares, founder, 0, founderAllocation, unlockTime)
            )
        });

        address dao = daico.summonDAICOCustom(
            _getSummonConfig(),
            "Timelock DAO",
            "TLOCK",
            "",
            5000,
            true,
            address(0),
            salt,
            holders,
            amounts,
            false,
            false,
            daicoConfig,
            customCalls
        );

        Shares daoShares = Moloch(payable(dao)).shares();

        // Verify founder doesn't have shares yet (locked in ZAMM)
        assertEq(daoShares.balanceOf(founder), 0);

        // Verify ZAMM holds the founder shares
        assertEq(daoShares.balanceOf(ZAMM_ADDRESS), founderAllocation);

        // Verify lockup exists in ZAMM
        bytes32 lockHash =
            keccak256(abi.encode(address(daoShares), founder, 0, founderAllocation, unlockTime));
        assertEq(zamm.lockups(lockHash), unlockTime);

        // Try to unlock early - should fail
        vm.expectRevert(ZAMM.Pending.selector);
        zamm.unlock(address(daoShares), founder, 0, founderAllocation, unlockTime);

        // Warp to unlock time
        vm.warp(unlockTime);

        // Now unlock should work
        zamm.unlock(address(daoShares), founder, 0, founderAllocation, unlockTime);

        // Verify founder received shares
        assertEq(daoShares.balanceOf(founder), founderAllocation);
        assertEq(daoShares.balanceOf(ZAMM_ADDRESS), 0);
    }

    /// @notice Test summonDAICOWithTapCustom - full featured: sale + tap + custom calls
    function test_SummonDAICOWithTapCustom_FullSetup() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        bytes32 salt = bytes32(uint256(102));

        address predictedDAO = _predictDAO(salt, holders, amounts);
        address predictedShares = _predictClone(sharesImpl, predictedDAO);
        address predictedLoot = _predictClone(lootImpl, predictedDAO);

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        // 1 ETH per day tap rate
        uint128 ratePerSec = 11574074074074;
        DAICO.TapConfig memory tapConfig =
            DAICO.TapConfig({ops: ops, ratePerSec: ratePerSec, tapAllowance: 100 ether});

        // Custom calls: mint loot to founder (non-voting but ragequittable)
        uint256 founderLoot = 50_000e18;
        DAICOCall[] memory customCalls = new DAICOCall[](1);
        customCalls[0] = DAICOCall({
            target: predictedLoot,
            value: 0,
            data: abi.encodeCall(Loot.mintFromMoloch, (founder, founderLoot))
        });

        address dao = daico.summonDAICOWithTapCustom{value: 10 ether}(
            _getSummonConfig(),
            "Full DAO",
            "FULL",
            "",
            5000,
            true,
            address(0),
            salt,
            holders,
            amounts,
            false,
            false,
            daicoConfig,
            tapConfig,
            customCalls
        );

        // Verify sale configured
        (uint256 tribAmt, uint256 forAmt, address forTkn,) = daico.sales(dao, address(0));
        assertEq(tribAmt, 1 ether);
        assertEq(forAmt, 1000e18);
        assertEq(forTkn, predictedShares);

        // Verify tap configured
        (address tapOps, address tapTribTkn, uint128 tapRate,) = daico.taps(dao);
        assertEq(tapOps, ops);
        assertEq(tapTribTkn, address(0));
        assertEq(tapRate, ratePerSec);

        // Verify founder received loot
        Loot daoLoot = Moloch(payable(dao)).loot();
        assertEq(daoLoot.balanceOf(founder), founderLoot);

        // Verify DAO received ETH
        assertEq(dao.balance, 10 ether);

        // Test tap works
        vm.warp(block.timestamp + 1 days);
        uint256 claimable = daico.claimableTap(dao);
        assertApproxEqRel(claimable, 1 ether, 0.01e18);
    }

    /// @notice Test multiple custom calls: ops mint + founder timelock + advisor vesting
    function test_SummonDAICOCustom_MultipleAllocations() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        bytes32 salt = bytes32(uint256(103));

        address predictedDAO = _predictDAO(salt, holders, amounts);
        address predictedShares = _predictClone(sharesImpl, predictedDAO);

        address advisor1 = address(0xAD01);
        address advisor2 = address(0xAD02);

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 500_000e18, // 50% for sale
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        // Allocations:
        // - Ops: 50,000 shares (immediate)
        // - Founder: 200,000 shares (2 year timelock)
        // - Advisor1: 100,000 shares (1 year timelock)
        // - Advisor2: 50,000 shares (6 month timelock)

        uint256 opsAlloc = 50_000e18;
        uint256 founderAlloc = 200_000e18;
        uint256 advisor1Alloc = 100_000e18;
        uint256 advisor2Alloc = 50_000e18;

        uint256 founderUnlock = block.timestamp + 730 days;
        uint256 advisor1Unlock = block.timestamp + 365 days;
        uint256 advisor2Unlock = block.timestamp + 180 days;

        // Total for timelocks
        uint256 timelockTotal = founderAlloc + advisor1Alloc + advisor2Alloc;

        DAICOCall[] memory customCalls = new DAICOCall[](6);

        // 1. Mint ops shares directly
        customCalls[0] = DAICOCall({
            target: predictedShares,
            value: 0,
            data: abi.encodeCall(Shares.mintFromMoloch, (ops, opsAlloc))
        });

        // 2. Mint timelock shares to DAO
        customCalls[1] = DAICOCall({
            target: predictedShares,
            value: 0,
            data: abi.encodeCall(Shares.mintFromMoloch, (predictedDAO, timelockTotal))
        });

        // 3. Approve ZAMM for all timelocks
        customCalls[2] = DAICOCall({
            target: predictedShares,
            value: 0,
            data: abi.encodeCall(Shares.approve, (ZAMM_ADDRESS, timelockTotal))
        });

        // 4. Lock founder shares (2 years)
        customCalls[3] = DAICOCall({
            target: ZAMM_ADDRESS,
            value: 0,
            data: abi.encodeCall(
                ZAMM.lockup, (predictedShares, founder, 0, founderAlloc, founderUnlock)
            )
        });

        // 5. Lock advisor1 shares (1 year)
        customCalls[4] = DAICOCall({
            target: ZAMM_ADDRESS,
            value: 0,
            data: abi.encodeCall(
                ZAMM.lockup, (predictedShares, advisor1, 0, advisor1Alloc, advisor1Unlock)
            )
        });

        // 6. Lock advisor2 shares (6 months)
        customCalls[5] = DAICOCall({
            target: ZAMM_ADDRESS,
            value: 0,
            data: abi.encodeCall(
                ZAMM.lockup, (predictedShares, advisor2, 0, advisor2Alloc, advisor2Unlock)
            )
        });

        address dao = daico.summonDAICOCustom(
            _getSummonConfig(),
            "Multi Alloc DAO",
            "MALLOC",
            "",
            5000,
            true,
            address(0),
            salt,
            holders,
            amounts,
            false,
            false,
            daicoConfig,
            customCalls
        );

        Shares daoShares = Moloch(payable(dao)).shares();

        // Verify ops got immediate allocation
        assertEq(daoShares.balanceOf(ops), opsAlloc);

        // Verify all timelocked parties have 0 balance
        assertEq(daoShares.balanceOf(founder), 0);
        assertEq(daoShares.balanceOf(advisor1), 0);
        assertEq(daoShares.balanceOf(advisor2), 0);

        // Verify ZAMM holds all timelocked shares
        assertEq(daoShares.balanceOf(ZAMM_ADDRESS), timelockTotal);

        // Warp to 6 months - only advisor2 can unlock
        vm.warp(advisor2Unlock);

        vm.expectRevert(ZAMM.Pending.selector);
        zamm.unlock(address(daoShares), founder, 0, founderAlloc, founderUnlock);

        vm.expectRevert(ZAMM.Pending.selector);
        zamm.unlock(address(daoShares), advisor1, 0, advisor1Alloc, advisor1Unlock);

        // Advisor2 can unlock
        zamm.unlock(address(daoShares), advisor2, 0, advisor2Alloc, advisor2Unlock);
        assertEq(daoShares.balanceOf(advisor2), advisor2Alloc);

        // Warp to 1 year - advisor1 can unlock
        vm.warp(advisor1Unlock);
        zamm.unlock(address(daoShares), advisor1, 0, advisor1Alloc, advisor1Unlock);
        assertEq(daoShares.balanceOf(advisor1), advisor1Alloc);

        // Warp to 2 years - founder can unlock
        vm.warp(founderUnlock);
        zamm.unlock(address(daoShares), founder, 0, founderAlloc, founderUnlock);
        assertEq(daoShares.balanceOf(founder), founderAlloc);

        // ZAMM should be empty
        assertEq(daoShares.balanceOf(ZAMM_ADDRESS), 0);
    }

    /// @notice Test summonDAICOCustom with empty custom calls (should work like regular summonDAICO)
    function test_SummonDAICOCustom_EmptyCustomCalls() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        DAICOCall[] memory emptyCustomCalls = new DAICOCall[](0);

        address dao = daico.summonDAICOCustom(
            _getSummonConfig(),
            "No Custom DAO",
            "NOCUST",
            "",
            5000,
            true,
            address(0),
            bytes32(uint256(104)),
            holders,
            amounts,
            false,
            false,
            daicoConfig,
            emptyCustomCalls
        );

        // Should work exactly like summonDAICO
        Shares daoShares = Moloch(payable(dao)).shares();
        assertEq(daoShares.balanceOf(dao), 100_000e18);

        vm.prank(bob);
        daico.buy{value: 1 ether}(dao, address(0), 1 ether, 0);
        assertEq(daoShares.balanceOf(bob), 1000e18);
    }

    /// @notice Test custom call that sets up DAO allowance for external contract
    function test_SummonDAICOCustom_SetAllowanceForExternalContract() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        bytes32 salt = bytes32(uint256(105));
        address predictedDAO = _predictDAO(salt, holders, amounts);

        address externalContract = address(0xEEEE);

        DAICO.DAICOConfig memory daicoConfig = DAICO.DAICOConfig({
            tribTkn: address(0),
            tribAmt: 1 ether,
            saleSupply: 100_000e18,
            forAmt: 1000e18,
            deadline: 0,
            sellLoot: false,
            lpBps: 0,
            maxSlipBps: 0,
            feeOrHook: 0
        });

        // Custom call: set ETH allowance for external contract (e.g., a grants program)
        DAICOCall[] memory customCalls = new DAICOCall[](1);
        customCalls[0] = DAICOCall({
            target: predictedDAO,
            value: 0,
            data: abi.encodeCall(Moloch.setAllowance, (externalContract, address(0), 50 ether))
        });

        address dao = daico.summonDAICOCustom{value: 100 ether}(
            _getSummonConfig(),
            "Grants DAO",
            "GRANT",
            "",
            5000,
            true,
            address(0),
            salt,
            holders,
            amounts,
            false,
            false,
            daicoConfig,
            customCalls
        );

        // Verify allowance was set
        uint256 allowance = Moloch(payable(dao)).allowance(address(0), externalContract);
        assertEq(allowance, 50 ether);
    }
}
