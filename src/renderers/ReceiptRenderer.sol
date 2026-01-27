// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {IMoloch, ICardRenderer} from "./RendererInterfaces.sol";
import {Display} from "./Display.sol";

/// @title ReceiptRenderer
/// @notice Renders vote receipt cards.
contract ReceiptRenderer is ICardRenderer {
    function render(IMoloch dao, uint256 id) external view returns (string memory) {
        uint8 s = dao.receiptSupport(id);

        uint256 proposalId_ = dao.receiptProposal(id);
        IMoloch.FutarchyConfig memory F = dao.futarchy(proposalId_);

        string memory stance = s == 1 ? "YES" : s == 0 ? "NO" : "ABSTAIN";

        string memory status;
        if (!F.enabled) {
            status = "SEALED";
        } else if (!F.resolved) {
            status = "OPEN";
        } else {
            status = (F.winner == s) ? "REDEEMABLE" : "SEALED";
        }

        string memory orgName = Display.esc(dao.name(0));

        string memory svg = Display.svgHeader(orgName, "VOTE RECEIPT");

        if (s == 1) {
            svg = string.concat(
                svg,
                "<text x='210' y='135' class='m' font-size='9' fill='#fff' text-anchor='middle'>|</text>",
                "<text x='210' y='146' class='m' font-size='9' fill='#fff' text-anchor='middle'>/_\\</text>",
                "<text x='210' y='157' class='m' font-size='9' fill='#fff' text-anchor='middle'>/   \\</text>",
                "<text x='210' y='168' class='m' font-size='9' fill='#fff' text-anchor='middle'>|  *  |</text>",
                "<text x='210' y='179' class='m' font-size='9' fill='#fff' text-anchor='middle'>|     |</text>",
                "<text x='210' y='190' class='m' font-size='9' fill='#fff' text-anchor='middle'>|     |</text>",
                "<text x='210' y='201' class='m' font-size='9' fill='#fff' text-anchor='middle'>|_____|</text>"
            );
        } else if (s == 0) {
            svg = string.concat(
                svg,
                "<text x='210' y='145' class='m' font-size='9' fill='#fff' text-anchor='middle'>\\       /</text>",
                "<text x='210' y='156' class='m' font-size='9' fill='#fff' text-anchor='middle'> \\     / </text>",
                "<text x='210' y='167' class='m' font-size='9' fill='#fff' text-anchor='middle'>  \\   /  </text>",
                "<text x='210' y='178' class='m' font-size='9' fill='#fff' text-anchor='middle'>    X    </text>",
                "<text x='210' y='189' class='m' font-size='9' fill='#fff' text-anchor='middle'>  /   \\  </text>",
                "<text x='210' y='200' class='m' font-size='9' fill='#fff' text-anchor='middle'> /     \\ </text>",
                "<text x='210' y='211' class='m' font-size='9' fill='#fff' text-anchor='middle'>/       \\</text>"
            );
        } else {
            svg = string.concat(
                svg,
                "<text x='210' y='145' class='m' font-size='9' fill='#fff' text-anchor='middle'>___</text>",
                "<text x='210' y='156' class='m' font-size='9' fill='#fff' text-anchor='middle'>/     \\</text>",
                "<text x='210' y='167' class='m' font-size='9' fill='#fff' text-anchor='middle'>|       |</text>",
                "<text x='210' y='178' class='m' font-size='9' fill='#fff' text-anchor='middle'>|       |</text>",
                "<text x='210' y='189' class='m' font-size='9' fill='#fff' text-anchor='middle'>|       |</text>",
                "<text x='210' y='200' class='m' font-size='9' fill='#fff' text-anchor='middle'>\\     /</text>",
                "<text x='210' y='211' class='m' font-size='9' fill='#fff' text-anchor='middle'>---</text>"
            );
        }

        svg = string.concat(
            svg, "<line x1='40' y1='240' x2='380' y2='240' stroke='#fff' stroke-width='1'/>"
        );

        svg = string.concat(
            svg,
            "<text x='60' y='275' class='g' font-size='10' fill='#aaa' letter-spacing='1'>Proposal</text>",
            "<text x='60' y='292' class='m' font-size='9' fill='#fff'>",
            Display.shortDec4(proposalId_),
            "</text>",
            "<text x='60' y='325' class='g' font-size='10' fill='#aaa' letter-spacing='1'>Stance</text>",
            "<text x='60' y='345' class='gb' font-size='14' fill='#fff'>",
            stance,
            "</text>",
            "<text x='60' y='378' class='g' font-size='10' fill='#aaa' letter-spacing='1'>Weight</text>",
            "<text x='60' y='395' class='m' font-size='9' fill='#fff'>",
            Display.fmtAmount18Simple(dao.totalSupply(id)),
            " votes</text>"
        );

        if (F.enabled) {
            address rt = F.rewardToken;
            address sharesToken = dao.shares();
            string memory unit = " LOOT";

            if (rt == address(0)) {
                unit = " ETH";
            } else if (rt == sharesToken || rt == address(dao)) {
                unit = " SHARES";
            }

            svg = string.concat(
                svg,
                "<text x='60' y='428' class='g' font-size='10' fill='#aaa' letter-spacing='1'>Futarchy</text>",
                "<text x='60' y='445' class='m' font-size='9' fill='#fff'>Pool ",
                Display.fmtAmount18Simple(F.pool),
                unit,
                "</text>"
            );

            if (F.resolved) {
                uint256 whole = F.payoutPerUnit / 1e18;
                uint256 frac = (F.payoutPerUnit % 1e18) / 1e15;
                string memory f = Display.toString(1000 + frac);
                bytes memory fb = bytes(f);
                string memory fracStr = string(abi.encodePacked(fb[1], fb[2], fb[3]));

                svg = string.concat(
                    svg,
                    "<text x='60' y='458' class='m' font-size='9' fill='#fff'>Payout ",
                    Display.toString(whole),
                    ".",
                    fracStr,
                    unit,
                    "/vote</text>"
                );
            }
        }

        svg = string.concat(
            svg,
            "<text x='210' y='510' class='g' font-size='12' fill='#fff' text-anchor='middle' letter-spacing='2'>",
            status,
            "</text>",
            "<line x1='40' y1='540' x2='380' y2='540' stroke='#fff' stroke-width='1'/>",
            "</svg>"
        );

        return Display.jsonImage(
            "Vote Receipt",
            string.concat(stance, " vote receipt - burn to claim rewards if winner"),
            svg
        );
    }
}
