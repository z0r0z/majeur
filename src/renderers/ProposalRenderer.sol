// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {IMoloch, ICardRenderer} from "./RendererInterfaces.sol";
import {Display} from "./Display.sol";

/// @title ProposalRenderer
/// @notice Renders proposal state cards.
contract ProposalRenderer is ICardRenderer {
    function render(IMoloch dao, uint256 id) external view returns (string memory) {
        string memory stateStr;
        IMoloch.ProposalState st = dao.state(id);

        if (st == IMoloch.ProposalState.Unopened) {
            stateStr = "UNOPENED";
        } else if (st == IMoloch.ProposalState.Active) {
            stateStr = "ACTIVE";
        } else if (st == IMoloch.ProposalState.Queued) {
            stateStr = "QUEUED";
        } else if (st == IMoloch.ProposalState.Succeeded) {
            stateStr = "SUCCEEDED";
        } else if (st == IMoloch.ProposalState.Defeated) {
            stateStr = "DEFEATED";
        } else if (st == IMoloch.ProposalState.Expired) {
            stateStr = "EXPIRED";
        } else if (st == IMoloch.ProposalState.Executed) {
            stateStr = "EXECUTED";
        }

        string memory rawOrgName = dao.name(0);
        string memory orgName = Display.esc(rawOrgName);

        string memory svg = Display.svgHeader(orgName, "PROPOSAL");

        svg = string.concat(
            svg,
            "<text x='210' y='155' class='m' font-size='9' fill='#fff' text-anchor='middle'>.---------.</text>",
            "<text x='210' y='166' class='m' font-size='9' fill='#fff' text-anchor='middle'>(     O     )</text>",
            "<text x='210' y='177' class='m' font-size='9' fill='#fff' text-anchor='middle'>'---------'</text>",
            "<line x1='40' y1='220' x2='380' y2='220' stroke='#fff' stroke-width='1'/>"
        );

        svg = string.concat(
            svg,
            "<text x='60' y='255' class='g' font-size='10' fill='#aaa' letter-spacing='1'>ID</text>",
            "<text x='60' y='272' class='m' font-size='9' fill='#fff'>",
            Display.shortDec4(id),
            "</text>"
        );

        uint256 snap = dao.snapshotBlock(id);
        bool opened = snap != 0 || dao.createdAt(id) != 0;

        if (opened) {
            svg = string.concat(
                svg,
                "<text x='60' y='305' class='g' font-size='10' fill='#aaa' letter-spacing='1'>Snapshot</text>",
                "<text x='60' y='322' class='m' font-size='9' fill='#fff'>Block ",
                Display.toString(snap),
                "</text>",
                "<text x='60' y='335' class='m' font-size='9' fill='#fff'>Supply ",
                Display.fmtAmount18Simple(dao.supplySnapshot(id)),
                "</text>"
            );
        }

        IMoloch.Tally memory t = dao.tallies(id);
        bool touchedTallies = (t.forVotes | t.againstVotes | t.abstainVotes) != 0;

        if (touchedTallies) {
            svg = string.concat(
                svg,
                "<text x='60' y='368' class='g' font-size='10' fill='#aaa' letter-spacing='1'>Tally</text>",
                "<text x='60' y='385' class='m' font-size='9' fill='#fff'>For      ",
                Display.fmtAmount18Simple(t.forVotes),
                "</text>",
                "<text x='60' y='398' class='m' font-size='9' fill='#fff'>Against  ",
                Display.fmtAmount18Simple(t.againstVotes),
                "</text>",
                "<text x='60' y='411' class='m' font-size='9' fill='#fff'>Abstain  ",
                Display.fmtAmount18Simple(t.abstainVotes),
                "</text>"
            );
        }

        svg = string.concat(
            svg,
            "<text x='210' y='465' class='g' font-size='12' fill='#fff' text-anchor='middle' letter-spacing='2'>",
            stateStr,
            "</text>",
            "<line x1='40' y1='495' x2='380' y2='495' stroke='#fff' stroke-width='1'/>",
            "</svg>"
        );

        return Display.jsonImage(
            string.concat(rawOrgName, " Proposal"), "Snapshot-weighted governance proposal", svg
        );
    }
}
