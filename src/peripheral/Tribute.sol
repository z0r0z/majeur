// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Simple tribute OTC escrow maker for DAO proposals.
contract Tribute {
    struct TributeOffer {
        uint256 tribAmt; // amount of tribTkn locked up
        address forTkn; // token (or ETH) for proposer
        uint256 forAmt; // amount of forTkn expected
    }

    event TributeProposed(
        address indexed proposer,
        address indexed dao,
        address tribTkn,
        uint256 tribAmt,
        address forTkn,
        uint256 forAmt
    );
    event TributeCancelled(
        address indexed proposer,
        address indexed dao,
        address tribTkn,
        uint256 tribAmt,
        address forTkn,
        uint256 forAmt
    );
    event TributeClaimed(
        address indexed proposer,
        address indexed dao,
        address tribTkn,
        uint256 tribAmt,
        address forTkn,
        uint256 forAmt
    );

    mapping(
        address proposer => mapping(address dao => mapping(address tribTkn => TributeOffer))
    ) public tributes;

    // Lightweight push arrays for discovery:
    struct DaoTributeRef {
        address proposer;
        address tribTkn;
    }

    struct ProposerTributeRef {
        address dao;
        address tribTkn;
    }

    /// @dev Per-DAO view: "what tributes are pointing at this DAO?":
    mapping(address dao => DaoTributeRef[]) public daoTributeRefs;

    /// @dev Per-proposer view: "what tributes has this address created?":
    mapping(address proposer => ProposerTributeRef[]) public proposerTributeRefs;

    constructor() payable {}

    error NoTribute();
    error InvalidParams();

    /// @notice Propose an OTC tribute:
    ///  - proposer locks up tribTkn (ERC20 or ETH)
    ///  - sets desired forTkn/forAmt from the DAO
    ///  - tribTkn == address(0) means ETH
    ///  - forTkn == address(0) means ETH
    function proposeTribute(
        address dao,
        address tribTkn,
        uint256 tribAmt,
        address forTkn,
        uint256 forAmt
    ) public payable nonReentrant {
        if (dao == address(0)) revert InvalidParams();
        if (forAmt == 0) revert InvalidParams();

        // handle the tribute side deposit (tribTkn)
        if (msg.value != 0) {
            // ETH tribute
            if (tribTkn != address(0)) revert InvalidParams();
            if (tribAmt != 0) revert InvalidParams();
            tribAmt = msg.value;
        } else {
            // ERC20 tribute
            if (tribTkn == address(0)) revert InvalidParams();
            if (tribAmt == 0) revert InvalidParams();
            safeTransferFrom(tribTkn, address(this), tribAmt);
        }

        TributeOffer storage offer = tributes[msg.sender][dao][tribTkn];
        // prevent overwriting an existing offer for same key
        if (offer.tribAmt != 0) revert InvalidParams();

        offer.tribAmt = tribAmt;
        offer.forTkn = forTkn;
        offer.forAmt = forAmt;

        // register escrow for onchain discovery
        daoTributeRefs[dao].push(DaoTributeRef({proposer: msg.sender, tribTkn: tribTkn}));

        proposerTributeRefs[msg.sender].push(ProposerTributeRef({dao: dao, tribTkn: tribTkn}));

        emit TributeProposed(msg.sender, dao, tribTkn, tribAmt, forTkn, forAmt);
    }

    /// @notice Proposer cancels their own tribute and gets tribTkn back.
    function cancelTribute(address dao, address tribTkn) public nonReentrant {
        TributeOffer memory offer = tributes[msg.sender][dao][tribTkn];
        if (offer.tribAmt == 0) revert NoTribute();

        delete tributes[msg.sender][dao][tribTkn];

        if (tribTkn == address(0)) {
            // ETH tribute
            safeTransferETH(msg.sender, offer.tribAmt);
        } else {
            // ERC20 tribute
            safeTransfer(tribTkn, msg.sender, offer.tribAmt);
        }

        emit TributeCancelled(msg.sender, dao, tribTkn, offer.tribAmt, offer.forTkn, offer.forAmt);
    }

    /// @notice DAO claims a tribute and atomically performs the OTC escrow swap:
    ///  - DAO receives tribTkn
    ///  - Proposer receives forTkn
    /// For ERC20 forTkn:
    ///  - DAO must `approve` this contract for at least forAmt before calling.
    /// For ETH forTkn:
    ///  - DAO must send exactly forAmt as msg.value.
    function claimTribute(address proposer, address tribTkn) public payable nonReentrant {
        address dao = msg.sender;

        TributeOffer memory offer = tributes[proposer][dao][tribTkn];
        if (offer.tribAmt == 0) revert NoTribute();

        delete tributes[proposer][dao][tribTkn];

        // 1) DAO pays the "for" side to the proposer
        if (offer.forTkn == address(0)) {
            // ETH as consideration
            if (msg.value != offer.forAmt) revert InvalidParams();
            if (offer.forAmt > 0) {
                safeTransferETH(proposer, offer.forAmt);
            }
        } else {
            // ERC20 as consideration, pull from DAO to proposer
            if (msg.value != 0) revert InvalidParams();
            if (offer.forAmt > 0) {
                safeTransferFrom(offer.forTkn, proposer, offer.forAmt);
            }
        }

        // 2) Contract sends the locked tribute to the DAO
        if (tribTkn == address(0)) {
            // ETH tribute
            safeTransferETH(dao, offer.tribAmt);
        } else {
            // ERC20 tribute
            safeTransfer(tribTkn, dao, offer.tribAmt);
        }

        emit TributeClaimed(proposer, dao, tribTkn, offer.tribAmt, offer.forTkn, offer.forAmt);
    }

    function getDaoTributeCount(address dao) public view returns (uint256) {
        return daoTributeRefs[dao].length;
    }

    function getProposerTributeCount(address proposer) public view returns (uint256) {
        return proposerTributeRefs[proposer].length;
    }

    struct ActiveTributeView {
        address proposer;
        address tribTkn;
        uint256 tribAmt;
        address forTkn;
        uint256 forAmt;
    }

    function getActiveDaoTributes(address dao)
        public
        view
        returns (ActiveTributeView[] memory result)
    {
        DaoTributeRef[] storage refs = daoTributeRefs[dao];
        uint256 len = refs.length;

        // first pass: count active
        uint256 count;
        for (uint256 i; i != len; ++i) {
            TributeOffer storage offer = tributes[refs[i].proposer][dao][refs[i].tribTkn];
            if (offer.tribAmt != 0) {
                unchecked {
                    ++count;
                }
            }
        }

        result = new ActiveTributeView[](count);
        uint256 idx;
        for (uint256 i; i != len; ++i) {
            DaoTributeRef storage r = refs[i];
            TributeOffer storage offer = tributes[r.proposer][dao][r.tribTkn];
            if (offer.tribAmt != 0) {
                result[idx] = ActiveTributeView({
                    proposer: r.proposer,
                    tribTkn: r.tribTkn,
                    tribAmt: offer.tribAmt,
                    forTkn: offer.forTkn,
                    forAmt: offer.forAmt
                });
                unchecked {
                    ++idx;
                }
            }
        }
    }

    uint256 constant REENTRANCY_GUARD_SLOT = 0x929eee149b4bd21268;

    modifier nonReentrant() {
        assembly ("memory-safe") {
            if tload(REENTRANCY_GUARD_SLOT) {
                mstore(0x00, 0xab143c06)
                revert(0x1c, 0x04)
            }
            tstore(REENTRANCY_GUARD_SLOT, address())
        }
        _;
        assembly ("memory-safe") {
            tstore(REENTRANCY_GUARD_SLOT, 0)
        }
    }
}

function safeTransferETH(address to, uint256 amount) {
    assembly ("memory-safe") {
        if iszero(call(gas(), to, amount, codesize(), 0x00, codesize(), 0x00)) {
            mstore(0x00, 0xb12d13eb)
            revert(0x1c, 0x04)
        }
    }
}

function safeTransfer(address token, address to, uint256 amount) {
    assembly ("memory-safe") {
        mstore(0x14, to)
        mstore(0x34, amount)
        mstore(0x00, 0xa9059cbb000000000000000000000000)
        let success := call(gas(), token, 0, 0x10, 0x44, 0x00, 0x20)
        if iszero(and(eq(mload(0x00), 1), success)) {
            if iszero(lt(or(iszero(extcodesize(token)), returndatasize()), success)) {
                mstore(0x00, 0x90b8ec18)
                revert(0x1c, 0x04)
            }
        }
        mstore(0x34, 0)
    }
}

function safeTransferFrom(address token, address to, uint256 amount) {
    assembly ("memory-safe") {
        let m := mload(0x40)
        mstore(0x60, amount)
        mstore(0x40, to)
        mstore(0x2c, shl(96, caller()))
        mstore(0x0c, 0x23b872dd000000000000000000000000)
        let success := call(gas(), token, 0, 0x1c, 0x64, 0x00, 0x20)
        if iszero(and(eq(mload(0x00), 1), success)) {
            if iszero(lt(or(iszero(extcodesize(token)), returndatasize()), success)) {
                mstore(0x00, 0x7939f424)
                revert(0x1c, 0x04)
            }
        }
        mstore(0x60, 0)
        mstore(0x40, m)
    }
}
