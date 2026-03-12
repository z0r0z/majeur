// Moloch.spec — Formal verification of Moloch core DAO contract
// Invariants 3-8, 11, 13-15, 30-40, 43-49, 94 from certora/invariants.md

methods {
    // ERC-6909
    function transfer(address, uint256, uint256) external returns (bool);
    function transferFrom(address, address, uint256, uint256) external returns (bool);
    function setOperator(address, bool) external returns (bool);
    function balanceOf(address, uint256) external returns (uint256) envfree;
    function totalSupply(uint256) external returns (uint256) envfree;

    // Voting
    function castVote(uint256, uint8) external;
    function openProposal(uint256) external;
    function cancelProposal(uint256) external;
    function executeByVotes(uint256) external;
    function queue(uint256) external;

    // Settings
    function setProposalThreshold(uint96) external;
    function setProposalTTL(uint64) external;
    function setTimelockDelay(uint64) external;
    function setQuorumAbsolute(uint96) external;
    function setMinYesVotesAbsolute(uint96) external;
    function setQuorumBps(uint16) external;
    function setRagequittable(bool) external;
    function setRenderer(address) external;
    function setAutoFutarchy(uint256, uint256) external;
    function setFutarchyRewardToken(address) external;
    function setPermitReceipt(uint256) external;
    function bumpConfig() external;

    // Sale
    function setSale(address, uint256, uint256, bool, bool, bool) external;
    function buyShares(address, uint256, uint256) external;

    // Allowance
    function setAllowance(address, address, uint256) external;
    function spendAllowance(address, uint256) external;

    // Harness getters
    function getExecuted(uint256) external returns (bool) envfree;
    function getCreatedAt(uint256) external returns (uint64) envfree;
    function getSnapshotBlock(uint256) external returns (uint48) envfree;
    function getSupplySnapshot(uint256) external returns (uint256) envfree;
    function getQueuedAt(uint256) external returns (uint64) envfree;
    function getIsPermitReceipt(uint256) external returns (bool) envfree;
    function getAllowance(address, address) external returns (uint256) envfree;
    function getSaleActive(address) external returns (bool) envfree;
    function getSaleCap(address) external returns (uint256) envfree;
    function getSalePrice(address) external returns (uint256) envfree;
    function getHasVoted(uint256, address) external returns (uint8) envfree;
    function getVoteWeight(uint256, address) external returns (uint96) envfree;
    function proposalThreshold() external returns (uint96) envfree;
    function proposalTTL() external returns (uint64) envfree;
    function timelockDelay() external returns (uint64) envfree;
    function quorumAbsolute() external returns (uint96) envfree;
    function minYesVotesAbsolute() external returns (uint96) envfree;
    function quorumBps() external returns (uint16) envfree;
    function ragequittable() external returns (bool) envfree;
    function renderer() external returns (address) envfree;
    function autoFutarchyParam() external returns (uint256) envfree;
    function autoFutarchyCap() external returns (uint256) envfree;
    function rewardToken() external returns (address) envfree;
    function config() external returns (uint64) envfree;
    function shares() external returns (address) envfree;
    function loot() external returns (address) envfree;
    function badges() external returns (address) envfree;

    // Summarize external calls
    function _.getPastVotes(address, uint48) external => NONDET;
    function _.getPastTotalSupply(uint48) external => NONDET;
    function _.getVotes(address) external => NONDET;
    function _.totalSupply() external => NONDET;
}

// ──────────────────────────────────────────────────────────────────
// Invariant 3: ERC-6909 transfer and transferFrom revert when
// isPermitReceipt[id] is true
// ──────────────────────────────────────────────────────────────────

rule transferRevertsForPermitReceipt(env e, address receiver, uint256 id, uint256 amount) {
    require getIsPermitReceipt(id);
    require e.msg.value == 0, "SAFE: not payable";

    transfer@withrevert(e, receiver, id, amount);

    assert lastReverted, "Invariant 3: transfer must revert for permit receipts";
}

rule transferFromRevertsForPermitReceipt(env e, address sender, address receiver,
    uint256 id, uint256 amount) {
    require getIsPermitReceipt(id);
    require e.msg.value == 0, "SAFE: not payable";

    transferFrom@withrevert(e, sender, receiver, id, amount);

    assert lastReverted, "Invariant 3: transferFrom must revert for permit receipts";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 4: executed[id] is a one-way latch
// ──────────────────────────────────────────────────────────────────

rule executedIsOneWayLatch(env e, method f, calldataarg args, uint256 id) {
    bool execBefore = getExecuted(id);

    f(e, args);

    bool execAfter = getExecuted(id);

    assert execBefore => execAfter,
        "Invariant 4: executed cannot revert from true to false";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 5: createdAt[id] is write-once
// ──────────────────────────────────────────────────────────────────

rule createdAtWriteOnce(env e, method f, calldataarg args, uint256 id) {
    uint64 before = getCreatedAt(id);

    f(e, args);

    uint64 after = getCreatedAt(id);

    assert before != 0 => after == before,
        "Invariant 5: createdAt cannot change once set";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 6: snapshotBlock[id] is write-once
// ──────────────────────────────────────────────────────────────────

rule snapshotBlockWriteOnce(env e, method f, calldataarg args, uint256 id) {
    uint48 before = getSnapshotBlock(id);

    f(e, args);

    uint48 after = getSnapshotBlock(id);

    assert before != 0 => after == before,
        "Invariant 6: snapshotBlock cannot change once set";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 7: supplySnapshot[id] is write-once
// ──────────────────────────────────────────────────────────────────

rule supplySnapshotWriteOnce(env e, method f, calldataarg args, uint256 id) {
    // supplySnapshot is only set in openProposal immediately after snapshotBlock,
    // so non-zero supplySnapshot implies non-zero snapshotBlock
    require getSupplySnapshot(id) != 0 => getSnapshotBlock(id) != 0,
        "SAFE: supplySnapshot and snapshotBlock are always set together in openProposal";

    uint256 before = getSupplySnapshot(id);

    f(e, args);

    uint256 after = getSupplySnapshot(id);

    assert before != 0 => after == before,
        "Invariant 7: supplySnapshot cannot change once set";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 8: queuedAt[id] is write-once
// ──────────────────────────────────────────────────────────────────

rule queuedAtWriteOnce(env e, method f, calldataarg args, uint256 id) {
    uint64 before = getQueuedAt(id);

    f(e, args);

    uint64 after = getQueuedAt(id);

    assert before != 0 => after == before,
        "Invariant 8: queuedAt cannot change once set";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 11: config is monotonically non-decreasing
// ──────────────────────────────────────────────────────────────────

rule configMonotonic(env e, method f, calldataarg args) {
    mathint before = config();
    require before < to_mathint(max_uint64),
        "SAFE: config counter cannot reach max_uint64 (18.4 quintillion DAO calls)";

    f(e, args);

    mathint after = config();

    assert after >= before,
        "Invariant 11: config must be monotonically non-decreasing";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 13: castVote reverts if executed[id] is true
// ──────────────────────────────────────────────────────────────────

rule castVoteRevertsIfExecuted(env e, uint256 id, uint8 support) {
    require getExecuted(id);
    require e.msg.value == 0, "SAFE: not payable";

    castVote@withrevert(e, id, support);

    assert lastReverted, "Invariant 13: castVote must revert if executed";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 14: castVote reverts if hasVoted[id][msg.sender] != 0
// ──────────────────────────────────────────────────────────────────

rule castVoteRevertsIfAlreadyVoted(env e, uint256 id, uint8 support) {
    require getHasVoted(id, e.msg.sender) != 0;
    require !getExecuted(id);
    require support <= 2;
    require getSnapshotBlock(id) != 0;
    require e.msg.value == 0, "SAFE: not payable";

    castVote@withrevert(e, id, support);

    assert lastReverted, "Invariant 14: castVote must revert if already voted";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 15: castVote only accepts support in {0, 1, 2}
// ──────────────────────────────────────────────────────────────────

rule castVoteRevertsOnInvalidSupport(env e, uint256 id, uint8 support) {
    require support > 2;
    require !getExecuted(id);
    require e.msg.value == 0, "SAFE: not payable";

    castVote@withrevert(e, id, support);

    assert lastReverted, "Invariant 15: castVote must revert for support > 2";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 30: proposalThreshold only changes via setProposalThreshold
// ──────────────────────────────────────────────────────────────────

rule proposalThresholdOnlyViaSet(env e, method f, calldataarg args) {
    uint96 before = proposalThreshold();

    f(e, args);

    uint96 after = proposalThreshold();

    assert after != before =>
        f.selector == sig:setProposalThreshold(uint96).selector,
        "Invariant 30: proposalThreshold only changes via setProposalThreshold";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 31: proposalTTL only changes via setProposalTTL
// ──────────────────────────────────────────────────────────────────

rule proposalTTLOnlyViaSet(env e, method f, calldataarg args) {
    uint64 before = proposalTTL();

    f(e, args);

    uint64 after = proposalTTL();

    assert after != before =>
        f.selector == sig:setProposalTTL(uint64).selector,
        "Invariant 31: proposalTTL only changes via setProposalTTL";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 32: timelockDelay only changes via setTimelockDelay
// ──────────────────────────────────────────────────────────────────

rule timelockDelayOnlyViaSet(env e, method f, calldataarg args) {
    uint64 before = timelockDelay();

    f(e, args);

    uint64 after = timelockDelay();

    assert after != before =>
        f.selector == sig:setTimelockDelay(uint64).selector,
        "Invariant 32: timelockDelay only changes via setTimelockDelay";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 33: quorumAbsolute only changes via setQuorumAbsolute
// ──────────────────────────────────────────────────────────────────

rule quorumAbsoluteOnlyViaSet(env e, method f, calldataarg args) {
    uint96 before = quorumAbsolute();

    f(e, args);

    uint96 after = quorumAbsolute();

    assert after != before =>
        f.selector == sig:setQuorumAbsolute(uint96).selector,
        "Invariant 33: quorumAbsolute only changes via setQuorumAbsolute";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 34: minYesVotesAbsolute only changes via set
// ──────────────────────────────────────────────────────────────────

rule minYesVotesAbsoluteOnlyViaSet(env e, method f, calldataarg args) {
    uint96 before = minYesVotesAbsolute();

    f(e, args);

    uint96 after = minYesVotesAbsolute();

    assert after != before =>
        f.selector == sig:setMinYesVotesAbsolute(uint96).selector,
        "Invariant 34: minYesVotesAbsolute only changes via setMinYesVotesAbsolute";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 35: quorumBps only changes via setQuorumBps
// ──────────────────────────────────────────────────────────────────

rule quorumBpsOnlyViaSet(env e, method f, calldataarg args) {
    uint16 before = quorumBps();

    f(e, args);

    uint16 after = quorumBps();

    assert after != before =>
        f.selector == sig:setQuorumBps(uint16).selector,
        "Invariant 35: quorumBps only changes via setQuorumBps";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 36: ragequittable only changes via setRagequittable
// ──────────────────────────────────────────────────────────────────

rule ragequittableOnlyViaSet(env e, method f, calldataarg args) {
    bool before = ragequittable();

    f(e, args);

    bool after = ragequittable();

    assert after != before =>
        f.selector == sig:setRagequittable(bool).selector,
        "Invariant 36: ragequittable only changes via setRagequittable";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 37: renderer only changes via setRenderer
// ──────────────────────────────────────────────────────────────────

rule rendererOnlyViaSet(env e, method f, calldataarg args) {
    address before = renderer();

    f(e, args);

    address after = renderer();

    assert after != before =>
        f.selector == sig:setRenderer(address).selector,
        "Invariant 37: renderer only changes via setRenderer";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 38: autoFutarchyParam/Cap only via setAutoFutarchy
// ──────────────────────────────────────────────────────────────────

rule autoFutarchyOnlyViaSet(env e, method f, calldataarg args) {
    uint256 paramBefore = autoFutarchyParam();
    uint256 capBefore = autoFutarchyCap();

    f(e, args);

    uint256 paramAfter = autoFutarchyParam();
    uint256 capAfter = autoFutarchyCap();

    assert (paramAfter != paramBefore || capAfter != capBefore) =>
        f.selector == sig:setAutoFutarchy(uint256, uint256).selector,
        "Invariant 38: autoFutarchy only changes via setAutoFutarchy";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 39: rewardToken only changes via setFutarchyRewardToken
// ──────────────────────────────────────────────────────────────────

rule rewardTokenOnlyViaSet(env e, method f, calldataarg args) {
    address before = rewardToken();

    f(e, args);

    address after = rewardToken();

    assert after != before =>
        f.selector == sig:setFutarchyRewardToken(address).selector,
        "Invariant 39: rewardToken only changes via setFutarchyRewardToken";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 43: buyShares reverts if sale not active
// ──────────────────────────────────────────────────────────────────

rule buySharesRevertsIfNotActive(env e, address payToken, uint256 shareAmount, uint256 maxPay) {
    require !getSaleActive(payToken);
    require shareAmount > 0;

    buyShares@withrevert(e, payToken, shareAmount, maxPay);

    assert lastReverted, "Invariant 43: buyShares must revert when sale not active";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 44: buyShares reverts if shareAmount == 0
// ──────────────────────────────────────────────────────────────────

rule buySharesRevertsOnZeroAmount(env e, address payToken, uint256 maxPay) {
    buyShares@withrevert(e, payToken, 0, maxPay);

    assert lastReverted, "Invariant 44: buyShares must revert when shareAmount == 0";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 46: buyShares decreases cap by shareAmount
// ──────────────────────────────────────────────────────────────────

rule buySharesDecreasesCap(env e, address payToken, uint256 shareAmount, uint256 maxPay) {
    uint256 capBefore = getSaleCap(payToken);
    require capBefore > 0;
    require shareAmount > 0 && shareAmount <= capBefore;

    buyShares(e, payToken, shareAmount, maxPay);

    uint256 capAfter = getSaleCap(payToken);

    assert to_mathint(capAfter) == to_mathint(capBefore) - to_mathint(shareAmount),
        "Invariant 46: cap must decrease by exactly shareAmount";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 47: buyShares reverts on slippage
// ──────────────────────────────────────────────────────────────────

rule buySharesRevertsOnSlippage(env e, address payToken, uint256 shareAmount, uint256 maxPay) {
    require shareAmount > 0 && maxPay > 0;
    require getSaleActive(payToken);

    uint256 price = getSalePrice(payToken);
    require price > 0;
    mathint cost = to_mathint(shareAmount) * to_mathint(price);
    require cost > to_mathint(maxPay);

    uint256 cap = getSaleCap(payToken);
    require cap == 0 || shareAmount <= cap;

    buyShares@withrevert(e, payToken, shareAmount, maxPay);

    assert lastReverted, "Invariant 47: buyShares must revert on slippage violation";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 48: spendAllowance decreases allowance by amount
// ──────────────────────────────────────────────────────────────────

rule spendAllowanceDecreases(env e, address token, uint256 amount) {
    mathint allowBefore = getAllowance(token, e.msg.sender);
    require allowBefore >= to_mathint(amount);
    require e.msg.value == 0, "SAFE: not payable";

    spendAllowance(e, token, amount);

    mathint allowAfter = getAllowance(token, e.msg.sender);

    assert allowAfter == allowBefore - to_mathint(amount),
        "Invariant 48: allowance must decrease by exactly amount";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 49: spendAllowance reverts if insufficient
// ──────────────────────────────────────────────────────────────────

rule spendAllowanceRevertsIfInsufficient(env e, address token, uint256 amount) {
    mathint allowBefore = getAllowance(token, e.msg.sender);
    require allowBefore < to_mathint(amount);
    require e.msg.value == 0, "SAFE: not payable";

    spendAllowance@withrevert(e, token, amount);

    assert lastReverted, "Invariant 49: spendAllowance must revert if insufficient";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 40: isPermitReceipt[id] only changes via setPermitReceipt
// ──────────────────────────────────────────────────────────────────

rule isPermitReceiptOnlyViaSet(env e, method f, calldataarg args, uint256 id) {
    bool before = getIsPermitReceipt(id);

    f(e, args);

    bool after = getIsPermitReceipt(id);

    assert after != before =>
        f.selector == sig:setPermitReceipt(uint256).selector,
        "Invariant 40: isPermitReceipt only changes via setPermitReceipt";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 45: setSale reverts if pricePerShare == 0
// ──────────────────────────────────────────────────────────────────

rule setSaleRevertsOnZeroPrice(env e, address payToken, uint256 pricePerShare,
    uint256 cap, bool minting, bool active, bool isLoot) {
    require pricePerShare == 0;

    setSale@withrevert(e, payToken, pricePerShare, cap, minting, active, isLoot);

    assert lastReverted, "Invariant 45: setSale must revert when pricePerShare == 0";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 94: shares, loot, badges addresses never change
// (set during init which is stripped; no setters exist)
// ──────────────────────────────────────────────────────────────────

rule sharesAddressImmutable(env e, method f, calldataarg args) {
    address before = shares();

    f(e, args);

    address after = shares();

    assert after == before,
        "Invariant 94: shares address must never change";
}

rule lootAddressImmutable(env e, method f, calldataarg args) {
    address before = loot();

    f(e, args);

    address after = loot();

    assert after == before,
        "Invariant 94: loot address must never change";
}

rule badgesAddressImmutable(env e, method f, calldataarg args) {
    address before = badges();

    f(e, args);

    address after = badges();

    assert after == before,
        "Invariant 94: badges address must never change";
}

// ──────────────────────────────────────────────────────────────────
// Satisfy rules (sanity)
// ──────────────────────────────────────────────────────────────────

rule castVoteSanity(env e, uint256 id, uint8 support) {
    require e.msg.value == 0, "SAFE: not payable";
    castVote(e, id, support);
    satisfy true;
}

rule buySharesSanity(env e, address payToken, uint256 shareAmount, uint256 maxPay) {
    buyShares(e, payToken, shareAmount, maxPay);
    satisfy true;
}

rule spendAllowanceSanity(env e, address token, uint256 amount) {
    require e.msg.value == 0, "SAFE: not payable";
    spendAllowance(e, token, amount);
    satisfy true;
}
