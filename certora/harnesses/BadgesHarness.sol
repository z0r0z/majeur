// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// Minimal interfaces referenced by Badges
interface IMolochView {
    function name(uint256 id) external view returns (string memory);
    function symbol(uint256 id) external view returns (string memory);
    function renderer() external view returns (address);
    function shares() external view returns (address);
}

interface IMajeurRenderer {
    function badgeTokenURI(address dao, uint256 seatId) external view returns (string memory);
}

interface IShares {
    function balanceOf(address) external view returns (uint256);
}

// Global errors
error SBT();
error Overflow();
error Unauthorized();

contract BadgesHarness {
    /* ERC721-ish */
    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    /* MAJEUR */
    address payable public DAO;

    /// @dev ERC721-ish SBT state:
    mapping(uint256 id => address) _ownerOf;
    mapping(address id => uint256) public seatOf;
    mapping(address id => uint256) public balanceOf;

    modifier onlyDAO() {
        require(msg.sender == DAO, Unauthorized());
        _;
    }

    error Minted();
    error NotMinted();

    constructor() payable {}

    function init() public payable {
        require(DAO == address(0), Unauthorized());
        DAO = payable(msg.sender);
    }

    function name() public view returns (string memory) {
        return string.concat(IMolochView(DAO).name(0), " Badges");
    }

    function symbol() public view returns (string memory) {
        return string.concat(IMolochView(DAO).symbol(0), "B");
    }

    function ownerOf(uint256 id) public view returns (address o) {
        o = _ownerOf[id];
        require(o != address(0), NotMinted());
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == 0x01ffc9a7
            || interfaceId == 0x80ac58cd
            || interfaceId == 0x5b5e139f;
    }

    function transferFrom(address, address, uint256) public pure {
        revert SBT();
    }

    /// @dev seat: 1..256:
    function mintSeat(address to, uint16 seat) public payable onlyDAO {
        uint256 id = uint256(seat);
        require(seat >= 1 && seat <= 256, NotMinted());
        require(to != address(0) && _ownerOf[id] == address(0) && balanceOf[to] == 0, Minted());
        _ownerOf[id] = to;
        balanceOf[to] = 1;
        seatOf[to] = id;
        emit Transfer(address(0), to, id);
    }

    function burnSeat(uint16 seat) public payable onlyDAO {
        uint256 id = uint256(seat);
        address from = _ownerOf[id];
        require(from != address(0), NotMinted());
        delete _ownerOf[id];
        delete seatOf[from];
        delete balanceOf[from];
        emit Transfer(from, address(0), id);
    }

    function tokenURI(uint256 id) public view returns (string memory) {
        address r = IMolochView(DAO).renderer();
        if (r == address(0)) return "";
        return IMajeurRenderer(r).badgeTokenURI(DAO, id);
    }

    /* ───────────── Top-256 seat bitmap logic ───────────── */

    uint256 occupied;

    struct Seat {
        address holder;
        uint96 bal;
    }
    Seat[256] seats;

    uint16 minSlot;
    uint96 minBal;

    function getSeats() public view returns (Seat[] memory out) {
        unchecked {
            uint256 m = occupied;
            uint256 s;
            while (m != 0) {
                m &= (m - 1);
                ++s;
            }
            out = new Seat[](s);
            m = occupied;
            uint256 n;
            while (m != 0) {
                uint16 i = uint16(_ffs(m));
                out[n++] = seats[i];
                m &= (m - 1);
            }
        }
    }

    function onSharesChanged(address a) public payable onlyDAO {
        unchecked {
            IShares _shares = IShares(address(IMolochView(DAO).shares()));

            uint256 bal256 = _shares.balanceOf(a);
            require(bal256 <= type(uint96).max, Overflow());
            uint96 bal = uint96(bal256);

            uint16 pos = uint16(seatOf[a]);

            if (bal == 0) {
                if (pos != 0) {
                    uint16 slot = pos - 1;
                    seats[slot] = Seat({holder: address(0), bal: 0});
                    _setFree(slot);
                    burnSeat(pos);
                    if (slot == minSlot) _recomputeMin();
                }
                return;
            }

            if (pos != 0) {
                uint16 slot = pos - 1;
                seats[slot].bal = bal;
                if (slot == minSlot) {
                    if (bal > minBal) {
                        _recomputeMin();
                    } else {
                        minBal = bal;
                    }
                } else if (minBal == 0 || bal < minBal) {
                    minSlot = slot;
                    minBal = bal;
                }
                return;
            }

            (uint16 freeSlot, bool ok) = _firstFree();
            if (ok) {
                seats[freeSlot] = Seat({holder: a, bal: bal});
                _setUsed(freeSlot);
                mintSeat(a, freeSlot + 1);
                if (minBal == 0 || bal < minBal) {
                    minSlot = freeSlot;
                    minBal = bal;
                }
                return;
            }

            if (bal > minBal) {
                uint16 slot = minSlot;
                burnSeat(slot + 1);
                seats[slot] = Seat({holder: a, bal: bal});
                mintSeat(a, slot + 1);
                _recomputeMin();
            }
        }
    }

    function _firstFree() internal view returns (uint16 slot, bool ok) {
        uint256 z = ~occupied;
        if (z == 0) return (0, false);
        return (uint16(_ffs(z)), true);
    }

    function _setUsed(uint16 slot) internal {
        occupied |= (uint256(1) << slot);
    }

    function _setFree(uint16 slot) internal {
        occupied &= ~(uint256(1) << slot);
    }

    function _recomputeMin() internal {
        unchecked {
            uint16 ms;
            uint96 mb = type(uint96).max;
            for (uint256 m = occupied; m != 0; m &= (m - 1)) {
                uint16 i = uint16(_ffs(m));
                uint96 b = seats[i].bal;
                if (b != 0 && b < mb) {
                    mb = b;
                    ms = i;
                }
            }
            minSlot = ms;
            minBal = (mb == type(uint96).max) ? 0 : mb;
        }
    }

    function _ffs(uint256 x) internal pure returns (uint256 r) {
        assembly ("memory-safe") {
            x := and(x, add(not(x), 1))
            r := shl(5, shr(252, shl(shl(2, shr(250, mul(x,
                0xb6db6db6ddddddddd34d34d349249249210842108c6318c639ce739cffffffff))),
                0x8040405543005266443200005020610674053026020000107506200176117077)))
            r := or(r, byte(and(div(0xd76453e0, shr(r, x)), 0x1f),
                0x001f0d1e100c1d070f090b19131c1706010e11080a1a141802121b1503160405))
        }
    }

    // ───── Harness getters for internal state ─────

    function getOwnerOfSeat(uint256 id) external view returns (address) {
        return _ownerOf[id];
    }

    function getOccupied() external view returns (uint256) {
        return occupied;
    }

    function getSeatHolder(uint16 slot) external view returns (address) {
        return seats[slot].holder;
    }

    function getSeatBal(uint16 slot) external view returns (uint96) {
        return seats[slot].bal;
    }

    function getMinSlot() external view returns (uint16) {
        return minSlot;
    }

    function getMinBal() external view returns (uint96) {
        return minBal;
    }
}
