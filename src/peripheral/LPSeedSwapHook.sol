// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @dev Minimal ZAMM interface for LP, swap, and pool state operations.
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
}

/// @dev Minimal ShareSale interface for checking remaining allowance.
interface IShareSale {
    function sales(address dao)
        external
        view
        returns (address token, address payToken, uint40 deadline, uint256 price);
}

/// @dev ZAMM singleton address.
IZAMM constant ZAMM = IZAMM(0x000000000000040470635EB91b7CE4D132D616eD);

/// @dev Hook encoding flag — only beforeAction is used (afterAction is not registered).
uint256 constant FLAG_BEFORE = 1 << 255;

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
///     - minSupply:   seed only after DAO's tokenB balance drops to this threshold
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
///     lpSeed.setFee(feeBps)         // update LP swap fee for the pool
///     lpSeed.setLaunchFee(bps, t)   // set launch premium that decays to feeBps
///     lpSeed.setDaoFee(...)         // set DAO revenue fee on routed swaps
///     lpSeed.setBeneficiary(addr)   // update fee beneficiary
contract LPSeedSwapHook {
    error NotReady();
    error Slippage();
    error NotHooked();
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
    event DaoFeeUpdated(address indexed dao, address beneficiary, uint16 buyBps, uint16 sellBps);
    event BeneficiaryUpdated(address indexed dao, address beneficiary);

    struct SeedConfig {
        address tokenA; // first token (ERC20, or address(0) for ETH)
        address tokenB; // second token (ERC20, must be nonzero)
        uint128 amountA; // amount of tokenA to seed
        uint128 amountB; // amount of tokenB to seed
        uint16 feeBps; // target swap fee (0 = DEFAULT_FEE_BPS)
        uint16 launchBps; // initial fee post-seed, decays to feeBps (0 = no launch premium)
        uint40 deadline; // seed only after this timestamp (0 = no time gate)
        uint40 decayPeriod; // seconds to decay from launchBps to feeBps (0 = instant target)
        address shareSale; // if set, seed only after this ShareSale's allowance is spent
        uint128 minSupply; // if set, seed only after DAO's tokenB balance <= minSupply
        uint128 tokenBSnapshot; // tokenB balance at configure time (griefing resistance for minSupply)
        uint40 seeded; // 0 = not seeded, else block.timestamp when seeded
        address mintTokenA; // if set, use this for spendAllowance instead of tokenA (sentinel mint path)
        address mintTokenB; // if set, use this for spendAllowance instead of tokenB (sentinel mint path)
    }

    /// @notice DAO fee config for routed swaps. Separate from seed config so fees
    ///         can be updated independently. When beneficiary != 0, swaps must route
    ///         through this contract's swapExactIn/swapExactOut.
    struct DaoFeeConfig {
        address beneficiary; // fee recipient (address(0) = disabled, allows direct ZAMM swaps)
        uint16 buyBps; // fee bps when zeroForOne (token0 → token1)
        uint16 sellBps; // fee bps when !zeroForOne (token1 → token0)
        bool buyOnInput; // true = buy fee on input (token0), false = on output (token1)
        bool sellOnInput; // true = sell fee on input (token1), false = on output (token0)
    }

    /// @dev Keyed by DAO address. Set via configure() called by the DAO itself.
    mapping(address dao => SeedConfig) public seeds;

    /// @dev DAO fee config, keyed by DAO address. Set via setDaoFee().
    mapping(address dao => DaoFeeConfig) public daoFees;

    /// @dev Reverse mapping: poolId → DAO address. Set during configure() and seed().
    mapping(uint256 poolId => address dao) public poolDAO;

    /// @dev Transient storage slot for seeding bypass flag.
    ///      Signals to beforeAction that addLiquidity is from seed(), not external.
    uint256 constant SEEDING_SLOT = 0x4c505365656453696e676c65746f6e;

    /// @notice Configure with default fee (backwards-compatible with SafeSummoner).
    function configure(
        address tokenA,
        uint128 amountA,
        address tokenB,
        uint128 amountB,
        uint40 deadline,
        address shareSale,
        uint128 minSupply
    ) public {
        configure(tokenA, amountA, tokenB, amountB, 0, deadline, shareSale, minSupply);
    }

    /// @notice Configure LP seed parameters. Must be called by the DAO (e.g. in initCalls).
    /// @param tokenA     First token (address(0) = ETH)
    /// @param amountA    Amount of tokenA to seed
    /// @param tokenB     Second token (must be nonzero ERC20)
    /// @param amountB    Amount of tokenB to seed
    /// @param feeBps     Swap fee in basis points (0 = DEFAULT_FEE_BPS, max 10_000)
    /// @param deadline   Seed only after this timestamp (0 = no time gate)
    /// @param shareSale  ShareSale address to check for sale completion (address(0) = no check)
    /// @param minSupply  Seed only after DAO's tokenB balance <= this (0 = no check)
    function configure(
        address tokenA,
        uint128 amountA,
        address tokenB,
        uint128 amountB,
        uint16 feeBps,
        uint40 deadline,
        address shareSale,
        uint128 minSupply
    ) public {
        configure(
            tokenA,
            amountA,
            tokenB,
            amountB,
            feeBps,
            deadline,
            shareSale,
            minSupply,
            address(0),
            address(0)
        );
    }

    /// @notice Configure LP seed with sentinel mint tokens for mint-on-spend via Moloch allowance.
    /// @dev When mintTokenA/B are set, seed() calls spendAllowance with the sentinel address
    ///      instead of the real ERC20, triggering Moloch's _payout to mint tokens to this contract.
    ///      Use address(dao) for shares sentinel, address(1007) for loot sentinel.
    ///      tokenA/tokenB must still be the real ERC20 addresses (used for pool key and ZAMM).
    /// @param mintTokenA Sentinel for spendAllowance on tokenA side (address(0) = use tokenA directly)
    /// @param mintTokenB Sentinel for spendAllowance on tokenB side (address(0) = use tokenB directly)
    function configure(
        address tokenA,
        uint128 amountA,
        address tokenB,
        uint128 amountB,
        uint16 feeBps,
        uint40 deadline,
        address shareSale,
        uint128 minSupply,
        address mintTokenA,
        address mintTokenB
    ) public {
        if (amountA == 0 || amountB == 0 || tokenB == address(0)) {
            revert InvalidParams();
        }
        if (tokenA == tokenB) revert InvalidParams();
        if (feeBps > 10_000) revert InvalidParams();
        if (seeds[msg.sender].seeded != 0) revert AlreadySeeded();

        // Clean up stale poolDAO entry if reconfiguring with different tokens
        {
            SeedConfig storage old = seeds[msg.sender];
            if (old.amountA != 0 && (old.tokenA != tokenA || old.tokenB != tokenB)) {
                (address ot0, address ot1) =
                    old.tokenA < old.tokenB ? (old.tokenA, old.tokenB) : (old.tokenB, old.tokenA);
                IZAMM.PoolKey memory oldKey = IZAMM.PoolKey({
                    id0: 0, id1: 0, token0: ot0, token1: ot1, feeOrHook: hookFeeOrHook()
                });
                delete poolDAO[uint256(keccak256(abi.encode(oldKey)))];
            }
        }

        seeds[msg.sender] = SeedConfig({
            tokenA: tokenA,
            tokenB: tokenB,
            amountA: amountA,
            amountB: amountB,
            feeBps: feeBps,
            launchBps: 0,
            deadline: deadline,
            decayPeriod: 0,
            shareSale: shareSale,
            minSupply: minSupply,
            tokenBSnapshot: minSupply != 0 ? uint128(balanceOf(tokenB, msg.sender)) : 0,
            seeded: 0,
            mintTokenA: mintTokenA,
            mintTokenB: mintTokenB
        });

        // Reserve pool ID at configure time so beforeAction blocks
        // frontrun addLiquidity before seed() runs.
        (address t0, address t1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        IZAMM.PoolKey memory key =
            IZAMM.PoolKey({id0: 0, id1: 0, token0: t0, token1: t1, feeOrHook: hookFeeOrHook()});
        uint256 poolId = uint256(keccak256(abi.encode(key)));
        // Prevent overwriting a pool already claimed by a different DAO
        address existing = poolDAO[poolId];
        if (existing != address(0) && existing != msg.sender) {
            revert Unauthorized();
        }
        poolDAO[poolId] = msg.sender;

        emit Configured(msg.sender, tokenA, amountA, tokenB, amountB);
    }

    /// @notice Seed ZAMM liquidity. Permissionless — anyone can trigger once conditions are met.
    ///         LP shares go to the DAO. One-shot: reverts if already seeded.
    /// @param dao The DAO to seed liquidity for
    function seed(address dao) public returns (uint256 liquidity) {
        SeedConfig storage cfg = seeds[dao];
        if (cfg.amountA == 0) revert NotConfigured();
        if (cfg.seeded != 0) revert AlreadySeeded();

        // Check gating conditions
        if (!_isReady(dao, cfg)) revert NotReady();

        // Mark seeded before external calls (CEI)
        cfg.seeded = uint40(block.timestamp);

        uint128 amtA = cfg.amountA;
        uint128 amtB = cfg.amountB;
        address tokenA = cfg.tokenA;
        address tokenB = cfg.tokenB;

        // Treasury clamping: cap seed amounts to what the DAO actually has.
        // Prevents revert if sale undersold, members ragequit, or treasury was spent.
        // Skip for mint sentinel paths — tokens are minted on-demand by spendAllowance.
        if (cfg.mintTokenA == address(0)) {
            uint256 balA = tokenA == address(0) ? dao.balance : balanceOf(tokenA, dao);
            if (amtA > balA) amtA = uint128(balA);
        }
        if (cfg.mintTokenB == address(0)) {
            uint256 balB = tokenB == address(0) ? dao.balance : balanceOf(tokenB, dao);
            if (amtB > balB) amtB = uint128(balB);
        }

        // Abort if treasury clamping zeroed either side — nothing to seed
        if (amtA == 0 || amtB == 0) revert NotReady();

        // Arb protection: if gated by a ShareSale, clamp LP ratio so shares are not
        // underpriced vs what buyers paid. Excess shares are refunded to the DAO.
        if (cfg.shareSale != address(0)) {
            (, address payToken,, uint256 salePrice) = IShareSale(cfg.shareSale).sales(dao);
            if (salePrice != 0) {
                // Determine which LP side is the pay token and which is the shares token.
                bool aIsPay = (payToken == address(0)) ? tokenA == address(0) : tokenA == payToken;
                uint256 payAmt = aIsPay ? uint256(amtA) : uint256(amtB);
                // Max shares the pay side can support at sale price
                uint256 maxShares = payAmt * 1e18 / salePrice;
                if (aIsPay) {
                    if (amtB > maxShares) amtB = uint128(maxShares);
                } else {
                    if (amtA > maxShares) amtA = uint128(maxShares);
                }
            }
        }

        // Abort if arb clamping zeroed either side
        if (amtA == 0 || amtB == 0) revert NotReady();

        // Pull tokens from DAO via allowance. When mintToken is set, spendAllowance
        // uses the Moloch sentinel (e.g. address(dao) for shares) to mint-on-spend
        // instead of transferring pre-minted tokens.
        IMoloch(dao).spendAllowance(cfg.mintTokenA != address(0) ? cfg.mintTokenA : tokenA, amtA);
        IMoloch(dao).spendAllowance(cfg.mintTokenB != address(0) ? cfg.mintTokenB : tokenB, amtB);

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

        // Re-register poolId → dao. Revert if already claimed by a different seeded DAO.
        uint256 poolId = uint256(keccak256(abi.encode(key)));
        address existing = poolDAO[poolId];
        if (existing != address(0) && existing != dao && seeds[existing].seeded != 0) {
            revert AlreadySeeded();
        }
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
        if (cfg.amountA == 0 || cfg.seeded != 0) return false;
        return _isReady(dao, cfg);
    }

    /// @notice Cancel the seed config. Only callable by the DAO.
    ///         DAO should reclaim allowances separately via setAllowance(lpSeed, token, 0).
    function cancel() public {
        SeedConfig storage cfg = seeds[msg.sender];
        if (cfg.amountA == 0) revert NotConfigured();
        if (cfg.seeded != 0) revert AlreadySeeded();

        // Clean up poolDAO so this pool key isn't permanently blocked
        (address t0, address t1) =
            cfg.tokenA < cfg.tokenB ? (cfg.tokenA, cfg.tokenB) : (cfg.tokenB, cfg.tokenA);
        IZAMM.PoolKey memory key =
            IZAMM.PoolKey({id0: 0, id1: 0, token0: t0, token1: t1, feeOrHook: hookFeeOrHook()});
        uint256 poolId = uint256(keccak256(abi.encode(key)));
        if (poolDAO[poolId] != msg.sender) revert Unauthorized();
        delete poolDAO[poolId];

        delete daoFees[msg.sender];
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
        // Block fee changes during active launch decay to prevent discontinuous fee jumps
        if (cfg.launchBps != 0 && cfg.decayPeriod != 0 && cfg.seeded != 0) {
            if (block.timestamp < cfg.seeded + cfg.decayPeriod) revert NotReady();
        }
        uint16 old = cfg.feeBps;
        cfg.feeBps = newFeeBps;
        emit FeeUpdated(msg.sender, old, newFeeBps);
    }

    /// @notice Set launch fee premium. Fee starts at launchBps post-seed and linearly
    ///         decays to feeBps over decayPeriod seconds. Must be called before seed().
    /// @param launchBps   Initial fee in basis points (0 = no launch premium, max 10_000)
    /// @param decayPeriod Seconds to decay from launchBps to feeBps (0 = instant target)
    function setLaunchFee(uint16 launchBps, uint40 decayPeriod) public {
        if (launchBps > 10_000) revert InvalidParams();
        if (launchBps != 0 && decayPeriod == 0) revert InvalidParams();
        SeedConfig storage cfg = seeds[msg.sender];
        if (cfg.amountA == 0) revert NotConfigured();
        if (cfg.seeded != 0) revert AlreadySeeded();
        cfg.launchBps = launchBps;
        cfg.decayPeriod = decayPeriod;
    }

    /// @notice Set DAO revenue fee. When beneficiary is set, swaps must route through
    ///         this contract's swapExactIn/swapExactOut — direct ZAMM swaps are blocked.
    /// @param beneficiary  Recipient of fee revenue (address(0) disables routing enforcement)
    /// @param buyBps       Fee bps on zeroForOne swaps (token0 → token1)
    /// @param sellBps      Fee bps on !zeroForOne swaps (token1 → token0)
    /// @param buyOnInput   true = buy fee deducted from input (token0), false = from output (token1)
    /// @param sellOnInput  true = sell fee deducted from input (token1), false = from output (token0)
    function setDaoFee(
        address beneficiary,
        uint16 buyBps,
        uint16 sellBps,
        bool buyOnInput,
        bool sellOnInput
    ) public {
        if (buyBps >= 10_000 || sellBps >= 10_000) revert InvalidParams();
        // Require beneficiary when rates are set, and rates when beneficiary is set
        if (beneficiary == address(0) && (buyBps | sellBps) != 0) revert InvalidParams();
        if (beneficiary != address(0) && (buyBps | sellBps) == 0) revert InvalidParams();
        if (seeds[msg.sender].amountA == 0) revert NotConfigured();
        daoFees[msg.sender] = DaoFeeConfig(beneficiary, buyBps, sellBps, buyOnInput, sellOnInput);
        emit DaoFeeUpdated(msg.sender, beneficiary, buyBps, sellBps);
    }

    /// @notice Update fee beneficiary without changing fee rates. Only callable by DAO.
    ///         Setting to address(0) disables routing enforcement (allows direct ZAMM swaps).
    ///         Setting to non-zero requires existing fee rates (set via setDaoFee first).
    function setBeneficiary(address beneficiary) public {
        if (seeds[msg.sender].amountA == 0) revert NotConfigured();
        DaoFeeConfig storage f = daoFees[msg.sender];
        if (beneficiary != address(0) && (f.buyBps | f.sellBps) == 0) revert InvalidParams();
        f.beneficiary = beneficiary;
        emit BeneficiaryUpdated(msg.sender, beneficiary);
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
    function beforeAction(bytes4 sig, uint256 poolId, address sender, bytes calldata)
        public
        payable
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
            if (dao != address(0) && seeds[dao].seeded == 0) {
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
        SeedConfig storage cfg = seeds[dao];
        if (cfg.seeded == 0) revert NotReady();

        // If DAO fee is active, swaps must route through this contract
        if (daoFees[dao].beneficiary != address(0)) {
            if (sig == IZAMM.swap.selector) revert NotHooked();
            if (sender != address(this)) revert NotHooked();
        }

        return effectiveFee(dao);
    }

    // ── View Helpers (quoting) ─────────────────────────────────

    /// @notice Current effective ZAMM pool fee for a DAO's pool, in basis points.
    ///         Accounts for launch fee decay. Returns 0 if not seeded.
    function effectiveFee(address dao) public view returns (uint256 feeBps) {
        SeedConfig storage cfg = seeds[dao];
        if (cfg.seeded == 0) return 0;

        uint256 target = cfg.feeBps == 0 ? DEFAULT_FEE_BPS : cfg.feeBps;
        uint256 launch = cfg.launchBps;
        if (launch != 0) {
            uint256 decay = cfg.decayPeriod;
            if (decay != 0) {
                uint256 elapsed = block.timestamp - cfg.seeded;
                if (elapsed < decay) {
                    if (launch >= target) {
                        return launch - (launch - target) * elapsed / decay;
                    } else {
                        return launch + (target - launch) * elapsed / decay;
                    }
                }
            }
        }
        return target;
    }

    /// @notice Derive the ZAMM PoolKey and pool ID for a DAO's configured pair.
    ///         Reverts if the DAO has no seed config.
    function poolKeyOf(address dao) public view returns (IZAMM.PoolKey memory key, uint256 poolId) {
        SeedConfig storage cfg = seeds[dao];
        if (cfg.amountA == 0) revert NotConfigured();
        (address t0, address t1) =
            cfg.tokenA < cfg.tokenB ? (cfg.tokenA, cfg.tokenB) : (cfg.tokenB, cfg.tokenA);
        key = IZAMM.PoolKey({id0: 0, id1: 0, token0: t0, token1: t1, feeOrHook: hookFeeOrHook()});
        poolId = uint256(keccak256(abi.encode(key)));
    }

    /// @notice One-call swap quoter. Returns the pool key, all fees, and routing info.
    /// @param dao         The DAO whose pool you're quoting
    /// @param zeroForOne  Swap direction (true = token0 → token1)
    /// @return key          ZAMM PoolKey (pass directly to swap functions)
    /// @return poolFeeBps   Current ZAMM pool fee (with launch decay, 0 if not seeded)
    /// @return daoFeeBps    DAO revenue fee for this direction (0 if disabled)
    /// @return feeOnInput   Whether DAO fee is deducted from input (true) or output (false)
    /// @return beneficiary  Fee recipient (address(0) = swap via ZAMM directly, non-zero = route via this contract)
    function quoteSwap(address dao, bool zeroForOne)
        public
        view
        returns (
            IZAMM.PoolKey memory key,
            uint256 poolFeeBps,
            uint256 daoFeeBps,
            bool feeOnInput,
            address beneficiary
        )
    {
        (key,) = poolKeyOf(dao);
        poolFeeBps = effectiveFee(dao);
        DaoFeeConfig storage fee = daoFees[dao];
        beneficiary = fee.beneficiary;
        if (beneficiary != address(0)) {
            daoFeeBps = zeroForOne ? fee.buyBps : fee.sellBps;
            feeOnInput = zeroForOne ? fee.buyOnInput : fee.sellOnInput;
        }
    }

    /// @notice Quote exact-input swap: given `amountIn`, returns net `amountOut` after all fees.
    /// @param dao         The DAO whose pool you're quoting
    /// @param amountIn    Input amount (gross, before any DAO fee)
    /// @param zeroForOne  Swap direction (true = token0 → token1)
    /// @return amountOut  Net output amount the user receives
    /// @return daoTax     DAO fee amount deducted (in input or output token depending on config)
    function quoteExactIn(address dao, uint256 amountIn, bool zeroForOne)
        public
        view
        returns (uint256 amountOut, uint256 daoTax)
    {
        (, uint256 poolId) = poolKeyOf(dao);
        uint256 poolFee = effectiveFee(dao);
        (uint112 r0, uint112 r1,,,,,) = ZAMM.pools(poolId);
        (uint256 rIn, uint256 rOut) =
            zeroForOne ? (uint256(r0), uint256(r1)) : (uint256(r1), uint256(r0));

        DaoFeeConfig storage fee = daoFees[dao];
        uint256 bps = zeroForOne ? fee.buyBps : fee.sellBps;
        bool onInput = zeroForOne ? fee.buyOnInput : fee.sellOnInput;

        if (fee.beneficiary != address(0) && bps != 0) {
            if (onInput) {
                daoTax = (amountIn * bps) / 10_000;
                uint256 net = amountIn - daoTax;
                amountOut = _getAmountOut(net, rIn, rOut, poolFee);
            } else {
                uint256 gross = _getAmountOut(amountIn, rIn, rOut, poolFee);
                daoTax = (gross * bps) / 10_000;
                amountOut = gross - daoTax;
            }
        } else {
            amountOut = _getAmountOut(amountIn, rIn, rOut, poolFee);
        }
    }

    /// @notice Quote exact-output swap: given desired net `amountOut`, returns gross `amountIn` needed.
    /// @param dao         The DAO whose pool you're quoting
    /// @param amountOut   Desired net output amount the user receives
    /// @param zeroForOne  Swap direction (true = token0 → token1)
    /// @return amountIn   Gross input amount required (including any DAO fee)
    /// @return daoTax     DAO fee amount deducted (in input or output token depending on config)
    function quoteExactOut(address dao, uint256 amountOut, bool zeroForOne)
        public
        view
        returns (uint256 amountIn, uint256 daoTax)
    {
        (, uint256 poolId) = poolKeyOf(dao);
        uint256 poolFee = effectiveFee(dao);
        (uint112 r0, uint112 r1,,,,,) = ZAMM.pools(poolId);
        (uint256 rIn, uint256 rOut) =
            zeroForOne ? (uint256(r0), uint256(r1)) : (uint256(r1), uint256(r0));

        DaoFeeConfig storage fee = daoFees[dao];
        uint256 bps = zeroForOne ? fee.buyBps : fee.sellBps;
        bool onInput = zeroForOne ? fee.buyOnInput : fee.sellOnInput;

        if (fee.beneficiary != address(0) && bps != 0) {
            if (onInput) {
                uint256 net = _getAmountIn(amountOut, rIn, rOut, poolFee);
                daoTax = (net * bps + (10_000 - bps) - 1) / (10_000 - bps);
                amountIn = net + daoTax;
            } else {
                uint256 gross = bps != 0
                    ? (amountOut * 10_000 + (10_000 - bps) - 1) / (10_000 - bps)
                    : amountOut;
                daoTax = gross - amountOut;
                amountIn = _getAmountIn(gross, rIn, rOut, poolFee);
            }
        } else {
            amountIn = _getAmountIn(amountOut, rIn, rOut, poolFee);
        }
    }

    /// @dev Constant-product getAmountOut (mirrors ZAMM._getAmountOut).
    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut, uint256 swapFee)
        internal
        pure
        returns (uint256)
    {
        uint256 amountInWithFee = amountIn * (10_000 - swapFee);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 10_000) + amountInWithFee;
        return numerator / denominator;
    }

    /// @dev Constant-product getAmountIn (mirrors ZAMM._getAmountIn).
    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut, uint256 swapFee)
        internal
        pure
        returns (uint256)
    {
        uint256 numerator = reserveIn * amountOut * 10_000;
        uint256 denominator = (reserveOut - amountOut) * (10_000 - swapFee);
        return (numerator / denominator) + 1;
    }

    // ── Routed Swaps (DAO fee) ─────────────────────────────────

    /// @dev Reentrancy guard for swap routing.
    uint256 constant SWAP_LOCK_SLOT = 0x4c5053656564537761704c6f636b;

    modifier lock() {
        assembly ("memory-safe") {
            if tload(SWAP_LOCK_SLOT) {
                mstore(0x00, 0xab143c06)
                revert(0x1c, 0x04)
            }
            tstore(SWAP_LOCK_SLOT, address())
        }
        _;
        assembly ("memory-safe") {
            tstore(SWAP_LOCK_SLOT, 0)
        }
    }

    /// @notice Swap exact input through ZAMM with DAO fee.
    ///         Required for pools with an active DAO fee (direct ZAMM swaps are blocked).
    /// @dev When feeOnInput: fee deducted from input before ZAMM swap, amountOutMin checked by ZAMM.
    ///      When feeOnOutput: fee deducted from ZAMM output, amountOutMin checked against net received.
    function swapExactIn(
        IZAMM.PoolKey calldata poolKey,
        uint256 amountIn,
        uint256 amountOutMin,
        bool zeroForOne,
        address to,
        uint256 deadline
    ) public payable lock returns (uint256 amountOut) {
        uint256 poolId = uint256(keccak256(abi.encode(poolKey)));
        DaoFeeConfig storage fee = daoFees[poolDAO[poolId]];
        uint256 bps = zeroForOne ? fee.buyBps : fee.sellBps;
        address ben = fee.beneficiary;
        bool onInput = zeroForOne ? fee.buyOnInput : fee.sellOnInput;

        address tokenIn = zeroForOne ? poolKey.token0 : poolKey.token1;
        address tokenOut = zeroForOne ? poolKey.token1 : poolKey.token0;

        // For ETH input, msg.value IS the amount; for ERC20 input, no ETH allowed
        if (tokenIn == address(0)) {
            amountIn = msg.value;
        } else {
            if (msg.value != 0) revert InvalidParams();
        }

        if (onInput) {
            // ── Fee on input ────────────────────────────────────────
            if (tokenIn == address(0)) {
                uint256 tax = (amountIn * bps) / 10_000;
                uint256 net = amountIn - tax;
                if (tax != 0) safeTransferETH(ben, tax);
                amountOut = ZAMM.swapExactIn{value: net}(
                    poolKey, net, amountOutMin, zeroForOne, to, deadline
                );
            } else {
                safeTransferFrom(tokenIn, address(this), amountIn);
                uint256 tax = (amountIn * bps) / 10_000;
                uint256 net = amountIn - tax;
                if (tax != 0) safeTransfer(tokenIn, ben, tax);
                ensureApproval(tokenIn, address(ZAMM));
                amountOut = ZAMM.swapExactIn(poolKey, net, amountOutMin, zeroForOne, to, deadline);
            }
        } else {
            // ── Fee on output ───────────────────────────────────────
            if (tokenIn == address(0)) {
                amountOut = ZAMM.swapExactIn{value: amountIn}(
                    poolKey, amountIn, 0, zeroForOne, address(this), deadline
                );
            } else {
                safeTransferFrom(tokenIn, address(this), amountIn);
                ensureApproval(tokenIn, address(ZAMM));
                amountOut =
                    ZAMM.swapExactIn(poolKey, amountIn, 0, zeroForOne, address(this), deadline);
            }
            uint256 tax = (amountOut * bps) / 10_000;
            uint256 net = amountOut - tax;
            if (net < amountOutMin) revert Slippage();
            if (tokenOut == address(0)) {
                if (tax != 0) safeTransferETH(ben, tax);
                safeTransferETH(to, net);
            } else {
                if (tax != 0) safeTransfer(tokenOut, ben, tax);
                safeTransfer(tokenOut, to, net);
            }
            amountOut = net;
        }
    }

    /// @notice Swap exact output through ZAMM with DAO fee.
    ///         `amountOut` is the net amount `to` receives after fees.
    function swapExactOut(
        IZAMM.PoolKey calldata poolKey,
        uint256 amountOut,
        uint256 amountInMax,
        bool zeroForOne,
        address to,
        uint256 deadline
    ) public payable lock returns (uint256 amountIn) {
        uint256 poolId = uint256(keccak256(abi.encode(poolKey)));
        DaoFeeConfig storage fee = daoFees[poolDAO[poolId]];
        uint256 bps = zeroForOne ? fee.buyBps : fee.sellBps;
        address ben = fee.beneficiary;
        bool onInput = zeroForOne ? fee.buyOnInput : fee.sellOnInput;

        address tokenIn = zeroForOne ? poolKey.token0 : poolKey.token1;
        address tokenOut = zeroForOne ? poolKey.token1 : poolKey.token0;

        // For ETH input, msg.value IS the max; for ERC20 input, no ETH allowed
        if (tokenIn == address(0)) {
            amountInMax = msg.value;
        } else {
            if (msg.value != 0) revert InvalidParams();
        }

        if (onInput) {
            // ── Fee on input ────────────────────────────────────────
            if (tokenIn == address(0)) {
                // Derive max net ETH for ZAMM after tax
                uint256 netMax = (amountInMax * (10_000 - bps)) / 10_000;
                amountIn = ZAMM.swapExactOut{value: netMax}(
                    poolKey, amountOut, netMax, zeroForOne, to, deadline
                );
                uint256 tax = (amountIn * bps) / (10_000 - bps);
                uint256 spent = amountIn + tax;
                if (tax != 0) safeTransferETH(ben, tax);
                uint256 refund = amountInMax - spent;
                if (refund != 0) safeTransferETH(msg.sender, refund);
                amountIn = spent; // return gross to caller
            } else {
                safeTransferFrom(tokenIn, address(this), amountInMax);
                ensureApproval(tokenIn, address(ZAMM));
                uint256 netMax = (amountInMax * (10_000 - bps)) / 10_000;
                amountIn = ZAMM.swapExactOut(poolKey, amountOut, netMax, zeroForOne, to, deadline);
                uint256 tax = (amountIn * bps) / (10_000 - bps);
                if (tax != 0) safeTransfer(tokenIn, ben, tax);
                uint256 refund = amountInMax - amountIn - tax;
                if (refund != 0) safeTransfer(tokenIn, msg.sender, refund);
                amountIn = amountIn + tax; // return gross to caller
            }
        } else {
            // ── Fee on output ───────────────────────────────────────
            // Gross output from ZAMM to give user amountOut net
            uint256 gross =
                bps != 0 ? (amountOut * 10_000 + (10_000 - bps) - 1) / (10_000 - bps) : amountOut;

            if (tokenIn == address(0)) {
                amountIn = ZAMM.swapExactOut{value: amountInMax}(
                    poolKey, gross, amountInMax, zeroForOne, address(this), deadline
                );
                uint256 refund = amountInMax - amountIn;
                if (refund != 0) safeTransferETH(msg.sender, refund);
            } else {
                safeTransferFrom(tokenIn, address(this), amountInMax);
                ensureApproval(tokenIn, address(ZAMM));
                amountIn = ZAMM.swapExactOut(
                    poolKey, gross, amountInMax, zeroForOne, address(this), deadline
                );
                uint256 refund = amountInMax - amountIn;
                if (refund != 0) safeTransfer(tokenIn, msg.sender, refund);
            }

            uint256 tax = gross - amountOut;
            if (tokenOut == address(0)) {
                if (tax != 0) safeTransferETH(ben, tax);
                safeTransferETH(to, amountOut);
            } else {
                if (tax != 0) safeTransfer(tokenOut, ben, tax);
                safeTransfer(tokenOut, to, amountOut);
            }
        }
    }

    // ── Internal ─────────────────────────────────────────────────

    function _isReady(address dao, SeedConfig memory cfg) internal view returns (bool) {
        // Time gate
        if (cfg.deadline != 0 && block.timestamp <= cfg.deadline) return false;

        // ShareSale completion gate: sale allowance must be fully spent (== 0),
        // OR a deadline has passed (handles dust / unsold remainder).
        // Checks: 1) sale's own deadline, then 2) LPSeed's cfg.deadline as backstop.
        if (cfg.shareSale != address(0)) {
            (address saleToken,, uint40 saleDeadline,) = IShareSale(cfg.shareSale).sales(dao);
            if (saleToken == address(0)) return false; // sale not configured yet
            uint256 remaining = IMoloch(dao).allowance(saleToken, cfg.shareSale);
            if (remaining != 0) {
                // Bypass dust if sale deadline OR LPSeed deadline has passed
                bool salePast = saleDeadline != 0 && block.timestamp > saleDeadline;
                bool seedPast = cfg.deadline != 0 && block.timestamp > cfg.deadline;
                if (!salePast && !seedPast) return false;
            }
        }

        // Supply gate: DAO's tokenB balance must be at or below threshold.
        // Cap at snapshot to ignore unsolicited deposits (griefing resistance).
        if (cfg.minSupply != 0) {
            uint256 daoBal = balanceOf(cfg.tokenB, dao);
            if (cfg.tokenBSnapshot != 0 && daoBal > cfg.tokenBSnapshot) {
                daoBal = cfg.tokenBSnapshot;
            }
            if (daoBal > cfg.minSupply) return false;
        }

        return true;
    }

    /// @dev Accept ETH from DAO via spendAllowance and from ZAMM during fee-on-output swaps.
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                          INIT CALL HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Generate initCalls for setting up an LP seed with mint-on-spend.
    /// @dev Returns 3 calls: setAllowance(tokenA), setAllowance(tokenB), configure().
    ///      When mintTokenA/B are set, allowances use the Moloch sentinel (e.g. address(dao)
    ///      for shares) so spendAllowance mints tokens directly instead of requiring premint.
    /// @param mintTokenA Moloch sentinel for tokenA (address(0) = regular transfer, address(dao) = mint shares)
    /// @param mintTokenB Moloch sentinel for tokenB (address(0) = regular transfer, address(dao) = mint shares)
    function seedInitCalls(
        address dao,
        address tokenA,
        uint128 amountA,
        address tokenB,
        uint128 amountB,
        uint16 feeBps,
        uint40 deadline,
        address shareSale,
        uint128 minSupply,
        address mintTokenA,
        address mintTokenB
    ) public view returns (address[3] memory targets, bytes[3] memory data) {
        // 0. dao.setAllowance(lpSeed, allowTokenA, amountA)
        targets[0] = dao;
        data[0] = abi.encodeCall(
            IMoloch.setAllowance,
            (address(this), mintTokenA != address(0) ? mintTokenA : tokenA, amountA)
        );

        // 1. dao.setAllowance(lpSeed, allowTokenB, amountB)
        targets[1] = dao;
        data[1] = abi.encodeCall(
            IMoloch.setAllowance,
            (address(this), mintTokenB != address(0) ? mintTokenB : tokenB, amountB)
        );

        // 2. lpSeed.configure(...)
        targets[2] = address(this);
        data[2] = abi.encodeWithSignature(
            "configure(address,uint128,address,uint128,uint16,uint40,address,uint128,address,address)",
            tokenA,
            amountA,
            tokenB,
            amountB,
            feeBps,
            deadline,
            shareSale,
            minSupply,
            mintTokenA,
            mintTokenB
        );
    }

    /// @notice Generate an initCall for setting the DAO revenue fee.
    function daoFeeInitCall(
        address beneficiary,
        uint16 buyBps,
        uint16 sellBps,
        bool buyOnInput,
        bool sellOnInput
    ) public view returns (address target, uint256 value, bytes memory data) {
        target = address(this);
        value = 0;
        data =
            abi.encodeCall(this.setDaoFee, (beneficiary, buyBps, sellBps, buyOnInput, sellOnInput));
    }

    /// @notice Generate an initCall for setting the launch fee premium.
    ///         Include after seedInitCalls in the DAO's initCalls array.
    function launchFeeInitCall(uint16 launchBps, uint40 decayPeriod)
        public
        view
        returns (address target, uint256 value, bytes memory data)
    {
        target = address(this);
        value = 0;
        data = abi.encodeCall(this.setLaunchFee, (launchBps, decayPeriod));
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
