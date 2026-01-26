// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IMoloch, ICovenantRenderer} from "./RendererInterfaces.sol";
import {Display} from "./Display.sol";

/// @title CovenantRenderer
/// @notice Renders the DUNA Covenant card for a DAO's contractURI.
contract CovenantRenderer is ICovenantRenderer {
    function render(IMoloch dao) external view returns (string memory) {
        string memory rawOrgName = dao.name(0);
        string memory rawOrgSymbol = dao.symbol(0);

        string memory orgName =
            bytes(rawOrgName).length != 0 ? Display.esc(rawOrgName) : "UNNAMED DAO";
        string memory orgSymbol =
            bytes(rawOrgSymbol).length != 0 ? Display.esc(rawOrgSymbol) : "N/A";
        string memory orgShort = Display.shortAddr4(address(dao));

        IMoloch shares = IMoloch(dao.shares());
        IMoloch loot = IMoloch(dao.loot());

        uint256 shareSupply = shares.totalSupply();
        uint256 lootSupply = loot.totalSupply();

        string memory svg = string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' width='420' height='600' viewBox='0 0 420 600'>",
            "<title>",
            orgName,
            " - DUNA Covenant</title>",
            "<desc>Wyoming Decentralized Unincorporated Nonprofit Association operating charter and member agreement.</desc>",
            "<defs><style>",
            ".g{font-family:'EB Garamond',serif;}",
            ".gb{font-family:'EB Garamond',serif;font-weight:600;}",
            ".m{font-family:'Courier Prime',monospace;font-variant-ligatures:none;}",
            ".c{font-family:'EB Garamond',serif;font-style:italic;font-size:7px;fill:#ccc;}",
            "text{text-rendering:geometricPrecision;}",
            "</style></defs>",
            "<rect width='420' height='600' fill='#000'/>",
            "<rect x='20' y='20' width='380' height='560' fill='none' stroke='#8b0000' stroke-width='2'/>"
        );

        svg = string.concat(
            svg,
            "<text x='210' y='55' class='gb' font-size='18' fill='#fff' text-anchor='middle' letter-spacing='3'>",
            orgName,
            "</text>",
            "<text x='210' y='75' class='g' font-size='10' fill='#8b0000' text-anchor='middle' letter-spacing='2'>DUNA COVENANT</text>",
            "<line x1='40' y1='90' x2='380' y2='90' stroke='#8b0000' stroke-width='1'/>"
        );

        svg = string.concat(
            svg,
            "<text x='210' y='115' class='m' font-size='7' fill='#8b0000' text-anchor='middle'>___/\\___</text>",
            "<text x='210' y='124' class='m' font-size='7' fill='#8b0000' text-anchor='middle'>/  \\  /  \\</text>",
            "<text x='210' y='133' class='m' font-size='7' fill='#8b0000' text-anchor='middle'>/    \\/    \\</text>",
            "<text x='210' y='142' class='m' font-size='7' fill='#8b0000' text-anchor='middle'>\\  /\\  /\\  /</text>",
            "<text x='210' y='151' class='m' font-size='7' fill='#8b0000' text-anchor='middle'>\\/  \\/  \\/</text>",
            "<text x='210' y='160' class='m' font-size='7' fill='#8b0000' text-anchor='middle'>*</text>",
            "<line x1='60' y1='175' x2='360' y2='175' stroke='#8b0000' stroke-width='0.5' opacity='0.5'/>"
        );

        svg = string.concat(
            svg,
            "<text x='60' y='195' class='g' font-size='9' fill='#aaa'>Organization</text>",
            "<text x='60' y='208' class='m' font-size='8' fill='#fff'>",
            orgShort,
            "</text>",
            "<text x='60' y='228' class='g' font-size='9' fill='#aaa'>Name / Symbol</text>",
            "<text x='60' y='241' class='m' font-size='8' fill='#fff'>",
            orgName,
            " / ",
            orgSymbol,
            "</text>"
        );

        svg = string.concat(
            svg,
            "<text x='60' y='261' class='g' font-size='9' fill='#aaa'>Share Supply</text>",
            "<text x='60' y='274' class='m' font-size='8' fill='#fff'>",
            Display.fmtAmount18Simple(shareSupply),
            "</text>"
        );

        if (lootSupply != 0) {
            svg = string.concat(
                svg,
                "<text x='220' y='261' class='g' font-size='9' fill='#aaa'>Loot Supply</text>",
                "<text x='220' y='274' class='m' font-size='8' fill='#fff'>",
                Display.fmtAmount18Simple(lootSupply),
                "</text>"
            );
        }

        svg = string.concat(
            svg,
            "<line x1='60' y1='290' x2='360' y2='290' stroke='#8b0000' stroke-width='0.5' opacity='0.5'/>",
            "<text x='210' y='310' class='g' font-size='10' fill='#8b0000' text-anchor='middle'>WYOMING DUNA</text>",
            "<text x='210' y='325' class='c' text-anchor='middle'>W.S. 17-32-101 et seq.</text>",
            "<text x='210' y='340' class='c' text-anchor='middle'><tspan x='210' dy='0'>By transacting with address ",
            orgShort,
            "</tspan>",
            "<tspan x='210' dy='9'>you acknowledge this organization operates as a</tspan>",
            "<tspan x='210' dy='9'>Wyoming Decentralized Unincorporated Nonprofit Association</tspan>",
            "<tspan x='210' dy='9'>(W.S. 17-32-101 et seq.). Holding members covenant to:</tspan>",
            "<tspan x='210' dy='11'>(i) defer to this smart contract for internal governance;</tspan>",
            "<tspan x='210' dy='9'>(ii) use DAO procedures and designated arbitrators</tspan>",
            "<tspan x='210' dy='9'>for disputes; (iii) help maintain or wind up this organization;</tspan>",
            "<tspan x='210' dy='9'>(iv) participate in good faith; and (v) manage</tspan>",
            "<tspan x='210' dy='9'>their own legal compliance and self-help.</tspan></text>"
        );

        svg = string.concat(
            svg,
            "<text x='210' y='445' class='c' text-anchor='middle'>Share tokens represent governance rights.</text>",
            "<text x='210' y='455' class='c' text-anchor='middle'>Share transfers are ",
            shares.transfersLocked() ? "DISABLED" : "ENABLED",
            ". Ragequit rights are ",
            dao.ragequittable() ? "ENABLED" : "DISABLED",
            ".</text>"
        );

        uint256 nextY = 465;
        if (lootSupply != 0) {
            svg = string.concat(
                svg,
                "<text x='210' y='",
                Display.toString(nextY),
                "' class='c' text-anchor='middle'>Loot transfers are ",
                loot.transfersLocked() ? "DISABLED" : "ENABLED",
                ".</text>"
            );
            unchecked {
                nextY += 10;
            }
        }

        svg = string.concat(
            svg,
            "<text x='210' y='",
            Display.toString(nextY),
            "' class='c' text-anchor='middle'>This Covenant is amendable by DAO vote.</text>"
        );

        svg = string.concat(
            svg,
            "<text x='210' y='",
            Display.toString(nextY + 20),
            "' class='c' text-anchor='middle'>No warranty (express or implied); members participate at own risk; not legal, tax or investment advice.</text>"
        );

        svg = string.concat(
            svg,
            "<line x1='60' y1='520' x2='360' y2='520' stroke='#8b0000' stroke-width='0.5' opacity='0.5'/>",
            "<text x='210' y='540' class='m' font-size='8' fill='#8b0000' text-anchor='middle'><![CDATA[ < THE DAO DEMANDS SACRIFICE > ]]></text>",
            "<text x='210' y='560' class='g' font-size='7' fill='#444' text-anchor='middle' letter-spacing='1'>CODE IS LAW - DUNA PROTECTED</text>",
            "</svg>"
        );

        return Display.jsonImage(
            string.concat(
                bytes(rawOrgName).length != 0 ? rawOrgName : "UNNAMED DAO", " DUNA Covenant"
            ),
            "Wyoming Decentralized Unincorporated Nonprofit Association operating charter and member agreement",
            svg
        );
    }
}
