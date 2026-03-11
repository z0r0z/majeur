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
}

/// @dev Deployed singletons (same CREATE2 addresses on all supported chains).
ISummoner constant SUMMONER = ISummoner(0x0000000000330B8df9E3bc5E553074DA58eE9138);
address constant MOLOCH_IMPL = 0x643A45B599D81be3f3A68F37EB3De55fF10673C1;

/// @title SafeSummoner
/// @notice Safe wrapper around the deployed Summoner that enforces audit-derived
/// configuration guidance and builds initCalls from a typed struct.
///
/// @dev Audit findings addressed:
///   KF#11  — Enforces proposalThreshold > 0 (prevents front-run cancel, proposal spam)
///   KF#17  — Enforces non-zero quorum when futarchy is configured (prevents premature NO-resolution)
///   KF#2   — Blocks quorumBps + minting sale combo (supply manipulation via buy → ragequit)
///   KF#12  — Validates quorumBps range at summon time (init skips this check)
///   Config — Requires proposalTTL > 0 (prevents proposals lingering indefinitely)
///   Config — Requires proposalTTL > timelockDelay (prevents proposals expiring in queue)
contract SafeSummoner {
    error QuorumBpsOutOfRange();
    error ProposalThresholdRequired();
    error ProposalTTLRequired();
    error QuorumRequiredForFutarchy();
    error MintingSaleWithDynamicQuorum();
    error NoInitialHolders();
    error TimelockExceedsTTL();
    error SalePriceRequired();

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
        uint256 saleCap; // 0 = unlimited (only valid with saleMinting)
        bool saleMinting; // true = mint new, false = transfer from DAO
        bool saleIsLoot; // true = sell loot instead of shares
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

    /// @notice Preview the initCalls that safeSummon would generate for off-chain inspection.
    /// @dev Uses address(0) as DAO placeholder since the address isn't known yet.
    function previewCalls(SafeConfig calldata config) public pure returns (Call[] memory) {
        Call[] memory empty = new Call[](0);
        return _buildCalls(address(0), config, empty);
    }

    /// @notice Predict the DAO address that would be deployed with the given parameters.
    function predictDAO(bytes32 salt, address[] calldata initHolders, uint256[] calldata initShares)
        public
        pure
        returns (address)
    {
        return _predictDAO(salt, initHolders, initShares);
    }

    // ── Validation ────────────────────────────────────────────────

    function _validate(uint16 quorumBps, SafeConfig calldata c, uint256 holderCount) internal pure {
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

        // KF#2: minting sale + dynamic-only quorum = supply manipulation
        if (c.saleActive && c.saleMinting && quorumBps > 0 && c.quorumAbsolute == 0) {
            revert MintingSaleWithDynamicQuorum();
        }

        if (c.saleActive && c.salePricePerShare == 0) revert SalePriceRequired();
    }

    // ── Call Builder ──────────────────────────────────────────────

    function _buildCalls(address dao, SafeConfig calldata c, Call[] memory extra)
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

        // --- Extra calls ---
        for (uint256 j; j < extra.length; j++) {
            calls[i++] = extra[j];
        }
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
}
