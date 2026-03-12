// DAICO.spec — Formal verification of DAICO (sale + tap + LP) contract
// Invariants 106-118, 116 from certora/invariants.md

methods {
    // Sale config
    function setSale(address, uint256, address, uint256, uint40) external;
    function setSaleWithTap(address, uint256, address, uint256, uint40, address, uint128) external;
    function setSaleWithLP(address, uint256, address, uint256, uint40, uint16, uint16, uint256) external;
    function setSaleWithLPAndTap(address, uint256, address, uint256, uint40, uint16, uint16, uint256, address, uint128) external;
    function setTapOps(address) external;
    function setTapRate(uint128) external;
    function setLPConfig(address, uint16, uint16, uint256) external;

    // Buy
    function buy(address, address, uint256, uint256) external;
    function buyExactOut(address, address, uint256, uint256) external;

    // Tap
    function claimTap(address) external returns (uint256);

    // Harness getters
    function getSaleTribAmt(address, address) external returns (uint256) envfree;
    function getSaleForAmt(address, address) external returns (uint256) envfree;
    function getSaleForTkn(address, address) external returns (address) envfree;
    function getSaleDeadline(address, address) external returns (uint40) envfree;
    function getTapOps(address) external returns (address) envfree;
    function getTapTribTkn(address) external returns (address) envfree;
    function getTapRatePerSec(address) external returns (uint128) envfree;
    function getTapLastClaim(address) external returns (uint64) envfree;
    function getLPBps(address, address) external returns (uint16) envfree;
    function getDaoTapBalance(address) external returns (uint256) envfree;
}

// ──────────────────────────────────────────────────────────────────
// Invariant 106: setSale, setSaleWithTap, setSaleWithLP,
// setSaleWithLPAndTap, setLPConfig, setTapOps, setTapRate all
// record msg.sender as the DAO
// ──────────────────────────────────────────────────────────────────

// Verify that after setSale, the sale is keyed by msg.sender
rule setSaleRecordsSenderAsDao(env e, address tribTkn, uint256 tribAmt,
    address forTkn, uint256 forAmt, uint40 deadline) {

    require tribAmt > 0 && forAmt > 0 && forTkn != 0;
    require e.msg.value == 0, "SAFE: not payable";

    setSale(e, tribTkn, tribAmt, forTkn, forAmt, deadline);

    assert getSaleTribAmt(e.msg.sender, tribTkn) == tribAmt,
        "Invariant 106: sale keyed by msg.sender";
    assert getSaleForAmt(e.msg.sender, tribTkn) == forAmt,
        "Invariant 106: sale forAmt keyed by msg.sender";
}

// Verify taps are keyed by msg.sender
rule setSaleWithTapRecordsSender(env e, address tribTkn, uint256 tribAmt,
    address forTkn, uint256 forAmt, uint40 deadline, address ops, uint128 ratePerSec) {

    require tribAmt > 0 && forAmt > 0 && forTkn != 0;
    require ops != 0 && ratePerSec > 0;
    require e.msg.value == 0, "SAFE: not payable";

    setSaleWithTap(e, tribTkn, tribAmt, forTkn, forAmt, deadline, ops, ratePerSec);

    assert getTapOps(e.msg.sender) == ops,
        "Invariant 106: tap keyed by msg.sender";
    assert getTapRatePerSec(e.msg.sender) == ratePerSec,
        "Invariant 106: tap rate keyed by msg.sender";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 107: buy reverts if no active sale exists
// ──────────────────────────────────────────────────────────────────

rule buyRevertsOnNoSale(env e, address dao, address tribTkn, uint256 payAmt, uint256 minBuyAmt) {
    require getSaleTribAmt(dao, tribTkn) == 0
        || getSaleForAmt(dao, tribTkn) == 0
        || getSaleForTkn(dao, tribTkn) == 0;
    require dao != 0 && payAmt > 0;

    buy@withrevert(e, dao, tribTkn, payAmt, minBuyAmt);

    assert lastReverted, "Invariant 107: buy must revert when no active sale";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 108: buy reverts if deadline has passed
// ──────────────────────────────────────────────────────────────────

rule buyRevertsOnExpired(env e, address dao, address tribTkn, uint256 payAmt, uint256 minBuyAmt) {
    uint40 deadline = getSaleDeadline(dao, tribTkn);
    require deadline != 0;
    require to_mathint(e.block.timestamp) > to_mathint(deadline);
    require dao != 0 && payAmt > 0;
    require getSaleTribAmt(dao, tribTkn) > 0;
    require getSaleForAmt(dao, tribTkn) > 0;
    require getSaleForTkn(dao, tribTkn) != 0;

    buy@withrevert(e, dao, tribTkn, payAmt, minBuyAmt);

    assert lastReverted, "Invariant 108: buy must revert after deadline";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 109: buy reverts if payAmt == 0
// ──────────────────────────────────────────────────────────────────

rule buyRevertsOnZeroPay(env e, address dao, address tribTkn, uint256 minBuyAmt) {
    require dao != 0;

    buy@withrevert(e, dao, tribTkn, 0, minBuyAmt);

    assert lastReverted, "Invariant 109: buy must revert when payAmt == 0";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 110: buy reverts if computed buyAmt would be zero
// ──────────────────────────────────────────────────────────────────

rule buyRevertsOnZeroBuyAmt(env e, address dao, address tribTkn, uint256 payAmt, uint256 minBuyAmt) {
    require dao != 0 && payAmt > 0;

    uint256 tribAmt = getSaleTribAmt(dao, tribTkn);
    uint256 forAmt = getSaleForAmt(dao, tribTkn);
    require tribAmt > 0 && forAmt > 0;
    require getSaleForTkn(dao, tribTkn) != 0;

    // Ensure the computed buyAmt rounds to zero
    require forAmt * payAmt < tribAmt;

    uint40 deadline = getSaleDeadline(dao, tribTkn);
    require deadline == 0 || to_mathint(e.block.timestamp) <= to_mathint(deadline);

    buy@withrevert(e, dao, tribTkn, payAmt, minBuyAmt);

    assert lastReverted, "Invariant 110: buy must revert when buyAmt == 0";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 111: buy reverts on slippage violation
// ──────────────────────────────────────────────────────────────────

rule buyRevertsOnSlippage(env e, address dao, address tribTkn, uint256 payAmt, uint256 minBuyAmt) {
    require dao != 0 && payAmt > 0 && minBuyAmt > 0;

    uint256 tribAmt = getSaleTribAmt(dao, tribTkn);
    uint256 forAmt = getSaleForAmt(dao, tribTkn);
    require tribAmt > 0 && forAmt > 0;
    require getSaleForTkn(dao, tribTkn) != 0;

    // Compute buyAmt
    mathint buyAmt = (to_mathint(forAmt) * to_mathint(payAmt)) / to_mathint(tribAmt);
    require buyAmt > 0; // don't overlap with Inv 110
    require buyAmt < to_mathint(minBuyAmt);

    uint40 deadline = getSaleDeadline(dao, tribTkn);
    require deadline == 0 || to_mathint(e.block.timestamp) <= to_mathint(deadline);

    buy@withrevert(e, dao, tribTkn, payAmt, minBuyAmt);

    assert lastReverted, "Invariant 111: buy must revert on slippage violation";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 112: buyExactOut reverts on slippage violation
// ──────────────────────────────────────────────────────────────────

rule buyExactOutRevertsOnSlippage(env e, address dao, address tribTkn,
    uint256 buyAmt, uint256 maxPayAmt) {

    require dao != 0 && buyAmt > 0 && maxPayAmt > 0;

    uint256 tribAmt = getSaleTribAmt(dao, tribTkn);
    uint256 forAmt = getSaleForAmt(dao, tribTkn);
    require tribAmt > 0 && forAmt > 0;
    require getSaleForTkn(dao, tribTkn) != 0;

    // Compute payAmt = ceil(buyAmt * tribAmt / forAmt)
    mathint num = to_mathint(buyAmt) * to_mathint(tribAmt);
    mathint payAmt = (num + to_mathint(forAmt) - 1) / to_mathint(forAmt);
    require payAmt > 0;
    require payAmt > to_mathint(maxPayAmt);

    uint40 deadline = getSaleDeadline(dao, tribTkn);
    require deadline == 0 || to_mathint(e.block.timestamp) <= to_mathint(deadline);

    buyExactOut@withrevert(e, dao, tribTkn, buyAmt, maxPayAmt);

    assert lastReverted, "Invariant 112: buyExactOut must revert on slippage violation";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 113: claimTap reverts if ratePerSec == 0
// ──────────────────────────────────────────────────────────────────

rule claimTapRevertsOnZeroRate(env e, address dao) {
    require getTapRatePerSec(dao) == 0;
    require e.msg.value == 0, "SAFE: not payable";

    claimTap@withrevert(e, dao);

    assert lastReverted, "Invariant 113: claimTap must revert when ratePerSec == 0";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 114: claimTap reverts if ops == address(0)
// ──────────────────────────────────────────────────────────────────

rule claimTapRevertsOnZeroOps(env e, address dao) {
    require getTapOps(dao) == 0;
    require e.msg.value == 0, "SAFE: not payable";

    claimTap@withrevert(e, dao);

    assert lastReverted, "Invariant 114: claimTap must revert when ops == address(0)";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 115: claimTap reverts if elapsed time is zero
// ──────────────────────────────────────────────────────────────────

rule claimTapRevertsOnZeroElapsed(env e, address dao) {
    require getTapRatePerSec(dao) > 0;
    require getTapOps(dao) != 0;
    // elapsed = block.timestamp - lastClaim == 0
    require to_mathint(e.block.timestamp) == to_mathint(getTapLastClaim(dao));
    require e.msg.value == 0, "SAFE: not payable";

    claimTap@withrevert(e, dao);

    assert lastReverted, "Invariant 115: claimTap must revert when elapsed == 0";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 117: After claimTap, lastClaim == block.timestamp
// ──────────────────────────────────────────────────────────────────

rule claimTapUpdatesLastClaim(env e, address dao) {
    require e.msg.value == 0, "SAFE: not payable";
    require e.block.timestamp <= max_uint64,
        "SAFE: block.timestamp fits in uint64 (year ~584 billion)";

    claimTap(e, dao);

    assert to_mathint(getTapLastClaim(dao)) == to_mathint(e.block.timestamp),
        "Invariant 117: lastClaim must equal block.timestamp after claimTap";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 118: setLPConfig reverts if lpBps > 9999
// ──────────────────────────────────────────────────────────────────

rule setLPConfigRevertsOnBadBps(env e, address tribTkn, uint16 lpBps, uint16 maxSlipBps,
    uint256 feeOrHook) {

    require to_mathint(lpBps) >= 10000;
    require e.msg.value == 0, "SAFE: not payable";

    setLPConfig@withrevert(e, tribTkn, lpBps, maxSlipBps, feeOrHook);

    assert lastReverted, "Invariant 118: setLPConfig must revert when lpBps >= 10000";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 116: claimTap amount is at most min(owed, daoTapBalance)
// ──────────────────────────────────────────────────────────────────

rule claimTapAmountCapped(env e, address dao) {
    uint128 rate = getTapRatePerSec(dao);
    uint64 lastClaimBefore = getTapLastClaim(dao);
    uint256 available = getDaoTapBalance(dao);

    require rate > 0;
    require getTapOps(dao) != 0;
    require e.msg.value == 0, "SAFE: not payable";
    require e.block.timestamp <= max_uint64,
        "SAFE: block.timestamp fits in uint64";
    require to_mathint(e.block.timestamp) > to_mathint(lastClaimBefore),
        "SAFE: time must have elapsed";

    mathint elapsed = to_mathint(e.block.timestamp) - to_mathint(lastClaimBefore);
    mathint owed = to_mathint(rate) * elapsed;

    uint256 claimed = claimTap(e, dao);

    assert to_mathint(claimed) <= owed,
        "Invariant 116: claimed must not exceed owed";
    assert to_mathint(claimed) <= to_mathint(available),
        "Invariant 116: claimed must not exceed available balance";
}

// ──────────────────────────────────────────────────────────────────
// [L-01] claimTap forfeits owed amounts on partial claims
//
// When claimed < owed (due to allowance/balance caps), lastClaim
// still advances to block.timestamp. The elapsed time consumed
// exceeds the time actually paid for, permanently forfeiting
// (owed - claimed) tokens with no recovery mechanism.
//
// This rule is expected to be VIOLATED — the violation confirms
// the L-01 finding.
// ──────────────────────────────────────────────────────────────────

/// @notice !VIOLATED — confirms L-01: time consumed exceeds time paid for
/// @cause lastClaim advances full elapsed even when claimed < owed
rule claimTapForfeitureOnPartialClaim(env e, address dao) {
    uint128 rate = getTapRatePerSec(dao);
    uint64 lastClaimBefore = getTapLastClaim(dao);

    require rate > 0;
    require getTapOps(dao) != 0;
    require e.msg.value == 0, "SAFE: not payable";
    require e.block.timestamp <= max_uint64,
        "SAFE: block.timestamp fits in uint64";
    require to_mathint(e.block.timestamp) > to_mathint(lastClaimBefore),
        "SAFE: time must have elapsed for a valid claim";

    // Compute owed amount before the call
    mathint elapsed = to_mathint(e.block.timestamp) - to_mathint(lastClaimBefore);
    mathint owed = to_mathint(rate) * elapsed;

    uint256 claimed = claimTap(e, dao);

    // Time consumed by the timestamp advance
    mathint timeConsumed = to_mathint(getTapLastClaim(dao)) - to_mathint(lastClaimBefore);
    // Time that the claimed amount actually pays for
    mathint timePaidFor = to_mathint(claimed) / to_mathint(rate);

    // A correct implementation would only advance lastClaim by the time
    // corresponding to the amount actually claimed. This assertion will
    // be VIOLATED when claimed < owed, proving the forfeiture bug.
    assert timeConsumed == timePaidFor,
        "L-01: claimTap must not consume more time than paid for";
}

// Demonstrate that a partial claim scenario exists
rule claimTapPartialClaimExists(env e, address dao) {
    uint128 rate = getTapRatePerSec(dao);
    uint64 lastClaimBefore = getTapLastClaim(dao);

    require rate > 0;
    require getTapOps(dao) != 0;
    require e.msg.value == 0, "SAFE: not payable";
    require e.block.timestamp <= max_uint64,
        "SAFE: block.timestamp fits in uint64";
    require to_mathint(e.block.timestamp) > to_mathint(lastClaimBefore),
        "SAFE: time must have elapsed";

    mathint elapsed = to_mathint(e.block.timestamp) - to_mathint(lastClaimBefore);
    mathint owed = to_mathint(rate) * elapsed;

    uint256 claimed = claimTap(e, dao);

    // Prove there exists a scenario where claimed < owed
    satisfy to_mathint(claimed) < owed;
}

// ──────────────────────────────────────────────────────────────────
// Satisfy rules (sanity)
// ──────────────────────────────────────────────────────────────────

rule setSaleSanity(env e, address tribTkn, uint256 tribAmt, address forTkn,
    uint256 forAmt, uint40 deadline) {
    require e.msg.value == 0, "SAFE: not payable";
    setSale(e, tribTkn, tribAmt, forTkn, forAmt, deadline);
    satisfy true;
}

rule buySanity(env e, address dao, address tribTkn, uint256 payAmt, uint256 minBuyAmt) {
    buy(e, dao, tribTkn, payAmt, minBuyAmt);
    satisfy true;
}

rule claimTapSanity(env e, address dao) {
    require e.msg.value == 0, "SAFE: not payable";
    claimTap(e, dao);
    satisfy true;
}
