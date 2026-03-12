// Tribute.spec — Formal verification of Tribute escrow contract
// Invariants 97-105 from certora/invariants.md

methods {
    function tributes(address, address, address) external
        returns (uint256, address, uint256) envfree;
    function getDaoTributeCount(address) external returns (uint256) envfree;
    function getProposerTributeCount(address) external returns (uint256) envfree;
    function proposeTribute(address, address, uint256, address, uint256) external;
    function cancelTribute(address, address) external;
    function claimTribute(address, address) external;

    // Summarize external token calls as NONDET
    // The free functions safeTransfer, safeTransferFrom, safeTransferETH
    // use low-level assembly calls — summarize their targets
    function _.transfer(address, uint256) external => NONDET;
    function _.transferFrom(address, address, uint256) external => NONDET;
}

// ──────────────────────────────────────────────────────────────────
// Helper: extract tribAmt from the tributes mapping
// ──────────────────────────────────────────────────────────────────

function getTribAmt(address proposer, address dao, address tribTkn) returns uint256 {
    uint256 tribAmt; address forTkn; uint256 forAmt;
    tribAmt, forTkn, forAmt = tributes(proposer, dao, tribTkn);
    return tribAmt;
}

function getForTkn(address proposer, address dao, address tribTkn) returns address {
    uint256 tribAmt; address forTkn; uint256 forAmt;
    tribAmt, forTkn, forAmt = tributes(proposer, dao, tribTkn);
    return forTkn;
}

function getForAmt(address proposer, address dao, address tribTkn) returns uint256 {
    uint256 tribAmt; address forTkn; uint256 forAmt;
    tribAmt, forTkn, forAmt = tributes(proposer, dao, tribTkn);
    return forAmt;
}

// ──────────────────────────────────────────────────────────────────
// Invariant 97: proposeTribute reverts if an offer already exists
// for the (msg.sender, dao, tribTkn) triple (no overwrites)
// ──────────────────────────────────────────────────────────────────

rule proposeTributeRevertsOnExistingOffer(
    env e, address dao, address tribTkn, uint256 tribAmt, address forTkn, uint256 forAmt
) {
    uint256 existingAmt = getTribAmt(e.msg.sender, dao, tribTkn);

    require existingAmt != 0;

    proposeTribute@withrevert(e, dao, tribTkn, tribAmt, forTkn, forAmt);

    assert lastReverted, "Invariant 97: must revert when offer already exists";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 98: After a successful cancelTribute, the entry is deleted
// ──────────────────────────────────────────────────────────────────

rule cancelTributeDeletesEntry(env e, address dao, address tribTkn) {
    require e.msg.value == 0, "SAFE: cancelTribute is not payable";

    cancelTribute(e, dao, tribTkn);

    uint256 tribAmtAfter = getTribAmt(e.msg.sender, dao, tribTkn);
    address forTknAfter = getForTkn(e.msg.sender, dao, tribTkn);
    uint256 forAmtAfter = getForAmt(e.msg.sender, dao, tribTkn);

    assert tribAmtAfter == 0, "Invariant 98: tribAmt must be zeroed after cancel";
    assert forAmtAfter == 0, "Invariant 98: forAmt must be zeroed after cancel";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 99: After a successful claimTribute, the entry is deleted
// ──────────────────────────────────────────────────────────────────

rule claimTributeDeletesEntry(env e, address proposer, address tribTkn) {
    address dao = e.msg.sender;

    claimTribute(e, proposer, tribTkn);

    uint256 tribAmtAfter = getTribAmt(proposer, dao, tribTkn);
    uint256 forAmtAfter = getForAmt(proposer, dao, tribTkn);

    assert tribAmtAfter == 0, "Invariant 99: tribAmt must be zeroed after claim";
    assert forAmtAfter == 0, "Invariant 99: forAmt must be zeroed after claim";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 100: cancelTribute reverts if no offer exists
// ──────────────────────────────────────────────────────────────────

rule cancelTributeRevertsIfNoOffer(env e, address dao, address tribTkn) {
    uint256 existingAmt = getTribAmt(e.msg.sender, dao, tribTkn);

    require existingAmt == 0;
    require e.msg.value == 0, "SAFE: cancelTribute is not payable";

    cancelTribute@withrevert(e, dao, tribTkn);

    assert lastReverted, "Invariant 100: must revert when no offer exists";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 101: claimTribute reverts if no offer exists
// ──────────────────────────────────────────────────────────────────

rule claimTributeRevertsIfNoOffer(env e, address proposer, address tribTkn) {
    address dao = e.msg.sender;
    uint256 existingAmt = getTribAmt(proposer, dao, tribTkn);

    require existingAmt == 0;

    claimTribute@withrevert(e, proposer, tribTkn);

    assert lastReverted, "Invariant 101: must revert when no offer exists";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 102: Only the original proposer can cancel their own
// tribute via cancelTribute.
// cancelTribute uses msg.sender as the proposer key, so by design
// another user calling cancelTribute cannot affect a different
// proposer's offer. We verify: calling cancelTribute does not
// modify another proposer's offer.
// ──────────────────────────────────────────────────────────────────

rule cancelDoesNotAffectOtherProposer(
    env e, address dao, address tribTkn, address otherProposer
) {
    require otherProposer != e.msg.sender, "SAFE: different proposer";
    require e.msg.value == 0, "SAFE: cancelTribute is not payable";

    uint256 otherAmtBefore = getTribAmt(otherProposer, dao, tribTkn);

    cancelTribute@withrevert(e, dao, tribTkn);

    uint256 otherAmtAfter = getTribAmt(otherProposer, dao, tribTkn);

    assert otherAmtAfter == otherAmtBefore,
        "Invariant 102: cancel must not affect other proposer's offer";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 103: Only the DAO (msg.sender) can claim a tribute
// directed at itself. claimTribute uses msg.sender as the dao key.
// We verify: calling claimTribute does not modify tributes directed
// at a different DAO.
// ──────────────────────────────────────────────────────────────────

rule claimDoesNotAffectOtherDao(
    env e, address proposer, address tribTkn, address otherDao
) {
    require otherDao != e.msg.sender, "SAFE: different DAO";

    uint256 otherAmtBefore = getTribAmt(proposer, otherDao, tribTkn);

    claimTribute@withrevert(e, proposer, tribTkn);

    uint256 otherAmtAfter = getTribAmt(proposer, otherDao, tribTkn);

    assert otherAmtAfter == otherAmtBefore,
        "Invariant 103: claim must not affect tributes directed at other DAOs";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 104: daoTributeRefs[dao].length is monotonically
// non-decreasing (Pattern 3 monotonic)
// ──────────────────────────────────────────────────────────────────

rule daoTributeRefsMonotonic(env e, method f, calldataarg args, address dao) {
    mathint lenBefore = getDaoTributeCount(dao);

    f(e, args);

    mathint lenAfter = getDaoTributeCount(dao);

    assert lenAfter >= lenBefore,
        "Invariant 104: daoTributeRefs length must never decrease";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 105: proposerTributeRefs[proposer].length is monotonically
// non-decreasing (Pattern 3 monotonic)
// ──────────────────────────────────────────────────────────────────

rule proposerTributeRefsMonotonic(env e, method f, calldataarg args, address proposer) {
    mathint lenBefore = getProposerTributeCount(proposer);

    f(e, args);

    mathint lenAfter = getProposerTributeCount(proposer);

    assert lenAfter >= lenBefore,
        "Invariant 105: proposerTributeRefs length must never decrease";
}

// ──────────────────────────────────────────────────────────────────
// Satisfy rules (sanity)
// ──────────────────────────────────────────────────────────────────

rule proposeTributeSanity(
    env e, address dao, address tribTkn, uint256 tribAmt, address forTkn, uint256 forAmt
) {
    proposeTribute(e, dao, tribTkn, tribAmt, forTkn, forAmt);
    satisfy true;
}

rule cancelTributeSanity(env e, address dao, address tribTkn) {
    require e.msg.value == 0, "SAFE: not payable";
    cancelTribute(e, dao, tribTkn);
    satisfy true;
}
