// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

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
}

/// @dev Minimal Moloch interface for tap mechanism.
interface IMoloch {
    function spendAllowance(address token, uint256 amount) external;
    function setAllowance(address spender, address token, uint256 amount) external;
    function allowance(address token, address spender) external view returns (uint256);
    function setTransfersLocked(bool sharesLocked, bool lootLocked) external;
}

/// @dev Minimal Shares/Loot interface for minting and approval.
interface ISharesLoot {
    function mintFromMoloch(address to, uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @dev Summoner call struct.
struct Call {
    address target;
    uint256 value;
    bytes data;
}

/// @dev Minimal Summoner interface.
interface ISummoner {
    function summon(
        string calldata orgName,
        string calldata orgSymbol,
        string calldata orgURI,
        uint16 quorumBps,
        bool ragequittable,
        address renderer,
        bytes32 salt,
        address[] calldata initHolders,
        uint256[] calldata initShares,
        Call[] calldata initCalls
    ) external payable returns (address);
}

/// @dev ZAMM singleton address.
IZAMM constant ZAMM = IZAMM(0x000000000000040470635EB91b7CE4D132D616eD);

/// @notice DAO-driven OTC sale contract with optional LP initialization:
/// - DAO calls setSale() to define a fixed price.
/// - Users can:
///     * buy()        : exact-in (pay exact tribTkn, get >= minBuyAmt forTkn)
///     * buyExactOut(): exact-out (get exact buyAmt forTkn, pay <= maxPayAmt tribTkn)
/// - DAO caps distribution by approving this contract to spend forTkn (ERC20 approve).
/// - Optional lpBps splits tribute between DAO treasury and ZAMM liquidity.
contract DAICO {
    struct TributeOffer {
        uint256 tribAmt; // base "pay" amount in tribTkn units
        uint256 forAmt; // base "receive" amount in forTkn units
        address forTkn; // ERC20 token being sold by DAO
        uint40 deadline; // unix timestamp after which sale expires (0 = no deadline)
    }

    struct Tap {
        address ops; // beneficiary who can receive tap claims
        address tribTkn; // token being tapped (ETH = address(0), or ERC20)
        uint128 ratePerSec; // smallest-unit/sec (handles 6-dec like USDC)
        uint64 lastClaim; // last claim timestamp
    }

    struct LPConfig {
        uint16 lpBps; // portion of tribTkn to LP (0-10000 bps, 0 = disabled)
        uint16 maxSlipBps; // max slippage for LP adds (default 100 = 1%)
        uint256 feeOrHook; // pool fee in bps or hook address
    }

    /// @dev DAO => payment token (ERC20 or ETH=address(0)) => sale terms
    mapping(address dao => mapping(address tribTkn => TributeOffer)) public sales;

    /// @dev DAO => tap config
    mapping(address dao => Tap) public taps;

    /// @dev DAO => tribTkn => LP config (optional)
    mapping(address dao => mapping(address tribTkn => LPConfig)) public lpConfigs;

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

    event TapOpsUpdated(address indexed dao, address indexed oldOps, address indexed newOps);

    event TapRateUpdated(address indexed dao, uint128 oldRate, uint128 newRate);

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

    error NoTap();
    error NoSale();
    error Expired();
    error BadLPBps();
    error Unauthorized();
    error InvalidParams();
    error NothingToClaim();
    error SlippageExceeded();

    constructor() payable {}

    // --- Reentrancy guard (transient storage) ---

    uint256 constant REENTRANCY_GUARD_SLOT = 0x929eee149b4bd21268;

    modifier nonReentrant() {
        assembly ("memory-safe") {
            if tload(REENTRANCY_GUARD_SLOT) {
                mstore(0x00, 0xab143c06)
                revert(0x1c, 0x04)
            }
            tstore(REENTRANCY_GUARD_SLOT, address())
        }
        _;
        assembly ("memory-safe") {
            tstore(REENTRANCY_GUARD_SLOT, 0)
        }
    }

    // ------------------
    //  DAO: configure sale
    // ------------------

    /// @notice Set or clear a sale for a given payment token.
    /// @param tribTkn  Token buyers pay in (ERC20, or address(0) for ETH).
    /// @param tribAmt  Base pay amount in tribTkn units.
    /// @param forTkn   ERC20 token the DAO is selling (must be nonzero when setting).
    /// @param forAmt   Base receive amount in forTkn units.
    /// @param deadline Unix timestamp after which sale expires (0 = no deadline).
    ///
    /// Examples (off-chain encoding, assuming 18-dec shares):
    ///  - "1 ETH for 1 share":
    ///       tribTkn = ETH (0), tribAmt = 1e18, forTkn = SHARE, forAmt = 1e18
    ///  - "1 ETH for 1,000,000 shares":
    ///       tribTkn = ETH (0), tribAmt = 1e18, forTkn = SHARE, forAmt = 1_000_000e18
    ///  - "100 USDC (6dec) for 1 share (18dec)":
    ///       tribTkn = USDC, tribAmt = 100e6, forTkn = SHARE, forAmt = 1e18
    ///
    /// To TURN OFF a sale for (dao, tribTkn), pass tribAmt == 0 or forAmt == 0.
    function setSale(
        address tribTkn,
        uint256 tribAmt,
        address forTkn,
        uint256 forAmt,
        uint40 deadline
    ) public {
        address dao = msg.sender;

        // Turning sale OFF: any zero side clears it.
        if (tribAmt == 0 || forAmt == 0) {
            delete sales[dao][tribTkn];
            emit SaleSet(dao, tribTkn, 0, address(0), 0, 0);
            return;
        }

        // forTkn must be a real ERC20; ETH only allowed on payment side.
        if (forTkn == address(0)) revert InvalidParams();

        TributeOffer storage offer = sales[dao][tribTkn];
        offer.tribAmt = tribAmt;
        offer.forAmt = forAmt;
        offer.forTkn = forTkn;
        offer.deadline = deadline;

        emit SaleSet(dao, tribTkn, tribAmt, forTkn, forAmt, deadline);
    }

    /// @notice Set up a sale with an associated tap for the ops beneficiary.
    /// @param tribTkn    Payment token (ETH or ERC20 like USDC).
    /// @param tribAmt    Base pay amount.
    /// @param forTkn     Token being sold.
    /// @param forAmt     Base receive amount.
    /// @param deadline   Sale deadline (0 = none).
    /// @param ops        Beneficiary address for tap claims.
    /// @param ratePerSec Rate at which ops can claim tribTkn (smallest units/sec).
    /// @dev The DAO must call Moloch.setAllowance(DAICO, tribTkn, amount) to fund the tap.
    function setSaleWithTap(
        address tribTkn,
        uint256 tribAmt,
        address forTkn,
        uint256 forAmt,
        uint40 deadline,
        address ops,
        uint128 ratePerSec
    ) public {
        setSale(tribTkn, tribAmt, forTkn, forAmt, deadline);

        address dao = msg.sender;

        // Clear tap if rate is 0 or no ops
        if (ratePerSec == 0 || ops == address(0)) {
            delete taps[dao];
            emit TapSet(dao, address(0), tribTkn, 0);
            return;
        }

        taps[dao] = Tap({
            ops: ops, tribTkn: tribTkn, ratePerSec: ratePerSec, lastClaim: uint64(block.timestamp)
        });

        emit TapSet(dao, ops, tribTkn, ratePerSec);
    }

    /// @notice Update the ops beneficiary for an existing tap.
    /// @param newOps New beneficiary address. Setting to address(0) disables claiming.
    /// @dev Only callable by the DAO (msg.sender must be the DAO that set the tap).
    function setTapOps(address newOps) public {
        address dao = msg.sender;
        Tap storage tap = taps[dao];

        if (tap.ratePerSec == 0 && tap.ops == address(0)) revert NoTap();

        address oldOps = tap.ops;
        tap.ops = newOps;

        emit TapOpsUpdated(dao, oldOps, newOps);
    }

    /// @notice Update the tap rate for an existing tap (non-retroactive).
    /// @param newRate New rate in smallest units per second. Setting to 0 freezes the tap.
    /// @dev Only callable by the DAO. Per Vitalik's DAICO: token holders can vote to
    ///      raise the tap (give team more funds) or lower/freeze it (loss of confidence).
    ///      Rate changes are non-retroactive: unclaimed time at old rate is forfeited,
    ///      and new rate applies only from this moment forward.
    function setTapRate(uint128 newRate) public {
        address dao = msg.sender;
        Tap storage tap = taps[dao];

        if (tap.ratePerSec == 0 && tap.ops == address(0)) revert NoTap();

        tap.lastClaim = uint64(block.timestamp);
        uint128 oldRate = tap.ratePerSec;
        tap.ratePerSec = newRate;

        emit TapRateUpdated(dao, oldRate, newRate);
    }

    // ------------------
    //  DAO: configure LP
    // ------------------

    /// @notice Set LP config for a sale. Portion of tribute goes to ZAMM liquidity.
    /// @param tribTkn   Payment token for the sale.
    /// @param lpBps     Basis points of tribute to LP (0-9999, 0 = disabled).
    ///                  NOTE: Buyers receive (10000 - lpBps) / 10000 of the quoted rate.
    ///                  E.g., lpBps=5000 means 50% to LP, buyer gets 50% of tokens.
    /// @param maxSlipBps Max slippage for LP adds (default 100 = 1%).
    /// @param feeOrHook Pool fee in bps or hook address.
    /// @dev If using LP, DAO must also approve DAICO to spend forTkn. LP shares go to DAO.
    function setLPConfig(address tribTkn, uint16 lpBps, uint16 maxSlipBps, uint256 feeOrHook)
        public
    {
        // 100% lpBps leaves nothing for buyer; >100% is invalid
        if (lpBps >= 10_000 || maxSlipBps > 10_000) revert BadLPBps();

        address dao = msg.sender;

        if (lpBps == 0) {
            delete lpConfigs[dao][tribTkn];
            emit LPConfigSet(dao, tribTkn, 0, 0);
            return;
        }

        lpConfigs[dao][tribTkn] = LPConfig({
            lpBps: lpBps, maxSlipBps: maxSlipBps == 0 ? 100 : maxSlipBps, feeOrHook: feeOrHook
        });

        emit LPConfigSet(dao, tribTkn, lpBps, feeOrHook);
    }

    /// @notice Convenience: set sale + LP config in one call.
    function setSaleWithLP(
        address tribTkn,
        uint256 tribAmt,
        address forTkn,
        uint256 forAmt,
        uint40 deadline,
        uint16 lpBps,
        uint16 maxSlipBps,
        uint256 feeOrHook
    ) public {
        setSale(tribTkn, tribAmt, forTkn, forAmt, deadline);
        setLPConfig(tribTkn, lpBps, maxSlipBps, feeOrHook);
    }

    /// @notice Convenience: set sale + LP config + tap in one call.
    function setSaleWithLPAndTap(
        address tribTkn,
        uint256 tribAmt,
        address forTkn,
        uint256 forAmt,
        uint40 deadline,
        uint16 lpBps,
        uint16 maxSlipBps,
        uint256 feeOrHook,
        address ops,
        uint128 ratePerSec
    ) public {
        setSale(tribTkn, tribAmt, forTkn, forAmt, deadline);
        setLPConfig(tribTkn, lpBps, maxSlipBps, feeOrHook);

        address dao = msg.sender;

        // Clear tap if rate is 0 or no ops
        if (ratePerSec == 0 || ops == address(0)) {
            delete taps[dao];
            emit TapSet(dao, address(0), tribTkn, 0);
            return;
        }

        taps[dao] = Tap({
            ops: ops, tribTkn: tribTkn, ratePerSec: ratePerSec, lastClaim: uint64(block.timestamp)
        });

        emit TapSet(dao, ops, tribTkn, ratePerSec);
    }

    // ------------------
    //  Internal: LP init
    // ------------------

    /// @dev Initialize liquidity with a portion of tribute. Returns (tribUsed, forTknUsed, refund).
    ///      Handles pool drift: if spot > OTC rate, caps LP slice to prevent buyer underflow.
    function _initLP(
        address dao,
        address tribTkn,
        address forTkn,
        uint256 tribForLP,
        uint256 forTknRate, // forTkn per tribTkn (×1e18)
        LPConfig memory lp
    ) internal returns (uint256 tribUsed, uint256 forTknUsed, uint256 refund) {
        if (tribForLP == 0) return (0, 0, 0);

        // Build canonical pool key (token0 < token1)
        IZAMM.PoolKey memory key;
        bool tribIsToken0 = tribTkn < forTkn;

        if (tribIsToken0) {
            key = IZAMM.PoolKey({
                id0: 0, id1: 0, token0: tribTkn, token1: forTkn, feeOrHook: lp.feeOrHook
            });
        } else {
            key = IZAMM.PoolKey({
                id0: 0, id1: 0, token0: forTkn, token1: tribTkn, feeOrHook: lp.feeOrHook
            });
        }

        uint256 poolId = uint256(keccak256(abi.encode(key)));

        // Check pool reserves for drift adjustment
        (uint112 r0, uint112 r1,,,,,) = ZAMM.pools(poolId);

        uint256 tribLPUsed = tribForLP;

        // If pool exists, check for drift and cap LP slice if needed
        if (r0 != 0 && r1 != 0) {
            // Compute spot rate: forTkn per tribTkn (×1e18)
            uint256 spotX18 = tribIsToken0
                ? (uint256(r1) * 1e18) / uint256(r0)  // forTkn/tribTkn
                : (uint256(r0) * 1e18) / uint256(r1);

            // If spot > OTC rate, cap LP to prevent buyer from getting fewer coins
            // Formula from zICO: tribLPUsed ≤ totalTrib * spot / (2*spot - rate)
            if (spotX18 > forTknRate) {
                uint256 denom = (spotX18 * 2) - forTknRate;
                uint256 capTrib = (tribForLP * spotX18) / denom;
                if (capTrib < tribLPUsed) tribLPUsed = capTrib;
            }
        }

        if (tribLPUsed == 0) return (0, 0, tribForLP);

        // Compute forTkn needed at OTC rate
        uint256 forTknDesired = (tribLPUsed * forTknRate) / 1e18;
        if (forTknDesired == 0) return (0, 0, tribForLP);

        // Pull forTkn from DAO for LP
        safeTransferFrom(forTkn, dao, address(this), forTknDesired);

        // Approve ZAMM to spend tokens (max approval once, compatible with USDT-style tokens)
        if (tribTkn != address(0)) {
            ensureApproval(tribTkn, address(ZAMM));
        }
        ensureApproval(forTkn, address(ZAMM));

        // Slippage bounds
        uint256 tribMin = tribLPUsed - (tribLPUsed * lp.maxSlipBps) / 10_000;
        uint256 forTknMin = forTknDesired - (forTknDesired * lp.maxSlipBps) / 10_000;

        // Add liquidity - LP shares go to DAO
        uint256 amount0Desired = tribIsToken0 ? tribLPUsed : forTknDesired;
        uint256 amount1Desired = tribIsToken0 ? forTknDesired : tribLPUsed;
        uint256 amount0Min = tribIsToken0 ? tribMin : forTknMin;
        uint256 amount1Min = tribIsToken0 ? forTknMin : tribMin;

        uint256 ethValue = tribTkn == address(0) ? tribLPUsed : 0;

        (uint256 used0, uint256 used1, uint256 liquidity) = ZAMM.addLiquidity{value: ethValue}(
            key, amount0Desired, amount1Desired, amount0Min, amount1Min, dao, block.timestamp
        );

        tribUsed = tribIsToken0 ? used0 : used1;
        forTknUsed = tribIsToken0 ? used1 : used0;

        // Refund unused tribute (includes both ZAMM's unused portion and drift cap)
        refund = tribForLP - tribUsed;

        // Return unused ERC20 tribute to DAO (ETH refund handled via tribForDAO in buy())
        if (tribTkn != address(0) && refund != 0) {
            safeTransfer(tribTkn, dao, refund);
        }

        // Return unused forTkn to DAO
        uint256 unusedForTkn = forTknDesired - forTknUsed;
        if (unusedForTkn != 0) {
            safeTransfer(forTkn, dao, unusedForTkn);
        }

        emit LPInitialized(dao, tribTkn, tribUsed, forTknUsed, liquidity);
    }

    // ------------------
    //  User: exact-in buy
    // ------------------

    /// @notice Exact-in buy:
    ///  - You specify exactly how much tribTkn to pay (`payAmt`).
    ///  - Contract computes how much forTkn you get.
    ///  - Optional slippage bound: if `minBuyAmt != 0`, you must receive at least `minBuyAmt`.
    ///  - If LP is configured, a portion goes to ZAMM liquidity (with drift protection).
    ///
    /// @param dao        DAO whose sale to use.
    /// @param tribTkn    Token you're paying in (must match sale's tribTkn).
    /// @param payAmt     How much tribTkn you are paying (in base units).
    /// @param minBuyAmt  Minimum forTkn you are willing to receive (0 = no bound).
    function buy(address dao, address tribTkn, uint256 payAmt, uint256 minBuyAmt)
        public
        payable
        nonReentrant
    {
        if (dao == address(0)) revert InvalidParams();
        if (payAmt == 0) revert InvalidParams();

        TributeOffer memory offer = sales[dao][tribTkn];
        if (offer.tribAmt == 0 || offer.forAmt == 0 || offer.forTkn == address(0)) {
            revert NoSale();
        }
        if (offer.deadline != 0 && block.timestamp > offer.deadline) revert Expired();

        LPConfig memory lp = lpConfigs[dao][tribTkn];

        // Compute LP portion (if configured)
        uint256 tribForLP = (lp.lpBps != 0) ? (payAmt * lp.lpBps) / 10_000 : 0;
        uint256 tribForDAO = payAmt - tribForLP;

        // Validate msg.value upfront
        if (tribTkn == address(0)) {
            if (msg.value < payAmt) revert InvalidParams();
        } else {
            if (msg.value != 0) revert InvalidParams();
        }

        // Handle LP initialization with drift protection
        uint256 forTknLPUsed;
        if (tribForLP != 0) {
            // Rate: forTkn per tribTkn (×1e18)
            uint256 rateX18 = (offer.forAmt * 1e18) / offer.tribAmt;

            // Pull ERC20 tribute for LP (ETH already validated above)
            if (tribTkn != address(0)) {
                safeTransferFrom(tribTkn, msg.sender, address(this), tribForLP);
            }

            uint256 refund;
            (, forTknLPUsed, refund) = _initLP(dao, tribTkn, offer.forTkn, tribForLP, rateX18, lp);

            // Add any LP refund back to DAO portion (ETH only - ERC20 handled in _initLP)
            if (tribTkn == address(0)) {
                tribForDAO += refund;
            }
        }

        // Buyer receives: OTC-priced coins minus coins used for LP
        uint256 grossBuyAmt = (offer.forAmt * payAmt) / offer.tribAmt;
        uint256 buyAmt = grossBuyAmt - forTknLPUsed;

        if (buyAmt == 0) revert InvalidParams();
        if (minBuyAmt != 0 && buyAmt < minBuyAmt) revert SlippageExceeded();

        // Transfer tribute to DAO
        if (tribTkn == address(0)) {
            safeTransferETH(dao, tribForDAO);
            unchecked {
                uint256 excess = msg.value - payAmt;
                if (excess != 0) safeTransferETH(msg.sender, excess);
            }
        } else {
            if (tribForDAO != 0) {
                safeTransferFrom(tribTkn, msg.sender, dao, tribForDAO);
            }
        }

        // Transfer forTkn to buyer
        safeTransferFrom(offer.forTkn, dao, msg.sender, buyAmt);

        emit SaleBought(msg.sender, dao, tribTkn, payAmt, offer.forTkn, buyAmt);
    }

    // ------------------
    //  User: exact-out buy
    // ------------------

    /// @notice Exact-out buy:
    ///  - You specify exactly how much forTkn you want (`buyAmt`).
    ///  - Contract computes how much tribTkn you must pay (including LP portion if configured).
    ///  - If LP is configured, gross forTkn = buyAmt * 10000 / (10000 - lpBps), and LP gets the difference.
    ///  - Optional bound: if `maxPayAmt != 0`, you will never pay more than `maxPayAmt`.
    ///
    /// @param dao        DAO whose sale to use.
    /// @param tribTkn    Token you're paying in (must match sale's tribTkn).
    /// @param buyAmt     Exact amount of forTkn you want (in base units).
    /// @param maxPayAmt  Max tribTkn you are willing to pay (0 = no bound).
    function buyExactOut(address dao, address tribTkn, uint256 buyAmt, uint256 maxPayAmt)
        public
        payable
        nonReentrant
    {
        if (dao == address(0)) revert InvalidParams();
        if (buyAmt == 0) revert InvalidParams();

        TributeOffer memory offer = sales[dao][tribTkn];
        if (offer.tribAmt == 0 || offer.forAmt == 0 || offer.forTkn == address(0)) {
            revert NoSale();
        }
        if (offer.deadline != 0 && block.timestamp > offer.deadline) revert Expired();

        LPConfig memory lp = lpConfigs[dao][tribTkn];

        // Compute gross forTkn needed (scales up if LP is configured)
        // grossForTkn = buyAmt * 10000 / (10000 - lpBps)
        uint256 grossBuyAmt;
        if (lp.lpBps != 0) {
            grossBuyAmt = (buyAmt * 10_000 + (10_000 - lp.lpBps) - 1) / (10_000 - lp.lpBps);
        } else {
            grossBuyAmt = buyAmt;
        }

        // payAmt = ceil(grossBuyAmt * tribAmt / forAmt)
        uint256 num = grossBuyAmt * offer.tribAmt;
        uint256 payAmt = (num + offer.forAmt - 1) / offer.forAmt;
        if (payAmt == 0) revert InvalidParams();
        if (maxPayAmt != 0 && payAmt > maxPayAmt) revert SlippageExceeded();

        // Handle LP if configured
        uint256 tribForLP = (lp.lpBps != 0) ? (payAmt * lp.lpBps) / 10_000 : 0;
        uint256 tribForDAO = payAmt - tribForLP;

        // Validate msg.value upfront
        if (tribTkn == address(0)) {
            if (msg.value < payAmt) revert InvalidParams();
        } else {
            if (msg.value != 0) revert InvalidParams();
        }

        uint256 forTknLPUsed;
        if (tribForLP != 0) {
            uint256 rateX18 = (offer.forAmt * 1e18) / offer.tribAmt;

            // Pull ERC20 tribute for LP (ETH already validated above)
            if (tribTkn != address(0)) {
                safeTransferFrom(tribTkn, msg.sender, address(this), tribForLP);
            }

            uint256 refund;
            (, forTknLPUsed, refund) = _initLP(dao, tribTkn, offer.forTkn, tribForLP, rateX18, lp);

            // Add LP refund back to DAO portion (ETH only - ERC20 handled in _initLP)
            if (tribTkn == address(0)) {
                tribForDAO += refund;
            }
        }

        // Transfer tribute to DAO
        if (tribTkn == address(0)) {
            safeTransferETH(dao, tribForDAO);
            unchecked {
                uint256 excess = msg.value - payAmt;
                if (excess != 0) safeTransferETH(msg.sender, excess);
            }
        } else {
            if (tribForDAO != 0) {
                safeTransferFrom(tribTkn, msg.sender, dao, tribForDAO);
            }
        }

        // Transfer exact buyAmt to buyer
        safeTransferFrom(offer.forTkn, dao, msg.sender, buyAmt);

        emit SaleBought(msg.sender, dao, tribTkn, payAmt, offer.forTkn, buyAmt);
    }

    // ------------------
    //  Views / quotes
    // ------------------

    /// @notice Quote how much forTkn you'd get for an exact-in trade (LP and drift-aware).
    /// @dev Returns 0 if sale is inactive or expired. Accounts for LP deduction with drift protection.
    function quoteBuy(address dao, address tribTkn, uint256 payAmt)
        public
        view
        returns (uint256 buyAmt)
    {
        if (payAmt == 0 || dao == address(0)) return 0;
        TributeOffer memory offer = sales[dao][tribTkn];
        if (offer.tribAmt == 0 || offer.forAmt == 0 || offer.forTkn == address(0)) return 0;
        if (offer.deadline != 0 && block.timestamp > offer.deadline) return 0;

        uint256 grossBuyAmt = (offer.forAmt * payAmt) / offer.tribAmt;

        // Account for LP deduction if configured (with drift protection)
        LPConfig memory lp = lpConfigs[dao][tribTkn];
        if (lp.lpBps != 0) {
            uint256 forTknLPUsed = _quoteLPUsed(tribTkn, offer.forTkn, payAmt, offer, lp);
            buyAmt = grossBuyAmt - forTknLPUsed;
        } else {
            buyAmt = grossBuyAmt;
        }
    }

    /// @notice Quote how much tribTkn you'd pay for an exact-out trade (LP-aware).
    /// @dev Returns 0 if sale is inactive or expired. Accounts for LP overhead if configured.
    ///      Note: exact-out guarantees buyAmt, so drift doesn't affect the quote.
    function quotePayExactOut(address dao, address tribTkn, uint256 buyAmt)
        public
        view
        returns (uint256 payAmt)
    {
        if (buyAmt == 0 || dao == address(0)) return 0;
        TributeOffer memory offer = sales[dao][tribTkn];
        if (offer.tribAmt == 0 || offer.forAmt == 0 || offer.forTkn == address(0)) return 0;
        if (offer.deadline != 0 && block.timestamp > offer.deadline) return 0;

        LPConfig memory lp = lpConfigs[dao][tribTkn];

        // Compute gross forTkn needed (scales up if LP is configured)
        uint256 grossBuyAmt;
        if (lp.lpBps != 0) {
            grossBuyAmt = (buyAmt * 10_000 + (10_000 - lp.lpBps) - 1) / (10_000 - lp.lpBps);
        } else {
            grossBuyAmt = buyAmt;
        }

        uint256 num = grossBuyAmt * offer.tribAmt;
        payAmt = (num + offer.forAmt - 1) / offer.forAmt;
    }

    /// @dev Compute forTkn used for LP with drift protection (mirrors _initLP logic).
    function _quoteLPUsed(
        address tribTkn,
        address forTkn,
        uint256 payAmt,
        TributeOffer memory offer,
        LPConfig memory lp
    ) internal view returns (uint256 forTknLPUsed) {
        uint256 tribForLP = (payAmt * lp.lpBps) / 10_000;
        if (tribForLP == 0) return 0;

        uint256 rateX18 = (offer.forAmt * 1e18) / offer.tribAmt;

        // Build canonical pool key (token0 < token1)
        IZAMM.PoolKey memory key;
        bool tribIsToken0 = tribTkn < forTkn;

        if (tribIsToken0) {
            key = IZAMM.PoolKey({
                id0: 0, id1: 0, token0: tribTkn, token1: forTkn, feeOrHook: lp.feeOrHook
            });
        } else {
            key = IZAMM.PoolKey({
                id0: 0, id1: 0, token0: forTkn, token1: tribTkn, feeOrHook: lp.feeOrHook
            });
        }

        uint256 poolId = uint256(keccak256(abi.encode(key)));
        (uint112 r0, uint112 r1,,,,,) = ZAMM.pools(poolId);

        uint256 tribLPUsed = tribForLP;

        // Apply drift protection if pool exists
        if (r0 != 0 && r1 != 0) {
            uint256 spotX18 = tribIsToken0
                ? (uint256(r1) * 1e18) / uint256(r0)
                : (uint256(r0) * 1e18) / uint256(r1);

            if (spotX18 > rateX18) {
                uint256 denom = (spotX18 * 2) - rateX18;
                uint256 capTrib = (tribForLP * spotX18) / denom;
                if (capTrib < tribLPUsed) tribLPUsed = capTrib;
            }
        }

        if (tribLPUsed == 0) return 0;

        // forTknLPUsed at OTC rate
        forTknLPUsed = (tribLPUsed * rateX18) / 1e18;
    }

    // ------------------
    //  Tap: claim vested funds
    // ------------------

    /// @notice Claim accrued tap. Anyone can call; funds go to ops.
    /// @param dao The DAO whose tap to claim from.
    /// @return claimed Amount claimed.
    /// @dev Pulls from DAO's Moloch allowance via spendAllowance, then forwards to ops.
    ///      Dynamically adjusts to min(owed, allowance, daoBalance) to handle ragequits/spending.
    function claimTap(address dao) public nonReentrant returns (uint256 claimed) {
        Tap storage tap = taps[dao];
        if (tap.ratePerSec == 0) revert NoTap();
        if (tap.ops == address(0)) revert NoTap();

        uint64 elapsed;
        unchecked {
            elapsed = uint64(block.timestamp) - tap.lastClaim;
        }
        if (elapsed == 0) revert NothingToClaim();

        // Calculate claimable based on time
        uint256 owed = uint256(tap.ratePerSec) * uint256(elapsed);
        if (owed == 0) revert NothingToClaim();

        address tribTkn = tap.tribTkn;
        address ops = tap.ops;

        // Check DAO's remaining allowance to this contract
        uint256 allowance = IMoloch(dao).allowance(tribTkn, address(this));

        // Check DAO's actual balance (may be reduced by ragequit or other spending)
        uint256 daoBalance = tribTkn == address(0) ? dao.balance : balanceOf(tribTkn, dao);

        // Claim min(owed, allowance, daoBalance) - tap is capped by what DAO can actually pay
        claimed = owed < allowance ? owed : allowance;
        if (claimed > daoBalance) claimed = daoBalance;
        if (claimed == 0) revert NothingToClaim();

        // Update timestamp BEFORE external calls (CEI)
        tap.lastClaim = uint64(block.timestamp);

        // 1) Pull from DAO -> DAICO (spendAllowance sends to msg.sender)
        IMoloch(dao).spendAllowance(tribTkn, claimed);

        // 2) Forward to ops
        if (tribTkn == address(0)) {
            safeTransferETH(ops, claimed);
        } else {
            safeTransfer(tribTkn, ops, claimed);
        }

        emit TapClaimed(dao, ops, tribTkn, claimed);
    }

    /// @notice View: how much is owed based on time (ignoring allowance/balance caps).
    function pendingTap(address dao) public view returns (uint256 owed) {
        Tap memory tap = taps[dao];
        if (tap.ratePerSec == 0) return 0;

        unchecked {
            uint64 elapsed = uint64(block.timestamp) - tap.lastClaim;
            owed = uint256(tap.ratePerSec) * uint256(elapsed);
        }
    }

    /// @notice View: how much can actually be claimed (min of owed, allowance, and DAO balance).
    /// @dev Accounts for ragequits and other DAO spending that may reduce available funds.
    function claimableTap(address dao) public view returns (uint256) {
        Tap memory tap = taps[dao];
        if (tap.ops == address(0)) return 0;

        uint256 owed = pendingTap(dao);
        if (owed == 0) return 0;
        uint256 allowance = IMoloch(dao).allowance(tap.tribTkn, address(this));
        uint256 daoBalance = tap.tribTkn == address(0) ? dao.balance : balanceOf(tap.tribTkn, dao);

        uint256 claimable = owed < allowance ? owed : allowance;
        if (claimable > daoBalance) claimable = daoBalance;

        return claimable;
    }

    // ------------------
    //  Summon wrappers
    // ------------------

    /// @notice DAICO sale configuration for summon wrappers
    struct DAICOConfig {
        address tribTkn; // Payment token (ETH = address(0))
        uint256 tribAmt; // Base pay amount
        uint256 saleSupply; // Amount to mint for sale
        uint256 forAmt; // Base receive amount
        uint40 deadline; // Sale deadline (0 = none)
        bool sellLoot; // true = sell loot, false = sell shares
        // LP config (optional - set lpBps=0 to disable)
        // NOTE: Buyers receive (10000 - lpBps) / 10000 of quoted rate
        uint16 lpBps; // Portion of tribute to LP (0-9999, 0 = disabled)
        uint16 maxSlipBps; // Max slippage for LP adds (0 = default 1%)
        uint256 feeOrHook; // Pool fee in bps or hook address
    }

    /// @notice Tap configuration for summon wrappers
    struct TapConfig {
        address ops; // Tap beneficiary
        uint128 ratePerSec; // Tap rate
        uint256 tapAllowance; // Total tap budget
    }

    /// @notice Summon config containing implementation addresses for CREATE2 prediction.
    struct SummonConfig {
        address summoner; // Summoner contract
        address molochImpl; // Moloch implementation (for DAO address prediction)
        address sharesImpl; // Shares implementation (for shares address prediction)
        address lootImpl; // Loot implementation (for loot address prediction)
    }

    /// @notice Summon a DAO with DAICO sale pre-configured via initCalls.
    /// @dev Uses CREATE2 address prediction to build initCalls that the DAO executes.
    /// @param summonConfig Summoner and implementation addresses.
    /// @param orgName      DAO name.
    /// @param orgSymbol    DAO symbol.
    /// @param orgURI       DAO metadata URI.
    /// @param quorumBps    Quorum in basis points (e.g., 5000 = 50%).
    /// @param ragequittable Whether ragequit is enabled.
    /// @param renderer     Optional renderer address.
    /// @param salt         Salt for CREATE2.
    /// @param initHolders  Initial share holders.
    /// @param initShares   Initial share amounts.
    /// @param sharesLocked Whether shares are non-transferable.
    /// @param lootLocked   Whether loot is non-transferable.
    /// @param daicoConfig  DAICO sale configuration.
    /// @return dao         The newly created DAO address.
    function summonDAICO(
        SummonConfig calldata summonConfig,
        string calldata orgName,
        string calldata orgSymbol,
        string calldata orgURI,
        uint16 quorumBps,
        bool ragequittable,
        address renderer,
        bytes32 salt,
        address[] calldata initHolders,
        uint256[] calldata initShares,
        bool sharesLocked,
        bool lootLocked,
        DAICOConfig calldata daicoConfig
    ) public payable returns (address dao) {
        Call[] memory initCalls = _buildInitCalls(
            summonConfig,
            salt,
            initHolders,
            initShares,
            sharesLocked,
            lootLocked,
            daicoConfig,
            TapConfig(address(0), 0, 0)
        );

        dao = ISummoner(summonConfig.summoner).summon{value: msg.value}(
            orgName,
            orgSymbol,
            orgURI,
            quorumBps,
            ragequittable,
            renderer,
            salt,
            initHolders,
            initShares,
            initCalls
        );
    }

    /// @notice Summon a DAO with DAICO sale + custom initCalls for additional setup.
    /// @dev Custom calls are appended after DAICO setup. Useful for ops team mints with
    ///      timelocks, vesting schedules, or any other post-initialization configuration.
    /// @param summonConfig Summoner and implementation addresses.
    /// @param orgName      DAO name.
    /// @param orgSymbol    DAO symbol.
    /// @param orgURI       DAO metadata URI.
    /// @param quorumBps    Quorum in basis points.
    /// @param ragequittable Whether ragequit is enabled.
    /// @param renderer     Optional renderer address.
    /// @param salt         Salt for CREATE2.
    /// @param initHolders  Initial share holders.
    /// @param initShares   Initial share amounts.
    /// @param sharesLocked Whether shares are non-transferable.
    /// @param lootLocked   Whether loot is non-transferable.
    /// @param daicoConfig  DAICO sale configuration.
    /// @param customCalls  Additional calls to execute after DAICO setup (e.g., ops mints, vesting).
    /// @return dao         The newly created DAO address.
    function summonDAICOCustom(
        SummonConfig calldata summonConfig,
        string calldata orgName,
        string calldata orgSymbol,
        string calldata orgURI,
        uint16 quorumBps,
        bool ragequittable,
        address renderer,
        bytes32 salt,
        address[] calldata initHolders,
        uint256[] calldata initShares,
        bool sharesLocked,
        bool lootLocked,
        DAICOConfig calldata daicoConfig,
        Call[] calldata customCalls
    ) public payable returns (address dao) {
        Call[] memory baseCalls = _buildInitCalls(
            summonConfig,
            salt,
            initHolders,
            initShares,
            sharesLocked,
            lootLocked,
            daicoConfig,
            TapConfig(address(0), 0, 0)
        );

        // Merge base calls with custom calls
        Call[] memory initCalls = new Call[](baseCalls.length + customCalls.length);
        for (uint256 i; i < baseCalls.length; ++i) {
            initCalls[i] = baseCalls[i];
        }
        for (uint256 i; i < customCalls.length; ++i) {
            initCalls[baseCalls.length + i] = customCalls[i];
        }

        dao = ISummoner(summonConfig.summoner).summon{value: msg.value}(
            orgName,
            orgSymbol,
            orgURI,
            quorumBps,
            ragequittable,
            renderer,
            salt,
            initHolders,
            initShares,
            initCalls
        );
    }

    /// @notice Summon a DAO with DAICO sale + tap pre-configured.
    /// @param summonConfig Summoner and implementation addresses.
    /// @param orgName      DAO name.
    /// @param orgSymbol    DAO symbol.
    /// @param orgURI       DAO metadata URI.
    /// @param quorumBps    Quorum in basis points.
    /// @param ragequittable Whether ragequit is enabled.
    /// @param renderer     Optional renderer address.
    /// @param salt         Salt for CREATE2.
    /// @param initHolders  Initial share holders.
    /// @param initShares   Initial share amounts.
    /// @param sharesLocked Whether shares are non-transferable.
    /// @param lootLocked   Whether loot is non-transferable.
    /// @param daicoConfig  DAICO sale configuration.
    /// @param tapConfig    Tap configuration.
    /// @return dao         The newly created DAO address.
    function summonDAICOWithTap(
        SummonConfig calldata summonConfig,
        string calldata orgName,
        string calldata orgSymbol,
        string calldata orgURI,
        uint16 quorumBps,
        bool ragequittable,
        address renderer,
        bytes32 salt,
        address[] calldata initHolders,
        uint256[] calldata initShares,
        bool sharesLocked,
        bool lootLocked,
        DAICOConfig calldata daicoConfig,
        TapConfig calldata tapConfig
    ) public payable returns (address dao) {
        Call[] memory initCalls = _buildInitCalls(
            summonConfig,
            salt,
            initHolders,
            initShares,
            sharesLocked,
            lootLocked,
            daicoConfig,
            tapConfig
        );

        dao = ISummoner(summonConfig.summoner).summon{value: msg.value}(
            orgName,
            orgSymbol,
            orgURI,
            quorumBps,
            ragequittable,
            renderer,
            salt,
            initHolders,
            initShares,
            initCalls
        );
    }

    /// @notice Summon a DAO with DAICO sale + tap + custom initCalls.
    /// @dev Most flexible option: full DAICO setup with tap plus custom calls appended.
    /// @param summonConfig Summoner and implementation addresses.
    /// @param orgName      DAO name.
    /// @param orgSymbol    DAO symbol.
    /// @param orgURI       DAO metadata URI.
    /// @param quorumBps    Quorum in basis points.
    /// @param ragequittable Whether ragequit is enabled.
    /// @param renderer     Optional renderer address.
    /// @param salt         Salt for CREATE2.
    /// @param initHolders  Initial share holders.
    /// @param initShares   Initial share amounts.
    /// @param sharesLocked Whether shares are non-transferable.
    /// @param lootLocked   Whether loot is non-transferable.
    /// @param daicoConfig  DAICO sale configuration.
    /// @param tapConfig    Tap configuration.
    /// @param customCalls  Additional calls to execute after DAICO setup (e.g., ops mints, vesting).
    /// @return dao         The newly created DAO address.
    function summonDAICOWithTapCustom(
        SummonConfig calldata summonConfig,
        string calldata orgName,
        string calldata orgSymbol,
        string calldata orgURI,
        uint16 quorumBps,
        bool ragequittable,
        address renderer,
        bytes32 salt,
        address[] calldata initHolders,
        uint256[] calldata initShares,
        bool sharesLocked,
        bool lootLocked,
        DAICOConfig calldata daicoConfig,
        TapConfig calldata tapConfig,
        Call[] calldata customCalls
    ) public payable returns (address dao) {
        Call[] memory baseCalls = _buildInitCalls(
            summonConfig,
            salt,
            initHolders,
            initShares,
            sharesLocked,
            lootLocked,
            daicoConfig,
            tapConfig
        );

        // Merge base calls with custom calls
        Call[] memory initCalls = new Call[](baseCalls.length + customCalls.length);
        for (uint256 i; i < baseCalls.length; ++i) {
            initCalls[i] = baseCalls[i];
        }
        for (uint256 i; i < customCalls.length; ++i) {
            initCalls[baseCalls.length + i] = customCalls[i];
        }

        dao = ISummoner(summonConfig.summoner).summon{value: msg.value}(
            orgName,
            orgSymbol,
            orgURI,
            quorumBps,
            ragequittable,
            renderer,
            salt,
            initHolders,
            initShares,
            initCalls
        );
    }

    /// @dev Build the initCalls array for DAO initialization with DAICO setup.
    function _buildInitCalls(
        SummonConfig calldata summonConfig,
        bytes32 salt,
        address[] calldata initHolders,
        uint256[] calldata initShares,
        bool sharesLocked,
        bool lootLocked,
        DAICOConfig calldata daicoConfig,
        TapConfig memory tapConfig
    ) internal view returns (Call[] memory initCalls) {
        // Predict the DAO address
        address daoAddr = _predictDAO(
            summonConfig.summoner, summonConfig.molochImpl, salt, initHolders, initShares
        );

        // Predict shares/loot addresses (deployed from DAO via CREATE2)
        bytes32 daoSalt = bytes32(bytes20(daoAddr));
        address sharesAddr = _predictClone(summonConfig.sharesImpl, daoSalt, daoAddr);
        address lootAddr = _predictClone(summonConfig.lootImpl, daoSalt, daoAddr);

        // Determine which token we're selling
        address forTkn = daicoConfig.sellLoot ? lootAddr : sharesAddr;

        // Check if tap is enabled
        bool hasTap =
            tapConfig.ops != address(0) && tapConfig.ratePerSec > 0 && tapConfig.tapAllowance > 0;

        // Count number of calls needed
        uint256 numCalls = 3; // mint, approve, setupDAICO
        if (sharesLocked || lootLocked) numCalls++;
        if (hasTap) numCalls++; // setAllowance for tap

        initCalls = new Call[](numCalls);
        uint256 idx;

        // 1. Set transfers locked (if needed)
        if (sharesLocked || lootLocked) {
            initCalls[idx++] = Call({
                target: daoAddr,
                value: 0,
                data: abi.encodeCall(IMoloch.setTransfersLocked, (sharesLocked, lootLocked))
            });
        }

        // 2. Mint sale supply to DAO
        initCalls[idx++] = Call({
            target: forTkn,
            value: 0,
            data: abi.encodeCall(ISharesLoot.mintFromMoloch, (daoAddr, daicoConfig.saleSupply))
        });

        // 3. Approve DAICO to transfer tokens
        initCalls[idx++] = Call({
            target: forTkn,
            value: 0,
            data: abi.encodeCall(ISharesLoot.approve, (address(this), daicoConfig.saleSupply))
        });

        // 4. Set tap allowance (if tap enabled)
        if (hasTap) {
            initCalls[idx++] = Call({
                target: daoAddr,
                value: 0,
                data: abi.encodeCall(
                    IMoloch.setAllowance,
                    (address(this), daicoConfig.tribTkn, tapConfig.tapAllowance)
                )
            });
        }

        // 5. Configure the sale on DAICO
        initCalls[idx] = Call({
            target: address(this),
            value: 0,
            data: abi.encodeCall(this.setupDAICO, (daoAddr, forTkn, daicoConfig, tapConfig))
        });
    }

    /// @notice Callback from DAO's initCalls to complete DAICO setup.
    /// @dev Called by the newly summoned DAO during initialization.
    ///      Only stores config - minting/approval done via earlier initCalls.
    function setupDAICO(
        address dao,
        address forTkn,
        DAICOConfig calldata daicoConfig,
        TapConfig calldata tapConfig
    ) public {
        // Verify caller is the DAO (security check)
        require(msg.sender == dao, Unauthorized());

        // Validate sale params
        if (daicoConfig.tribAmt == 0 || daicoConfig.forAmt == 0 || forTkn == address(0)) {
            revert InvalidParams();
        }
        // 100% lpBps leaves nothing for buyer; >100% is invalid
        if (daicoConfig.lpBps >= 10_000 || daicoConfig.maxSlipBps > 10_000) revert BadLPBps();

        // Check if tap is enabled
        bool hasTap =
            tapConfig.ops != address(0) && tapConfig.ratePerSec > 0 && tapConfig.tapAllowance > 0;

        // Store tap config (if enabled)
        if (hasTap) {
            taps[dao] = Tap({
                ops: tapConfig.ops,
                tribTkn: daicoConfig.tribTkn,
                ratePerSec: tapConfig.ratePerSec,
                lastClaim: uint64(block.timestamp)
            });
            emit TapSet(dao, tapConfig.ops, daicoConfig.tribTkn, tapConfig.ratePerSec);
        }

        // Store LP config (if enabled)
        if (daicoConfig.lpBps != 0) {
            lpConfigs[dao][daicoConfig.tribTkn] = LPConfig({
                lpBps: daicoConfig.lpBps,
                maxSlipBps: daicoConfig.maxSlipBps == 0 ? 100 : daicoConfig.maxSlipBps,
                feeOrHook: daicoConfig.feeOrHook
            });
            emit LPConfigSet(dao, daicoConfig.tribTkn, daicoConfig.lpBps, daicoConfig.feeOrHook);
        }

        // Store sale config
        TributeOffer storage offer = sales[dao][daicoConfig.tribTkn];
        offer.tribAmt = daicoConfig.tribAmt;
        offer.forAmt = daicoConfig.forAmt;
        offer.forTkn = forTkn;
        offer.deadline = daicoConfig.deadline;

        emit SaleSet(
            dao,
            daicoConfig.tribTkn,
            daicoConfig.tribAmt,
            forTkn,
            daicoConfig.forAmt,
            daicoConfig.deadline
        );
    }

    /// @dev Predict DAO address from Summoner's CREATE2.
    function _predictDAO(
        address summoner,
        address molochImpl,
        bytes32 salt,
        address[] calldata initHolders,
        uint256[] calldata initShares
    ) internal pure returns (address) {
        bytes32 _salt = keccak256(abi.encode(initHolders, initShares, salt));

        // Minimal proxy creation code
        bytes memory creationCode = abi.encodePacked(
            hex"602d5f8160095f39f35f5f365f5f37365f73",
            molochImpl,
            hex"5af43d5f5f3e6029573d5ffd5b3d5ff3"
        );

        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), summoner, _salt, keccak256(creationCode))
                    )
                )
            )
        );
    }

    /// @dev Predict clone address from CREATE2 within the DAO.
    function _predictClone(address impl, bytes32 salt, address deployer)
        internal
        pure
        returns (address)
    {
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

    // ------------------
    //  Receive ETH
    // ------------------

    /// @dev Accept ETH from Moloch.spendAllowance for ETH taps.
    receive() external payable {}
}

// ------------------
//  Low-level helpers
// ------------------

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

function safeTransferFrom(address token, address from, address to, uint256 amount) {
    assembly ("memory-safe") {
        let m := mload(0x40)
        mstore(0x60, amount)
        mstore(0x40, to)
        mstore(0x2c, shl(96, from))
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
///      Compatible with USDT-style tokens that require allowance to be 0 before setting non-zero.
///      We check against uint128.max as threshold because:
///      1. It's astronomically large (3.4e38) - will never be exhausted
///      2. After ZAMM uses some allowance via transferFrom, it stays above threshold
///      3. This avoids re-approving on every call (which breaks USDT)
function ensureApproval(address token, address spender) {
    assembly ("memory-safe") {
        // Check current allowance: allowance(address,address)
        mstore(0x00, 0xdd62ed3e000000000000000000000000)
        mstore(0x14, address())
        mstore(0x34, spender)
        let success := staticcall(gas(), token, 0x10, 0x44, 0x00, 0x20)

        // If allowance is below threshold (type(uint128).max), set max approval
        // type(uint128).max = 0xffffffffffffffffffffffffffffffff
        if iszero(and(success, gt(mload(0x00), 0xffffffffffffffffffffffffffffffff))) {
            // Set max approval: approve(address,uint256)
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
