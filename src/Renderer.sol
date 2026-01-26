// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IMoloch, ICovenantRenderer, ICardRenderer} from "./renderers/RendererInterfaces.sol";

/// @title Renderer
/// @notice Moloch (Majeur) URI SVG renderer router. Dispatches to immutable sub-renderers.
contract Renderer {
    address immutable covenant;
    address immutable proposal;
    address immutable receipt;
    address immutable permit;
    address immutable badge;

    constructor(address _c, address _p, address _r, address _pm, address _b) payable {
        covenant = _c;
        proposal = _p;
        receipt = _r;
        permit = _pm;
        badge = _b;
    }

    function daoContractURI(IMoloch dao) public view returns (string memory) {
        return ICovenantRenderer(covenant).render(dao);
    }

    function daoTokenURI(IMoloch dao, uint256 id) public view returns (string memory) {
        if (dao.receiptProposal(id) != 0) return ICardRenderer(receipt).render(dao, id);

        IMoloch.Tally memory t = dao.tallies(id);
        bool touchedTallies = (t.forVotes | t.againstVotes | t.abstainVotes) != 0;
        bool opened = dao.snapshotBlock(id) != 0 || dao.createdAt(id) != 0;

        if (!opened && !touchedTallies && dao.totalSupply(id) != 0) {
            return ICardRenderer(permit).render(dao, id);
        }
        return ICardRenderer(proposal).render(dao, id);
    }

    function badgeTokenURI(IMoloch dao, uint256 seatId) public view returns (string memory) {
        return ICardRenderer(badge).render(dao, seatId);
    }
}
