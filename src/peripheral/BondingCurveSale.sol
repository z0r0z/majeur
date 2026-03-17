// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title BondingCurveSale
/// @notice Singleton for selling DAO shares or loot on a linear bonding curve.
///         Drop-in alternative to ShareSale — same allowance system, same IShareSale
///         interface for LPSeedSwapHook compatibility.
///
///   Price rises linearly from startPrice to endPrice as tokens are sold.
///   Cost for N tokens = N * averagePrice, where averagePrice is the midpoint
///   of the price at the current position and the price after buying N tokens.
///
///   The `sales()` getter returns endPrice as `price` so that LPSeedSwapHook's
///   arb protection clamp uses the highest (final) sale price for LP seeding.
///
///   Setup (via SafeSummoner extraCalls):
///     1. dao.setAllowance(bondingCurveSale, address(dao), cap)
///     2. bondingCurveSale.configure(address(dao), payToken, startPrice, endPrice, cap, deadline)
///
///   Usage:
///     bondingCurveSale.buy{value: cost}(dao, amount)
contract BondingCurveSale {
    error InsufficientPayment();
    error NotConfigured();
    error UnexpectedETH();
    error InvalidCurve();
    error ZeroAmount();
    error ZeroPrice();
    error Expired();

    event Configured(
        address indexed dao,
        address token,
        address payToken,
        uint256 startPrice,
        uint256 endPrice,
        uint256 cap,
        uint40 deadline
    );
    event Purchase(address indexed dao, address indexed buyer, uint256 amount, uint256 cost);

    struct Sale {
        address token; // allowance token: address(dao) for shares, address(1007) for loot
        address payToken; // address(0) = ETH
        uint40 deadline; // unix timestamp after which buys revert (0 = no deadline)
        uint256 price; // endPrice — for IShareSale compatibility (LPSeedSwapHook reads this)
        uint256 startPrice; // price at 0% sold
        uint256 cap; // total tokens for sale (should match allowance)
    }

    /// @dev Keyed by DAO address. Set via configure() called by the DAO itself.
    mapping(address dao => Sale) public sales;

    constructor() payable {}

    /// @notice Configure bonding curve sale parameters. Must be called by the DAO.
    /// @param token      Allowance token: use address(dao) for shares, address(1007) for loot
    /// @param payToken   Payment token (address(0) = ETH)
    /// @param startPrice Price at 0% sold (1e18 scaled), must be > 0
    /// @param endPrice   Price at 100% sold (1e18 scaled), must be >= startPrice
    /// @param cap        Total tokens for sale (should match the allowance granted)
    /// @param deadline   Unix timestamp after which buys revert (0 = no deadline)
    function configure(
        address token,
        address payToken,
        uint256 startPrice,
        uint256 endPrice,
        uint256 cap,
        uint40 deadline
    ) public {
        if (startPrice == 0) revert ZeroPrice();
        if (endPrice < startPrice) revert InvalidCurve();
        if (cap == 0) revert ZeroAmount();
        sales[msg.sender] = Sale(token, payToken, deadline, endPrice, startPrice, cap);
        emit Configured(msg.sender, token, payToken, startPrice, endPrice, cap, deadline);
    }

    /// @notice Compute the cost for buying `amount` tokens from `dao` at current curve position.
    /// @return cost The payment required (in payToken units or wei)
    function quote(address dao, uint256 amount) public view returns (uint256 cost) {
        Sale memory s = sales[dao];
        if (s.price == 0) revert NotConfigured();
        uint256 remaining = IMoloch(dao).allowance(s.token, address(this));
        if (amount > remaining) amount = remaining;
        if (amount == 0) revert ZeroAmount();
        cost = _cost(s, s.cap - remaining, amount);
    }

    /// @notice Buy shares or loot from a DAO on the bonding curve (exact-out).
    ///         Caps to remaining allowance if amount exceeds it.
    ///         Refunds excess ETH for ETH-priced sales.
    /// @param dao    The DAO to buy from
    /// @param amount Max shares/loot to buy (capped to remaining)
    function buy(address dao, uint256 amount) public payable {
        if (amount == 0) revert ZeroAmount();
        Sale memory s = sales[dao];
        if (s.price == 0) revert NotConfigured();
        if (s.deadline != 0 && block.timestamp > s.deadline) revert Expired();

        // Cap to remaining allowance
        uint256 remaining = IMoloch(dao).allowance(s.token, address(this));
        if (amount > remaining) amount = remaining;
        if (amount == 0) revert ZeroAmount();

        uint256 sold = s.cap - remaining;
        uint256 cost = _cost(s, sold, amount);

        // Spend allowance first (CEI: effects before interactions)
        IMoloch(dao).spendAllowance(s.token, amount);

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
            if (msg.value != 0) revert UnexpectedETH();
            safeTransferFrom(s.payToken, dao, cost);
        }

        safeTransfer(_resolveToken(dao, s.token), msg.sender, amount);

        emit Purchase(dao, msg.sender, amount, cost);
    }

    /// @notice Buy shares or loot with exact ETH input on the bonding curve.
    ///         Computes max amount from msg.value via quadratic formula, caps to remaining, refunds excess.
    /// @param dao The DAO to buy from
    function buyExactIn(address dao) public payable {
        Sale memory s = sales[dao];
        if (s.price == 0) revert NotConfigured();
        if (s.payToken != address(0)) revert UnexpectedETH();
        if (s.deadline != 0 && block.timestamp > s.deadline) revert Expired();
        if (msg.value == 0) revert ZeroAmount();

        uint256 remaining = IMoloch(dao).allowance(s.token, address(this));
        uint256 sold = s.cap - remaining;

        // Compute max amount affordable from msg.value on the curve.
        // Solve: slope*amount² + (2*cap*startPrice + 2*slope*sold)*amount = 2*cap*1e18*msg.value
        // Quadratic: amount = (-b + sqrt(b² + 4ac)) / (2a)
        // where a = slope, b = 2*cap*startPrice + 2*slope*sold, c = 2*cap*1e18*msg.value
        // When slope == 0 (flat): amount = msg.value * 1e18 / startPrice
        //
        // To avoid overflow in b² and 4ac, divide all terms by a common scale factor.
        // Divide quadratic by (2*cap): amount² * slope/(2*cap) + amount * (startPrice + slope*sold/cap) = 1e18*msg.value
        // Let a' = slope, b' = 2*cap*startPrice + 2*slope*sold, scale = 2*cap
        // amount = (-b' + sqrt(b'² + 4*a'*scale*1e18*msg.value)) / (2*a')
        // Rewrite to avoid b'²: scale everything by 1/scale²
        // amount = scale * (-b'/scale + sqrt((b'/scale)² + 4*a'*1e18*msg.value/scale)) / (2*a')
        uint256 amount;
        uint256 slope = s.price - s.startPrice;
        if (slope == 0) {
            amount = msg.value * 1e18 / s.startPrice;
        } else {
            // Scale down by dividing by 2*cap to prevent overflow
            // b_s = b / (2*cap) = startPrice + slope * sold / cap
            uint256 b_s = s.startPrice + slope * sold / s.cap;
            // disc_s = b_s² + 4 * slope * 1e18 * msg.value / (2*cap)
            //        = b_s² + 2 * slope * 1e18 * msg.value / cap
            uint256 disc_s = b_s * b_s + 2 * slope * msg.value * 1e18 / s.cap;
            // amount = (sqrt(disc_s) - b_s) * (2*cap) / (2*slope)
            //        = (sqrt(disc_s) - b_s) * cap / slope
            uint256 sqrtDisc = sqrt(disc_s);
            amount = sqrtDisc > b_s ? (sqrtDisc - b_s) * s.cap / slope : 0;
        }

        // Cap to remaining allowance
        if (amount > remaining) amount = remaining;
        if (amount == 0) revert ZeroAmount();

        uint256 cost = _cost(s, sold, amount);
        // Clamp: sqrt truncation + ceil in _cost can overshoot by 1 wei
        if (cost > msg.value) cost = msg.value;

        // Spend allowance first (CEI: effects before interactions)
        IMoloch(dao).spendAllowance(s.token, amount);

        safeTransferETH(dao, cost);
        if (msg.value > cost) {
            unchecked {
                safeTransferETH(msg.sender, msg.value - cost);
            }
        }

        safeTransfer(_resolveToken(dao, s.token), msg.sender, amount);

        emit Purchase(dao, msg.sender, amount, cost);
    }

    /// @notice Generate initCalls for setting up a BondingCurveSale.
    /// @dev Returns (target, data) pairs for use in initCalls or extraCalls.
    function saleInitCalls(
        address dao,
        address token,
        uint256 cap,
        address payToken,
        uint256 startPrice,
        uint256 endPrice,
        uint40 deadline
    )
        public
        view
        returns (address target1, bytes memory data1, address target2, bytes memory data2)
    {
        target1 = dao;
        data1 = abi.encodeCall(IMoloch.setAllowance, (address(this), token, cap));
        target2 = address(this);
        data2 =
            abi.encodeCall(this.configure, (token, payToken, startPrice, endPrice, cap, deadline));
    }

    /// @dev Resolve allowance token sentinel to actual ERC20 address.
    function _resolveToken(address dao, address token) internal view returns (address) {
        if (token == dao) return address(IMoloch(dao).shares());
        if (token == address(1007)) return address(IMoloch(dao).loot());
        return token;
    }

    /// @dev Compute cost for `amount` tokens starting at position `sold` on the curve.
    ///      Linear curve: price(x) = startPrice + (endPrice - startPrice) * x / cap
    ///      Cost = amount * avgPrice / 1e18, where avgPrice = (price(sold) + price(sold+amount)) / 2
    ///      Rounded up to prevent dust.
    function _cost(Sale memory s, uint256 sold, uint256 amount) internal pure returns (uint256) {
        // avgPrice = startPrice + slope * (2*sold + amount) / 2
        // where slope = (endPrice - startPrice) / cap
        // = startPrice + (endPrice - startPrice) * (2*sold + amount) / (2*cap)
        //
        // cost = amount * avgPrice / 1e18 (rounded up)
        // = amount * (startPrice + (endPrice - startPrice) * (2*sold + amount) / (2*cap)) / 1e18
        // = (amount * (2*cap*startPrice + (endPrice - startPrice) * (2*sold + amount)) + 2*cap*1e18 - 1) / (2*cap*1e18)
        uint256 slope = s.price - s.startPrice; // endPrice - startPrice
        uint256 twoCap = 2 * s.cap;
        uint256 numerator = amount * (twoCap * s.startPrice + slope * (2 * sold + amount));
        uint256 denominator = twoCap * 1e18;
        return (numerator + denominator - 1) / denominator; // round up
    }
}

interface IMoloch {
    function spendAllowance(address token, uint256 amount) external;
    function setAllowance(address spender, address token, uint256 amount) external;
    function allowance(address token, address spender) external view returns (uint256);
    function shares() external view returns (address);
    function loot() external view returns (address);
}

function sqrt(uint256 x) pure returns (uint256 z) {
    assembly ("memory-safe") {
        z := 181

        let r := shl(7, lt(0xffffffffffffffffffffffffffffffffff, x))
        r := or(r, shl(6, lt(0xffffffffffffffffff, shr(r, x))))
        r := or(r, shl(5, lt(0xffffffffff, shr(r, x))))
        r := or(r, shl(4, lt(0xffffff, shr(r, x))))
        z := shl(shr(1, r), z)

        z := shr(18, mul(z, add(shr(r, x), 65536)))

        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))

        z := sub(z, lt(div(x, z), z))
    }
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
