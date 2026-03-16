// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "../lib/forge-std/src/Test.sol";
import {Tribute} from "../src/peripheral/Tribute.sol";

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

contract TributeTest is Test {
    Tribute internal tribute;
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;

    address internal proposer = address(0x1111);
    address internal dao = address(0x2222);
    address internal otherUser = address(0x3333);

    event TributeProposed(
        address indexed proposer,
        address indexed dao,
        address tribTkn,
        uint256 tribAmt,
        address forTkn,
        uint256 forAmt
    );
    event TributeCancelled(
        address indexed proposer,
        address indexed dao,
        address tribTkn,
        uint256 tribAmt,
        address forTkn,
        uint256 forAmt
    );
    event TributeClaimed(
        address indexed proposer,
        address indexed dao,
        address tribTkn,
        uint256 tribAmt,
        address forTkn,
        uint256 forAmt
    );

    function setUp() public {
        tribute = new Tribute();
        tokenA = new MockERC20("Token A", "TKNA", 18);
        tokenB = new MockERC20("Token B", "TKNB", 18);

        // Fund accounts
        vm.deal(proposer, 100 ether);
        vm.deal(dao, 100 ether);
        tokenA.mint(proposer, 1000 ether);
        tokenB.mint(dao, 1000 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        PROPOSE TRIBUTE - ETH
    //////////////////////////////////////////////////////////////*/

    function test_proposeTribute_ETH_forERC20() public {
        uint256 tribAmt = 1 ether;
        uint256 forAmt = 100 ether;

        vm.prank(proposer);
        vm.expectEmit(true, true, false, true);
        emit TributeProposed(proposer, dao, address(0), tribAmt, address(tokenB), forAmt);
        tribute.proposeTribute{value: tribAmt}(dao, address(0), 0, address(tokenB), forAmt);

        // Check tribute was stored
        (uint256 storedTribAmt, address storedForTkn, uint256 storedForAmt) =
            tribute.tributes(proposer, dao, address(0));
        assertEq(storedTribAmt, tribAmt);
        assertEq(storedForTkn, address(tokenB));
        assertEq(storedForAmt, forAmt);

        // Check ETH was transferred to contract
        assertEq(address(tribute).balance, tribAmt);

        // Check discovery arrays via paginated views
        (Tribute.ActiveTributeView[] memory daoViews,) = tribute.getActiveDaoTributes(dao, 0, 10);
        assertEq(daoViews.length, 1);
        (Tribute.ActiveTributeView[] memory propViews,) =
            tribute.getActiveProposerTributes(proposer, 0, 10);
        assertEq(propViews.length, 1);
    }

    function test_proposeTribute_ETH_forETH() public {
        uint256 tribAmt = 1 ether;
        uint256 forAmt = 2 ether;

        vm.prank(proposer);
        tribute.proposeTribute{value: tribAmt}(dao, address(0), 0, address(0), forAmt);

        (uint256 storedTribAmt, address storedForTkn, uint256 storedForAmt) =
            tribute.tributes(proposer, dao, address(0));
        assertEq(storedTribAmt, tribAmt);
        assertEq(storedForTkn, address(0));
        assertEq(storedForAmt, forAmt);
    }

    /*//////////////////////////////////////////////////////////////
                        PROPOSE TRIBUTE - ERC20
    //////////////////////////////////////////////////////////////*/

    function test_proposeTribute_ERC20_forERC20() public {
        uint256 tribAmt = 50 ether;
        uint256 forAmt = 100 ether;

        vm.startPrank(proposer);
        tokenA.approve(address(tribute), tribAmt);

        vm.expectEmit(true, true, false, true);
        emit TributeProposed(proposer, dao, address(tokenA), tribAmt, address(tokenB), forAmt);
        tribute.proposeTribute(dao, address(tokenA), tribAmt, address(tokenB), forAmt);
        vm.stopPrank();

        // Check tribute was stored
        (uint256 storedTribAmt, address storedForTkn, uint256 storedForAmt) =
            tribute.tributes(proposer, dao, address(tokenA));
        assertEq(storedTribAmt, tribAmt);
        assertEq(storedForTkn, address(tokenB));
        assertEq(storedForAmt, forAmt);

        // Check token was transferred to contract
        assertEq(tokenA.balanceOf(address(tribute)), tribAmt);
        assertEq(tokenA.balanceOf(proposer), 1000 ether - tribAmt);
    }

    function test_proposeTribute_ERC20_forETH() public {
        uint256 tribAmt = 50 ether;
        uint256 forAmt = 1 ether;

        vm.startPrank(proposer);
        tokenA.approve(address(tribute), tribAmt);
        tribute.proposeTribute(dao, address(tokenA), tribAmt, address(0), forAmt);
        vm.stopPrank();

        (uint256 storedTribAmt, address storedForTkn, uint256 storedForAmt) =
            tribute.tributes(proposer, dao, address(tokenA));
        assertEq(storedTribAmt, tribAmt);
        assertEq(storedForTkn, address(0));
        assertEq(storedForAmt, forAmt);
    }

    /*//////////////////////////////////////////////////////////////
                        PROPOSE TRIBUTE - REVERTS
    //////////////////////////////////////////////////////////////*/

    function test_proposeTribute_revert_zeroDao() public {
        vm.prank(proposer);
        vm.expectRevert(Tribute.InvalidParams.selector);
        tribute.proposeTribute{value: 1 ether}(
            address(0), address(0), 0, address(tokenB), 100 ether
        );
    }

    function test_proposeTribute_revert_zeroForAmt() public {
        vm.prank(proposer);
        vm.expectRevert(Tribute.InvalidParams.selector);
        tribute.proposeTribute{value: 1 ether}(dao, address(0), 0, address(tokenB), 0);
    }

    function test_proposeTribute_revert_ETH_withNonZeroTribTkn() public {
        vm.prank(proposer);
        vm.expectRevert(Tribute.InvalidParams.selector);
        tribute.proposeTribute{value: 1 ether}(dao, address(tokenA), 0, address(tokenB), 100 ether);
    }

    function test_proposeTribute_revert_ETH_withNonZeroTribAmt() public {
        vm.prank(proposer);
        vm.expectRevert(Tribute.InvalidParams.selector);
        tribute.proposeTribute{value: 1 ether}(dao, address(0), 1 ether, address(tokenB), 100 ether);
    }

    function test_proposeTribute_revert_ERC20_withZeroTribAmt() public {
        vm.prank(proposer);
        vm.expectRevert(Tribute.InvalidParams.selector);
        tribute.proposeTribute(dao, address(tokenA), 0, address(tokenB), 100 ether);
    }

    function test_proposeTribute_revert_duplicateOffer() public {
        vm.startPrank(proposer);
        tribute.proposeTribute{value: 1 ether}(dao, address(0), 0, address(tokenB), 100 ether);

        vm.expectRevert(Tribute.InvalidParams.selector);
        tribute.proposeTribute{value: 1 ether}(dao, address(0), 0, address(tokenB), 50 ether);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        CANCEL TRIBUTE
    //////////////////////////////////////////////////////////////*/

    function test_cancelTribute_ETH() public {
        uint256 tribAmt = 1 ether;
        uint256 proposerBalanceBefore = proposer.balance;

        vm.prank(proposer);
        tribute.proposeTribute{value: tribAmt}(dao, address(0), 0, address(tokenB), 100 ether);

        assertEq(proposer.balance, proposerBalanceBefore - tribAmt);

        vm.prank(proposer);
        vm.expectEmit(true, true, false, true);
        emit TributeCancelled(proposer, dao, address(0), tribAmt, address(tokenB), 100 ether);
        tribute.cancelTribute(dao, address(0));

        // Check tribute was deleted
        (uint256 storedTribAmt,,) = tribute.tributes(proposer, dao, address(0));
        assertEq(storedTribAmt, 0);

        // Check ETH was returned
        assertEq(proposer.balance, proposerBalanceBefore);
    }

    function test_cancelTribute_ERC20() public {
        uint256 tribAmt = 50 ether;
        uint256 proposerBalanceBefore = tokenA.balanceOf(proposer);

        vm.startPrank(proposer);
        tokenA.approve(address(tribute), tribAmt);
        tribute.proposeTribute(dao, address(tokenA), tribAmt, address(tokenB), 100 ether);

        assertEq(tokenA.balanceOf(proposer), proposerBalanceBefore - tribAmt);

        vm.expectEmit(true, true, false, true);
        emit TributeCancelled(proposer, dao, address(tokenA), tribAmt, address(tokenB), 100 ether);
        tribute.cancelTribute(dao, address(tokenA));
        vm.stopPrank();

        // Check tribute was deleted
        (uint256 storedTribAmt,,) = tribute.tributes(proposer, dao, address(tokenA));
        assertEq(storedTribAmt, 0);

        // Check token was returned
        assertEq(tokenA.balanceOf(proposer), proposerBalanceBefore);
    }

    function test_cancelTribute_revert_noTribute() public {
        vm.prank(proposer);
        vm.expectRevert(Tribute.NoTribute.selector);
        tribute.cancelTribute(dao, address(0));
    }

    function test_cancelTribute_revert_wrongProposer() public {
        vm.prank(proposer);
        tribute.proposeTribute{value: 1 ether}(dao, address(0), 0, address(tokenB), 100 ether);

        // Other user cannot cancel proposer's tribute
        vm.prank(otherUser);
        vm.expectRevert(Tribute.NoTribute.selector);
        tribute.cancelTribute(dao, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        CLAIM TRIBUTE
    //////////////////////////////////////////////////////////////*/

    function test_claimTribute_ETHtrib_ERC20for() public {
        uint256 tribAmt = 1 ether;
        uint256 forAmt = 100 ether;

        // Proposer creates tribute
        vm.prank(proposer);
        tribute.proposeTribute{value: tribAmt}(dao, address(0), 0, address(tokenB), forAmt);

        uint256 daoEthBefore = dao.balance;
        uint256 proposerTokenBBefore = tokenB.balanceOf(proposer);

        // DAO approves and claims
        vm.startPrank(dao);
        tokenB.approve(address(tribute), forAmt);

        vm.expectEmit(true, true, false, true);
        emit TributeClaimed(proposer, dao, address(0), tribAmt, address(tokenB), forAmt);
        tribute.claimTribute(proposer, address(0), tribAmt, address(tokenB), forAmt);
        vm.stopPrank();

        // Check tribute was deleted
        (uint256 storedTribAmt,,) = tribute.tributes(proposer, dao, address(0));
        assertEq(storedTribAmt, 0);

        // Check DAO received ETH tribute
        assertEq(dao.balance, daoEthBefore + tribAmt);

        // Check proposer received tokenB
        assertEq(tokenB.balanceOf(proposer), proposerTokenBBefore + forAmt);
    }

    function test_claimTribute_ERC20trib_ETHfor() public {
        uint256 tribAmt = 50 ether;
        uint256 forAmt = 1 ether;

        // Proposer creates tribute
        vm.startPrank(proposer);
        tokenA.approve(address(tribute), tribAmt);
        tribute.proposeTribute(dao, address(tokenA), tribAmt, address(0), forAmt);
        vm.stopPrank();

        uint256 daoTokenABefore = tokenA.balanceOf(dao);
        uint256 proposerEthBefore = proposer.balance;

        // DAO claims with ETH
        vm.prank(dao);
        vm.expectEmit(true, true, false, true);
        emit TributeClaimed(proposer, dao, address(tokenA), tribAmt, address(0), forAmt);
        tribute.claimTribute{value: forAmt}(proposer, address(tokenA), tribAmt, address(0), forAmt);

        // Check tribute was deleted
        (uint256 storedTribAmt,,) = tribute.tributes(proposer, dao, address(tokenA));
        assertEq(storedTribAmt, 0);

        // Check DAO received tokenA tribute
        assertEq(tokenA.balanceOf(dao), daoTokenABefore + tribAmt);

        // Check proposer received ETH
        assertEq(proposer.balance, proposerEthBefore + forAmt);
    }

    function test_claimTribute_ERC20trib_ERC20for() public {
        uint256 tribAmt = 50 ether;
        uint256 forAmt = 100 ether;

        // Proposer creates tribute
        vm.startPrank(proposer);
        tokenA.approve(address(tribute), tribAmt);
        tribute.proposeTribute(dao, address(tokenA), tribAmt, address(tokenB), forAmt);
        vm.stopPrank();

        uint256 daoTokenABefore = tokenA.balanceOf(dao);
        uint256 proposerTokenBBefore = tokenB.balanceOf(proposer);

        // DAO approves and claims
        vm.startPrank(dao);
        tokenB.approve(address(tribute), forAmt);
        tribute.claimTribute(proposer, address(tokenA), tribAmt, address(tokenB), forAmt);
        vm.stopPrank();

        // Check DAO received tokenA
        assertEq(tokenA.balanceOf(dao), daoTokenABefore + tribAmt);

        // Check proposer received tokenB
        assertEq(tokenB.balanceOf(proposer), proposerTokenBBefore + forAmt);
    }

    function test_claimTribute_ETHtrib_ETHfor() public {
        uint256 tribAmt = 1 ether;
        uint256 forAmt = 2 ether;

        // Proposer creates tribute
        vm.prank(proposer);
        tribute.proposeTribute{value: tribAmt}(dao, address(0), 0, address(0), forAmt);

        uint256 daoEthBefore = dao.balance;
        uint256 proposerEthBefore = proposer.balance;

        // DAO claims with ETH
        vm.prank(dao);
        tribute.claimTribute{value: forAmt}(proposer, address(0), tribAmt, address(0), forAmt);

        // Check DAO received ETH tribute (net: tribAmt - forAmt)
        assertEq(dao.balance, daoEthBefore - forAmt + tribAmt);

        // Check proposer received forAmt
        assertEq(proposer.balance, proposerEthBefore + forAmt);
    }

    function test_claimTribute_revert_noTribute() public {
        vm.prank(dao);
        vm.expectRevert(Tribute.NoTribute.selector);
        tribute.claimTribute(proposer, address(0), 1 ether, address(tokenB), 100 ether);
    }

    function test_claimTribute_revert_wrongETHAmount() public {
        vm.prank(proposer);
        tribute.proposeTribute{value: 1 ether}(dao, address(0), 0, address(0), 2 ether);

        // Wrong ETH amount
        vm.prank(dao);
        vm.expectRevert(Tribute.InvalidParams.selector);
        tribute.claimTribute{value: 1 ether}(proposer, address(0), 1 ether, address(0), 2 ether);
    }

    function test_claimTribute_revert_unexpectedETH() public {
        vm.startPrank(proposer);
        tokenA.approve(address(tribute), 50 ether);
        tribute.proposeTribute(dao, address(tokenA), 50 ether, address(tokenB), 100 ether);
        vm.stopPrank();

        // Sending ETH when forTkn is ERC20
        vm.prank(dao);
        vm.expectRevert(Tribute.InvalidParams.selector);
        tribute.claimTribute{value: 1 ether}(
            proposer, address(tokenA), 50 ether, address(tokenB), 100 ether
        );
    }

    /*//////////////////////////////////////////////////////////////
                        BAIT AND SWITCH PREVENTION
    //////////////////////////////////////////////////////////////*/

    function test_claimTribute_revert_baitAndSwitch() public {
        uint256 tribAmt = 100 ether;
        uint256 forAmt = 50 ether;

        // Proposer creates generous tribute
        vm.startPrank(proposer);
        tokenA.approve(address(tribute), tribAmt);
        tribute.proposeTribute(dao, address(tokenA), tribAmt, address(tokenB), forAmt);
        vm.stopPrank();

        // Proposer cancels and re-proposes with worse terms
        vm.startPrank(proposer);
        tribute.cancelTribute(dao, address(tokenA));
        tokenA.approve(address(tribute), 1 ether);
        tribute.proposeTribute(dao, address(tokenA), 1 ether, address(tokenB), forAmt);
        vm.stopPrank();

        // DAO tries to claim with original terms — reverts
        vm.startPrank(dao);
        tokenB.approve(address(tribute), forAmt);
        vm.expectRevert(Tribute.TermsMismatch.selector);
        tribute.claimTribute(proposer, address(tokenA), tribAmt, address(tokenB), forAmt);
        vm.stopPrank();
    }

    function test_claimTribute_revert_termsMismatch_tribAmt() public {
        vm.prank(proposer);
        tribute.proposeTribute{value: 1 ether}(dao, address(0), 0, address(tokenB), 100 ether);

        vm.startPrank(dao);
        tokenB.approve(address(tribute), 100 ether);
        vm.expectRevert(Tribute.TermsMismatch.selector);
        tribute.claimTribute(proposer, address(0), 999 ether, address(tokenB), 100 ether);
        vm.stopPrank();
    }

    function test_claimTribute_revert_termsMismatch_forTkn() public {
        vm.prank(proposer);
        tribute.proposeTribute{value: 1 ether}(dao, address(0), 0, address(tokenB), 100 ether);

        vm.startPrank(dao);
        vm.expectRevert(Tribute.TermsMismatch.selector);
        tribute.claimTribute(proposer, address(0), 1 ether, address(tokenA), 100 ether);
        vm.stopPrank();
    }

    function test_claimTribute_revert_termsMismatch_forAmt() public {
        vm.prank(proposer);
        tribute.proposeTribute{value: 1 ether}(dao, address(0), 0, address(tokenB), 100 ether);

        vm.startPrank(dao);
        tokenB.approve(address(tribute), 200 ether);
        vm.expectRevert(Tribute.TermsMismatch.selector);
        tribute.claimTribute(proposer, address(0), 1 ether, address(tokenB), 200 ether);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_getActiveDaoTributes() public {
        // Create multiple tributes to same DAO
        vm.startPrank(proposer);
        tribute.proposeTribute{value: 1 ether}(dao, address(0), 0, address(tokenB), 100 ether);

        tokenA.approve(address(tribute), 50 ether);
        tribute.proposeTribute(dao, address(tokenA), 50 ether, address(tokenB), 200 ether);
        vm.stopPrank();

        // Create tribute from other user
        vm.deal(otherUser, 10 ether);
        vm.prank(otherUser);
        tribute.proposeTribute{value: 2 ether}(dao, address(0), 0, address(tokenB), 150 ether);

        // Get active tributes (paginated, large limit)
        (Tribute.ActiveTributeView[] memory active, uint256 next) =
            tribute.getActiveDaoTributes(dao, 0, 100);
        assertEq(active.length, 3);
        assertEq(next, 0); // no more pages

        // Cancel one tribute
        vm.prank(proposer);
        tribute.cancelTribute(dao, address(0));

        // Should now have 2 active tributes
        (active, next) = tribute.getActiveDaoTributes(dao, 0, 100);
        assertEq(active.length, 2);
        assertEq(next, 0);
    }

    function test_getActiveDaoTributes_pagination() public {
        // Create 3 tributes from different users
        vm.prank(proposer);
        tribute.proposeTribute{value: 1 ether}(dao, address(0), 0, address(tokenB), 100 ether);

        vm.startPrank(proposer);
        tokenA.approve(address(tribute), 50 ether);
        tribute.proposeTribute(dao, address(tokenA), 50 ether, address(tokenB), 200 ether);
        vm.stopPrank();

        vm.deal(otherUser, 10 ether);
        vm.prank(otherUser);
        tribute.proposeTribute{value: 2 ether}(dao, address(0), 0, address(tokenB), 150 ether);

        // Page 1: limit 2
        (Tribute.ActiveTributeView[] memory page1, uint256 next1) =
            tribute.getActiveDaoTributes(dao, 0, 2);
        assertEq(page1.length, 2);
        assertTrue(next1 != 0); // more to scan

        // Page 2: continue from next1
        (Tribute.ActiveTributeView[] memory page2, uint256 next2) =
            tribute.getActiveDaoTributes(dao, next1, 2);
        assertEq(page2.length, 1);
        assertEq(next2, 0); // done
    }

    function test_getActiveDaoTributes_empty() public view {
        (Tribute.ActiveTributeView[] memory active, uint256 next) =
            tribute.getActiveDaoTributes(dao, 0, 100);
        assertEq(active.length, 0);
        assertEq(next, 0);
    }

    function test_getActiveDaoTributes_startOutOfBounds() public view {
        (Tribute.ActiveTributeView[] memory active, uint256 next) =
            tribute.getActiveDaoTributes(dao, 999, 10);
        assertEq(active.length, 0);
        assertEq(next, 0);
    }

    function test_getActiveProposerTributes_startOutOfBounds() public view {
        (Tribute.ActiveTributeView[] memory active, uint256 next) =
            tribute.getActiveProposerTributes(proposer, 999, 10);
        assertEq(active.length, 0);
        assertEq(next, 0);
    }

    function test_getActiveProposerTributes() public {
        address dao2 = address(0x4444);

        vm.startPrank(proposer);
        tribute.proposeTribute{value: 1 ether}(dao, address(0), 0, address(tokenB), 100 ether);
        tribute.proposeTribute{value: 2 ether}(dao2, address(0), 0, address(tokenB), 200 ether);
        vm.stopPrank();

        (Tribute.ActiveTributeView[] memory active, uint256 next) =
            tribute.getActiveProposerTributes(proposer, 0, 100);
        assertEq(active.length, 2);
        assertEq(next, 0);

        // Verify correct dao addresses in results
        assertEq(active[0].dao, dao);
        assertEq(active[1].dao, dao2);
    }

    function test_getActiveProposerTributes_pagination() public {
        address dao2 = address(0x4444);
        address dao3 = address(0x5555);

        vm.startPrank(proposer);
        tribute.proposeTribute{value: 1 ether}(dao, address(0), 0, address(tokenB), 100 ether);
        tribute.proposeTribute{value: 2 ether}(dao2, address(0), 0, address(tokenB), 200 ether);
        tribute.proposeTribute{value: 3 ether}(dao3, address(0), 0, address(tokenB), 300 ether);
        vm.stopPrank();

        // Page 1
        (Tribute.ActiveTributeView[] memory page1, uint256 next1) =
            tribute.getActiveProposerTributes(proposer, 0, 2);
        assertEq(page1.length, 2);
        assertTrue(next1 != 0);

        // Page 2
        (Tribute.ActiveTributeView[] memory page2, uint256 next2) =
            tribute.getActiveProposerTributes(proposer, next1, 2);
        assertEq(page2.length, 1);
        assertEq(next2, 0);
    }

    function test_multipleTributesToDifferentDAOs() public {
        address dao2 = address(0x4444);

        vm.startPrank(proposer);
        tribute.proposeTribute{value: 1 ether}(dao, address(0), 0, address(tokenB), 100 ether);
        tribute.proposeTribute{value: 2 ether}(dao2, address(0), 0, address(tokenB), 200 ether);
        vm.stopPrank();

        (Tribute.ActiveTributeView[] memory daoActive,) = tribute.getActiveDaoTributes(dao, 0, 100);
        (Tribute.ActiveTributeView[] memory dao2Active,) =
            tribute.getActiveDaoTributes(dao2, 0, 100);
        (Tribute.ActiveTributeView[] memory propActive,) =
            tribute.getActiveProposerTributes(proposer, 0, 100);
        assertEq(daoActive.length, 1);
        assertEq(dao2Active.length, 1);
        assertEq(propActive.length, 2);
    }
}
