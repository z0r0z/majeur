// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// Minimal interface for the Moloch reference in Loot.name() / Loot.symbol()
interface IMolochView {
    function name(uint256 id) external view returns (string memory);
    function symbol(uint256 id) external view returns (string memory);
}

// Global errors used by Loot
error Locked();
error Unauthorized();

contract LootHarness {
    /* ERC20 */
    event Approval(address indexed from, address indexed to, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount);

    uint8 public constant decimals = 18;

    bool public transfersLocked;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    /* MAJEUR */
    address payable public DAO;

    modifier onlyDAO() {
        require(msg.sender == DAO, Unauthorized());
        _;
    }

    constructor() payable {}

    function init() public payable {
        require(DAO == address(0), Unauthorized());
        DAO = payable(msg.sender);
    }

    function name() public view returns (string memory) {
        return string.concat(IMolochView(DAO).name(0), " Loot");
    }

    function symbol() public view returns (string memory) {
        return IMolochView(DAO).symbol(0);
    }

    function approve(address to, uint256 amount) public returns (bool) {
        allowance[msg.sender][to] = amount;
        emit Approval(msg.sender, to, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        _checkUnlocked(msg.sender, to);
        _moveTokens(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        _checkUnlocked(from, to);

        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        _moveTokens(from, to, amount);
        return true;
    }

    function setTransfersLocked(bool locked) public payable onlyDAO {
        transfersLocked = locked;
    }

    function mintFromMoloch(address to, uint256 amount) public payable onlyDAO {
        _mint(to, amount);
    }

    function burnFromMoloch(address from, uint256 amount) public payable onlyDAO {
        balanceOf[from] -= amount;
        unchecked {
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        unchecked {
            balanceOf[to] += amount;
        }
        emit Transfer(address(0), to, amount);
    }

    function _moveTokens(address from, address to, uint256 amount) internal {
        balanceOf[from] -= amount;
        unchecked {
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
    }

    function _checkUnlocked(address from, address to) internal view {
        if (transfersLocked && from != DAO && to != DAO) {
            revert Locked();
        }
    }
}
