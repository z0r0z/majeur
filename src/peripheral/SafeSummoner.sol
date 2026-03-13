// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

struct Call {
    address target;
    uint256 value;
    bytes data;
}

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

interface IMoloch {
    function setProposalThreshold(uint96 v) external;
    function setProposalTTL(uint64 s) external;
    function setTimelockDelay(uint64 s) external;
    function setQuorumAbsolute(uint96 v) external;
    function setMinYesVotesAbsolute(uint96 v) external;
    function setTransfersLocked(bool sharesLocked, bool lootLocked) external;
    function setAutoFutarchy(uint256 param, uint256 cap) external;
    function setFutarchyRewardToken(address _rewardToken) external;
    function setSale(
        address payToken,
        uint256 pricePerShare,
        uint256 cap,
        bool minting,
        bool active,
        bool isLoot
    ) external;
    function setPermit(
        uint8 op,
        address to,
        uint256 value,
        bytes calldata data,
        bytes32 nonce,
        address spender,
        uint256 count
    ) external;
    function setAllowance(address spender, address token, uint256 amount) external;
}

interface IShareSale {
    function configure(address token, address payToken, uint256 price, uint40 deadline) external;
}

interface ITapVest {
    function configure(address token, address beneficiary, uint128 ratePerSec) external;
}

interface ILPSeedSwapHook {
    function configure(
        address tokenA,
        uint128 amountA,
        address tokenB,
        uint128 amountB,
        uint40 deadline,
        address shareSale,
        uint128 minSupply
    ) external;
}

interface ISharesLoot {
    function mintFromMoloch(address to, uint256 amount) external;
}

interface IShareBurner {
    function burnUnsold(address shares, uint256 deadline) external payable;
}

/// @dev Deployed singletons (same CREATE2/3 addresses on all supported chains).
ISummoner constant SUMMONER = ISummoner(0x0000000000330B8df9E3bc5E553074DA58eE9138);
address constant MOLOCH_IMPL = 0x643A45B599D81be3f3A68F37EB3De55fF10673C1;
address constant SHARES_IMPL = 0x71E9b38d301b5A58cb998C1295045FE276Acf600;
address constant LOOT_IMPL = 0x6f1f2aF76a3aDD953277e9F369242697C87bc6A5;
address constant SHARE_BURNER = 0x000000000040084694F7B6fb2846D067B4c3Aa9f;
address constant RENDERER = 0x000000000011C799980827F52d3137b4abD6E654;

/// @title SafeSummoner
/// @notice Safe wrapper around the deployed Summoner that enforces audit-derived
/// configuration guidance and builds initCalls from a typed struct.
///
/// @dev Audit findings addressed:
///   KF#11  — Enforces proposalThreshold > 0 (prevents front-run cancel, proposal spam)
///   KF#17  — Enforces non-zero quorum when futarchy is configured (prevents premature NO-resolution)
///   KF#3   — Enforces autoFutarchyCap > 0 when futarchy enabled (bounds per-proposal earmarks,
///            prevents unbounded minted-loot farming via NO-coalition repeated defeats)
///   KF#2   — Blocks quorumBps + minting sale combo (supply manipulation via buy -> ragequit)
///   KF#12  — Validates quorumBps range at summon time (init skips this check)
///   Config — Requires proposalTTL > 0 (prevents proposals lingering indefinitely)
///   Config — Requires proposalTTL > timelockDelay (prevents proposals expiring in queue)
contract SafeSummoner {
    error NoInitialHolders();
    error SalePriceRequired();
    error ModuleSaleConflict();
    error SeedGateWithoutSale();
    error TimelockExceedsTTL();
    error FutarchyCapRequired();
    error ProposalTTLRequired();
    error QuorumBpsOutOfRange();
    error ProposalThresholdRequired();
    error QuorumRequiredForFutarchy();
    error MintingSaleWithDynamicQuorum();

    /// @dev Typed configuration for safe DAO deployment.
    /// Zero values mean "skip" (use Moloch defaults) except where validation requires otherwise.
    struct SafeConfig {
        // ── Governance (validated) ──
        uint96 proposalThreshold; // Must be > 0. Prevents KF#11 griefing.
        uint64 proposalTTL; // Must be > 0. Prevents indefinite proposals.
        // ── Governance (optional) ──
        uint64 timelockDelay; // 0 = no timelock
        uint96 quorumAbsolute; // 0 = rely on quorumBps from summon params
        uint96 minYesVotes; // 0 = no absolute YES floor
        // ── Transfers ──
        bool lockShares; // true = shares non-transferable at launch
        bool lockLoot; // true = loot non-transferable at launch
        // ── Futarchy ──
        uint256 autoFutarchyParam; // 0 = off. 1..10000 = BPS of supply; >10000 = absolute
        uint256 autoFutarchyCap; // Per-proposal cap. 0 = no cap
        address futarchyRewardToken; // Only checked if autoFutarchyParam > 0
        // ── Sale ──
        bool saleActive;
        address salePayToken; // address(0) = ETH
        uint256 salePricePerShare; // Required if saleActive
        uint256 saleCap; // 0 = unlimited (non-minting sales are naturally capped by DAO balance)
        bool saleMinting; // true = mint new, false = transfer from DAO
        bool saleIsLoot; // true = sell loot instead of shares
        // ── ShareBurner ──
        uint256 saleBurnDeadline; // 0 = no auto-burn. >0 = timestamp after which unsold shares are burnable
    }

    /// @dev ShareSale module config. singleton = address(0) to skip.
    ///      Uses Moloch allowance sentinels: address(dao) = mint shares, address(1007) = mint loot.
    struct SaleModule {
        address singleton; // ShareSale contract address (0 = skip)
        address payToken; // address(0) = ETH
        uint40 deadline; // unix timestamp after which buys revert (0 = no deadline)
        uint256 price; // per-token price (1e18 scaled)
        uint256 cap; // sale cap (allowance amount)
        bool sellLoot; // true = sell loot, false = sell shares
        bool minting; // true = mint on buy (sentinel), false = transfer from DAO balance
    }

    /// @dev TapVest module config. singleton = address(0) to skip.
    struct TapModule {
        address singleton; // TapVest contract address (0 = skip)
        address token; // vested token (address(0) = ETH)
        uint256 budget; // total budget (allowance)
        address beneficiary; // tap recipient
        uint128 ratePerSec; // vesting rate in smallest-unit/sec
    }

    /// @dev LPSeedSwapHook module config. singleton = address(0) to skip.
    ///      Token sentinels: address(1) = DAO shares, address(2) = DAO loot.
    ///      When a sentinel is used, the wrapper mints that amount to the DAO
    ///      and resolves it to the predicted shares/loot ERC20 address.
    ///      LPSeedSwapHook acts as a ZAMM hook — the pool's feeOrHook is always derived
    ///      from the LPSeedSwapHook singleton address, preventing frontrun pool creation.
    struct SeedModule {
        address singleton; // LPSeedSwapHook contract address (0 = skip)
        address tokenA; // first token (address(0)=ETH, address(1)=shares, address(2)=loot)
        uint128 amountA; // amount of tokenA to seed
        address tokenB; // second token (address(1)=shares, address(2)=loot, or ERC20)
        uint128 amountB; // amount of tokenB to seed
        uint40 deadline; // time gate (0 = none)
        bool gateBySale; // if true, gate LP seeding on SaleModule completion
        uint128 minSupply; // balance gate (0 = none)
    }

    constructor() payable {}

    /// @notice Deploy a new DAO with validated configuration.
    /// @param orgName      DAO display name
    /// @param orgSymbol    DAO token symbol
    /// @param orgURI       DAO metadata URI (empty = default)
    /// @param quorumBps    Quorum as basis points of snapshot supply (e.g. 2000 = 20%)
    /// @param ragequittable Whether members can ragequit
    /// @param renderer     On-chain renderer address (address(0) = default)
    /// @param salt         CREATE2 salt for deterministic addresses
    /// @param initHolders  Initial share holders
    /// @param initShares   Initial share amounts (must match initHolders length)
    /// @param config       Typed configuration struct
    /// @param extraCalls   Additional raw initCalls appended after config (advanced use)
    function safeSummon(
        string calldata orgName,
        string calldata orgSymbol,
        string calldata orgURI,
        uint16 quorumBps,
        bool ragequittable,
        address renderer,
        bytes32 salt,
        address[] calldata initHolders,
        uint256[] calldata initShares,
        SafeConfig calldata config,
        Call[] calldata extraCalls
    ) public payable returns (address dao) {
        // ── Validate ──────────────────────────────────────────────
        _validate(quorumBps, config, initHolders.length);

        // ── Predict DAO address ───────────────────────────────────
        address daoAddr = _predictDAO(salt, initHolders, initShares);

        // ── Build initCalls ───────────────────────────────────────
        Call[] memory calls = _buildCalls(daoAddr, config, extraCalls);

        // ── Summon ────────────────────────────────────────────────
        dao = SUMMONER.summon{value: msg.value}(
            orgName,
            orgSymbol,
            orgURI,
            quorumBps,
            ragequittable,
            renderer,
            salt,
            initHolders,
            initShares,
            calls
        );
    }

    // ── Presets ─────────────────────────────────────────────────
    // Standard configurations for trustless one-click deployment.
    // UIs can call these directly without constructing a SafeConfig.
    // proposalThreshold defaults to 1% of initial supply (floor 1).

    /// @notice Standard DAO: 7-day voting, 2-day timelock, 10% quorum, ragequittable.
    /// Suitable for treasuries, protocol governance, and grants committees.
    function summonStandard(
        string calldata orgName,
        string calldata orgSymbol,
        string calldata orgURI,
        bytes32 salt,
        address[] calldata initHolders,
        uint256[] calldata initShares
    ) public payable returns (address) {
        SafeConfig memory c;
        c.proposalThreshold = _defaultThreshold(initShares);
        c.proposalTTL = 7 days;
        c.timelockDelay = 2 days;
        return
            _summonPreset(orgName, orgSymbol, orgURI, 1000, true, salt, initHolders, initShares, c);
    }

    /// @notice Fast DAO: 3-day voting, 1-day timelock, 10% quorum, ragequittable.
    /// Suitable for agile teams, working groups, and sub-DAOs.
    function summonFast(
        string calldata orgName,
        string calldata orgSymbol,
        string calldata orgURI,
        bytes32 salt,
        address[] calldata initHolders,
        uint256[] calldata initShares
    ) public payable returns (address) {
        SafeConfig memory c;
        c.proposalThreshold = _defaultThreshold(initShares);
        c.proposalTTL = 3 days;
        c.timelockDelay = 1 days;
        return
            _summonPreset(orgName, orgSymbol, orgURI, 1000, true, salt, initHolders, initShares, c);
    }

    /// @notice Minimal DAO: 3-day voting, no timelock, 5% quorum, ragequittable.
    /// Suitable for small clubs, investment groups, and informal collectives.
    function summonMinimal(
        string calldata orgName,
        string calldata orgSymbol,
        string calldata orgURI,
        bytes32 salt,
        address[] calldata initHolders,
        uint256[] calldata initShares
    ) public payable returns (address) {
        SafeConfig memory c;
        c.proposalThreshold = _defaultThreshold(initShares);
        c.proposalTTL = 3 days;
        return
            _summonPreset(orgName, orgSymbol, orgURI, 500, true, salt, initHolders, initShares, c);
    }

    /// @notice Standard non-ragequittable: 7-day voting, 2-day timelock, 10% quorum.
    /// Suitable for protocol treasuries and grant programs where exit liquidity
    /// should not drain the pool.
    function summonLocked(
        string calldata orgName,
        string calldata orgSymbol,
        string calldata orgURI,
        bytes32 salt,
        address[] calldata initHolders,
        uint256[] calldata initShares
    ) public payable returns (address) {
        SafeConfig memory c;
        c.proposalThreshold = _defaultThreshold(initShares);
        c.proposalTTL = 7 days;
        c.timelockDelay = 2 days;
        return
            _summonPreset(orgName, orgSymbol, orgURI, 1000, false, salt, initHolders, initShares, c);
    }

    // ── Modular DAICO ─────────────────────────────────────────
    // Compose ShareSale + TapVest + LPSeedSwapHook singletons as pluggable modules
    // to achieve DAICO-like functionality without coupling to a single contract.
    // Set module.singleton = address(0) to skip any module.

    /// @notice Deploy a DAO with full config + modular sale/tap/seed.
    /// @dev Combines SafeConfig governance with standalone peripheral singletons.
    ///      Cannot use SafeConfig.saleActive simultaneously with SaleModule.
    function safeSummonDAICO(
        string calldata orgName,
        string calldata orgSymbol,
        string calldata orgURI,
        uint16 quorumBps,
        bool ragequittable,
        address renderer,
        bytes32 salt,
        address[] calldata initHolders,
        uint256[] calldata initShares,
        SafeConfig calldata config,
        SaleModule calldata sale,
        TapModule calldata tap,
        SeedModule calldata seed,
        Call[] calldata extraCalls
    ) public payable returns (address dao) {
        if (config.saleActive && sale.singleton != address(0)) {
            revert ModuleSaleConflict();
        }
        _validate(quorumBps, config, initHolders.length);
        _validateModules(quorumBps, config.quorumAbsolute, sale, seed);

        address daoAddr = _predictDAO(salt, initHolders, initShares);
        Call[] memory modCalls = _buildModuleCalls(daoAddr, sale, tap, seed);

        // Merge: modules + extraCalls
        Call[] memory allExtra = new Call[](modCalls.length + extraCalls.length);
        uint256 idx;
        for (uint256 j; j < modCalls.length; j++) {
            allExtra[idx++] = modCalls[j];
        }
        for (uint256 j; j < extraCalls.length; j++) {
            allExtra[idx++] = extraCalls[j];
        }

        Call[] memory calls = _buildCalls(daoAddr, config, allExtra);

        dao = SUMMONER.summon{value: msg.value}(
            orgName,
            orgSymbol,
            orgURI,
            quorumBps,
            ragequittable,
            renderer,
            salt,
            initHolders,
            initShares,
            calls
        );
    }

    /// @notice Standard DAO (7d voting, 2d timelock, 10% quorum) + modular DAICO.
    function summonStandardDAICO(
        string calldata orgName,
        string calldata orgSymbol,
        string calldata orgURI,
        bytes32 salt,
        address[] calldata initHolders,
        uint256[] calldata initShares,
        SaleModule calldata sale,
        TapModule calldata tap,
        SeedModule calldata seed
    ) public payable returns (address) {
        SafeConfig memory c;
        c.proposalThreshold = _defaultThreshold(initShares);
        c.proposalTTL = 7 days;
        c.timelockDelay = 2 days;
        return _summonDAICOPreset(
            orgName,
            orgSymbol,
            orgURI,
            1000,
            true,
            salt,
            initHolders,
            initShares,
            c,
            sale,
            tap,
            seed
        );
    }

    /// @notice Fast DAO (3d voting, 1d timelock, 10% quorum) + modular DAICO.
    function summonFastDAICO(
        string calldata orgName,
        string calldata orgSymbol,
        string calldata orgURI,
        bytes32 salt,
        address[] calldata initHolders,
        uint256[] calldata initShares,
        SaleModule calldata sale,
        TapModule calldata tap,
        SeedModule calldata seed
    ) public payable returns (address) {
        SafeConfig memory c;
        c.proposalThreshold = _defaultThreshold(initShares);
        c.proposalTTL = 3 days;
        c.timelockDelay = 1 days;
        return _summonDAICOPreset(
            orgName,
            orgSymbol,
            orgURI,
            1000,
            true,
            salt,
            initHolders,
            initShares,
            c,
            sale,
            tap,
            seed
        );
    }

    function _summonDAICOPreset(
        string calldata orgName,
        string calldata orgSymbol,
        string calldata orgURI,
        uint16 quorumBps,
        bool ragequittable,
        bytes32 salt,
        address[] calldata initHolders,
        uint256[] calldata initShares,
        SafeConfig memory config,
        SaleModule calldata sale,
        TapModule calldata tap,
        SeedModule calldata seed
    ) internal returns (address) {
        _validate(quorumBps, config, initHolders.length);
        _validateModules(quorumBps, config.quorumAbsolute, sale, seed);

        address daoAddr = _predictDAO(salt, initHolders, initShares);
        Call[] memory modCalls = _buildModuleCalls(daoAddr, sale, tap, seed);
        Call[] memory calls = _buildCalls(daoAddr, config, modCalls);

        return SUMMONER.summon{value: msg.value}(
            orgName,
            orgSymbol,
            orgURI,
            quorumBps,
            ragequittable,
            RENDERER,
            salt,
            initHolders,
            initShares,
            calls
        );
    }

    function _summonPreset(
        string calldata orgName,
        string calldata orgSymbol,
        string calldata orgURI,
        uint16 quorumBps,
        bool ragequittable,
        bytes32 salt,
        address[] calldata initHolders,
        uint256[] calldata initShares,
        SafeConfig memory config
    ) internal returns (address) {
        _validate(quorumBps, config, initHolders.length);
        address daoAddr = _predictDAO(salt, initHolders, initShares);
        Call[] memory extra = new Call[](0);
        Call[] memory calls = _buildCalls(daoAddr, config, extra);
        return SUMMONER.summon{value: msg.value}(
            orgName,
            orgSymbol,
            orgURI,
            quorumBps,
            ragequittable,
            RENDERER,
            salt,
            initHolders,
            initShares,
            calls
        );
    }

    // ── Views ──────────────────────────────────────────────────

    /// @notice Preview the initCalls that safeSummon would generate for off-chain inspection.
    /// @dev Uses address(0) as DAO placeholder since the address isn't known yet.
    function previewCalls(SafeConfig calldata config) public pure returns (Call[] memory) {
        Call[] memory empty = new Call[](0);
        return _buildCalls(address(0), config, empty);
    }

    /// @notice Preview the module initCalls that safeSummonDAICO would generate.
    /// @dev Uses address(0) as DAO placeholder. Sentinel tokens resolve to predicted addresses.
    function previewModuleCalls(
        SaleModule calldata sale,
        TapModule calldata tap,
        SeedModule calldata seed
    ) public pure returns (Call[] memory) {
        return _buildModuleCalls(address(0), sale, tap, seed);
    }

    /// @notice Predict the DAO address that would be deployed with the given parameters.
    function predictDAO(bytes32 salt, address[] calldata initHolders, uint256[] calldata initShares)
        public
        pure
        returns (address)
    {
        return _predictDAO(salt, initHolders, initShares);
    }

    /// @notice Predict the Shares token address for a given DAO.
    function predictShares(address dao) public pure returns (address) {
        return _predictShares(dao);
    }

    /// @notice Predict the Loot token address for a given DAO.
    function predictLoot(address dao) public pure returns (address) {
        return _predictLoot(dao);
    }

    // ── Validation ────────────────────────────────────────────────

    function _validate(uint16 quorumBps, SafeConfig memory c, uint256 holderCount) internal pure {
        if (holderCount == 0) revert NoInitialHolders();
        if (c.proposalThreshold == 0) revert ProposalThresholdRequired();
        if (c.proposalTTL == 0) revert ProposalTTLRequired();
        if (quorumBps > 10_000) revert QuorumBpsOutOfRange();

        // Timelock must be shorter than TTL so proposals don't expire while queued
        if (c.timelockDelay > 0 && c.proposalTTL <= c.timelockDelay) {
            revert TimelockExceedsTTL();
        }

        // KF#17: futarchy + zero quorum = premature NO-resolution freeze
        if (c.autoFutarchyParam > 0 && quorumBps == 0 && c.quorumAbsolute == 0) {
            revert QuorumRequiredForFutarchy();
        }

        // KF#3: uncapped auto-futarchy allows unbounded per-proposal earmarks.
        // Default rewardToken (address(0) → minted loot) has no natural balance cap,
        // enabling NO-coalition farming of treasury via repeated proposal defeats.
        if (c.autoFutarchyParam > 0 && c.autoFutarchyCap == 0) {
            revert FutarchyCapRequired();
        }

        // KF#2: minting sale + dynamic-only quorum = supply manipulation
        if (c.saleActive && c.saleMinting && quorumBps > 0 && c.quorumAbsolute == 0) {
            revert MintingSaleWithDynamicQuorum();
        }

        if (c.saleActive && c.salePricePerShare == 0) revert SalePriceRequired();
    }

    /// @dev Validate module-specific constraints.
    function _validateModules(
        uint16 quorumBps,
        uint96 quorumAbsolute,
        SaleModule memory sale,
        SeedModule memory seed
    ) internal pure {
        if (sale.singleton != address(0)) {
            if (sale.price == 0) revert SalePriceRequired();
            // KF#2: minting sale + dynamic-only quorum = supply manipulation
            if (sale.minting && quorumBps > 0 && quorumAbsolute == 0) {
                revert MintingSaleWithDynamicQuorum();
            }
        }
        // SeedModule gate-by-sale requires a SaleModule to gate on
        if (seed.singleton != address(0) && seed.gateBySale && sale.singleton == address(0)) {
            revert SeedGateWithoutSale();
        }
    }

    // ── Call Builder ──────────────────────────────────────────────

    function _buildCalls(address dao, SafeConfig memory c, Call[] memory extra)
        internal
        pure
        returns (Call[] memory calls)
    {
        // Count required calls
        uint256 n = 2; // proposalThreshold + proposalTTL (always set)
        if (c.timelockDelay > 0) n++;
        if (c.quorumAbsolute > 0) n++;
        if (c.minYesVotes > 0) n++;
        if (c.lockShares || c.lockLoot) n++;
        if (c.autoFutarchyParam > 0) {
            n++; // setAutoFutarchy
            if (c.futarchyRewardToken != address(0)) n++; // setFutarchyRewardToken
        }
        if (c.saleActive) n++;
        if (c.saleBurnDeadline > 0) n++;

        calls = new Call[](n + extra.length);
        uint256 i;

        // --- Required ---
        calls[i++] =
            Call(dao, 0, abi.encodeCall(IMoloch.setProposalThreshold, (c.proposalThreshold)));
        calls[i++] = Call(dao, 0, abi.encodeCall(IMoloch.setProposalTTL, (c.proposalTTL)));

        // --- Optional governance ---
        if (c.timelockDelay > 0) {
            calls[i++] = Call(dao, 0, abi.encodeCall(IMoloch.setTimelockDelay, (c.timelockDelay)));
        }
        if (c.quorumAbsolute > 0) {
            calls[i++] = Call(dao, 0, abi.encodeCall(IMoloch.setQuorumAbsolute, (c.quorumAbsolute)));
        }
        if (c.minYesVotes > 0) {
            calls[i++] =
                Call(dao, 0, abi.encodeCall(IMoloch.setMinYesVotesAbsolute, (c.minYesVotes)));
        }

        // --- Transfers ---
        if (c.lockShares || c.lockLoot) {
            calls[i++] = Call(
                dao, 0, abi.encodeCall(IMoloch.setTransfersLocked, (c.lockShares, c.lockLoot))
            );
        }

        // --- Futarchy ---
        if (c.autoFutarchyParam > 0) {
            calls[i++] = Call(
                dao,
                0,
                abi.encodeCall(IMoloch.setAutoFutarchy, (c.autoFutarchyParam, c.autoFutarchyCap))
            );
            if (c.futarchyRewardToken != address(0)) {
                calls[i++] = Call(
                    dao, 0, abi.encodeCall(IMoloch.setFutarchyRewardToken, (c.futarchyRewardToken))
                );
            }
        }

        // --- Sale ---
        if (c.saleActive) {
            calls[i++] = Call(
                dao,
                0,
                abi.encodeCall(
                    IMoloch.setSale,
                    (
                        c.salePayToken,
                        c.salePricePerShare,
                        c.saleCap,
                        c.saleMinting,
                        true,
                        c.saleIsLoot
                    )
                )
            );
        }

        // --- ShareBurner permit ---
        if (c.saleBurnDeadline > 0) {
            address sharesAddr = _predictShares(dao);
            bytes memory burnData =
                abi.encodeCall(IShareBurner.burnUnsold, (sharesAddr, c.saleBurnDeadline));
            calls[i++] = Call(
                dao,
                0,
                abi.encodeCall(
                    IMoloch.setPermit,
                    (
                        uint8(1), // op = delegatecall
                        SHARE_BURNER, // target
                        uint256(0), // value
                        burnData, // encoded burnUnsold
                        keccak256("ShareBurner"), // nonce
                        SHARE_BURNER, // spender
                        uint256(1) // count = 1 (one-shot)
                    )
                )
            );
        }

        // --- Extra calls ---
        for (uint256 j; j < extra.length; j++) {
            calls[i++] = extra[j];
        }
    }

    // ── ShareBurner Helper ────────────────────────────────────────

    /// @notice Generate the setPermit Call for ShareBurner inclusion in initCalls or proposals.
    /// @dev Useful for DAOs that want to add burn-after-deadline outside of SafeSummoner presets.
    function burnPermitCall(
        bytes32 salt,
        address[] calldata initHolders,
        uint256[] calldata initShares,
        uint256 deadline
    ) public pure returns (Call memory) {
        address dao = _predictDAO(salt, initHolders, initShares);
        address sharesAddr = _predictShares(dao);
        bytes memory burnData = abi.encodeCall(IShareBurner.burnUnsold, (sharesAddr, deadline));
        return Call(
            dao,
            0,
            abi.encodeCall(
                IMoloch.setPermit,
                (
                    uint8(1),
                    SHARE_BURNER,
                    uint256(0),
                    burnData,
                    keccak256("ShareBurner"),
                    SHARE_BURNER,
                    uint256(1)
                )
            )
        );
    }

    // ── Module Call Builder ────────────────────────────────────────

    /// @dev Build initCalls for ShareSale, TapVest, and LPSeedSwapHook modules.
    ///      Order: SaleModule → TapModule → SeedModule (mints → allowances → configure).
    function _buildModuleCalls(
        address dao,
        SaleModule memory sale,
        TapModule memory tap,
        SeedModule memory seed
    ) internal pure returns (Call[] memory calls) {
        // Count calls
        uint256 n;
        if (sale.singleton != address(0)) n += 2; // setAllowance + configure
        if (tap.singleton != address(0)) n += 2; // setAllowance + configure
        if (seed.singleton != address(0)) {
            n += 3; // 2x setAllowance + configure
            if (_isSeedSentinel(seed.tokenA)) n++; // mint
            if (_isSeedSentinel(seed.tokenB)) n++; // mint
        }

        calls = new Call[](n);
        uint256 i;

        // ── SaleModule ──────────────────────────────────────────
        if (sale.singleton != address(0)) {
            address saleToken = _resolveSaleToken(dao, sale);
            calls[i++] = Call(
                dao, 0, abi.encodeCall(IMoloch.setAllowance, (sale.singleton, saleToken, sale.cap))
            );
            calls[i++] = Call(
                sale.singleton,
                0,
                abi.encodeCall(
                    IShareSale.configure, (saleToken, sale.payToken, sale.price, sale.deadline)
                )
            );
        }

        // ── TapModule ───────────────────────────────────────────
        if (tap.singleton != address(0)) {
            calls[i++] = Call(
                dao, 0, abi.encodeCall(IMoloch.setAllowance, (tap.singleton, tap.token, tap.budget))
            );
            calls[i++] = Call(
                tap.singleton,
                0,
                abi.encodeCall(ITapVest.configure, (tap.token, tap.beneficiary, tap.ratePerSec))
            );
        }

        // ── SeedModule ──────────────────────────────────────────
        if (seed.singleton != address(0)) {
            address tokenA = _resolveSeedToken(dao, seed.tokenA);
            address tokenB = _resolveSeedToken(dao, seed.tokenB);
            address shareSale = seed.gateBySale ? sale.singleton : address(0);

            // Mint sentinel tokens to DAO (must precede allowance)
            if (_isSeedSentinel(seed.tokenA)) {
                calls[i++] = Call(
                    tokenA,
                    0,
                    abi.encodeCall(ISharesLoot.mintFromMoloch, (dao, uint256(seed.amountA)))
                );
            }
            if (_isSeedSentinel(seed.tokenB)) {
                calls[i++] = Call(
                    tokenB,
                    0,
                    abi.encodeCall(ISharesLoot.mintFromMoloch, (dao, uint256(seed.amountB)))
                );
            }

            // Set allowances
            calls[i++] = Call(
                dao,
                0,
                abi.encodeCall(
                    IMoloch.setAllowance, (seed.singleton, tokenA, uint256(seed.amountA))
                )
            );
            calls[i++] = Call(
                dao,
                0,
                abi.encodeCall(
                    IMoloch.setAllowance, (seed.singleton, tokenB, uint256(seed.amountB))
                )
            );

            // Configure LPSeedSwapHook
            calls[i++] = Call(
                seed.singleton,
                0,
                abi.encodeCall(
                    ILPSeedSwapHook.configure,
                    (
                        tokenA,
                        seed.amountA,
                        tokenB,
                        seed.amountB,
                        seed.deadline,
                        shareSale,
                        seed.minSupply
                    )
                )
            );
        }
    }

    /// @dev Returns true for LPSeedSwapHook sentinel tokens that require minting.
    ///      address(1) = DAO shares, address(2) = DAO loot.
    function _isSeedSentinel(address token) internal pure returns (bool) {
        return token == address(1) || token == address(2);
    }

    /// @dev Resolve SaleModule token to Moloch allowance sentinel or predicted ERC20 address.
    ///      Minting path: address(dao) for shares, address(1007) for loot.
    ///      Transfer path: predicted shares/loot ERC20 address.
    function _resolveSaleToken(address dao, SaleModule memory sale)
        internal
        pure
        returns (address)
    {
        if (sale.minting) {
            return sale.sellLoot ? address(1007) : dao;
        }
        return sale.sellLoot ? _predictLoot(dao) : _predictShares(dao);
    }

    /// @dev Resolve SeedModule token sentinel to predicted ERC20 address.
    ///      address(1) → shares, address(2) → loot, otherwise pass-through.
    function _resolveSeedToken(address dao, address token) internal pure returns (address) {
        if (token == address(1)) return _predictShares(dao);
        if (token == address(2)) return _predictLoot(dao);
        return token;
    }

    // ── Defaults ──────────────────────────────────────────────────

    /// @dev 1% of total initial shares, floored at 1. Ensures proposalThreshold
    /// scales with supply so any single holder of ≥1% can propose.
    function _defaultThreshold(uint256[] calldata initShares) internal pure returns (uint96) {
        uint256 total;
        for (uint256 i; i < initShares.length; i++) {
            total += initShares[i];
        }
        uint256 t = total / 100; // 1%
        if (t == 0) t = 1;
        return uint96(t);
    }

    // ── Address Prediction ────────────────────────────────────────

    function _predictDAO(
        bytes32 salt,
        address[] calldata initHolders,
        uint256[] calldata initShares
    ) internal pure returns (address) {
        bytes32 _salt = keccak256(abi.encode(initHolders, initShares, salt));
        bytes memory creationCode = abi.encodePacked(
            hex"602d5f8160095f39f35f5f365f5f37365f73",
            MOLOCH_IMPL,
            hex"5af43d5f5f3e6029573d5ffd5b3d5ff3"
        );
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), address(SUMMONER), _salt, keccak256(creationCode)
                        )
                    )
                )
            )
        );
    }

    /// @dev Predict a token proxy address deployed via CREATE2 from the DAO.
    /// All token proxies (shares, loot, badges) use salt = bytes32(bytes20(dao))
    /// and differ only by implementation address in the minimal proxy creation code.
    function _predictToken(address dao, address impl) internal pure returns (address) {
        bytes32 _salt = bytes32(bytes20(dao));
        bytes memory creationCode = abi.encodePacked(
            hex"602d5f8160095f39f35f5f365f5f37365f73", impl, hex"5af43d5f5f3e6029573d5ffd5b3d5ff3"
        );
        return address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xff), dao, _salt, keccak256(creationCode)))
                )
            )
        );
    }

    function _predictShares(address dao) internal pure returns (address) {
        return _predictToken(dao, SHARES_IMPL);
    }

    function _predictLoot(address dao) internal pure returns (address) {
        return _predictToken(dao, LOOT_IMPL);
    }
}
