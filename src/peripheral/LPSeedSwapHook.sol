// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @dev Minimal ZAMM interface for LP initialization.
interface IZAMM {
    struct PoolKey {
        uint256 id0;
        uint256 id1;
        address token0;
        address token1;
        uint256 feeOrHook;
    }

    function pools(uint256 poolId)
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast,
            uint256 price0CumulativeLast,
            uint256 price1CumulativeLast,
            uint256 kLast,
            uint256 supply
        );

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

/// @dev Minimal Moloch interface.
interface IMoloch {
    function spendAllowance(address token, uint256 amount) external;
    function setAllowance(address spender, address token, uint256 amount) external;
    function allowance(address token, address spender) external view returns (uint256);
    function shares() external view returns (address);
    function loot() external view returns (address);
}

/// @dev Minimal ShareSale interface for checking remaining allowance.
interface IShareSale {
    function sales(address dao)
        external
        view
        returns (address token, address payToken, uint40 deadline, uint256 price);
}

/// @dev ZAMM hook interface.
interface IZAMMHook {
    function beforeAction(bytes4 sig, uint256 poolId, address sender, bytes calldata data)
        external
        payable
        returns (uint256 feeBps);

    function afterAction(
        bytes4 sig,
        uint256 poolId,
        address sender,
        int256 d0,
        int256 d1,
        int256 dLiq,
        bytes calldata data
    ) external payable;
}

/// @dev ZAMM singleton address.
IZAMM constant ZAMM = IZAMM(0x000000000000040470635EB91b7CE4D132D616eD);

/// @dev Hook encoding flags.
uint256 constant FLAG_BEFORE = 1 << 255;
uint256 constant FLAG_AFTER = 1 << 254;

/// @dev Default swap fee when none configured (30 bps = 0.30%).
uint16 constant DEFAULT_FEE_BPS = 30;

/// @title LPSeedSwapHook
/// @notice Singleton hook for seeding ZAMM liquidity from DAO treasury tokens.
///         Acts as a ZAMM hook to give DAOs exclusive control over pool initialization:
///         - Pre-seed: blocks all addLiquidity (prevents frontrun pool creation)
///         - Post-seed: returns DAO-configured fee on swaps, open LP for all
///
///   DAOs configure a seed by calling `configure()` in an initCall and granting
///   this contract allowances for both tokens via `setAllowance()`.
///   Seeding is gated by optional conditions:
///     - deadline:    seed only after a timestamp (e.g. after a sale ends)
///     - shareSale:   seed only after a ShareSale allowance is fully spent (sale sold out)
///     - minSupply:   seed only after DAO's forTkn balance drops to this threshold
///
///   Uses the Moloch allowance system for both tokens. The DAO retains custody
///   until seed() pulls via spendAllowance.
///
///   Setup (include in Summoner initCalls or SafeSummoner extraCalls):
///     1. dao.setAllowance(lpSeed, tokenA, amountA)
///     2. dao.setAllowance(lpSeed, tokenB, amountB)
///     3. lpSeed.configure(tokenA, amountA, tokenB, amountB, deadline, shareSale, minSupply)
///
///   Usage:
///     lpSeed.seed(dao)              // permissionless once conditions met
///     lpSeed.seedable(dao)          // view: check if conditions are met
///
///   DAO governance:
///     lpSeed.cancel()               // cancel seeding, DAO reclaims allowances
///     lpSeed.setFee(feeBps)         // update swap fee for the pool
contract LPSeedSwapHook is IZAMMHook {
    error NotReady();
    error Unauthorized();
    error AlreadySeeded();
    error InvalidParams();
    error NotConfigured();

    event Configured(
        address indexed dao, address tokenA, uint256 amountA, address tokenB, uint256 amountB
    );
    event Seeded(address indexed dao, uint256 amount0, uint256 amount1, uint256 liquidity);
    event Cancelled(address indexed dao);
    event FeeUpdated(address indexed dao, uint16 oldFee, uint16 newFee);

    struct SeedConfig {
        address tokenA; // first token (ERC20, or address(0) for ETH)
        address tokenB; // second token (ERC20, must be nonzero)
        uint128 amountA; // amount of tokenA to seed
        uint128 amountB; // amount of tokenB to seed
        uint16 feeBps; // swap fee (0 = DEFAULT_FEE_BPS)
        uint40 deadline; // seed only after this timestamp (0 = no time gate)
        address shareSale; // if set, seed only after this ShareSale's allowance is spent
        uint128 minSupply; // if set, seed only after DAO's tokenB balance <= minSupply
        bool seeded; // true after seed() succeeds
    }

    /// @dev Keyed by DAO address. Set via configure() called by the DAO itself.
    mapping(address dao => SeedConfig) public seeds;

    /// @dev Reverse mapping: poolId → DAO address. Set during seed().
    mapping(uint256 poolId => address dao) public poolDAO;

    /// @dev Transient storage slot for reentrancy guard during seed().
    ///      Signals to beforeAction that addLiquidity is from seed(), not external.
    uint256 constant SEEDING_SLOT = 0x4c505365656453696e676c65746f6e;

    /// @notice Configure LP seed parameters. Must be called by the DAO (e.g. in initCalls).
    /// @param tokenA     First token (address(0) = ETH)
    /// @param amountA    Amount of tokenA to seed
    /// @param tokenB     Second token (must be nonzero ERC20)
    /// @param amountB    Amount of tokenB to seed
    /// @param deadline   Seed only after this timestamp (0 = no time gate)
    /// @param shareSale  ShareSale address to check for sale completion (address(0) = no check)
    /// @param minSupply  Seed only after DAO's tokenB balance <= this (0 = no check)
    function configure(
        address tokenA,
        uint128 amountA,
        address tokenB,
        uint128 amountB,
        uint40 deadline,
        address shareSale,
        uint128 minSupply
    ) public {
        if (amountA == 0 || amountB == 0 || tokenB == address(0)) {
            revert InvalidParams();
        }
        if (tokenA == tokenB) revert InvalidParams();

        seeds[msg.sender] = SeedConfig({
            tokenA: tokenA,
            tokenB: tokenB,
            amountA: amountA,
            amountB: amountB,
            feeBps: 0,
            deadline: deadline,
            shareSale: shareSale,
            minSupply: minSupply,
            seeded: false
        });

        // Reserve pool ID at configure time so beforeAction blocks
        // frontrun addLiquidity before seed() runs.
        (address t0, address t1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        IZAMM.PoolKey memory key =
            IZAMM.PoolKey({id0: 0, id1: 0, token0: t0, token1: t1, feeOrHook: hookFeeOrHook()});
        uint256 poolId = uint256(keccak256(abi.encode(key)));
        poolDAO[poolId] = msg.sender;

        emit Configured(msg.sender, tokenA, amountA, tokenB, amountB);
    }

    /// @notice Seed ZAMM liquidity. Permissionless — anyone can trigger once conditions are met.
    ///         LP shares go to the DAO. One-shot: reverts if already seeded.
    /// @param dao The DAO to seed liquidity for
    function seed(address dao) public returns (uint256 liquidity) {
        SeedConfig storage cfg = seeds[dao];
        if (cfg.amountA == 0) revert NotConfigured();
        if (cfg.seeded) revert AlreadySeeded();

        // Check gating conditions
        _checkReady(dao, cfg);

        // Mark seeded before external calls (CEI)
        cfg.seeded = true;

        uint128 amtA = cfg.amountA;
        uint128 amtB = cfg.amountB;
        address tokenA = cfg.tokenA;
        address tokenB = cfg.tokenB;

        // Pull tokens from DAO via allowance (ETH uses address(0) allowance path)
        IMoloch(dao).spendAllowance(tokenA, amtA);
        IMoloch(dao).spendAllowance(tokenB, amtB);

        // Build canonical pool key (token0 < token1)
        // For ETH (address(0)), it's always token0
        address t0 = tokenA;
        address t1 = tokenB;
        uint256 amt0 = amtA;
        uint256 amt1 = amtB;
        if (t0 > t1) {
            (t0, t1) = (t1, t0);
            (amt0, amt1) = (amt1, amt0);
        }

        uint256 feeOrHook = hookFeeOrHook();

        IZAMM.PoolKey memory key =
            IZAMM.PoolKey({id0: 0, id1: 0, token0: t0, token1: t1, feeOrHook: feeOrHook});

        // Register poolId → dao for hook callbacks
        uint256 poolId = uint256(keccak256(abi.encode(key)));
        poolDAO[poolId] = dao;

        // Approve ZAMM to spend tokens
        if (tokenA != address(0)) ensureApproval(tokenA, address(ZAMM));
        ensureApproval(tokenB, address(ZAMM));

        // Add liquidity — LP shares go to DAO
        // First LP always gets exact amounts, so min = 0
        // Transient flag signals beforeAction to allow this addLiquidity
        uint256 ethValue = tokenA == address(0) ? amtA : 0;
        assembly ("memory-safe") {
            tstore(SEEDING_SLOT, address())
        }
        (uint256 used0, uint256 used1, uint256 liq) =
            ZAMM.addLiquidity{value: ethValue}(key, amt0, amt1, 0, 0, dao, block.timestamp);
        assembly ("memory-safe") {
            tstore(SEEDING_SLOT, 0)
        }
        liquidity = liq;

        // Refund unused tokens to DAO
        uint256 unused0 = amt0 - used0;
        uint256 unused1 = amt1 - used1;

        if (t0 == address(0)) {
            if (unused0 != 0) safeTransferETH(dao, unused0);
            if (unused1 != 0) safeTransfer(t1, dao, unused1);
        } else {
            if (unused0 != 0) safeTransfer(t0, dao, unused0);
            if (unused1 != 0) safeTransfer(t1, dao, unused1);
        }

        emit Seeded(dao, used0, used1, liquidity);
    }

    /// @notice View: whether seed conditions are met.
    function seedable(address dao) public view returns (bool) {
        SeedConfig memory cfg = seeds[dao];
        if (cfg.amountA == 0 || cfg.seeded) return false;
        return _isReady(dao, cfg);
    }

    /// @notice Cancel the seed config. Only callable by the DAO.
    ///         DAO should reclaim allowances separately via setAllowance(lpSeed, token, 0).
    function cancel() public {
        SeedConfig storage cfg = seeds[msg.sender];
        if (cfg.amountA == 0) revert NotConfigured();
        delete seeds[msg.sender];
        emit Cancelled(msg.sender);
    }

    // ── DAO Governance ──────────────────────────────────────────

    /// @notice Update swap fee for the pool. Only callable by the DAO.
    /// @param newFeeBps New fee in basis points (0 = use DEFAULT_FEE_BPS).
    function setFee(uint16 newFeeBps) public {
        if (newFeeBps > 10_000) revert InvalidParams();
        SeedConfig storage cfg = seeds[msg.sender];
        if (cfg.amountA == 0) revert NotConfigured();
        uint16 old = cfg.feeBps;
        cfg.feeBps = newFeeBps;
        emit FeeUpdated(msg.sender, old, newFeeBps);
    }

    // ── ZAMM Hook ─────────────────────────────────────────────

    /// @notice Get the encoded feeOrHook value for pool keys using LPSeed as hook.
    function hookFeeOrHook() public view returns (uint256) {
        return uint256(uint160(address(this))) | FLAG_BEFORE;
    }

    /// @notice ZAMM hook: gate addLiquidity pre-seed, return fee on swaps.
    /// @dev Pre-seed: only seed() can addLiquidity (blocks frontrun pool creation).
    ///      Post-seed: all LP operations allowed, swaps charged DAO-configured fee.
    ///      Unregistered pools (poolDAO not set): LP allowed, swaps revert.
    function beforeAction(bytes4 sig, uint256 poolId, address, bytes calldata)
        external
        payable
        override
        returns (uint256 feeBps)
    {
        if (msg.sender != address(ZAMM)) revert Unauthorized();

        address dao = poolDAO[poolId];

        // addLiquidity / removeLiquidity
        if (
            sig != IZAMM.swapExactIn.selector && sig != IZAMM.swapExactOut.selector
                && sig != IZAMM.swap.selector
        ) {
            // Pre-seed: only allow addLiquidity from seed() (transient flag set)
            if (dao != address(0) && !seeds[dao].seeded) {
                bool seeding;
                assembly ("memory-safe") {
                    seeding := tload(SEEDING_SLOT)
                }
                if (!seeding) revert NotReady();
            }
            return 0; // no fee on LP operations
        }

        // Swaps: require registered + seeded pool
        if (dao == address(0)) revert NotConfigured();
        if (!seeds[dao].seeded) revert NotReady();

        // Return DAO-configured fee (0 → default 30 bps)
        uint16 fee = seeds[dao].feeBps;
        return fee == 0 ? DEFAULT_FEE_BPS : fee;
    }

    /// @notice ZAMM hook: no-op after action.
    function afterAction(bytes4, uint256, address, int256, int256, int256, bytes calldata)
        external
        payable
        override
    {
        if (msg.sender != address(ZAMM)) revert Unauthorized();
    }

    // ── Internal ─────────────────────────────────────────────────

    function _isReady(address dao, SeedConfig memory cfg) internal view returns (bool) {
        // Time gate
        if (cfg.deadline != 0 && block.timestamp <= cfg.deadline) return false;

        // ShareSale completion gate: sale allowance must be fully spent (== 0)
        if (cfg.shareSale != address(0)) {
            (address saleToken,,,) = IShareSale(cfg.shareSale).sales(dao);
            if (saleToken == address(0)) return false; // sale not configured yet
            uint256 remaining = IMoloch(dao).allowance(saleToken, cfg.shareSale);
            if (remaining != 0) return false;
        }

        // Supply gate: DAO's tokenB balance must be at or below threshold
        if (cfg.minSupply != 0) {
            uint256 daoBal = balanceOf(cfg.tokenB, dao);
            if (daoBal > cfg.minSupply) return false;
        }

        return true;
    }

    function _checkReady(address dao, SeedConfig memory cfg) internal view {
        if (!_isReady(dao, cfg)) revert NotReady();
    }

    /// @dev Accept ETH from DAO via spendAllowance.
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                          INIT CALL HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Generate initCalls for setting up an LP seed.
    /// @dev Returns 3 calls: setAllowance(tokenA), setAllowance(tokenB), configure().
    function seedInitCalls(
        address dao,
        address tokenA,
        uint128 amountA,
        address tokenB,
        uint128 amountB,
        uint40 deadline,
        address shareSale,
        uint128 minSupply
    )
        public
        view
        returns (
            address target1,
            bytes memory data1,
            address target2,
            bytes memory data2,
            address target3,
            bytes memory data3
        )
    {
        // 1. dao.setAllowance(lpSeed, tokenA, amountA)
        target1 = dao;
        data1 = abi.encodeCall(IMoloch.setAllowance, (address(this), tokenA, amountA));

        // 2. dao.setAllowance(lpSeed, tokenB, amountB)
        target2 = dao;
        data2 = abi.encodeCall(IMoloch.setAllowance, (address(this), tokenB, amountB));

        // 3. lpSeed.configure(...)
        target3 = address(this);
        data3 = abi.encodeCall(
            this.configure, (tokenA, amountA, tokenB, amountB, deadline, shareSale, minSupply)
        );
    }
}

function balanceOf(address token, address account) view returns (uint256 amount) {
    assembly ("memory-safe") {
        mstore(0x14, account)
        mstore(0x00, 0x70a08231000000000000000000000000)
        amount := mul(
            mload(0x20),
            and(gt(returndatasize(), 0x1f), staticcall(gas(), token, 0x10, 0x24, 0x20, 0x20))
        )
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

/// @dev Ensures approval to spender is sufficient (>= type(uint128).max threshold).
///      Works with USDT-style tokens because the first approval starts from 0,
///      and subsequent calls skip the branch since allowance stays above threshold.
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
