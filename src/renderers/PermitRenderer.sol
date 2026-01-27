// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {IMoloch, ICardRenderer} from "./RendererInterfaces.sol";
import {Display} from "./Display.sol";

/// @title PermitRenderer
/// @notice Renders permit cards.
contract PermitRenderer is ICardRenderer {
    function render(IMoloch dao, uint256 id) external view returns (string memory) {
        uint256 supply = dao.totalSupply(id);
        string memory usesStr = supply == 0 ? "NONE" : Display.fmtComma(supply);

        string memory orgName = Display.esc(dao.name(0));

        string memory svg = Display.svgHeader(orgName, "PERMIT");

        svg = string.concat(
            svg,
            "<text x='210' y='140' class='m' font-size='9' fill='#fff' text-anchor='middle'>___</text>",
            "<text x='210' y='151' class='m' font-size='9' fill='#fff' text-anchor='middle'>( o )</text>",
            "<text x='210' y='162' class='m' font-size='9' fill='#fff' text-anchor='middle'>| |</text>",
            "<text x='210' y='173' class='m' font-size='9' fill='#fff' text-anchor='middle'>| |</text>",
            "<text x='210' y='184' class='m' font-size='9' fill='#fff' text-anchor='middle'>====###====</text>",
            "<text x='210' y='195' class='m' font-size='9' fill='#fff' text-anchor='middle'>| |</text>",
            "<text x='210' y='206' class='m' font-size='9' fill='#fff' text-anchor='middle'>| |</text>",
            "<text x='210' y='217' class='m' font-size='9' fill='#fff' text-anchor='middle'>|_|</text>",
            "<line x1='40' y1='245' x2='380' y2='245' stroke='#fff' stroke-width='1'/>"
        );

        svg = string.concat(
            svg,
            "<text x='60' y='280' class='g' font-size='10' fill='#aaa' letter-spacing='1'>Intent ID</text>",
            "<text x='60' y='297' class='m' font-size='9' fill='#fff'>",
            Display.shortDec4(id),
            "</text>",
            "<text x='60' y='330' class='g' font-size='10' fill='#aaa' letter-spacing='1'>Total Supply</text>",
            "<text x='60' y='350' class='gb' font-size='14' fill='#fff'>",
            usesStr,
            "</text>"
        );

        svg = string.concat(
            svg,
            "<text x='210' y='480' class='g' font-size='12' fill='#fff' text-anchor='middle' letter-spacing='2'>ACTIVE</text>",
            "<line x1='40' y1='520' x2='380' y2='520' stroke='#fff' stroke-width='1'/>",
            "</svg>"
        );

        return Display.jsonImage("Permit", "Pre-approved execution permit", svg);
    }
}
