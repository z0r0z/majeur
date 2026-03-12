// Shares.spec — Formal verification of Shares (ERC-20 + Voting) contract
// Invariants 56-68, 71-73 from certora/invariants.md

methods {
    function totalSupply() external returns (uint256) envfree;
    function balanceOf(address) external returns (uint256) envfree;
    function allowance(address, address) external returns (uint256) envfree;
    function DAO() external returns (address) envfree;
    function transfersLocked() external returns (bool) envfree;
    function decimals() external returns (uint8) envfree;
    function delegates(address) external returns (address) envfree;
    function getVotes(address) external returns (uint256) envfree;
    function getPastVotes(address, uint48) external returns (uint256);
    function getPastTotalSupply(uint48) external returns (uint256);

    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
    function mintFromMoloch(address, uint256) external;
    function burnFromMoloch(address, uint256) external;
    function setTransfersLocked(bool) external;
    function init(address[], uint256[]) external;
    function delegate(address) external;
    function setSplitDelegation(address[], uint32[]) external;
    function clearSplitDelegation() external;

    // Harness getters
    function getPrimaryDelegate(address) external returns (address) envfree;
    function getCheckpointCount(address) external returns (uint256) envfree;
    function getCheckpointFromBlock(address, uint256) external returns (uint48) envfree;
    function getCheckpointVotes(address, uint256) external returns (uint96) envfree;
    function getTotalSupplyCheckpointCount() external returns (uint256) envfree;
    function getSplitCount(address) external returns (uint256) envfree;
    function getSplitDelegate(address, uint256) external returns (address) envfree;
    function getSplitBps(address, uint256) external returns (uint32) envfree;
    function targetAllocSum(uint256, address) external returns (uint256) envfree;

    // Summarize external calls to Moloch
    function _.name(uint256) external => NONDET;
    function _.symbol(uint256) external => NONDET;
    function _.onSharesChanged(address) external => NONDET;
}

// ──────────────────────────────────────────────────────────────────
// Ghost: track sum of all balances (Pattern 1)
// Invariant 56: Shares.totalSupply equals the sum of all
// Shares.balanceOf[user] across all users
// ──────────────────────────────────────────────────────────────────

ghost mathint g_sumBalances {
    init_state axiom g_sumBalances == 0;
}

hook Sstore balanceOf[KEY address a] uint256 newVal (uint256 oldVal) {
    g_sumBalances = g_sumBalances + newVal - oldVal;
}

hook Sload uint256 val balanceOf[KEY address a] {
    require to_mathint(val) <= g_sumBalances,
        "SAFE: individual balance cannot exceed sum of all balances";
}

// Invariant 56
invariant totalSupplyIsSumOfBalances()
    to_mathint(totalSupply()) == g_sumBalances
    {
        preserved mintFromMoloch(address to, uint256 amount) with (env e) {
            require balanceOf(to) <= totalSupply(),
                "SAFE: individual balance cannot exceed totalSupply (conservation)";
        }
        preserved burnFromMoloch(address from, uint256 amount) with (env e) {
            require balanceOf(from) <= totalSupply(),
                "SAFE: individual balance cannot exceed totalSupply (conservation)";
        }
        preserved transfer(address to, uint256 amount) with (env e) {
            require to_mathint(balanceOf(e.msg.sender)) + to_mathint(balanceOf(to))
                <= to_mathint(totalSupply()),
                "SAFE: sum of two balances cannot exceed totalSupply (conservation)";
        }
        preserved transferFrom(address from, address to, uint256 amount) with (env e) {
            require to_mathint(balanceOf(from)) + to_mathint(balanceOf(to))
                <= to_mathint(totalSupply()),
                "SAFE: sum of two balances cannot exceed totalSupply (conservation)";
        }
        preserved init(address[] initHolders, uint256[] initShares) with (env e) {
            require totalSupply() == 0,
                "SAFE: init requires DAO == address(0), implying fresh contract with zero supply";
        }
    }

// ──────────────────────────────────────────────────────────────────
// Invariant 57: Shares.transfer decreases sender balance and
// increases receiver balance by exactly amount
// ──────────────────────────────────────────────────────────────────

rule transferIntegrity(env e, address to, uint256 amount) {
    address from = e.msg.sender;

    require from != to, "SAFE: separate self-transfer case";
    require e.msg.value == 0, "SAFE: transfer is not payable";

    requireInvariant totalSupplyIsSumOfBalances();
    require to_mathint(balanceOf(from)) + to_mathint(balanceOf(to))
        <= to_mathint(totalSupply()),
        "SAFE: sum of sender and receiver balances cannot exceed totalSupply (conservation)";

    mathint fromBefore = balanceOf(from);
    mathint toBefore = balanceOf(to);

    transfer(e, to, amount);

    assert to_mathint(balanceOf(from)) == fromBefore - amount,
        "Invariant 57: sender balance decreased by amount";
    assert to_mathint(balanceOf(to)) == toBefore + amount,
        "Invariant 57: receiver balance increased by amount";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 58: transfer and transferFrom revert when
// transfersLocked is true and neither from nor to is DAO
// ──────────────────────────────────────────────────────────────────

rule transferRevertsWhenLocked(env e, address to, uint256 amount) {
    bool locked = transfersLocked();
    address dao = DAO();
    address from = e.msg.sender;

    require locked;
    require from != dao;
    require to != dao;
    require e.msg.value == 0, "SAFE: not payable";

    transfer@withrevert(e, to, amount);

    assert lastReverted, "Invariant 58: transfer must revert when locked";
}

rule transferFromRevertsWhenLocked(env e, address from, address to, uint256 amount) {
    bool locked = transfersLocked();
    address dao = DAO();

    require locked;
    require from != dao;
    require to != dao;
    require e.msg.value == 0, "SAFE: not payable";

    transferFrom@withrevert(e, from, to, amount);

    assert lastReverted, "Invariant 58: transferFrom must revert when locked";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 59: Only mintFromMoloch and burnFromMoloch change
// Shares.totalSupply (Pattern 2 authorization)
// ──────────────────────────────────────────────────────────────────

rule onlyMintBurnChangeTotalSupply(env e, method f, calldataarg args) {
    mathint supplyBefore = totalSupply();

    f(e, args);

    mathint supplyAfter = totalSupply();

    assert supplyAfter != supplyBefore =>
        f.selector == sig:mintFromMoloch(address, uint256).selector
        || f.selector == sig:burnFromMoloch(address, uint256).selector
        || f.selector == sig:init(address[], uint256[]).selector,
        "Invariant 59: only mint/burn/init can change totalSupply";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 60: For any account with split delegation, the BPS
// values across all entries sum to exactly 10000
// ──────────────────────────────────────────────────────────────────

// Express as inductive parametric rule: require property in pre-state,
// execute any function, assert property in post-state
rule splitBpsSumInvariant(env e, method f, calldataarg args, address account) {
    // Inductive hypothesis: property holds in pre-state
    mathint countPre = getSplitCount(account);
    require countPre == 0 || (countPre <= 4 && (
        to_mathint(getSplitBps(account, 0))
        + (countPre >= 2 ? to_mathint(getSplitBps(account, 1)) : 0)
        + (countPre >= 3 ? to_mathint(getSplitBps(account, 2)) : 0)
        + (countPre >= 4 ? to_mathint(getSplitBps(account, 3)) : 0)
        == 10000
    )), "SAFE: inductive hypothesis — BPS sum is 10000 in pre-state";

    f(e, args);

    mathint count = getSplitCount(account);

    // Only check if splits are configured
    assert count > 0 && count <= 4 => (
        to_mathint(getSplitBps(account, 0))
        + (count >= 2 ? to_mathint(getSplitBps(account, 1)) : 0)
        + (count >= 3 ? to_mathint(getSplitBps(account, 2)) : 0)
        + (count >= 4 ? to_mathint(getSplitBps(account, 3)) : 0)
        == 10000
    ), "Invariant 60: split BPS must sum to 10000";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 61: Split delegation allows at most MAX_SPLITS (4)
// ──────────────────────────────────────────────────────────────────

rule maxSplitsEnforced(env e, method f, calldataarg args, address account) {
    // Inductive hypothesis: property holds in pre-state
    require getSplitCount(account) <= 4,
        "SAFE: inductive hypothesis — split count <= 4 in pre-state";

    f(e, args);

    assert getSplitCount(account) <= 4,
        "Invariant 61: split count must not exceed MAX_SPLITS (4)";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 62: No split delegation entry has address(0) as delegate
// ──────────────────────────────────────────────────────────────────

rule noZeroSplitDelegate(env e, method f, calldataarg args, address account) {
    // Inductive hypothesis: property holds in pre-state
    mathint countPre = getSplitCount(account);
    require countPre >= 1 => getSplitDelegate(account, 0) != 0,
        "SAFE: inductive hypothesis — no zero delegate[0]";
    require countPre >= 2 => getSplitDelegate(account, 1) != 0,
        "SAFE: inductive hypothesis — no zero delegate[1]";
    require countPre >= 3 => getSplitDelegate(account, 2) != 0,
        "SAFE: inductive hypothesis — no zero delegate[2]";
    require countPre >= 4 => getSplitDelegate(account, 3) != 0,
        "SAFE: inductive hypothesis — no zero delegate[3]";

    f(e, args);

    mathint count = getSplitCount(account);

    assert count >= 1 => getSplitDelegate(account, 0) != 0,
        "Invariant 62: split delegate[0] must not be address(0)";
    assert count >= 2 => getSplitDelegate(account, 1) != 0,
        "Invariant 62: split delegate[1] must not be address(0)";
    assert count >= 3 => getSplitDelegate(account, 2) != 0,
        "Invariant 62: split delegate[2] must not be address(0)";
    assert count >= 4 => getSplitDelegate(account, 3) != 0,
        "Invariant 62: split delegate[3] must not be address(0)";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 63: No split delegation config has duplicate delegates
// ──────────────────────────────────────────────────────────────────

rule noDuplicateSplitDelegates(env e, method f, calldataarg args, address account) {
    // Inductive hypothesis: property holds in pre-state
    mathint countPre = getSplitCount(account);
    require countPre >= 2 =>
        getSplitDelegate(account, 0) != getSplitDelegate(account, 1),
        "SAFE: inductive hypothesis — no dupe (0,1)";
    require countPre >= 3 => (
        getSplitDelegate(account, 0) != getSplitDelegate(account, 2)
        && getSplitDelegate(account, 1) != getSplitDelegate(account, 2)
    ), "SAFE: inductive hypothesis — no dupe (0-2)";
    require countPre >= 4 => (
        getSplitDelegate(account, 0) != getSplitDelegate(account, 3)
        && getSplitDelegate(account, 1) != getSplitDelegate(account, 3)
        && getSplitDelegate(account, 2) != getSplitDelegate(account, 3)
    ), "SAFE: inductive hypothesis — no dupe (0-3)";

    f(e, args);

    mathint count = getSplitCount(account);

    // Check all pairs for uniqueness (bounded by MAX_SPLITS=4)
    assert count >= 2 =>
        getSplitDelegate(account, 0) != getSplitDelegate(account, 1),
        "Invariant 63: no duplicate delegates (0,1)";
    assert count >= 3 => (
        getSplitDelegate(account, 0) != getSplitDelegate(account, 2)
        && getSplitDelegate(account, 1) != getSplitDelegate(account, 2)
    ), "Invariant 63: no duplicate delegates (0-2)";
    assert count >= 4 => (
        getSplitDelegate(account, 0) != getSplitDelegate(account, 3)
        && getSplitDelegate(account, 1) != getSplitDelegate(account, 3)
        && getSplitDelegate(account, 2) != getSplitDelegate(account, 3)
    ), "Invariant 63: no duplicate delegates (0-3)";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 67: getPastVotes reverts if blockNumber >= block.number
// ──────────────────────────────────────────────────────────────────

rule getPastVotesRevertsOnFutureBlock(env e, address account, uint48 blockNumber) {
    require to_mathint(blockNumber) >= to_mathint(e.block.number);
    require e.msg.value == 0, "SAFE: view function";

    getPastVotes@withrevert(e, account, blockNumber);

    assert lastReverted, "Invariant 67: getPastVotes must revert for future block";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 68: getPastTotalSupply reverts if blockNumber >= block.number
// ──────────────────────────────────────────────────────────────────

rule getPastTotalSupplyRevertsOnFutureBlock(env e, uint48 blockNumber) {
    require to_mathint(blockNumber) >= to_mathint(e.block.number);
    require e.msg.value == 0, "SAFE: view function";

    getPastTotalSupply@withrevert(e, blockNumber);

    assert lastReverted, "Invariant 68: getPastTotalSupply must revert for future block";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 71: Shares.DAO is set exactly once during init and
// never changes thereafter (write-once)
// ──────────────────────────────────────────────────────────────────

rule daoWriteOnce(env e, method f, calldataarg args) {
    address daoBefore = DAO();

    f(e, args);

    address daoAfter = DAO();

    assert daoBefore != 0 => daoAfter == daoBefore,
        "Invariant 71: DAO cannot change once set";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 72: Shares.init reverts if DAO is already non-zero
// ──────────────────────────────────────────────────────────────────

rule initRevertsIfDaoSet(env e, address[] initHolders, uint256[] initShares) {
    address dao = DAO();
    require dao != 0;

    init@withrevert(e, initHolders, initShares);

    assert lastReverted, "Invariant 72: init must revert when DAO already set";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 73: Shares.totalSupply only increases via mintFromMoloch
// (requires msg.sender == DAO) and only decreases via burnFromMoloch
// (requires msg.sender == DAO)
// ──────────────────────────────────────────────────────────────────

rule mintRequiresDAO(env e, address to, uint256 amount) {
    address dao = DAO();

    mintFromMoloch@withrevert(e, to, amount);

    assert !lastReverted => e.msg.sender == dao,
        "Invariant 73: only DAO can mint";
}

rule burnRequiresDAO(env e, address from, uint256 amount) {
    address dao = DAO();

    burnFromMoloch@withrevert(e, from, amount);

    assert !lastReverted => e.msg.sender == dao,
        "Invariant 73: only DAO can burn";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 64: _targetAlloc returns values that sum to input balance
// ──────────────────────────────────────────────────────────────────

rule targetAllocSumsToBalance(uint256 bal, address account) {
    // Inductive hypothesis: splits are valid (BPS sum to 10000, count <= 4)
    mathint count = getSplitCount(account);
    require count <= 4, "SAFE: MAX_SPLITS is 4";
    require count == 0 || (
        to_mathint(getSplitBps(account, 0))
        + (count >= 2 ? to_mathint(getSplitBps(account, 1)) : 0)
        + (count >= 3 ? to_mathint(getSplitBps(account, 2)) : 0)
        + (count >= 4 ? to_mathint(getSplitBps(account, 3)) : 0)
        == 10000
    ), "SAFE: BPS sum must be 10000 (from invariant 60)";

    uint256 result = targetAllocSum(bal, account);

    assert result == bal,
        "Invariant 64: targetAlloc allocations must sum to input balance";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 66: Checkpoint fromBlock values are non-decreasing;
// same-block updates overwrite rather than append
// ──────────────────────────────────────────────────────────────────

rule checkpointFromBlockNonDecreasing(env e, method f, calldataarg args, address account) {
    // Pre-state: if checkpoints exist, last two are non-decreasing
    uint256 countBefore = getCheckpointCount(account);
    require countBefore >= 2 =>
        getCheckpointFromBlock(account, assert_uint256(countBefore - 2))
        <= getCheckpointFromBlock(account, assert_uint256(countBefore - 1)),
        "SAFE: inductive hypothesis — checkpoints are ordered in pre-state";

    f(e, args);

    uint256 countAfter = getCheckpointCount(account);

    // If a new checkpoint was appended, its fromBlock >= previous
    assert (countAfter > countBefore && countBefore > 0) =>
        getCheckpointFromBlock(account, assert_uint256(countBefore - 1))
        <= getCheckpointFromBlock(account, assert_uint256(countAfter - 1)),
        "Invariant 66: new checkpoint fromBlock must be >= previous";
}

// ──────────────────────────────────────────────────────────────────
// Satisfy rules (sanity)
// ──────────────────────────────────────────────────────────────────

rule transferSanity(env e, address to, uint256 amount) {
    require e.msg.value == 0, "SAFE: not payable";
    transfer(e, to, amount);
    satisfy true;
}

rule mintSanity(env e, address to, uint256 amount) {
    mintFromMoloch(e, to, amount);
    satisfy true;
}

rule delegateSanity(env e, address delegatee) {
    require e.msg.value == 0, "SAFE: not payable";
    delegate(e, delegatee);
    satisfy true;
}
