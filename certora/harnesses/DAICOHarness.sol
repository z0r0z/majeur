// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @dev Simplified DAICO harness for Certora verification of invariants 106-118.
/// Strips summon wrappers, CREATE2 prediction, LP initialization, and assembly helpers.
/// Preserves: setSale, buy (simplified), buyExactOut (simplified), claimTap, setLPConfig,
/// setSaleWithTap, setTapOps, setTapRate, and all validation logic.
contract DAICOHarness {
    struct TributeOffer {
        uint256 tribAmt;
        uint256 forAmt;
        address forTkn;
        uint40 deadline;
    }

    struct Tap {
        address ops;
        address tribTkn;
        uint128 ratePerSec;
        uint64 lastClaim;
    }

    struct LPConfig {
        uint16 lpBps;
        uint16 maxSlipBps;
        uint256 feeOrHook;
    }

    mapping(address dao => mapping(address tribTkn => TributeOffer)) public sales;
    mapping(address dao => Tap) public taps;
    mapping(address dao => mapping(address tribTkn => LPConfig)) public lpConfigs;

    // L-01 verification: models min(allowance, daoBalance) available for tap claims
    mapping(address dao => uint256) public daoTapBalance;

    error NoTap();
    error NoSale();
    error Expired();
    error BadLPBps();
    error InvalidParams();
    error NothingToClaim();
    error SlippageExceeded();

    constructor() payable {}

    // --- Sale configuration (Invariant 106) ---

    function setSale(
        address tribTkn,
        uint256 tribAmt,
        address forTkn,
        uint256 forAmt,
        uint40 deadline
    ) public {
        address dao = msg.sender;

        if (tribAmt == 0 || forAmt == 0) {
            delete sales[dao][tribTkn];
            return;
        }

        if (forTkn == address(0)) revert InvalidParams();

        TributeOffer storage offer = sales[dao][tribTkn];
        offer.tribAmt = tribAmt;
        offer.forAmt = forAmt;
        offer.forTkn = forTkn;
        offer.deadline = deadline;
    }

    function setSaleWithTap(
        address tribTkn,
        uint256 tribAmt,
        address forTkn,
        uint256 forAmt,
        uint40 deadline,
        address ops,
        uint128 ratePerSec
    ) public {
        setSale(tribTkn, tribAmt, forTkn, forAmt, deadline);

        address dao = msg.sender;

        if (ratePerSec == 0 || ops == address(0)) {
            delete taps[dao];
            return;
        }

        taps[dao] = Tap({
            ops: ops, tribTkn: tribTkn, ratePerSec: ratePerSec, lastClaim: uint64(block.timestamp)
        });
    }

    function setTapOps(address newOps) public {
        address dao = msg.sender;
        Tap storage tap = taps[dao];
        if (tap.ratePerSec == 0 && tap.ops == address(0)) revert NoTap();
        tap.ops = newOps;
    }

    function setTapRate(uint128 newRate) public {
        address dao = msg.sender;
        Tap storage tap = taps[dao];
        if (tap.ratePerSec == 0 && tap.ops == address(0)) revert NoTap();
        tap.lastClaim = uint64(block.timestamp);
        tap.ratePerSec = newRate;
    }

    // --- LP configuration (Invariant 118) ---

    function setLPConfig(address tribTkn, uint16 lpBps, uint16 maxSlipBps, uint256 feeOrHook)
        public
    {
        if (lpBps >= 10_000 || maxSlipBps > 10_000) revert BadLPBps();

        address dao = msg.sender;

        if (lpBps == 0) {
            delete lpConfigs[dao][tribTkn];
            return;
        }

        lpConfigs[dao][tribTkn] = LPConfig({
            lpBps: lpBps, maxSlipBps: maxSlipBps == 0 ? 100 : maxSlipBps, feeOrHook: feeOrHook
        });
    }

    function setSaleWithLP(
        address tribTkn,
        uint256 tribAmt,
        address forTkn,
        uint256 forAmt,
        uint40 deadline,
        uint16 lpBps,
        uint16 maxSlipBps,
        uint256 feeOrHook
    ) public {
        setSale(tribTkn, tribAmt, forTkn, forAmt, deadline);
        setLPConfig(tribTkn, lpBps, maxSlipBps, feeOrHook);
    }

    function setSaleWithLPAndTap(
        address tribTkn,
        uint256 tribAmt,
        address forTkn,
        uint256 forAmt,
        uint40 deadline,
        uint16 lpBps,
        uint16 maxSlipBps,
        uint256 feeOrHook,
        address ops,
        uint128 ratePerSec
    ) public {
        setSale(tribTkn, tribAmt, forTkn, forAmt, deadline);
        setLPConfig(tribTkn, lpBps, maxSlipBps, feeOrHook);

        address dao = msg.sender;

        if (ratePerSec == 0 || ops == address(0)) {
            delete taps[dao];
            return;
        }

        taps[dao] = Tap({
            ops: ops, tribTkn: tribTkn, ratePerSec: ratePerSec, lastClaim: uint64(block.timestamp)
        });
    }

    // --- Simplified buy (Invariants 107-111) ---
    // Strips LP initialization and external token transfers
    // Preserves all validation/revert logic

    function buy(address dao, address tribTkn, uint256 payAmt, uint256 minBuyAmt) public payable {
        if (dao == address(0)) revert InvalidParams();
        if (payAmt == 0) revert InvalidParams();

        TributeOffer memory offer = sales[dao][tribTkn];
        if (offer.tribAmt == 0 || offer.forAmt == 0 || offer.forTkn == address(0)) {
            revert NoSale();
        }
        if (offer.deadline != 0 && block.timestamp > offer.deadline) revert Expired();

        // Compute buy amount (simplified: no LP deduction)
        uint256 buyAmt = (offer.forAmt * payAmt) / offer.tribAmt;

        if (buyAmt == 0) revert InvalidParams();
        if (minBuyAmt != 0 && buyAmt < minBuyAmt) revert SlippageExceeded();
    }

    // --- Simplified buyExactOut (Invariant 112) ---

    function buyExactOut(address dao, address tribTkn, uint256 buyAmt, uint256 maxPayAmt)
        public
        payable
    {
        if (dao == address(0)) revert InvalidParams();
        if (buyAmt == 0) revert InvalidParams();

        TributeOffer memory offer = sales[dao][tribTkn];
        if (offer.tribAmt == 0 || offer.forAmt == 0 || offer.forTkn == address(0)) {
            revert NoSale();
        }
        if (offer.deadline != 0 && block.timestamp > offer.deadline) revert Expired();

        // payAmt = ceil(buyAmt * tribAmt / forAmt)
        uint256 num = buyAmt * offer.tribAmt;
        uint256 payAmt = (num + offer.forAmt - 1) / offer.forAmt;
        if (payAmt == 0) revert InvalidParams();
        if (maxPayAmt != 0 && payAmt > maxPayAmt) revert SlippageExceeded();
    }

    // --- Tap mechanism (Invariants 113-117) ---

    function claimTap(address dao) public returns (uint256 claimed) {
        Tap storage tap = taps[dao];
        if (tap.ratePerSec == 0) revert NoTap();
        if (tap.ops == address(0)) revert NoTap();

        uint64 elapsed;
        unchecked {
            elapsed = uint64(block.timestamp) - tap.lastClaim;
        }
        if (elapsed == 0) revert NothingToClaim();

        uint256 owed = uint256(tap.ratePerSec) * uint256(elapsed);
        if (owed == 0) revert NothingToClaim();

        // Cap by available balance (mirrors real contract's min(owed, allowance, daoBalance))
        // L-01: daoTapBalance models the constraint from allowance/treasury balance
        claimed = owed;
        uint256 available = daoTapBalance[dao];
        if (claimed > available) claimed = available;
        if (claimed == 0) revert NothingToClaim();

        // L-01 BUG: advances lastClaim to block.timestamp even on partial claims
        // The difference (owed - claimed) is permanently forfeited
        tap.lastClaim = uint64(block.timestamp);

        // Deduct from available balance
        daoTapBalance[dao] -= claimed;
    }

    // --- Harness getters ---

    function getSaleTribAmt(address dao, address tribTkn) external view returns (uint256) {
        return sales[dao][tribTkn].tribAmt;
    }

    function getSaleForAmt(address dao, address tribTkn) external view returns (uint256) {
        return sales[dao][tribTkn].forAmt;
    }

    function getSaleForTkn(address dao, address tribTkn) external view returns (address) {
        return sales[dao][tribTkn].forTkn;
    }

    function getSaleDeadline(address dao, address tribTkn) external view returns (uint40) {
        return sales[dao][tribTkn].deadline;
    }

    function getTapOps(address dao) external view returns (address) {
        return taps[dao].ops;
    }

    function getTapTribTkn(address dao) external view returns (address) {
        return taps[dao].tribTkn;
    }

    function getTapRatePerSec(address dao) external view returns (uint128) {
        return taps[dao].ratePerSec;
    }

    function getTapLastClaim(address dao) external view returns (uint64) {
        return taps[dao].lastClaim;
    }

    function getLPBps(address dao, address tribTkn) external view returns (uint16) {
        return lpConfigs[dao][tribTkn].lpBps;
    }

    function getDaoTapBalance(address dao) external view returns (uint256) {
        return daoTapBalance[dao];
    }
}
