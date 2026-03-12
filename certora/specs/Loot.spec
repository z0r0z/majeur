// Loot.spec — Formal verification of Loot (ERC-20) contract
// Invariants 74-79 from certora/invariants.md

methods {
    function totalSupply() external returns (uint256) envfree;
    function balanceOf(address) external returns (uint256) envfree;
    function allowance(address, address) external returns (uint256) envfree;
    function DAO() external returns (address) envfree;
    function transfersLocked() external returns (bool) envfree;
    function decimals() external returns (uint8) envfree;
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
    function mintFromMoloch(address, uint256) external;
    function burnFromMoloch(address, uint256) external;
    function setTransfersLocked(bool) external;
    function init() external;

    // Summarize external calls to Moloch (name/symbol) as NONDET
    function _.name(uint256) external => NONDET;
    function _.symbol(uint256) external => NONDET;
}

// ──────────────────────────────────────────────────────────────────
// Ghost: track sum of all balances (Pattern 1)
// Invariant 74: Loot.totalSupply equals the sum of all Loot.balanceOf[user]
// ──────────────────────────────────────────────────────────────────

ghost mathint g_sumBalances {
    init_state axiom g_sumBalances == 0;
}

hook Sstore balanceOf[KEY address a] uint256 newVal (uint256 oldVal) {
    g_sumBalances = g_sumBalances + newVal - oldVal;
}

// Invariant 74
// Preserved blocks needed because unchecked arithmetic in _mint/_moveTokens/burn
// can wrap in the prover's arbitrary state; constraining individual balances
// <= totalSupply eliminates false counterexamples (safe: follows from conservation)
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
    }

// ──────────────────────────────────────────────────────────────────
// Invariant 75: transfer and transferFrom revert when transfersLocked
// is true and neither from nor to is the DAO address
// ──────────────────────────────────────────────────────────────────

rule transferRevertsWhenLocked(env e, address to, uint256 amount) {
    bool locked = transfersLocked();
    address dao = DAO();
    address from = e.msg.sender;

    require locked;
    require from != dao;
    require to != dao;
    require e.msg.value == 0, "SAFE: transfer is not payable";

    transfer@withrevert(e, to, amount);

    assert lastReverted, "Invariant 75: transfer must revert when locked and neither party is DAO";
}

rule transferFromRevertsWhenLocked(env e, address from, address to, uint256 amount) {
    bool locked = transfersLocked();
    address dao = DAO();

    require locked;
    require from != dao;
    require to != dao;
    require e.msg.value == 0, "SAFE: transferFrom is not payable";

    transferFrom@withrevert(e, from, to, amount);

    assert lastReverted, "Invariant 75: transferFrom must revert when locked and neither party is DAO";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 76: Only mintFromMoloch and burnFromMoloch change
// Loot.totalSupply; transfers conserve it (Pattern 2 authorization)
// ──────────────────────────────────────────────────────────────────

rule onlyMintBurnChangeTotalSupply(env e, method f, calldataarg args) {
    mathint supplyBefore = totalSupply();

    f(e, args);

    mathint supplyAfter = totalSupply();

    assert supplyAfter != supplyBefore =>
        f.selector == sig:mintFromMoloch(address, uint256).selector
        || f.selector == sig:burnFromMoloch(address, uint256).selector,
        "Invariant 76: only mint/burn can change totalSupply";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 77: Loot.DAO is set exactly once during init and never
// changes thereafter (write-once latch)
// ──────────────────────────────────────────────────────────────────

rule daoWriteOnce(env e, method f, calldataarg args) {
    address daoBefore = DAO();

    f(e, args);

    address daoAfter = DAO();

    assert daoBefore != 0 => daoAfter == daoBefore,
        "Invariant 77: DAO cannot change once set to non-zero";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 78: Loot.init reverts if DAO is already non-zero
// ──────────────────────────────────────────────────────────────────

rule initRevertsIfDaoSet(env e) {
    address dao = DAO();

    require dao != 0;

    init@withrevert(e);

    assert lastReverted, "Invariant 78: init must revert when DAO is already set";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 79: Loot.totalSupply only increases via mintFromMoloch
// (which requires msg.sender == DAO) and only decreases via
// burnFromMoloch (which requires msg.sender == DAO)
// ──────────────────────────────────────────────────────────────────

rule mintRequiresDAO(env e, address to, uint256 amount) {
    address dao = DAO();

    mintFromMoloch@withrevert(e, to, amount);

    assert !lastReverted => e.msg.sender == dao,
        "Invariant 79: only DAO can mint";
}

rule burnRequiresDAO(env e, address from, uint256 amount) {
    address dao = DAO();

    burnFromMoloch@withrevert(e, from, amount);

    assert !lastReverted => e.msg.sender == dao,
        "Invariant 79: only DAO can burn";
}

// ──────────────────────────────────────────────────────────────────
// Transfer integrity (Pattern 4 conservation)
// Supporting rule: transfer moves exact amounts
// ──────────────────────────────────────────────────────────────────

rule transferIntegrity(env e, address to, uint256 amount) {
    address from = e.msg.sender;

    require from != to, "SAFE: separate self-transfer case";
    require e.msg.value == 0, "SAFE: transfer is not payable";

    requireInvariant totalSupplyIsSumOfBalances();
    require to_mathint(balanceOf(from)) + to_mathint(balanceOf(to)) <= to_mathint(totalSupply()),
        "SAFE: sum of sender and receiver balances cannot exceed totalSupply (conservation)";

    mathint fromBefore = balanceOf(from);
    mathint toBefore = balanceOf(to);

    transfer(e, to, amount);

    assert to_mathint(balanceOf(from)) == fromBefore - amount,
        "sender balance decreased by amount";
    assert to_mathint(balanceOf(to)) == toBefore + amount,
        "receiver balance increased by amount";
}

rule transferSelfIntegrity(env e, uint256 amount) {
    address from = e.msg.sender;
    require e.msg.value == 0, "SAFE: transfer is not payable";

    mathint fromBefore = balanceOf(from);

    transfer(e, from, amount);

    assert to_mathint(balanceOf(from)) == fromBefore,
        "self-transfer preserves balance";
}

// ──────────────────────────────────────────────────────────────────
// Satisfy rules (Pattern 12 sanity) — prove functions are reachable
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

rule burnSanity(env e, address from, uint256 amount) {
    burnFromMoloch(e, from, amount);
    satisfy true;
}

rule initSanity(env e) {
    init(e);
    satisfy true;
}
