// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IMoloch, ICardRenderer} from "./RendererInterfaces.sol";
import {Display} from "./Display.sol";

/// @title BadgeRenderer
/// @notice Renders member badge cards (top-256 holders).
contract BadgeRenderer is ICardRenderer {
    function render(IMoloch dao, uint256 seatId) external view returns (string memory) {
        IMoloch badges = IMoloch(dao.badges());
        address holder = badges.ownerOf(seatId);

        IMoloch sh = IMoloch(dao.shares());
        uint256 bal = sh.balanceOf(holder);
        uint256 ts = sh.totalSupply();

        string memory addr = Display.shortAddr4(holder);
        string memory pct = Display.percent2(bal, ts);
        string memory seatStr = Display.toString(seatId);

        string memory svg = Display.svgHeader(Display.esc(dao.name(0)), "MEMBER BADGE");

        svg = string.concat(
            svg,
            "<text x='210' y='135' class='m' font-size='9' fill='#fff' text-anchor='middle'>*    *    *</text>",
            "<text x='210' y='146' class='m' font-size='9' fill='#fff' text-anchor='middle'>/|\\  /|\\  /|\\</text>",
            "<text x='210' y='157' class='m' font-size='9' fill='#fff' text-anchor='middle'>+---+---+---+</text>",
            "<text x='210' y='168' class='m' font-size='9' fill='#fff' text-anchor='middle'>|   | * |   |</text>",
            "<text x='210' y='179' class='m' font-size='9' fill='#fff' text-anchor='middle'>|   |   |   |</text>",
            "<text x='210' y='190' class='m' font-size='9' fill='#fff' text-anchor='middle'>+---+---+---+</text>",
            "<text x='210' y='201' class='m' font-size='9' fill='#fff' text-anchor='middle'>\\         /</text>",
            "<text x='210' y='212' class='m' font-size='9' fill='#fff' text-anchor='middle'>---------</text>",
            "<line x1='40' y1='240' x2='380' y2='240' stroke='#fff' stroke-width='1'/>"
        );

        svg = string.concat(
            svg,
            "<text x='60' y='275' class='g' font-size='10' fill='#aaa' letter-spacing='1'>Address</text>",
            "<text x='60' y='292' class='m' font-size='9' fill='#fff'>",
            addr,
            "</text>",
            "<text x='60' y='325' class='g' font-size='10' fill='#aaa' letter-spacing='1'>Seat</text>",
            "<text x='60' y='345' class='gb' font-size='16' fill='#fff'>",
            seatStr,
            "</text>"
        );

        svg = string.concat(
            svg,
            "<text x='60' y='378' class='g' font-size='10' fill='#aaa' letter-spacing='1'>Balance</text>",
            "<text x='60' y='395' class='m' font-size='9' fill='#fff'>",
            Display.fmtAmount18Simple(bal),
            " shares</text>"
        );

        svg = string.concat(
            svg,
            "<text x='60' y='428' class='g' font-size='10' fill='#aaa' letter-spacing='1'>Ownership</text>",
            "<text x='60' y='445' class='m' font-size='9' fill='#fff'>",
            pct,
            "</text>"
        );

        svg = string.concat(
            svg,
            "<text x='210' y='500' class='g' font-size='12' fill='#fff' text-anchor='middle' letter-spacing='2'>TOP 256 - SEAT ",
            seatStr,
            "</text>"
        );

        svg = string.concat(
            svg,
            "<line x1='40' y1='540' x2='380' y2='540' stroke='#fff' stroke-width='1'/>",
            "<text x='210' y='565' class='g' font-size='8' fill='#444' text-anchor='middle' letter-spacing='1'>NON-TRANSFERABLE</text>",
            "</svg>"
        );

        return Display.jsonImage("Badges", "Top-256 holder badge (SBT)", svg);
    }
}
