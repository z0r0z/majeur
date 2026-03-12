// SafeSummoner.spec — Formal verification of SafeSummoner deployment validation
// Invariants 119-126 from certora/invariants.md

methods {
    function safeSummon(
        string,
        string,
        string,
        uint16,
        bool,
        address,
        bytes32,
        address[],
        uint256[],
        SafeSummoner.SafeConfig,
        SafeSummoner.Call[]
    ) external returns (address);
    function previewCalls(SafeSummoner.SafeConfig) external returns (SafeSummoner.Call[]);
    function predictDAO(bytes32, address[], uint256[]) external returns (address);

    // Summarize external SUMMONER.summon as NONDET since we only verify _validate
    function _.summon(
        string, string, string, uint16, bool, address, bytes32,
        address[], uint256[], SafeSummoner.Call[]
    ) external => NONDET;
}

// ──────────────────────────────────────────────────────────────────
// Invariant 119: safeSummon reverts if quorumBps > 10000
// ──────────────────────────────────────────────────────────────────

rule quorumBpsOutOfRange(
    env e,
    string orgName,
    string orgSymbol,
    string orgURI,
    uint16 quorumBps,
    bool ragequittable,
    address renderer,
    bytes32 salt,
    address[] initHolders,
    uint256[] initShares,
    SafeSummoner.SafeConfig config,
    SafeSummoner.Call[] extraCalls
) {
    require quorumBps > 10000;
    // Other params valid to isolate this condition
    require initHolders.length > 0;
    require config.proposalThreshold > 0;
    require config.proposalTTL > 0;

    safeSummon@withrevert(e, orgName, orgSymbol, orgURI, quorumBps,
        ragequittable, renderer, salt, initHolders, initShares, config, extraCalls);

    assert lastReverted, "Invariant 119: must revert when quorumBps > 10000";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 120: safeSummon reverts if proposalThreshold == 0
// ──────────────────────────────────────────────────────────────────

rule proposalThresholdRequired(
    env e,
    string orgName,
    string orgSymbol,
    string orgURI,
    uint16 quorumBps,
    bool ragequittable,
    address renderer,
    bytes32 salt,
    address[] initHolders,
    uint256[] initShares,
    SafeSummoner.SafeConfig config,
    SafeSummoner.Call[] extraCalls
) {
    require config.proposalThreshold == 0;
    require initHolders.length > 0;

    safeSummon@withrevert(e, orgName, orgSymbol, orgURI, quorumBps,
        ragequittable, renderer, salt, initHolders, initShares, config, extraCalls);

    assert lastReverted, "Invariant 120: must revert when proposalThreshold == 0";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 121: safeSummon reverts if proposalTTL == 0
// ──────────────────────────────────────────────────────────────────

rule proposalTTLRequired(
    env e,
    string orgName,
    string orgSymbol,
    string orgURI,
    uint16 quorumBps,
    bool ragequittable,
    address renderer,
    bytes32 salt,
    address[] initHolders,
    uint256[] initShares,
    SafeSummoner.SafeConfig config,
    SafeSummoner.Call[] extraCalls
) {
    require config.proposalTTL == 0;
    require config.proposalThreshold > 0;
    require initHolders.length > 0;

    safeSummon@withrevert(e, orgName, orgSymbol, orgURI, quorumBps,
        ragequittable, renderer, salt, initHolders, initShares, config, extraCalls);

    assert lastReverted, "Invariant 121: must revert when proposalTTL == 0";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 122: safeSummon reverts if initHolders.length == 0
// ──────────────────────────────────────────────────────────────────

rule noInitialHolders(
    env e,
    string orgName,
    string orgSymbol,
    string orgURI,
    uint16 quorumBps,
    bool ragequittable,
    address renderer,
    bytes32 salt,
    address[] initHolders,
    uint256[] initShares,
    SafeSummoner.SafeConfig config,
    SafeSummoner.Call[] extraCalls
) {
    require initHolders.length == 0;

    safeSummon@withrevert(e, orgName, orgSymbol, orgURI, quorumBps,
        ragequittable, renderer, salt, initHolders, initShares, config, extraCalls);

    assert lastReverted, "Invariant 122: must revert with no initial holders";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 123: safeSummon reverts if timelockDelay > 0 && proposalTTL <= timelockDelay
// ──────────────────────────────────────────────────────────────────

rule timelockExceedsTTL(
    env e,
    string orgName,
    string orgSymbol,
    string orgURI,
    uint16 quorumBps,
    bool ragequittable,
    address renderer,
    bytes32 salt,
    address[] initHolders,
    uint256[] initShares,
    SafeSummoner.SafeConfig config,
    SafeSummoner.Call[] extraCalls
) {
    require config.timelockDelay > 0;
    require config.proposalTTL <= config.timelockDelay;
    require config.proposalThreshold > 0;
    require config.proposalTTL > 0;
    require initHolders.length > 0;
    require quorumBps <= 10000;

    safeSummon@withrevert(e, orgName, orgSymbol, orgURI, quorumBps,
        ragequittable, renderer, salt, initHolders, initShares, config, extraCalls);

    assert lastReverted, "Invariant 123: must revert when timelock >= TTL";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 124: safeSummon reverts if futarchy enabled and both
// quorumBps == 0 and quorumAbsolute == 0
// ──────────────────────────────────────────────────────────────────

rule quorumRequiredForFutarchy(
    env e,
    string orgName,
    string orgSymbol,
    string orgURI,
    uint16 quorumBps,
    bool ragequittable,
    address renderer,
    bytes32 salt,
    address[] initHolders,
    uint256[] initShares,
    SafeSummoner.SafeConfig config,
    SafeSummoner.Call[] extraCalls
) {
    require config.autoFutarchyParam > 0;
    require quorumBps == 0;
    require config.quorumAbsolute == 0;
    require config.proposalThreshold > 0;
    require config.proposalTTL > 0;
    require initHolders.length > 0;

    safeSummon@withrevert(e, orgName, orgSymbol, orgURI, quorumBps,
        ragequittable, renderer, salt, initHolders, initShares, config, extraCalls);

    assert lastReverted, "Invariant 124: must revert when futarchy + no quorum";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 125: safeSummon reverts if saleActive && saleMinting &&
// quorumBps > 0 && quorumAbsolute == 0
// ──────────────────────────────────────────────────────────────────

rule mintingSaleWithDynamicQuorum(
    env e,
    string orgName,
    string orgSymbol,
    string orgURI,
    uint16 quorumBps,
    bool ragequittable,
    address renderer,
    bytes32 salt,
    address[] initHolders,
    uint256[] initShares,
    SafeSummoner.SafeConfig config,
    SafeSummoner.Call[] extraCalls
) {
    require config.saleActive;
    require config.saleMinting;
    require quorumBps > 0;
    require quorumBps <= 10000;
    require config.quorumAbsolute == 0;
    require config.proposalThreshold > 0;
    require config.proposalTTL > 0;
    require initHolders.length > 0;
    require config.salePricePerShare > 0;
    // Ensure no timelock conflict
    require config.timelockDelay == 0 || config.proposalTTL > config.timelockDelay;
    // Ensure no futarchy conflict
    require config.autoFutarchyParam == 0;

    safeSummon@withrevert(e, orgName, orgSymbol, orgURI, quorumBps,
        ragequittable, renderer, salt, initHolders, initShares, config, extraCalls);

    assert lastReverted, "Invariant 125: must revert for minting sale + dynamic-only quorum";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 126: safeSummon reverts if saleActive && salePricePerShare == 0
// ──────────────────────────────────────────────────────────────────

rule salePriceRequired(
    env e,
    string orgName,
    string orgSymbol,
    string orgURI,
    uint16 quorumBps,
    bool ragequittable,
    address renderer,
    bytes32 salt,
    address[] initHolders,
    uint256[] initShares,
    SafeSummoner.SafeConfig config,
    SafeSummoner.Call[] extraCalls
) {
    require config.saleActive;
    require config.salePricePerShare == 0;
    require config.proposalThreshold > 0;
    require config.proposalTTL > 0;
    require initHolders.length > 0;
    require quorumBps <= 10000;

    safeSummon@withrevert(e, orgName, orgSymbol, orgURI, quorumBps,
        ragequittable, renderer, salt, initHolders, initShares, config, extraCalls);

    assert lastReverted, "Invariant 126: must revert when sale active but price is 0";
}

// ──────────────────────────────────────────────────────────────────
// Satisfy: safeSummon is reachable with valid config
// ──────────────────────────────────────────────────────────────────

rule safeSummonSanity(
    env e,
    string orgName,
    string orgSymbol,
    string orgURI,
    uint16 quorumBps,
    bool ragequittable,
    address renderer,
    bytes32 salt,
    address[] initHolders,
    uint256[] initShares,
    SafeSummoner.SafeConfig config,
    SafeSummoner.Call[] extraCalls
) {
    safeSummon(e, orgName, orgSymbol, orgURI, quorumBps,
        ragequittable, renderer, salt, initHolders, initShares, config, extraCalls);
    satisfy true;
}
