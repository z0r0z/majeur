// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title BondingCurveSale
/// @notice Singleton for selling DAO shares or loot on a bonding curve.
///         Drop-in alternative to ShareSale — same allowance system, same IShareSale
///         interface for LPSeedSwapHook compatibility.
///
///   Three curve shapes are supported:
///     LINEAR    — price(x) = P₀ + slope · x/cap              (default)
///     QUADRATIC — price(x) = P₀ + slope · (x/cap)²           (steeper late-stage)
///     XYK       — price(x) = P₀ · T₀²/(T₀ − x)²            (virtual constant-product, pump.fun-style)
///
///   where P₀ = startPrice, slope = endPrice − startPrice, x = tokens already sold,
///   and T₀ = virtual token reserve computed so that price(cap) = endPrice.
///   Cost for N tokens is the integral of price(x) over [sold, sold+N], scaled by 1e18.
///
///   The `sales()` getter returns endPrice as `price` so that LPSeedSwapHook's
///   arb protection clamp uses the highest (final) sale price for LP seeding.
///
///   Setup (via SafeSummoner extraCalls):
///     1. dao.setAllowance(bondingCurveSale, address(dao), cap)
///     2. bondingCurveSale.configure(address(dao), payToken, startPrice, endPrice, cap, deadline, curveType)
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

    enum CurveType {
        LINEAR, // price(x) = P₀ + slope · x/cap
        QUADRATIC, // price(x) = P₀ + slope · (x/cap)²
        XYK // price(x) = P₀ · T₀²/(T₀ − x)²  (virtual constant-product)
    }

    event Configured(
        address indexed dao,
        address token,
        address payToken,
        uint256 startPrice,
        uint256 endPrice,
        uint256 cap,
        uint40 deadline,
        CurveType curveType
    );
    event Purchase(address indexed dao, address indexed buyer, uint256 amount, uint256 cost);

    struct Sale {
        address token; // allowance token: address(dao) for shares, address(1007) for loot
        address payToken; // address(0) = ETH
        uint40 deadline; // unix timestamp after which buys revert (0 = no deadline)
        uint256 price; // endPrice — for IShareSale compatibility (LPSeedSwapHook reads this)
        uint256 startPrice; // price at 0% sold
        uint256 cap; // total tokens for sale (should match allowance)
        CurveType curveType; // curve shape (LINEAR, QUADRATIC, XYK)
        uint256 virtualReserve; // T₀ for XYK curve (0 for LINEAR/QUADRATIC)
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
    /// @param curveType  Curve shape: LINEAR (0), QUADRATIC (1), or XYK (2)
    function configure(
        address token,
        address payToken,
        uint256 startPrice,
        uint256 endPrice,
        uint256 cap,
        uint40 deadline,
        CurveType curveType
    ) public {
        if (startPrice == 0) revert ZeroPrice();
        if (endPrice < startPrice) revert InvalidCurve();
        if (cap == 0) revert ZeroAmount();

        uint256 vr;
        if (curveType == CurveType.XYK && endPrice > startPrice) {
            // T₀ = cap · √endPrice / (√endPrice − √startPrice)
            // so that price(0) = startPrice and price(cap) = endPrice on the 1/(T₀−x)² curve.
            uint256 sqrtEnd = sqrt(endPrice);
            uint256 sqrtStart = sqrt(startPrice);
            vr = cap * sqrtEnd / (sqrtEnd - sqrtStart);
        }

        sales[msg.sender] =
            Sale(token, payToken, deadline, endPrice, startPrice, cap, curveType, vr);
        emit Configured(msg.sender, token, payToken, startPrice, endPrice, cap, deadline, curveType);
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
    ///         Computes max amount from msg.value, caps to remaining, refunds excess.
    /// @param dao The DAO to buy from
    function buyExactIn(address dao) public payable {
        Sale memory s = sales[dao];
        if (s.price == 0) revert NotConfigured();
        if (s.payToken != address(0)) revert UnexpectedETH();
        if (s.deadline != 0 && block.timestamp > s.deadline) revert Expired();
        if (msg.value == 0) revert ZeroAmount();

        uint256 remaining = IMoloch(dao).allowance(s.token, address(this));
        uint256 sold = s.cap - remaining;

        uint256 amount;
        uint256 slope = s.price - s.startPrice;

        if (slope == 0) {
            // Flat curve (all types degenerate): amount = msg.value * 1e18 / price
            amount = msg.value * 1e18 / s.startPrice;
        } else if (s.curveType == CurveType.LINEAR) {
            // Analytical solution via quadratic formula (existing logic).
            // Solve: slope·a² + (2·cap·P₀ + 2·slope·sold)·a = 2·cap·1e18·msg.value
            uint256 b_s = s.startPrice + slope * sold / s.cap;
            uint256 disc_s = b_s * b_s + 2 * slope * msg.value * 1e18 / s.cap;
            uint256 sqrtDisc = sqrt(disc_s);
            amount = sqrtDisc > b_s ? (sqrtDisc - b_s) * s.cap / slope : 0;
        } else if (s.curveType == CurveType.XYK) {
            // Analytical: amount = msg.value · R / (A + msg.value)
            // where R = T₀ − sold, A = startPrice · T₀² / (R · 1e18)
            uint256 T0 = s.virtualReserve;
            uint256 R = T0 - sold;
            uint256 A = s.startPrice * T0 * T0 / R / 1e18;
            amount = msg.value * R / (A + msg.value);
        } else {
            // QUADRATIC: binary search for max amount where _cost ≤ msg.value
            uint256 lo = 0;
            uint256 hi = remaining;
            while (lo < hi) {
                uint256 mid = (lo + hi + 1) / 2;
                if (_cost(s, sold, mid) <= msg.value) {
                    lo = mid;
                } else {
                    hi = mid - 1;
                }
            }
            amount = lo;
        }

        // Cap to remaining allowance
        if (amount > remaining) amount = remaining;
        if (amount == 0) revert ZeroAmount();

        uint256 cost = _cost(s, sold, amount);
        // Clamp: sqrt truncation / binary search rounding + ceil in _cost can overshoot
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
        uint40 deadline,
        CurveType curveType
    )
        public
        view
        returns (address target1, bytes memory data1, address target2, bytes memory data2)
    {
        target1 = dao;
        data1 = abi.encodeCall(IMoloch.setAllowance, (address(this), token, cap));
        target2 = address(this);
        data2 = abi.encodeCall(
            this.configure, (token, payToken, startPrice, endPrice, cap, deadline, curveType)
        );
    }

    /// @dev Resolve allowance token sentinel to actual ERC20 address.
    function _resolveToken(address dao, address token) internal view returns (address) {
        if (token == dao) return address(IMoloch(dao).shares());
        if (token == address(1007)) return address(IMoloch(dao).loot());
        return token;
    }

    /// @dev Compute cost for `amount` tokens starting at position `sold` on the curve.
    ///      Rounded up to prevent dust purchases.
    function _cost(Sale memory s, uint256 sold, uint256 amount) internal pure returns (uint256) {
        uint256 slope = s.price - s.startPrice; // endPrice - startPrice

        // Flat curve shortcut (works for all curve types when startPrice == endPrice)
        if (slope == 0) {
            return (amount * s.startPrice + 1e18 - 1) / 1e18;
        }

        if (s.curveType == CurveType.QUADRATIC) {
            // price(x) = P₀ + slope · (x/cap)²
            // integral from sold to sold+amount = amount·P₀ + slope·(3s²a + 3sa² + a³)/(3·cap²)
            // where s=sold, a=amount.  Factor out amount:
            // = amount · (P₀ + slope·(3s² + 3sa + a²)/(3·cap²))
            // Split division to avoid overflow: slope·term / (3·cap) / cap
            uint256 term = 3 * sold * sold + 3 * sold * amount + amount * amount;
            uint256 avgCurvePremium = slope * term / (3 * s.cap) / s.cap;
            uint256 avgPrice = s.startPrice + avgCurvePremium;
            return (amount * avgPrice + 1e18 - 1) / 1e18;
        }

        if (s.curveType == CurveType.XYK) {
            // price(x) = P₀ · T₀²/(T₀ − x)² where T₀ = virtualReserve
            // integral = P₀ · T₀² · [1/(T₀−b) − 1/(T₀−a)] where a=sold, b=sold+amount
            //          = P₀ · T₀² · amount / (rem · remAfter)
            // cost_wei = integral / 1e18, rounded up
            uint256 T0 = s.virtualReserve;
            uint256 rem = T0 - sold;
            uint256 remAfter = rem - amount;
            // Compute: startPrice · T₀ · amount / rem, then · T₀ / (remAfter · 1e18)
            uint256 step = s.startPrice * amount * T0 / rem;
            uint256 denom = remAfter * 1e18;
            return (step * T0 + denom - 1) / denom;
        }

        // LINEAR: price(x) = P₀ + slope · x/cap
        // avgPrice = P₀ + slope·(2·sold + amount)/(2·cap)
        // cost = amount · avgPrice / 1e18, rounded up
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
