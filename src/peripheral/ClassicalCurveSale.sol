// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ClassicalCurveSale
/// @notice Pump.fun-style bonding curve with virtual constant-product (XYK) pricing.
///         Holds tokens and ETH. Supports buying and selling. Graduates to ZAMM LP
///         when a configurable ETH target is reached (or all tokens sold).
///
///   Curve: price(x) = P₀ · T₀²/(T₀ − x)²
///   where P₀ = startPrice, T₀ = virtual token reserve, x = tokens sold.
///   Cost/proceeds for N tokens is the integral: P₀ · T₀² · N / ((T₀−x)(T₀−x−N))
///
///   Lifecycle:
///     1. Creator calls launch() (deploys ERC20 clone + configures curve atomically)
///        — or deploys token separately, approves this contract, calls configure()
///     2. Users buy() / sell() on the curve (fee charged both directions)
///     3. When raisedETH >= graduationTarget (or cap fully sold), trading freezes
///     4. Anyone calls graduate() — seeds ZAMM LP with this contract as hook
///
///   Post-graduation this contract acts as a ZAMM hook for the graduated pool:
///     - Returns pool swap fee via beforeAction()
///     - Enforces routed swaps when creator fee is active (swapExactIn/swapExactOut)
///     - Creator can configure revenue fees on swaps via setCreatorFee()
///
///   Keyed by token address — one curve per token, but creators can launch many tokens.
contract ClassicalCurveSale {
    error Slippage();
    error Graduated();
    error ZeroAmount();
    error NotGraduable();
    error Unauthorized();
    error InvalidParams();
    error NotConfigured();
    error AlreadyConfigured();
    error InsufficientPayment();
    error InsufficientLiquidity();

    event TokenCreated(address indexed creator, address indexed token);
    event Configured(
        address indexed creator,
        address indexed token,
        uint256 cap,
        uint256 startPrice,
        uint256 endPrice,
        uint256 graduationTarget,
        uint256 lpTokens
    );
    event Purchase(address indexed token, address indexed buyer, uint256 amount, uint256 cost);
    event Sold(address indexed token, address indexed seller, uint256 amount, uint256 proceeds);
    event GraduationComplete(
        address indexed token, uint256 ethSeeded, uint256 tokensSeeded, uint256 liquidity
    );
    event CreatorUpdated(address indexed token, address indexed newCreator);
    event LpRecipientUpdated(address indexed token, address indexed newRecipient);
    event CreatorFeeUpdated(
        address indexed token, address beneficiary, uint16 buyBps, uint16 sellBps
    );
    event VestingClaimed(address indexed token, address indexed creator, uint256 amount);

    /// @dev Packed into 6 storage slots (down from 11) for gas-efficient trades.
    ///      Hot-path fields share slots to minimise cold SLOADs (~10k gas saved per trade).
    struct CurveConfig {
        // slot 0 (26 bytes): auth + flags — read first on every trade
        address creator; // 20 B — who configured this sale
        uint16 feeBps; //  2 B — bonding curve trading fee (bps)
        uint16 poolFeeBps; //  2 B — ZAMM pool swap fee post-graduation
        bool graduated; //  1 B — trading frozen, ready for graduate()
        bool seeded; //  1 B — LP has been seeded via graduate()
        // slot 1 (32 bytes): supply counters — read + written every trade
        uint128 cap; // 16 B — tokens available on the curve
        uint128 sold; // 16 B — tokens currently outstanding
        // slot 2 (32 bytes): pricing — read every trade (1 cold SLOAD for both)
        uint128 startPrice; // 16 B — P₀ (price at x=0), 1e18 scaled
        uint128 endPrice; // 16 B — price at x=cap, 1e18 scaled
        // slot 3 (32 bytes): ETH accounting — read + written every trade
        uint128 raisedETH; // 16 B — net ETH held from buys minus sells
        uint128 graduationTarget; // 16 B — ETH threshold for graduation (0 = sell full cap)
        // slot 4 (32 bytes): curve shape + LP reserve — read on non-flat trades / graduation
        uint128 virtualReserve; // 16 B — T₀ for XYK pricing
        uint128 lpTokens; // 16 B — tokens reserved for LP pairing
        // slot 5 (20 bytes): LP config — only read on graduation
        address lpRecipient; // 20 B — who receives LP tokens (address(0) = burn)
    }

    /// @notice Creator fee config for post-graduation routed swaps.
    ///         When beneficiary != address(0), swaps must route through this contract.
    struct CreatorFee {
        address beneficiary; // fee recipient (address(0) = disabled, direct ZAMM swaps allowed)
        uint16 buyBps; // fee bps when buying token (ETH → token)
        uint16 sellBps; // fee bps when selling token (token → ETH)
        bool buyOnInput; // true = buy fee from ETH input, false = from token output
        bool sellOnInput; // true = sell fee from token input, false = from ETH output
    }

    /// @notice Creator token vesting (optional cliff + linear unlock).
    ///         cliff only (duration=0): all tokens unlock at start+cliff
    ///         cliff + duration: nothing until cliff, then linear over duration
    ///         duration only (cliff=0): linear from launch over duration
    struct CreatorVest {
        uint128 total; // total tokens allocated
        uint128 claimed; // tokens already claimed
        uint40 start; // vesting start timestamp (set at launch)
        uint40 cliff; // seconds before any tokens vest (0 = no cliff)
        uint40 duration; // linear vesting period after cliff (0 = all at cliff)
    }

    /// @dev Keyed by token address. One curve per token.
    mapping(address token => CurveConfig) internal _curves;

    /// @notice Creator fee config per token.
    mapping(address token => CreatorFee) public creatorFees;

    /// @dev Reverse lookup: ZAMM poolId → token. Set during graduate().
    mapping(uint256 poolId => address token) public poolToken;

    /// @notice Creator vesting schedule per token.
    mapping(address token => CreatorVest) public creatorVests;

    /// @notice Packed trade observations for charting (1 slot per trade).
    ///         Bits: [price:128][volume:80][timestamp:40][flags:8]
    ///         price     = avg execution price (1e18 scaled, cost·1e18/amount)
    ///         volume    = ETH cost/proceeds in wei (max ~1.2M ETH per trade)
    ///         timestamp = block.timestamp
    ///         flags     = 0x01 = sell
    mapping(address token => uint256[]) internal _observations;

    /// @dev Hook encoding flag — only beforeAction is used.
    uint256 constant FLAG_BEFORE = 1 << 255;

    /// @dev Default pool swap fee when none configured (25 bps = 0.25%).
    uint16 constant DEFAULT_POOL_FEE = 25;

    /// @dev Maximum creator fee per direction (10%).
    uint16 constant MAX_CREATOR_FEE_BPS = 1000;

    /// @dev Transient storage slot for seeding bypass in beforeAction.
    uint256 constant SEEDING_SLOT = 0x436c617373696353616c6553656564;

    /// @dev Transient storage slot for swap reentrancy lock.
    uint256 constant SWAP_LOCK_SLOT = 0x436c617373696353616c654c6f636b;

    ERC20 public immutable tokenImplementation;

    constructor() payable {
        tokenImplementation = new ERC20{salt: bytes32(0)}();
    }

    // ── Configuration ────────────────────────────────────────────

    /// @notice Deploy a new ERC20 clone and configure a bonding curve in one call.
    ///         Mints supply to this contract — cap + lpTokens for the curve, excess to creator.
    /// @param name             Token name
    /// @param symbol           Token symbol
    /// @param uri              Token contract URI (metadata)
    /// @param supply           Total supply to mint (must be >= cap + lpTokens)
    /// @param salt             Salt for deterministic create2 deployment
    /// @param cap              Tokens available on the curve
    /// @param startPrice       Price at 0% sold (1e18 scaled), must be > 0
    /// @param endPrice         Price at 100% sold (1e18 scaled), must be >= startPrice
    /// @param feeBps           Bonding curve trading fee in basis points (max 10_000)
    /// @param graduationTarget ETH threshold to trigger graduation (0 = sell full cap)
    /// @param lpTokens         Tokens to reserve for LP (pulled alongside cap)
    /// @param lpRecipient      Who receives LP tokens on graduation (address(0) = burn)
    /// @param poolFeeBps       ZAMM pool swap fee post-graduation (0 = default 25 bps)
    /// @param vestCliff        Cliff before any creator tokens vest in seconds (0 = no cliff)
    /// @param vestDuration     Linear vesting period after cliff in seconds (0 = all at cliff)
    function launch(
        address creator,
        string calldata name,
        string calldata symbol,
        string calldata uri,
        uint256 supply,
        bytes32 salt,
        uint256 cap,
        uint256 startPrice,
        uint256 endPrice,
        uint16 feeBps,
        uint256 graduationTarget,
        uint256 lpTokens,
        address lpRecipient,
        uint16 poolFeeBps,
        CreatorFee calldata creatorFee,
        uint40 vestCliff,
        uint40 vestDuration
    ) public returns (address token) {
        uint256 needed = cap + lpTokens;
        if (supply < needed) revert InvalidParams();

        // Deploy ERC20 clone via PUSH0 create2
        bytes32 _salt = keccak256(abi.encode(msg.sender, name, symbol, salt));
        ERC20 impl = tokenImplementation;
        assembly ("memory-safe") {
            mstore(0x24, 0x5af43d5f5f3e6029573d5ffd5b3d5ff3)
            mstore(0x14, impl)
            mstore(0x00, 0x602d5f8160095f39f35f5f365f5f37365f73)
            token := create2(0, 0x0e, 0x36, _salt)
            if iszero(token) {
                mstore(0x00, 0x30116425) // DeployFailed()
                revert(0x1c, 0x04)
            }
            mstore(0x24, 0)
        }

        // Mint supply to this contract
        ERC20(token).init(name, symbol, uri, supply, address(this));
        emit TokenCreated(msg.sender, token);

        // Creator allocation: vest or send immediately
        uint256 excess = supply - needed;
        if (excess != 0) {
            if (vestCliff != 0 || vestDuration != 0) {
                if (excess > type(uint128).max) revert InvalidParams();
                creatorVests[token] = CreatorVest({
                    total: uint128(excess),
                    claimed: 0,
                    start: uint40(block.timestamp),
                    cliff: vestCliff,
                    duration: vestDuration
                });
            } else {
                safeTransfer(token, creator, excess);
            }
        }

        // Configure curve (tokens already held, no transferFrom)
        _configure(
            creator,
            token,
            cap,
            startPrice,
            endPrice,
            feeBps,
            graduationTarget,
            lpTokens,
            lpRecipient,
            poolFeeBps,
            creatorFee
        );
    }

    /// @notice Configure a new bonding curve sale. Pulls cap + lpTokens from msg.sender.
    /// @dev    Only use with standard ERC20 tokens. Fee-on-transfer, rebasing, or callback-enabled
    ///         tokens (ERC777, etc.) may cause accounting mismatches or reentrancy issues.
    /// @param creator          Who controls this curve (receives fees, unsold tokens, governance)
    /// @param token            ERC20 to sell (must have approved this contract for cap + lpTokens)
    /// @param cap              Tokens available on the curve
    /// @param startPrice       Price at 0% sold (1e18 scaled), must be > 0
    /// @param endPrice         Price at 100% sold (1e18 scaled), must be >= startPrice
    /// @param feeBps           Bonding curve trading fee in basis points (max 10_000)
    /// @param graduationTarget ETH threshold to trigger graduation (0 = sell full cap)
    /// @param lpTokens         Tokens to reserve for LP (pulled alongside cap)
    /// @param lpRecipient      Who receives LP tokens on graduation (address(0) = burn)
    /// @param poolFeeBps       ZAMM pool swap fee post-graduation (0 = default 25 bps)
    function configure(
        address creator,
        address token,
        uint256 cap,
        uint256 startPrice,
        uint256 endPrice,
        uint16 feeBps,
        uint256 graduationTarget,
        uint256 lpTokens,
        address lpRecipient,
        uint16 poolFeeBps,
        CreatorFee calldata creatorFee
    ) public {
        if (token == address(0)) revert InvalidParams();

        _configure(
            creator,
            token,
            cap,
            startPrice,
            endPrice,
            feeBps,
            graduationTarget,
            lpTokens,
            lpRecipient,
            poolFeeBps,
            creatorFee
        );

        // Pull tokens from caller (cap for curve + lpTokens for LP reserve)
        safeTransferFrom(token, address(this), cap + lpTokens);
    }

    function _configure(
        address creator,
        address token,
        uint256 cap,
        uint256 startPrice,
        uint256 endPrice,
        uint16 feeBps,
        uint256 graduationTarget,
        uint256 lpTokens,
        address lpRecipient,
        uint16 poolFeeBps,
        CreatorFee calldata creatorFee
    ) internal {
        if (creator == address(0)) revert InvalidParams();
        if (cap == 0 || startPrice == 0) revert InvalidParams();
        if (endPrice < startPrice) revert InvalidParams();
        if (feeBps > 10_000 || poolFeeBps > 10_000) revert InvalidParams();
        if (_curves[token].creator != address(0)) revert AlreadyConfigured();

        // Compute virtual reserve T₀ so that price(0) = startPrice, price(cap) = endPrice
        uint256 vr;
        if (endPrice > startPrice) {
            // T₀ = cap · √endPrice / (√endPrice − √startPrice)
            uint256 sqrtEnd = sqrt(endPrice);
            uint256 sqrtStart = sqrt(startPrice);
            vr = cap * sqrtEnd / (sqrtEnd - sqrtStart);
        } else {
            // Flat price: T₀ doesn't matter, but set to 2·cap to avoid division issues
            vr = cap * 2;
        }
        if (vr > type(uint128).max) revert InvalidParams();
        if (cap > type(uint128).max) revert InvalidParams();
        if (startPrice > type(uint128).max) revert InvalidParams();
        if (endPrice > type(uint128).max) revert InvalidParams();
        if (lpTokens > type(uint128).max) revert InvalidParams();
        if (graduationTarget > type(uint128).max) revert InvalidParams();

        // Validate graduation target is achievable from full cap sale
        if (graduationTarget != 0) {
            uint256 maxETH;
            if (endPrice == startPrice) {
                maxETH = (cap * startPrice + 1e18 - 1) / 1e18;
            } else {
                uint256 remAfter = vr - cap;
                maxETH = mulDivUp(startPrice * cap, vr, remAfter * 1e18);
            }
            if (graduationTarget > maxETH) revert InvalidParams();
        }

        _curves[token] = CurveConfig({
            creator: creator,
            feeBps: feeBps,
            poolFeeBps: poolFeeBps,
            graduated: false,
            seeded: false,
            cap: uint128(cap),
            sold: 0,
            startPrice: uint128(startPrice),
            endPrice: uint128(endPrice),
            raisedETH: 0,
            graduationTarget: uint128(graduationTarget),
            virtualReserve: uint128(vr),
            lpTokens: uint128(lpTokens),
            lpRecipient: lpRecipient
        });

        // Set creator fee if provided
        if (creatorFee.beneficiary != address(0) || (creatorFee.buyBps | creatorFee.sellBps) != 0) {
            if (creatorFee.buyBps > MAX_CREATOR_FEE_BPS || creatorFee.sellBps > MAX_CREATOR_FEE_BPS)
            {
                revert InvalidParams();
            }
            if (
                creatorFee.beneficiary == address(0)
                    && (creatorFee.buyBps | creatorFee.sellBps) != 0
            ) {
                revert InvalidParams();
            }
            if (
                creatorFee.beneficiary != address(0)
                    && (creatorFee.buyBps | creatorFee.sellBps) == 0
            ) {
                revert InvalidParams();
            }
            creatorFees[token] = creatorFee;
            emit CreatorFeeUpdated(
                token, creatorFee.beneficiary, creatorFee.buyBps, creatorFee.sellBps
            );
        }

        emit Configured(creator, token, cap, startPrice, endPrice, graduationTarget, lpTokens);
    }

    // ── Views ────────────────────────────────────────────────────

    /// @notice Read curve state.
    function curves(address token)
        public
        view
        returns (
            address creator,
            uint256 cap,
            uint256 sold,
            uint256 virtualReserve,
            uint256 startPrice,
            uint256 endPrice,
            uint16 feeBps,
            uint16 poolFeeBps,
            uint256 raisedETH,
            uint256 graduationTarget,
            uint256 lpTokens,
            address lpRecipient,
            bool graduated,
            bool seeded
        )
    {
        CurveConfig storage c = _curves[token];
        return (
            c.creator,
            c.cap,
            c.sold,
            c.virtualReserve,
            c.startPrice,
            c.endPrice,
            c.feeBps,
            c.poolFeeBps,
            c.raisedETH,
            c.graduationTarget,
            c.lpTokens,
            c.lpRecipient,
            c.graduated,
            c.seeded
        );
    }

    /// @notice Compute the cost for buying `amount` tokens (before fee).
    function quote(address token, uint256 amount) public view returns (uint256 cost) {
        CurveConfig storage c = _curves[token];
        if (c.creator == address(0)) revert NotConfigured();
        uint256 sold = c.sold;
        uint256 remaining = c.cap - sold;
        if (amount > remaining) amount = remaining;
        if (amount == 0) revert ZeroAmount();
        cost = _cost(c.startPrice, c.endPrice, c.virtualReserve, sold, amount);
    }

    /// @notice Compute the proceeds for selling `amount` tokens (before fee).
    function quoteSell(address token, uint256 amount) public view returns (uint256 proceeds) {
        CurveConfig storage c = _curves[token];
        if (c.creator == address(0)) revert NotConfigured();
        uint256 sold = c.sold;
        if (amount > sold) amount = sold;
        if (amount == 0) revert ZeroAmount();
        proceeds = _cost(c.startPrice, c.endPrice, c.virtualReserve, sold - amount, amount);
    }

    /// @notice Whether the curve has met its graduation target and is ready for graduate().
    function graduable(address token) public view returns (bool) {
        CurveConfig storage c = _curves[token];
        return c.creator != address(0) && c.graduated && !c.seeded;
    }

    /// @notice Get the encoded feeOrHook value for pool keys using this contract as hook.
    function hookFeeOrHook() public view returns (uint256) {
        return uint256(uint160(address(this))) | FLAG_BEFORE;
    }

    /// @notice Derive the ZAMM PoolKey and pool ID for a token's graduated pool.
    function poolKeyOf(address token)
        public
        view
        returns (IZAMM.PoolKey memory key, uint256 poolId)
    {
        key = IZAMM.PoolKey({
            id0: 0, id1: 0, token0: address(0), token1: token, feeOrHook: hookFeeOrHook()
        });
        poolId = uint256(keccak256(abi.encode(key)));
    }

    // ── Observations ──────────────────────────────────────────────

    /// @notice Number of recorded observations for a token.
    function observationCount(address token) public view returns (uint256) {
        return _observations[token].length;
    }

    /// @notice Read a range of packed observations. Use `decodeObservation` to unpack.
    /// @param token The token to query
    /// @param from  Start index (inclusive)
    /// @param to    End index (exclusive, capped to length)
    function observe(address token, uint256 from, uint256 to)
        public
        view
        returns (uint256[] memory obs)
    {
        uint256[] storage arr = _observations[token];
        uint256 len = arr.length;
        if (to > len) to = len;
        if (from >= to) return obs;
        obs = new uint256[](to - from);
        for (uint256 i; i < obs.length; ++i) {
            obs[i] = arr[from + i];
        }
    }

    /// @notice Decode a packed observation into its components.
    function decodeObservation(uint256 packed)
        public
        pure
        returns (uint128 price, uint80 volume, uint40 timestamp, bool isSell)
    {
        price = uint128(packed >> 128);
        volume = uint80(packed >> 48);
        timestamp = uint40(packed >> 8);
        isSell = packed & 1 != 0;
    }

    /// @dev Record a trade observation (1 SSTORE).
    function _recordObservation(address token, uint256 cost, uint256 amount, bool isSell) internal {
        uint256 price = cost * 1e18 / amount;
        _observations[token].push(
            (price << 128) | (uint256(uint80(cost)) << 48) | (uint256(uint40(block.timestamp)) << 8)
                | (isSell ? 1 : 0)
        );
    }

    // ── Trading ──────────────────────────────────────────────────

    /// @notice Buy tokens on the bonding curve (exact-out). Fee is added on top of cost.
    ///         Caps to remaining if amount exceeds available. Refunds excess ETH.
    /// @param token     The token to buy
    /// @param amount    Max tokens to buy (capped to remaining)
    /// @param minAmount Minimum tokens to receive (slippage protection)
    function buy(address token, uint256 amount, uint256 minAmount) public payable lock {
        if (amount == 0) revert ZeroAmount();
        CurveConfig storage c = _curves[token];
        // slot 0: creator + feeBps + graduated
        address creator = c.creator;
        if (creator == address(0)) revert NotConfigured();
        if (c.graduated) revert Graduated();
        uint256 feeBps = c.feeBps;

        // slot 1: cap + sold
        uint256 cap = c.cap;
        uint256 sold = c.sold;
        uint256 remaining = cap - sold;
        if (amount > remaining) amount = remaining;
        if (amount == 0) revert ZeroAmount();
        if (amount < minAmount) revert Slippage();

        // slot 2: startPrice + endPrice  (slot 4: virtualReserve, only if non-flat)
        uint256 startPrice = c.startPrice;
        uint256 endPrice = c.endPrice;
        uint256 cost = _cost(startPrice, endPrice, c.virtualReserve, sold, amount);
        uint256 fee = (cost * feeBps) / 10_000;
        uint256 total = cost + fee;

        if (msg.value < total) revert InsufficientPayment();

        // slot 1 + slot 3: write back
        uint256 newSold = sold + amount;
        c.sold = uint128(newSold);
        uint256 newRaisedETH = c.raisedETH + cost;
        c.raisedETH = uint128(newRaisedETH);

        // slot 3 warm: graduation check using cached values
        _checkGraduation(c, newSold, cap, newRaisedETH, c.graduationTarget);

        safeTransfer(token, msg.sender, amount);
        if (fee != 0) safeTransferETH(creator, fee);

        if (msg.value > total) {
            unchecked {
                safeTransferETH(msg.sender, msg.value - total);
            }
        }

        emit Purchase(token, msg.sender, amount, total);
        _recordObservation(token, cost, amount, false);
    }

    /// @notice Buy tokens with exact ETH input. Fee is deducted from input first.
    /// @param token        The token to buy
    /// @param minAmountOut Minimum tokens to receive (slippage protection)
    function buyExactIn(address token, uint256 minAmountOut) public payable lock {
        CurveConfig storage c = _curves[token];
        address creator = c.creator;
        if (creator == address(0)) revert NotConfigured();
        if (c.graduated) revert Graduated();
        if (msg.value == 0) revert ZeroAmount();

        uint256 feeBps = c.feeBps;
        uint256 fee = (msg.value * feeBps) / 10_000;
        uint256 netETH = msg.value - fee;

        uint256 cap = c.cap;
        uint256 sold = c.sold;
        uint256 remaining = cap - sold;

        uint256 startPrice = c.startPrice;
        uint256 endPrice = c.endPrice;
        uint256 vr = c.virtualReserve;

        uint256 amount;
        if (startPrice == endPrice) {
            amount = netETH * 1e18 / startPrice;
        } else {
            uint256 R = vr - sold;
            uint256 A = mulDiv(startPrice, vr * vr, R * 1e18);
            amount = netETH * R / (A + netETH);
        }

        if (amount > remaining) amount = remaining;
        if (amount == 0) revert ZeroAmount();
        if (amount < minAmountOut) revert Slippage();

        uint256 cost = _cost(startPrice, endPrice, vr, sold, amount);
        while (cost > netETH) {
            // Approximation overshoot — reduce amount until cost fits within netETH
            if (amount <= 1) revert ZeroAmount();
            unchecked {
                amount -= 1;
            }
            cost = _cost(startPrice, endPrice, vr, sold, amount);
        }
        if (amount < minAmountOut) revert Slippage();

        uint256 newSold = sold + amount;
        c.sold = uint128(newSold);
        uint256 newRaisedETH = c.raisedETH + cost;
        c.raisedETH = uint128(newRaisedETH);

        _checkGraduation(c, newSold, cap, newRaisedETH, c.graduationTarget);

        // Recalculate fee on actual cost (not full msg.value) for consistency with buy()
        fee = (cost * feeBps) / 10_000;

        safeTransfer(token, msg.sender, amount);
        if (fee != 0) safeTransferETH(creator, fee);

        uint256 refund = msg.value - cost - fee;
        if (refund != 0) safeTransferETH(msg.sender, refund);

        emit Purchase(token, msg.sender, amount, cost + fee);
        _recordObservation(token, cost, amount, false);
    }

    /// @notice Sell tokens back to the curve. Fee is deducted from proceeds.
    ///         Caller must have approved this contract to transferFrom the token.
    /// @param token      The token to sell
    /// @param amount     Tokens to sell
    /// @param minProceeds Minimum net ETH to receive (slippage protection)
    function sell(address token, uint256 amount, uint256 minProceeds) public lock {
        if (amount == 0) revert ZeroAmount();
        CurveConfig storage c = _curves[token];
        address creator = c.creator;
        if (creator == address(0)) revert NotConfigured();
        if (c.graduated) revert Graduated();
        uint256 sold = c.sold;
        if (amount > sold) amount = sold;
        if (amount == 0) revert ZeroAmount();

        uint256 proceeds = _cost(c.startPrice, c.endPrice, c.virtualReserve, sold - amount, amount);
        uint256 fee = (proceeds * c.feeBps) / 10_000;
        uint256 net = proceeds - fee;

        uint256 raisedETH = c.raisedETH;
        if (net < minProceeds) revert Slippage();
        if (proceeds > raisedETH) revert InsufficientLiquidity();

        // CEI: update state before external calls
        c.sold = uint128(sold - amount);
        c.raisedETH = uint128(raisedETH - proceeds);

        safeTransferFrom(token, address(this), amount);
        safeTransferETH(msg.sender, net);
        if (fee != 0) safeTransferETH(creator, fee);

        emit Sold(token, msg.sender, amount, net);
        _recordObservation(token, proceeds, amount, true);
    }

    /// @notice Sell tokens for an exact ETH output. Fee is added on top (more tokens sold).
    ///         Caller must have approved this contract to transferFrom the token.
    /// @param token     The token to sell
    /// @param ethOut    Exact ETH to receive after fees
    /// @param maxTokens Maximum tokens to sell (slippage protection)
    function sellExactOut(address token, uint256 ethOut, uint256 maxTokens) public lock {
        if (ethOut == 0) revert ZeroAmount();
        CurveConfig storage c = _curves[token];
        address creator = c.creator;
        if (creator == address(0)) revert NotConfigured();
        if (c.graduated) revert Graduated();

        uint256 feeBps = c.feeBps;
        if (feeBps >= 10_000) revert InvalidParams();
        uint256 raisedETH = c.raisedETH;
        uint256 proceeds = (ethOut * 10_000 + (10_000 - feeBps) - 1) / (10_000 - feeBps);
        if (proceeds > raisedETH) revert InsufficientLiquidity();

        uint256 sold = c.sold;
        uint256 startPrice = c.startPrice;
        uint256 endPrice = c.endPrice;
        uint256 vr = c.virtualReserve;

        uint256 amount;
        if (startPrice == endPrice) {
            amount = (proceeds * 1e18 + startPrice - 1) / startPrice;
        } else {
            uint256 R = vr - sold;
            // A = startPrice · T₀² / 1e18, B = proceeds · R
            uint256 A = mulDiv(startPrice, vr * vr, 1e18);
            uint256 B = proceeds * R;
            if (B >= A) revert InsufficientLiquidity();
            uint256 denom = A - B;
            amount = mulDivUp(B, R, denom);
        }

        if (amount > sold) amount = sold;
        if (amount == 0) revert ZeroAmount();
        if (amount > maxTokens) revert Slippage();

        proceeds = _cost(startPrice, endPrice, vr, sold - amount, amount);
        uint256 fee = (proceeds * feeBps) / 10_000;
        uint256 net = proceeds - fee;

        if (net < ethOut) revert Slippage();
        if (proceeds > raisedETH) revert InsufficientLiquidity();

        // CEI: update state before external calls
        c.sold = uint128(sold - amount);
        c.raisedETH = uint128(raisedETH - proceeds);

        safeTransferFrom(token, address(this), amount);
        safeTransferETH(msg.sender, net);
        if (fee != 0) safeTransferETH(creator, fee);

        emit Sold(token, msg.sender, amount, net);
        _recordObservation(token, proceeds, amount, true);
    }

    // ── Graduation ───────────────────────────────────────────────

    /// @notice Seed ZAMM liquidity from graduated curve. Permissionless once graduated.
    ///         Pairs lpTokens with raisedETH. Unsold curve tokens are burned.
    ///         LP tokens sent to lpRecipient (or burned if address(0)).
    ///         Pool is created with this contract as ZAMM hook for fee governance.
    /// @param token The token whose curve has graduated
    function graduate(address token) public returns (uint256 liquidity) {
        CurveConfig storage c = _curves[token];
        if (c.creator == address(0)) revert NotConfigured();
        if (!c.graduated || c.seeded) revert NotGraduable();

        c.seeded = true;

        address creator = c.creator;
        uint256 ethForLP = c.raisedETH;
        uint256 tokensForLP = c.lpTokens;

        // Burn unsold curve tokens (prevents creator dump on freshly seeded pool)
        uint256 unsold = c.cap - c.sold;
        if (unsold != 0) safeTransfer(token, address(0xdead), unsold);

        // If no LP tokens or no ETH, just return funds to creator
        if (tokensForLP == 0 || ethForLP == 0) {
            if (tokensForLP != 0) safeTransfer(token, creator, tokensForLP);
            if (ethForLP != 0) safeTransferETH(creator, ethForLP);
            emit GraduationComplete(token, 0, 0, 0);
            return 0;
        }

        // Build pool key with self as hook (ETH = address(0) is always token0)
        (IZAMM.PoolKey memory key, uint256 poolId) = poolKeyOf(token);

        // Approve before registering pool to close reentrancy window via malicious token
        ensureApproval(token, address(ZAMM));

        // Register pool AFTER approval — prevents malicious token from front-running LP seeding
        poolToken[poolId] = token;

        address recipient = c.lpRecipient == address(0) ? address(0xdead) : c.lpRecipient;

        // Transient bypass so beforeAction allows this addLiquidity (scoped to this poolId)
        assembly ("memory-safe") {
            tstore(SEEDING_SLOT, add(poolId, 1))
        }
        (uint256 used0, uint256 used1, uint256 liq) = ZAMM.addLiquidity{value: ethForLP}(
            key, ethForLP, tokensForLP, 0, 0, recipient, block.timestamp
        );
        assembly ("memory-safe") {
            tstore(SEEDING_SLOT, 0)
        }
        liquidity = liq;

        // Refund unused amounts to creator
        uint256 unusedETH = ethForLP - used0;
        uint256 unusedTokens = tokensForLP - used1;
        if (unusedETH != 0) safeTransferETH(creator, unusedETH);
        if (unusedTokens != 0) safeTransfer(token, creator, unusedTokens);

        emit GraduationComplete(token, used0, used1, liquidity);
    }

    // ── ZAMM Hook ────────────────────────────────────────────────

    /// @notice ZAMM hook: gate addLiquidity pre-seed, return fee on swaps.
    ///         Pre-seed: only graduate() can addLiquidity (blocks frontrun pool creation).
    ///         Post-seed: all LP operations allowed, swaps charged pool fee.
    ///         When creator fee is active, swaps must route through this contract.
    function beforeAction(bytes4 sig, uint256 poolId, address sender, bytes calldata)
        public
        payable
        returns (uint256 feeBps)
    {
        if (msg.sender != address(ZAMM)) revert Unauthorized();

        address token = poolToken[poolId];

        // LP operations (addLiquidity / removeLiquidity)
        if (
            sig != IZAMM.swapExactIn.selector && sig != IZAMM.swapExactOut.selector
                && sig != IZAMM.swap.selector
        ) {
            // Pre-seed: only allow from graduate() via transient bypass (scoped to exact poolId)
            if (token == address(0)) {
                bool seeding;
                assembly ("memory-safe") {
                    seeding := eq(tload(SEEDING_SLOT), add(poolId, 1))
                }
                if (!seeding) revert NotConfigured();
            }
            return 0;
        }

        // Swaps: require registered pool
        if (token == address(0)) revert NotConfigured();

        // Enforce routing when creator fee is active
        if (creatorFees[token].beneficiary != address(0)) {
            if (sig == IZAMM.swap.selector) revert Unauthorized();
            if (sender != address(this)) revert Unauthorized();
        }

        uint16 pf = _curves[token].poolFeeBps;
        return pf == 0 ? DEFAULT_POOL_FEE : pf;
    }

    // ── Creator Governance ───────────────────────────────────────

    /// @notice Transfer creator role to a new address. Only callable by current creator.
    /// @dev    Setting a contract that rejects ETH as creator will DoS fee-bearing buys/sells.
    ///         Also transfers vesting claim rights — claim before transferring if needed.
    /// @param token      The token whose creator to update
    /// @param newCreator The new creator address (must not be address(0))
    function setCreator(address token, address newCreator) public {
        CurveConfig storage c = _curves[token];
        if (msg.sender != c.creator) revert Unauthorized();
        if (newCreator == address(0)) revert InvalidParams();
        c.creator = newCreator;
        emit CreatorUpdated(token, newCreator);
    }

    /// @notice Update LP recipient for graduation. Only callable by creator.
    ///         Allows configuring locked LP (e.g. set to a lock contract) before graduation.
    /// @param token        The token whose LP recipient to update
    /// @param newRecipient New LP recipient (address(0) = burn LP tokens)
    function setLpRecipient(address token, address newRecipient) public {
        CurveConfig storage c = _curves[token];
        if (msg.sender != c.creator) revert Unauthorized();
        if (c.graduated) revert Graduated();
        c.lpRecipient = newRecipient;
        emit LpRecipientUpdated(token, newRecipient);
    }

    /// @notice Configure creator revenue fee on post-graduation swaps.
    ///         When beneficiary is set, swaps must route through this contract's
    ///         swapExactIn/swapExactOut — direct ZAMM swaps are blocked by the hook.
    /// @param token        The token whose fee to configure
    /// @param beneficiary  Fee recipient (address(0) disables routing enforcement)
    /// @param buyBps       Fee bps when buying token (ETH → token)
    /// @param sellBps      Fee bps when selling token (token → ETH)
    /// @param buyOnInput   true = buy fee from ETH input, false = from token output
    /// @param sellOnInput  true = sell fee from token input, false = from ETH output
    function setCreatorFee(
        address token,
        address beneficiary,
        uint16 buyBps,
        uint16 sellBps,
        bool buyOnInput,
        bool sellOnInput
    ) public {
        CurveConfig storage c = _curves[token];
        if (msg.sender != c.creator) revert Unauthorized();
        if (buyBps > MAX_CREATOR_FEE_BPS || sellBps > MAX_CREATOR_FEE_BPS) revert InvalidParams();
        if (beneficiary == address(0) && (buyBps | sellBps) != 0) revert InvalidParams();
        if (beneficiary != address(0) && (buyBps | sellBps) == 0) revert InvalidParams();
        creatorFees[token] = CreatorFee(beneficiary, buyBps, sellBps, buyOnInput, sellOnInput);
        emit CreatorFeeUpdated(token, beneficiary, buyBps, sellBps);
    }

    /// @notice Claim vested creator tokens.
    ///         Cliff only: nothing until cliff, then 100%.
    ///         Cliff + duration: nothing until cliff, then linear over duration.
    ///         Duration only: linear from launch.
    /// @param token The token to claim vested allocation for
    function claimVested(address token) public {
        CurveConfig storage c = _curves[token];
        if (msg.sender != c.creator) revert Unauthorized();

        CreatorVest storage v = creatorVests[token];
        if (v.total == 0) revert NotConfigured();

        uint256 elapsed = block.timestamp - v.start;
        if (elapsed < v.cliff) revert ZeroAmount();

        uint256 vested;
        uint256 postCliff = elapsed - v.cliff;
        if (v.duration == 0 || postCliff >= v.duration) {
            vested = v.total;
        } else {
            vested = uint256(v.total) * postCliff / v.duration;
        }

        uint256 claimable = vested - v.claimed;
        if (claimable == 0) revert ZeroAmount();

        v.claimed = uint128(vested);
        safeTransfer(token, msg.sender, claimable);

        emit VestingClaimed(token, msg.sender, claimable);
    }

    // ── Routed Swaps (creator fee) ───────────────────────────────

    modifier lock() {
        assembly ("memory-safe") {
            if tload(SWAP_LOCK_SLOT) {
                mstore(0x00, 0xab143c06) // Reentrancy()
                revert(0x1c, 0x04)
            }
            tstore(SWAP_LOCK_SLOT, address())
        }
        _;
        assembly ("memory-safe") {
            tstore(SWAP_LOCK_SLOT, 0)
        }
    }

    /// @notice Swap exact input through ZAMM with creator fee.
    ///         Required for pools with an active creator fee.
    /// @param poolKey      ZAMM pool key (use poolKeyOf to derive)
    /// @param amountIn     Input amount (for ETH input, send as msg.value)
    /// @param amountOutMin Minimum output after all fees
    /// @param zeroForOne   true = ETH → token (buy), false = token → ETH (sell)
    /// @param to           Recipient of output tokens/ETH
    /// @param deadline     Transaction deadline
    function swapExactIn(
        IZAMM.PoolKey calldata poolKey,
        uint256 amountIn,
        uint256 amountOutMin,
        bool zeroForOne,
        address to,
        uint256 deadline
    ) public payable lock returns (uint256 amountOut) {
        address token = poolKey.token1;
        CreatorFee storage fee = creatorFees[token];
        uint256 bps = zeroForOne ? fee.buyBps : fee.sellBps;
        address ben = fee.beneficiary;
        bool onInput = zeroForOne ? fee.buyOnInput : fee.sellOnInput;

        if (zeroForOne) {
            // ETH → token
            amountIn = msg.value;
            if (onInput) {
                uint256 tax = (amountIn * bps) / 10_000;
                uint256 net = amountIn - tax;
                if (tax != 0) safeTransferETH(ben, tax);
                amountOut =
                    ZAMM.swapExactIn{value: net}(poolKey, net, amountOutMin, true, to, deadline);
            } else {
                amountOut = ZAMM.swapExactIn{value: amountIn}(
                    poolKey, amountIn, 0, true, address(this), deadline
                );
                uint256 tax = (amountOut * bps) / 10_000;
                uint256 net = amountOut - tax;
                if (net < amountOutMin) revert Slippage();
                if (tax != 0) safeTransfer(token, ben, tax);
                safeTransfer(token, to, net);
                amountOut = net;
            }
        } else {
            // token → ETH
            if (msg.value != 0) revert InvalidParams();
            safeTransferFrom(token, address(this), amountIn);
            ensureApproval(token, address(ZAMM));
            if (onInput) {
                uint256 tax = (amountIn * bps) / 10_000;
                uint256 net = amountIn - tax;
                if (tax != 0) safeTransfer(token, ben, tax);
                amountOut = ZAMM.swapExactIn(poolKey, net, amountOutMin, false, to, deadline);
            } else {
                amountOut = ZAMM.swapExactIn(poolKey, amountIn, 0, false, address(this), deadline);
                uint256 tax = (amountOut * bps) / 10_000;
                uint256 net = amountOut - tax;
                if (net < amountOutMin) revert Slippage();
                if (tax != 0) safeTransferETH(ben, tax);
                safeTransferETH(to, net);
                amountOut = net;
            }
        }
    }

    /// @notice Swap exact output through ZAMM with creator fee.
    ///         `amountOut` is the net amount `to` receives after fees.
    /// @param poolKey      ZAMM pool key (use poolKeyOf to derive)
    /// @param amountOut    Desired net output amount
    /// @param amountInMax  Maximum input (for ETH input, send as msg.value)
    /// @param zeroForOne   true = ETH → token (buy), false = token → ETH (sell)
    /// @param to           Recipient of output tokens/ETH
    /// @param deadline     Transaction deadline
    function swapExactOut(
        IZAMM.PoolKey calldata poolKey,
        uint256 amountOut,
        uint256 amountInMax,
        bool zeroForOne,
        address to,
        uint256 deadline
    ) public payable lock returns (uint256 amountIn) {
        address token = poolKey.token1;
        CreatorFee storage fee = creatorFees[token];
        uint256 bps = zeroForOne ? fee.buyBps : fee.sellBps;
        address ben = fee.beneficiary;
        bool onInput = zeroForOne ? fee.buyOnInput : fee.sellOnInput;

        if (zeroForOne) {
            // ETH → token
            amountInMax = msg.value;
            if (onInput) {
                uint256 netMax = (amountInMax * (10_000 - bps)) / 10_000;
                amountIn = ZAMM.swapExactOut{value: netMax}(
                    poolKey, amountOut, netMax, true, to, deadline
                );
                uint256 tax = (amountIn * bps) / (10_000 - bps);
                uint256 spent = amountIn + tax;
                if (tax != 0) safeTransferETH(ben, tax);
                uint256 refund = amountInMax - spent;
                if (refund != 0) safeTransferETH(msg.sender, refund);
                amountIn = spent;
            } else {
                uint256 gross = bps != 0
                    ? (amountOut * 10_000 + (10_000 - bps) - 1) / (10_000 - bps)
                    : amountOut;
                amountIn = ZAMM.swapExactOut{value: amountInMax}(
                    poolKey, gross, amountInMax, true, address(this), deadline
                );
                uint256 refund = amountInMax - amountIn;
                if (refund != 0) safeTransferETH(msg.sender, refund);
                uint256 tax = gross - amountOut;
                if (tax != 0) safeTransfer(token, ben, tax);
                safeTransfer(token, to, amountOut);
            }
        } else {
            // token → ETH
            if (msg.value != 0) revert InvalidParams();
            safeTransferFrom(token, address(this), amountInMax);
            ensureApproval(token, address(ZAMM));
            if (onInput) {
                uint256 netMax = (amountInMax * (10_000 - bps)) / 10_000;
                amountIn = ZAMM.swapExactOut(poolKey, amountOut, netMax, false, to, deadline);
                uint256 tax = (amountIn * bps) / (10_000 - bps);
                if (tax != 0) safeTransfer(token, ben, tax);
                uint256 refund = amountInMax - amountIn - tax;
                if (refund != 0) safeTransfer(token, msg.sender, refund);
                amountIn = amountIn + tax;
            } else {
                uint256 gross = bps != 0
                    ? (amountOut * 10_000 + (10_000 - bps) - 1) / (10_000 - bps)
                    : amountOut;
                amountIn =
                    ZAMM.swapExactOut(poolKey, gross, amountInMax, false, address(this), deadline);
                uint256 refund = amountInMax - amountIn;
                if (refund != 0) safeTransfer(token, msg.sender, refund);
                uint256 tax = gross - amountOut;
                if (tax != 0) safeTransferETH(ben, tax);
                safeTransferETH(to, amountOut);
            }
        }
    }

    // ── Internal ─────────────────────────────────────────────────

    /// @dev Check if graduation target is met and set the graduated flag.
    ///      Takes stack values to avoid re-SLOADing already-cached fields.
    function _checkGraduation(
        CurveConfig storage c,
        uint256 newSold,
        uint256 cap,
        uint256 newRaisedETH,
        uint256 graduationTarget
    ) internal {
        if (graduationTarget != 0) {
            if (newRaisedETH >= graduationTarget) c.graduated = true;
        } else if (newSold == cap) {
            c.graduated = true;
        }
    }

    /// @dev Compute cost for `amount` tokens starting at position `sold` on the XYK curve.
    ///      Pure with stack params to avoid redundant SLOADs — callers cache from storage once.
    ///      Integral: P₀ · T₀² · amount / ((T₀ − sold) · (T₀ − sold − amount))
    ///      Rounded up to prevent dust.
    function _cost(
        uint256 startPrice,
        uint256 endPrice,
        uint256 virtualReserve,
        uint256 sold,
        uint256 amount
    ) internal pure returns (uint256) {
        // Flat curve shortcut
        if (endPrice == startPrice) {
            return (amount * startPrice + 1e18 - 1) / 1e18;
        }

        uint256 rem = virtualReserve - sold;
        uint256 remAfter = rem - amount;
        uint256 step = mulDiv(startPrice * amount, virtualReserve, rem);
        return mulDivUp(step, virtualReserve, remAfter * 1e18);
    }

    // ── Multicall ──────────────────────────────────────────────

    /// @notice Batch multiple calls into a single transaction (e.g. graduate + setCreatorFee).
    ///         Non-payable to prevent msg.value double-spend across delegatecalls.
    function multicall(bytes[] calldata data) public {
        for (uint256 i; i < data.length; ++i) {
            (bool ok, bytes memory ret) = address(this).delegatecall(data[i]);
            if (!ok) {
                assembly ("memory-safe") {
                    revert(add(ret, 0x20), mload(ret))
                }
            }
        }
    }

    /// @dev Accept ETH (for ZAMM refunds during graduation and fee-on-output swaps).
    receive() external payable {}
}

/// @dev ZAMM interface for LP, swap, and pool state operations.
interface IZAMM {
    struct PoolKey {
        uint256 id0;
        uint256 id1;
        address token0;
        address token1;
        uint256 feeOrHook;
    }

    function addLiquidity(
        PoolKey calldata poolKey,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amount0, uint256 amount1, uint256 liquidity);

    function swapExactIn(
        PoolKey calldata poolKey,
        uint256 amountIn,
        uint256 amountOutMin,
        bool zeroForOne,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountOut);

    function swapExactOut(
        PoolKey calldata poolKey,
        uint256 amountOut,
        uint256 amountInMax,
        bool zeroForOne,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountIn);

    function swap(
        PoolKey calldata poolKey,
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;
}

/// @dev ZAMM singleton address.
IZAMM constant ZAMM = IZAMM(0x000000000000040470635EB91b7CE4D132D616eD);

/// @dev Returns floor(x * y / d) with full 512-bit intermediate precision.
///      Reverts on overflow (result > uint256) or d == 0.
///      From Solady FixedPointMathLib (https://github.com/Vectorized/solady).
function mulDiv(uint256 x, uint256 y, uint256 d) pure returns (uint256 z) {
    assembly ("memory-safe") {
        z := mul(x, y)
        for {} 1 {} {
            if iszero(mul(or(iszero(x), eq(div(z, x), y)), d)) {
                let mm := mulmod(x, y, not(0))
                let p1 := sub(mm, add(z, lt(mm, z)))
                let r := mulmod(x, y, d)
                let t := and(d, sub(0, d))
                if iszero(gt(d, p1)) {
                    mstore(0x00, 0xad251c27)
                    revert(0x1c, 0x04)
                }
                d := div(d, t)
                let inv := xor(2, mul(3, d))
                inv := mul(inv, sub(2, mul(d, inv)))
                inv := mul(inv, sub(2, mul(d, inv)))
                inv := mul(inv, sub(2, mul(d, inv)))
                inv := mul(inv, sub(2, mul(d, inv)))
                inv := mul(inv, sub(2, mul(d, inv)))
                z := mul(
                    or(mul(sub(p1, gt(r, z)), add(div(sub(0, t), t), 1)), div(sub(z, r), t)),
                    mul(sub(2, mul(d, inv)), inv)
                )
                break
            }
            z := div(z, d)
            break
        }
    }
}

/// @dev Returns ceil(x * y / d) with full 512-bit intermediate precision.
///      Reverts on overflow (result > uint256) or d == 0.
///      From Solady FixedPointMathLib (https://github.com/Vectorized/solady).
function mulDivUp(uint256 x, uint256 y, uint256 d) pure returns (uint256 z) {
    z = mulDiv(x, y, d);
    assembly ("memory-safe") {
        if mulmod(x, y, d) {
            z := add(z, 1)
            if iszero(z) {
                mstore(0x00, 0xad251c27)
                revert(0x1c, 0x04)
            }
        }
    }
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

function ensureApproval(address token, address spender) {
    assembly ("memory-safe") {
        mstore(0x00, 0xdd62ed3e000000000000000000000000)
        mstore(0x14, address())
        mstore(0x34, spender)
        let success := staticcall(gas(), token, 0x10, 0x44, 0x00, 0x20)

        if iszero(and(success, gt(mload(0x00), 0xffffffffffffffffffffffffffffffff))) {
            mstore(0x14, spender)
            mstore(0x34, not(0))
            mstore(0x00, 0x095ea7b3000000000000000000000000)
            success := call(gas(), token, 0, 0x10, 0x44, 0x00, 0x20)
            if iszero(and(eq(mload(0x00), 1), success)) {
                if iszero(lt(or(iszero(extcodesize(token)), returndatasize()), success)) {
                    mstore(0x00, 0x3e3f8f73)
                    revert(0x1c, 0x04)
                }
            }
        }
        mstore(0x34, 0)
    }
}

/// @notice Standard fungible token (https://eips.ethereum.org/EIPS/eip-20).
/// @author Zolidity (https://github.com/z0r0z/zolidity/blob/main/src/ERC20.sol)
contract ERC20 {
    event Approval(address indexed from, address indexed to, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount);

    string public name;
    string public symbol;
    string public contractURI;
    uint256 public constant decimals = 18;

    uint256 public totalSupply;

    mapping(address holder => uint256) public balanceOf;
    mapping(address holder => mapping(address spender => uint256)) public allowance;

    constructor() payable {}

    error InvalidInit();
    error Initialized();

    function init(
        string calldata _name,
        string calldata _symbol,
        string calldata _uri,
        uint256 supply,
        address to
    ) public payable {
        (name, symbol, contractURI) = (_name, _symbol, _uri);
        require(supply != 0, InvalidInit());
        require(totalSupply == 0, Initialized());
        totalSupply += supply;
        unchecked {
            balanceOf[to] += supply;
        }
        emit Transfer(address(0), to, supply);
    }

    function approve(address to, uint256 amount) public returns (bool) {
        allowance[msg.sender][to] = amount;
        emit Approval(msg.sender, to, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        balanceOf[msg.sender] -= amount;
        unchecked {
            balanceOf[to] += amount;
        }
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        unchecked {
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
        return true;
    }
}
