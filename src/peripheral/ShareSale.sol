// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ShareSale
/// @notice Singleton for selling DAO shares or loot via the allowance system.
///         DAOs configure a sale by calling `configure()` in an initCall and granting
///         this contract an allowance via `setAllowance(ShareSale, token, cap)`.
///
///   Mint path uses Moloch's _payout sentinel addresses:
///     token = address(dao)  -> mints shares
///     token = address(1007) -> mints loot
///
///   Pricing uses 1e18 scaling: cost = amount * price / 1e18
///     e.g. price = 0.01e18 means 0.01 ETH per whole share (1e18 units)
///     Works naturally with any payToken decimals.
///
///   Setup (include in Summoner initCalls or SafeSummoner extraCalls):
///     1. dao.setAllowance(shareSale, address(dao), cap)   // or address(1007) for loot
///     2. shareSale.configure(address(dao), payToken, price) // called BY dao -> keyed to msg.sender
///
///   Usage:
///     shareSale.buy{value: cost}(dao, amount)
contract ShareSale {
    error InsufficientPayment();
    error NotConfigured();
    error ZeroAmount();
    error ZeroPrice();

    event Configured(address indexed dao, address token, address payToken, uint256 price);
    event Purchase(address indexed dao, address indexed buyer, uint256 amount, uint256 cost);

    struct Sale {
        address token; // allowance token: address(dao) for shares, address(1007) for loot
        address payToken; // address(0) = ETH
        uint256 price; // cost per whole token (1e18 units), scaled by 1e18
        // e.g. 0.01 ETH per share = 0.01e18 = 1e16
        // cost = amount * price / 1e18
    }

    /// @dev Keyed by DAO address. Set via configure() called by the DAO itself.
    mapping(address dao => Sale) public sales;

    /// @notice Configure sale parameters. Must be called by the DAO (e.g. in initCalls).
    /// @param token    Allowance token: use address(dao) for shares, address(1007) for loot
    /// @param payToken Payment token (address(0) = ETH)
    /// @param price    Price per whole token (1e18 units), e.g. 0.01e18 = 0.01 ETH/share
    function configure(address token, address payToken, uint256 price) public {
        if (price == 0) revert ZeroPrice();
        sales[msg.sender] = Sale(token, payToken, price);
        emit Configured(msg.sender, token, payToken, price);
    }

    /// @notice Buy shares or loot from a DAO.
    /// @param dao    The DAO to buy from
    /// @param amount Number of shares/loot to buy
    function buy(address dao, uint256 amount) public payable {
        if (amount == 0) revert ZeroAmount();
        Sale memory s = sales[dao];
        if (s.price == 0) revert NotConfigured();

        uint256 cost;
        unchecked {
            cost = amount * s.price / 1e18;
        }

        // Collect payment
        if (s.payToken == address(0)) {
            if (msg.value < cost) revert InsufficientPayment();
            safeTransferETH(dao, cost);
            if (msg.value > cost) {
                unchecked {
                    safeTransferETH(msg.sender, msg.value - cost);
                }
            }
        } else {
            safeTransferFrom(s.payToken, dao, cost);
        }

        // Spend allowance — _payout mints/transfers to this contract
        IMoloch(dao).spendAllowance(s.token, amount);

        // Resolve actual token contract and forward to buyer
        address tokenAddr;
        if (s.token == dao) {
            tokenAddr = address(IMoloch(dao).shares());
        } else if (s.token == address(1007)) {
            tokenAddr = address(IMoloch(dao).loot());
        } else {
            tokenAddr = s.token;
        }
        safeTransfer(tokenAddr, msg.sender, amount);

        emit Purchase(dao, msg.sender, amount, cost);
    }

    /// @notice Generate initCalls for setting up a ShareSale.
    /// @dev Returns (target, value, data) tuples for use in initCalls or extraCalls.
    ///      Call 1: dao.setAllowance(shareSale, token, cap)
    ///      Call 2: shareSale.configure(token, payToken, price)  (target = this contract)
    function saleInitCalls(address dao, address token, uint256 cap, address payToken, uint256 price)
        public
        view
        returns (address target1, bytes memory data1, address target2, bytes memory data2)
    {
        target1 = dao;
        data1 = abi.encodeCall(IMoloch.setAllowance, (address(this), token, cap));
        target2 = address(this);
        data2 = abi.encodeCall(this.configure, (token, payToken, price));
    }
}

interface IMoloch {
    function spendAllowance(address token, uint256 amount) external;
    function setAllowance(address spender, address token, uint256 amount) external;
    function shares() external view returns (address);
    function loot() external view returns (address);
}

function safeTransferETH(address to, uint256 amount) {
    assembly ("memory-safe") {
        if iszero(call(gas(), to, amount, codesize(), 0x00, codesize(), 0x00)) {
            mstore(0x00, 0xb12d13eb)
            revert(0x1c, 0x04)
        }
    }
}

function safeTransfer(address token, address to, uint256 amount) {
    assembly ("memory-safe") {
        mstore(0x14, to)
        mstore(0x34, amount)
        mstore(0x00, 0xa9059cbb000000000000000000000000)
        let success := call(gas(), token, 0, 0x10, 0x44, 0x00, 0x20)
        if iszero(and(eq(mload(0x00), 1), success)) {
            if iszero(lt(or(iszero(extcodesize(token)), returndatasize()), success)) {
                mstore(0x00, 0x90b8ec18)
                revert(0x1c, 0x04)
            }
        }
        mstore(0x34, 0)
    }
}

function safeTransferFrom(address token, address to, uint256 amount) {
    assembly ("memory-safe") {
        let m := mload(0x40)
        mstore(0x60, amount)
        mstore(0x40, to)
        mstore(0x2c, shl(96, caller()))
        mstore(0x0c, 0x23b872dd000000000000000000000000)
        let success := call(gas(), token, 0, 0x1c, 0x64, 0x00, 0x20)
        if iszero(and(eq(mload(0x00), 1), success)) {
            if iszero(lt(or(iszero(extcodesize(token)), returndatasize()), success)) {
                mstore(0x00, 0x7939f424)
                revert(0x1c, 0x04)
            }
        }
        mstore(0x60, 0)
        mstore(0x40, m)
    }
}
