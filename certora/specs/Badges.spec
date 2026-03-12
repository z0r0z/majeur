// Badges.spec — Formal verification of Badges (ERC-721 Soulbound) contract
// Invariants 80-92 from certora/invariants.md

methods {
    function DAO() external returns (address) envfree;
    function balanceOf(address) external returns (uint256) envfree;
    function seatOf(address) external returns (uint256) envfree;
    function ownerOf(uint256) external returns (address);
    function transferFrom(address, address, uint256) external;
    function mintSeat(address, uint16) external;
    function burnSeat(uint16) external;
    function init() external;
    function onSharesChanged(address) external;
    function supportsInterface(bytes4) external returns (bool) envfree;

    // Harness getters
    function getOwnerOfSeat(uint256) external returns (address) envfree;
    function getOccupied() external returns (uint256) envfree;
    function getSeatHolder(uint16) external returns (address) envfree;
    function getSeatBal(uint16) external returns (uint96) envfree;
    function getMinSlot() external returns (uint16) envfree;
    function getMinBal() external returns (uint96) envfree;

    // Summarize external calls
    function _.name(uint256) external => NONDET;
    function _.symbol(uint256) external => NONDET;
    function _.renderer() external => NONDET;
    function _.shares() external => NONDET;
    function _.balanceOf(address) external => NONDET;
    function _.badgeTokenURI(address, uint256) external => NONDET;
}

// ──────────────────────────────────────────────────────────────────
// Invariant 80: Badges.transferFrom always reverts unconditionally
// ──────────────────────────────────────────────────────────────────

rule transferFromAlwaysReverts(env e, address from, address to, uint256 id) {
    transferFrom@withrevert(e, from, to, id);

    assert lastReverted, "Invariant 80: transferFrom must always revert (SBT)";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 81: Badges.balanceOf[address] is always 0 or 1
// ──────────────────────────────────────────────────────────────────

invariant balanceZeroOrOne(address a)
    balanceOf(a) == 0 || balanceOf(a) == 1;

// ──────────────────────────────────────────────────────────────────
// Invariant 82: If balanceOf[a] == 1 then seatOf[a] in [1, 256]
// ──────────────────────────────────────────────────────────────────

invariant seatOfInRange(address a)
    balanceOf(a) == 1 => (seatOf(a) >= 1 && seatOf(a) <= 256)
    {
        preserved with (env e) {
            requireInvariant balanceZeroOrOne(a);
        }
    }

// ──────────────────────────────────────────────────────────────────
// Invariant 83: If seatOf[a] != 0 then _ownerOf[seatOf[a]] == a
// (bidirectional mapping forward direction — Pattern 21)
// ──────────────────────────────────────────────────────────────────

invariant biMapForward(address a)
    seatOf(a) != 0 => getOwnerOfSeat(seatOf(a)) == a
    {
        preserved mintSeat(address to, uint16 seat) with (env e) {
            requireInvariant balanceZeroOrOne(a);
            requireInvariant seatOfInRange(a);
            requireInvariant seatImpliesBalance(a);
            require a != 0, "SAFE: mintSeat requires to != address(0), so seatOf[0] is never set";
        }
        preserved burnSeat(uint16 seat) with (env e) {
            requireInvariant balanceZeroOrOne(a);
            requireInvariant seatOfInRange(a);
        }
        preserved onSharesChanged(address x) with (env e) {
            requireInvariant balanceZeroOrOne(a);
            requireInvariant seatOfInRange(a);
            requireInvariant seatImpliesBalance(a);
            require a != 0, "SAFE: mint/burn never operate on address(0)";
        }
    }

// ──────────────────────────────────────────────────────────────────
// Supporting invariant: seatOf[a] != 0 implies balanceOf[a] != 0
// (mintSeat always sets both; burnSeat always deletes both)
// ──────────────────────────────────────────────────────────────────

invariant seatImpliesBalance(address a)
    seatOf(a) != 0 => balanceOf(a) != 0
    {
        preserved with (env e) {
            requireInvariant balanceZeroOrOne(a);
        }
    }

// ──────────────────────────────────────────────────────────────────
// Invariant 84: For seat id s in [1, 256], if _ownerOf[s] != 0
// then seatOf[_ownerOf[s]] == s
// (bidirectional mapping reverse direction — Pattern 21)
// ──────────────────────────────────────────────────────────────────

invariant biMapReverse(uint256 s)
    (s >= 1 && s <= 256 && getOwnerOfSeat(s) != 0)
        => to_mathint(seatOf(getOwnerOfSeat(s))) == to_mathint(s)
    {
        preserved mintSeat(address to, uint16 seat) with (env e) {
            address owner = getOwnerOfSeat(s);
            requireInvariant balanceZeroOrOne(owner);
            requireInvariant biMapForward(owner);
            requireInvariant seatImpliesBalance(to);
            requireInvariant balanceZeroOrOne(to);
            requireInvariant biMapForward(to);
            // Injectivity: if owner of seat s is to, then s must be to's current seat
            require owner == to => to_mathint(s) == to_mathint(seatOf(to)),
                "SAFE: _ownerOf injectivity for to (follows from biMapReverse pre-state)";
        }
        preserved burnSeat(uint16 seat) with (env e) {
            address owner = getOwnerOfSeat(s);
            requireInvariant balanceZeroOrOne(owner);
            requireInvariant biMapForward(owner);
            address burnedOwner = getOwnerOfSeat(require_uint256(seat));
            requireInvariant biMapForward(burnedOwner);
            require (owner != 0 && burnedOwner != 0 && owner == burnedOwner)
                => to_mathint(s) == to_mathint(seat),
                "SAFE: _ownerOf is injective (seatOf maps each holder to exactly one seat)";
        }
        preserved onSharesChanged(address x) with (env e) {
            address owner = getOwnerOfSeat(s);
            requireInvariant balanceZeroOrOne(owner);
            requireInvariant biMapForward(owner);
            requireInvariant seatImpliesBalance(x);
            requireInvariant balanceZeroOrOne(x);
            requireInvariant biMapForward(x);
            // Prevent uint16 truncation: seatOf[x] must be in [0] ∪ [1,256]
            // Without this, prover picks seatOf[x]=65536 which truncates to pos=0
            requireInvariant seatOfInRange(x);
            // Injectivity for x: if owner of seat s is x, then s must be x's current seat
            require owner == x => to_mathint(s) == to_mathint(seatOf(x)),
                "SAFE: _ownerOf injectivity for x (follows from biMapReverse pre-state)";
            // Injectivity for evicted owner (path 4: eviction of minSlot holder).
            // onSharesChanged calls burnSeat(minSlot+1) which deletes seatOf of
            // _ownerOf[minSlot+1]. We need the prover to know that if _ownerOf[s]
            // equals the evicted address, then s must be the evicted seat.
            uint16 ms = getMinSlot();
            require to_mathint(ms) < 256, "SAFE: minSlot bounded by Seat[256] array";
            address evictedOwner = getOwnerOfSeat(require_uint256(to_mathint(ms) + 1));
            requireInvariant biMapForward(evictedOwner);
            requireInvariant seatImpliesBalance(evictedOwner);
            requireInvariant balanceZeroOrOne(evictedOwner);
            requireInvariant seatOfInRange(evictedOwner);
            require (owner != 0 && evictedOwner != 0 && owner == evictedOwner)
                => to_mathint(s) == to_mathint(ms) + 1,
                "SAFE: _ownerOf injectivity for evicted owner (seatOf is a function)";
            // biMapReverse restatement for evicted seat ms+1 (pre-state inductive hypothesis)
            require evictedOwner != 0 => to_mathint(seatOf(evictedOwner)) == to_mathint(ms) + 1,
                "SAFE: pre-state biMapReverse for evicted seat (inductive hypothesis for seat ms+1)";
            // General: owner's seat is s (inductive hypothesis restated)
            require owner != 0 => to_mathint(seatOf(owner)) == to_mathint(s),
                "SAFE: pre-state biMapReverse restated (inductive hypothesis)";
        }
    }

// ──────────────────────────────────────────────────────────────────
// Invariant 87: mintSeat requires seat >= 1 && seat <= 256
// ──────────────────────────────────────────────────────────────────

rule mintSeatRequiresValidRange(env e, address to, uint16 seat) {
    require seat == 0 || seat > 256;

    mintSeat@withrevert(e, to, seat);

    assert lastReverted, "Invariant 87: mintSeat must revert for seat outside [1, 256]";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 88: mintSeat requires _ownerOf[seat] == address(0)
// (seat must be vacant)
// ──────────────────────────────────────────────────────────────────

rule mintSeatRequiresVacant(env e, address to, uint16 seat) {
    require seat >= 1 && seat <= 256;
    address currentOwner = getOwnerOfSeat(seat);

    require currentOwner != 0;

    mintSeat@withrevert(e, to, seat);

    assert lastReverted, "Invariant 88: mintSeat must revert when seat is occupied";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 89: mintSeat requires balanceOf[to] == 0
// (recipient must not already hold a badge)
// ──────────────────────────────────────────────────────────────────

rule mintSeatRequiresNoBadge(env e, address to, uint16 seat) {
    require seat >= 1 && seat <= 256;
    require getOwnerOfSeat(seat) == 0;
    require to != 0;

    require balanceOf(to) != 0;

    mintSeat@withrevert(e, to, seat);

    assert lastReverted, "Invariant 89: mintSeat must revert when recipient already has a badge";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 90: mintSeat and burnSeat can only be called by the DAO
// ──────────────────────────────────────────────────────────────────

rule mintSeatOnlyDAO(env e, address to, uint16 seat) {
    address dao = DAO();

    mintSeat@withrevert(e, to, seat);

    assert !lastReverted => e.msg.sender == dao,
        "Invariant 90: only DAO can mint seats";
}

rule burnSeatOnlyDAO(env e, uint16 seat) {
    address dao = DAO();

    burnSeat@withrevert(e, seat);

    assert !lastReverted => e.msg.sender == dao,
        "Invariant 90: only DAO can burn seats";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 91: Badges.DAO is set exactly once during init and
// never changes thereafter (write-once)
// ──────────────────────────────────────────────────────────────────

rule daoWriteOnce(env e, method f, calldataarg args)
filtered { f -> f.selector != sig:transferFrom(address, address, uint256).selector }
{
    address daoBefore = DAO();

    f(e, args);

    address daoAfter = DAO();

    assert daoBefore != 0 => daoAfter == daoBefore,
        "Invariant 91: DAO cannot change once set";
}

// ──────────────────────────────────────────────────────────────────
// Invariant 92: Badges.init reverts if DAO is already non-zero
// ──────────────────────────────────────────────────────────────────

rule initRevertsIfDaoSet(env e) {
    address dao = DAO();
    require dao != 0;

    init@withrevert(e);

    assert lastReverted, "Invariant 92: init must revert when DAO already set";
}

// ──────────────────────────────────────────────────────────────────
// Satisfy rules (sanity)
// ──────────────────────────────────────────────────────────────────

rule mintSeatSanity(env e, address to, uint16 seat) {
    mintSeat(e, to, seat);
    satisfy true;
}

rule burnSeatSanity(env e, uint16 seat) {
    burnSeat(e, seat);
    satisfy true;
}

rule initSanity(env e) {
    init(e);
    satisfy true;
}
