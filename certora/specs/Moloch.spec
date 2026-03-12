// Moloch.spec — Formal verification of Moloch core DAO contract
// Invariants 1, 3-8, 10-11, 13-17, 19-24, 27-28, 30-41, 43-49, 51-52, 94 from certora/invariants.md

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

    // Ragequit
    function ragequit(uint256, uint256) external;

    // Futarchy
    function fundFutarchy(uint256, uint256) external;
    function resolveFutarchyNo(uint256) external;
    function cashOutFutarchy(uint256, uint256) external;
    function finalizeFutarchyHarness(uint256, uint8) external;
    function getFutarchyEnabled(uint256) external returns (bool) envfree;
    function getFutarchyResolved(uint256) external returns (bool) envfree;
    function getFutarchyPool(uint256) external returns (uint256) envfree;
    function getFutarchyPayoutPerUnit(uint256) external returns (uint256) envfree;
    function getFutarchyFinalWinningSupply(uint256) external returns (uint256) envfree;
    function getFutarchyWinner(uint256) external returns (uint8) envfree;
    function getReceiptId(uint256, uint8) external returns (uint256) envfree;

    // Math
    function mulDiv(uint256, uint256, uint256) external returns (uint256) envfree;

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
    function getForVotes(uint256) external returns (uint96) envfree;
    function getAgainstVotes(uint256) external returns (uint96) envfree;
    function getAbstainVotes(uint256) external returns (uint96) envfree;
    function getState(uint256) external returns (uint8) envfree;
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
// Definitions
// ──────────────────────────────────────────────────────────────────

definition CVL_Executed() returns uint8 = 6;

// ──────────────────────────────────────────────────────────────────
// Invariant 1: ERC-6909 totalSupply[id] equals sum of balanceOf
// ──────────────────────────────────────────────────────────────────

ghost mapping(uint256 => mathint) g_sumBalances6909 {
    init_state axiom forall uint256 id. g_sumBalances6909[id] == 0;
}

hook Sstore balanceOf[KEY address owner][KEY uint256 id] uint256 newVal (uint256 oldVal) {
    g_sumBalances6909[id] = g_sumBalances6909[id] + newVal - oldVal;
}

hook Sload uint256 val balanceOf[KEY address owner][KEY uint256 id] {
    require to_mathint(val) <= g_sumBalances6909[id],
        "SAFE: individual balance cannot exceed sum of all balances";
}

invariant totalSupplyIsSumOfBalances6909(uint256 id)
    to_mathint(totalSupply(id)) == g_sumBalances6909[id];

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
// Invariant 10: Executed state is terminal — cannot transition
// to any other state
// ──────────────────────────────────────────────────────────────────

rule executedStateIsTerminal(env e, method f, calldataarg args, uint256 id) {
    require getState(id) == CVL_Executed();

    f(e, args);

    assert getState(id) == CVL_Executed(),
        "Invariant 10: Executed state cannot transition to any other state";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 16: castVote post-conditions — hasVoted and voteWeight
// are set correctly after a successful vote
// ──────────────────────────────────────────────────────────────────

rule castVotePostConditions(env e, uint256 id, uint8 support) {
    require !getExecuted(id);
    require getHasVoted(id, e.msg.sender) == 0;
    require support <= 2;
    require getSnapshotBlock(id) != 0;
    require e.msg.value == 0, "SAFE: not payable";

    castVote(e, id, support);

    assert to_mathint(getHasVoted(id, e.msg.sender)) == to_mathint(support) + 1,
        "Invariant 16: hasVoted must equal support + 1";
    assert getVoteWeight(id, e.msg.sender) > 0,
        "Invariant 16: voteWeight must be non-zero after successful vote";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 17: castVote tally integrity — only the relevant tally
// component changes; others remain unchanged
// ──────────────────────────────────────────────────────────────────

rule castVoteTallyIntegrity(env e, uint256 id, uint8 support) {
    require e.msg.value == 0, "SAFE: not payable";

    uint96 forBefore = getForVotes(id);
    uint96 againstBefore = getAgainstVotes(id);
    uint96 abstainBefore = getAbstainVotes(id);

    castVote(e, id, support);

    // Other tally components unchanged
    assert support != 1 => getForVotes(id) == forBefore,
        "Invariant 17: forVotes unchanged when not voting for";
    assert support != 0 => getAgainstVotes(id) == againstBefore,
        "Invariant 17: againstVotes unchanged when not voting against";
    assert support != 2 => getAbstainVotes(id) == abstainBefore,
        "Invariant 17: abstainVotes unchanged when not voting abstain";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 41: All governance parameter setters revert if
// msg.sender != address(this) (onlyDAO)
// ──────────────────────────────────────────────────────────────────

rule governanceSettersRevertIfNotDAO(env e, method f, calldataarg args)
filtered {
    f -> f.selector == sig:setProposalThreshold(uint96).selector
      || f.selector == sig:setProposalTTL(uint64).selector
      || f.selector == sig:setTimelockDelay(uint64).selector
      || f.selector == sig:setQuorumAbsolute(uint96).selector
      || f.selector == sig:setMinYesVotesAbsolute(uint96).selector
      || f.selector == sig:setQuorumBps(uint16).selector
      || f.selector == sig:setRagequittable(bool).selector
      || f.selector == sig:setRenderer(address).selector
      || f.selector == sig:setAutoFutarchy(uint256, uint256).selector
      || f.selector == sig:setFutarchyRewardToken(address).selector
      || f.selector == sig:setPermitReceipt(uint256).selector
      || f.selector == sig:bumpConfig().selector
      || f.selector == sig:setSale(address, uint256, uint256, bool, bool, bool).selector
      || f.selector == sig:setAllowance(address, address, uint256).selector
} {
    require e.msg.sender != currentContract;

    f@withrevert(e, args);

    assert lastReverted, "Invariant 41: governance setters must revert when sender != DAO";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 19: futarchy[id].resolved is a one-way latch
// ──────────────────────────────────────────────────────────────────

rule futarchyResolvedIsOneWayLatch(env e, method f, calldataarg args, uint256 id) {
    bool resolvedBefore = getFutarchyResolved(id);

    f(e, args);

    bool resolvedAfter = getFutarchyResolved(id);

    assert resolvedBefore => resolvedAfter,
        "Invariant 19: futarchy resolved cannot revert from true to false";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 20: futarchy[id].payoutPerUnit is write-once
// ──────────────────────────────────────────────────────────────────

rule payoutPerUnitWriteOnce(env e, method f, calldataarg args, uint256 id) {
    uint256 ppuBefore = getFutarchyPayoutPerUnit(id);

    // SAFE: payoutPerUnit and resolved are set atomically in _finalizeFutarchy
    require ppuBefore != 0 => getFutarchyResolved(id),
        "SAFE: payoutPerUnit is only set when resolved is set";

    f(e, args);

    uint256 ppuAfter = getFutarchyPayoutPerUnit(id);

    assert ppuBefore != 0 => ppuAfter == ppuBefore,
        "Invariant 20: payoutPerUnit cannot change once set";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 21: cashOutFutarchy reverts if not resolved
// ──────────────────────────────────────────────────────────────────

rule cashOutRevertsIfNotResolved(env e, uint256 id, uint256 amount) {
    require !getFutarchyResolved(id);
    require e.msg.value == 0, "SAFE: not payable";

    cashOutFutarchy@withrevert(e, id, amount);

    assert lastReverted, "Invariant 21: cashOutFutarchy must revert when not resolved";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 22: fundFutarchy reverts if resolved
// ──────────────────────────────────────────────────────────────────

rule fundFutarchyRevertsIfResolved(env e, uint256 id, uint256 amount) {
    require getFutarchyResolved(id);
    require amount > 0;
    require e.msg.value == 0, "SAFE: not payable";

    fundFutarchy@withrevert(e, id, amount);

    assert lastReverted, "Invariant 22: fundFutarchy must revert when already resolved";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 23: After finalization, finalWinningSupply equals
// totalSupply of the winning receipt token at that moment
// ──────────────────────────────────────────────────────────────────

rule finalWinningSupplyMatchesReceipt(env e, uint256 id, uint8 winner) {
    require winner <= 2, "SAFE: winner is a support value (0, 1, or 2)";
    require getFutarchyEnabled(id);
    require !getFutarchyResolved(id);
    require e.msg.value == 0, "SAFE: not payable";

    uint256 rid = getReceiptId(id, winner);
    uint256 receiptSupply = totalSupply(rid);

    finalizeFutarchyHarness(e, id, winner);

    // Only check if pool and winSupply were both non-zero (otherwise field stays 0)
    assert getFutarchyPool(id) != 0 && receiptSupply != 0 =>
        getFutarchyFinalWinningSupply(id) == receiptSupply,
        "Invariant 23: finalWinningSupply must equal receipt totalSupply at resolution";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 24: mulDiv(pool, amt, total) <= pool when amt <= total
// (ragequit payout can never exceed pool)
// ──────────────────────────────────────────────────────────────────

rule mulDivBoundLemma(uint256 pool, uint256 amt, uint256 total) {
    require total > 0, "SAFE: denominator must be positive";
    require amt <= total, "SAFE: ragequit burn amount cannot exceed total supply";

    // Avoid overflow in pool * amt
    require pool <= max_uint128, "SAFE: bound pool to prevent overflow in mulDiv";
    require amt <= max_uint128, "SAFE: bound amt to prevent overflow in mulDiv";

    uint256 result = mulDiv(pool, amt, total);

    assert to_mathint(result) <= to_mathint(pool),
        "Invariant 24: payout must not exceed pool";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 27: ragequit reverts if sharesToBurn == 0 && lootToBurn == 0
// ──────────────────────────────────────────────────────────────────

rule ragequitRevertsOnZeroBurn(env e) {
    require e.msg.value == 0, "SAFE: not payable";

    ragequit@withrevert(e, 0, 0);

    assert lastReverted, "Invariant 27: ragequit must revert when both burn amounts are zero";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 28: ragequit reverts if ragequittable is false
// ──────────────────────────────────────────────────────────────────

rule ragequitRevertsIfNotRagequittable(env e, uint256 sharesToBurn, uint256 lootToBurn) {
    require !ragequittable();
    require e.msg.value == 0, "SAFE: not payable";

    ragequit@withrevert(e, sharesToBurn, lootToBurn);

    assert lastReverted, "Invariant 28: ragequit must revert when ragequittable is false";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 51: executeByVotes reverts if proposal is Unopened
// (snapshotBlock[id] == 0)
// ──────────────────────────────────────────────────────────────────

rule executeRevertsIfUnopened(env e, uint256 id) {
    require getSnapshotBlock(id) == 0;
    require !getExecuted(id);
    require e.msg.value == 0, "SAFE: not payable";

    executeByVotes@withrevert(e, id);

    assert lastReverted, "Invariant 51: executeByVotes must revert for Unopened proposals";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 52: executeByVotes auto-queue — when timelockDelay != 0
// and queuedAt[id] == 0, sets queuedAt and does not execute
// ──────────────────────────────────────────────────────────────────

rule executeTimelockAutoQueue(env e, uint256 id) {
    require timelockDelay() != 0;
    require getQueuedAt(id) == 0;
    require !getExecuted(id);
    require getSnapshotBlock(id) != 0;
    require e.msg.value == 0, "SAFE: not payable";
    require e.block.timestamp <= max_uint64, "SAFE: timestamp fits in uint64";

    executeByVotes(e, id);

    assert getQueuedAt(id) == assert_uint64(e.block.timestamp),
        "Invariant 52: auto-queue must set queuedAt to block.timestamp";
    assert !getExecuted(id),
        "Invariant 52: auto-queue must not set executed to true";
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

rule fundFutarchySanity(env e, uint256 id, uint256 amount) {
    require e.msg.value == 0, "SAFE: not payable";
    fundFutarchy(e, id, amount);
    satisfy true;
}

rule cashOutFutarchySanity(env e, uint256 id, uint256 amount) {
    require e.msg.value == 0, "SAFE: not payable";
    cashOutFutarchy(e, id, amount);
    satisfy true;
}

rule ragequitSanity(env e, uint256 sharesToBurn, uint256 lootToBurn) {
    require e.msg.value == 0, "SAFE: not payable";
    ragequit(e, sharesToBurn, lootToBurn);
    satisfy true;
}
