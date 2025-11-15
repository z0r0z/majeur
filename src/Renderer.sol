// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IMajeurRenderer {
    function daoContractURI(IMoloch dao) external view returns (string memory);
    function daoTokenURI(IMoloch dao, uint256 id) external view returns (string memory);
    function badgeTokenURI(IMoloch dao, uint256 seatId) external view returns (string memory);
}

interface IMoloch {
    function name(uint256) external view returns (string memory);
    function symbol(uint256) external view returns (string memory);
    function supplySnapshot(uint256) external view returns (uint256);
    function transfersLocked() external view returns (bool);
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function shares() external view returns (address);
    function badges() external view returns (address);
    function loot() external view returns (address);
    function ownerOf(uint256) external view returns (address);
    function ragequittable() external view returns (bool);
    function receiptProposal(uint256) external view returns (uint256);
    function receiptSupport(uint256) external view returns (uint8);
    function totalSupply(uint256) external view returns (uint256);

    struct FutarchyConfig {
        bool enabled;
        address rewardToken;
        uint256 pool;
        bool resolved;
        uint8 winner;
        uint256 finalWinningSupply;
        uint256 payoutPerUnit;
    }

    function futarchy(uint256) external view returns (FutarchyConfig memory);

    struct Tally {
        uint96 forVotes;
        uint96 againstVotes;
        uint96 abstainVotes;
    }
    function tallies(uint256) external view returns (Tally memory);
    function createdAt(uint256) external view returns (uint64);
    function snapshotBlock(uint256) external view returns (uint48);
    function state(uint256) external view returns (ProposalState);

    enum ProposalState {
        Unopened,
        Active,
        Queued,
        Succeeded,
        Defeated,
        Expired,
        Executed
    }
}

contract Renderer {
    /* URI-SVG */
    function daoContractURI(IMoloch dao) public view returns (string memory) {
        string memory rawOrgName = dao.name(0);
        string memory rawOrgSymbol = dao.symbol(0);

        string memory orgName =
            bytes(rawOrgName).length != 0 ? Display.esc(rawOrgName) : "UNNAMED DAO";
        string memory orgSymbol =
            bytes(rawOrgSymbol).length != 0 ? Display.esc(rawOrgSymbol) : "N/A";
        string memory orgShort = Display.shortAddr4(address(dao)); // "0xAbCd...1234"

        IMoloch shares = IMoloch(dao.shares());
        IMoloch loot = IMoloch(dao.loot());

        // supplies
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
            ".c{font-family:'EB Garamond',serif;font-style:italic;font-size:8;fill:#ccc;}",
            "text{text-rendering:geometricPrecision;}",
            "</style></defs>",
            "<rect width='420' height='600' fill='#000'/>",
            "<rect x='20' y='20' width='380' height='560' fill='none' stroke='#8b0000' stroke-width='2'/>"
        );

        // title section - uses org name
        svg = string.concat(
            svg,
            "<text x='210' y='55' class='gb' font-size='18' fill='#fff' text-anchor='middle' letter-spacing='3'>",
            orgName,
            "</text>",
            "<text x='210' y='75' class='g' font-size='10' fill='#8b0000' text-anchor='middle' letter-spacing='2'>DUNA COVENANT</text>",
            "<line x1='40' y1='90' x2='380' y2='90' stroke='#8b0000' stroke-width='1'/>"
        );

        // ASCII sigil
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

        // organization data
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
            Display.fmtComma(shareSupply / 1e18),
            "</text>"
        );

        if (lootSupply != 0) {
            svg = string.concat(
                svg,
                "<text x='220' y='261' class='g' font-size='9' fill='#aaa'>Loot Supply</text>",
                "<text x='220' y='274' class='m' font-size='8' fill='#fff'>",
                Display.fmtComma(lootSupply / 1e18),
                "</text>"
            );
        }

        // DUNA covenant text - centered
        svg = string.concat(
            svg,
            "<line x1='60' y1='290' x2='360' y2='290' stroke='#8b0000' stroke-width='0.5' opacity='0.5'/>",
            "<text x='210' y='310' class='g' font-size='10' fill='#8b0000' text-anchor='middle'>WYOMING DUNA</text>",
            "<text x='210' y='325' class='c' text-anchor='middle'>W.S. 17-32-101 et seq.</text>"
        );

        // covenant terms - centered alignment
        svg = string.concat(
            svg,
            "<text x='210' y='345' class='c' text-anchor='middle'>By transacting with address ",
            orgShort,
            ", you</text>",
            "<text x='210' y='355' class='c' text-anchor='middle'>acknowledge this organization operates as a Decentralized</text>",
            "<text x='210' y='365' class='c' text-anchor='middle'>Unincorporated Nonprofit Association under Wyoming law.</text>",
            "<text x='210' y='385' class='c' text-anchor='middle'>Members agree to: (i) algorithmic governance via this smart contract,</text>",
            "<text x='210' y='395' class='c' text-anchor='middle'>(ii) limited liability considerations per W.S. 17-32-107,</text>",
            "<text x='210' y='405' class='c' text-anchor='middle'>(iii) dispute resolution through code-as-law principles,</text>",
            "<text x='210' y='415' class='c' text-anchor='middle'>(iv) good faith participation in DAO governance,</text>",
            "<text x='210' y='425' class='c' text-anchor='middle'>(v) adherence to applicable laws and self-help.</text>"
        );

        // transfer and ragequit status
        svg = string.concat(
            svg,
            "<text x='210' y='445' class='c' text-anchor='middle'>Share tokens represent governance rights.</text>",
            "<text x='210' y='455' class='c' text-anchor='middle'>Share transfers are ",
            shares.transfersLocked() ? "DISABLED" : "ENABLED",
            ". Ragequit rights are ",
            dao.ragequittable() ? "ENABLED" : "DISABLED",
            ".</text>"
        );

        // conditionally show loot transfers and adjust positioning
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

        // disclaimer - positioned dynamically
        svg = string.concat(
            svg,
            "<text x='210' y='",
            Display.toString(nextY + 20),
            "' class='c' text-anchor='middle'>No warranty, express or implied. Members participate at</text>",
            "<text x='210' y='",
            Display.toString(nextY + 30),
            "' class='c' text-anchor='middle'>own risk. Not legal, tax, or investment advice.</text>"
        );

        // bottom seal
        svg = string.concat(
            svg,
            "<line x1='60' y1='520' x2='360' y2='520' stroke='#8b0000' stroke-width='0.5' opacity='0.5'/>",
            "<text x='210' y='540' class='m' font-size='8' fill='#8b0000' text-anchor='middle'><![CDATA[ < THE DAO DEMANDS SACRIFICE > ]]></text>",
            "<text x='210' y='560' class='g' font-size='7' fill='#444' text-anchor='middle' letter-spacing='1'>CODE IS LAW - DUNA PROTECTED</text>",
            "</svg>"
        );

        // final JSON with embedded image
        return Display.jsonImage(
            string.concat(
                bytes(rawOrgName).length != 0 ? rawOrgName : "UNNAMED DAO", " DUNA Covenant"
            ),
            "Wyoming Decentralized Unincorporated Nonprofit Association operating charter and member agreement",
            svg
        );
    }

    /// @dev On-chain JSON/SVG card for a proposal id, or routes to receiptURI for vote receipts:
    function daoTokenURI(IMoloch dao, uint256 id) public view returns (string memory) {
        // 1) if this id is a vote receipt, delegate to the full receipt renderer
        if (dao.receiptProposal(id) != 0) return _receiptURI(dao, id);

        IMoloch.Tally memory t = dao.tallies(id);
        bool touchedTallies = (t.forVotes | t.againstVotes | t.abstainVotes) != 0;

        uint256 snap = dao.snapshotBlock(id);
        bool opened = snap != 0 || dao.createdAt(id) != 0;

        bool looksLikePermit = !opened && !touchedTallies && dao.totalSupply(id) != 0;
        if (looksLikePermit) return _permitCardURI(dao, id);

        // ----- Proposal Card -----
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
        string memory svg = Display.svgCardBase();
        string memory orgName = Display.esc(rawOrgName);

        // title
        svg = string.concat(
            svg,
            "<text x='210' y='55' class='gb' font-size='18' fill='#fff' text-anchor='middle' letter-spacing='3'>",
            orgName,
            "</text>",
            "<text x='210' y='75' class='g' font-size='11' fill='#fff' text-anchor='middle' letter-spacing='2'>PROPOSAL</text>",
            "<line x1='40' y1='90' x2='380' y2='90' stroke='#fff' stroke-width='1'/>"
        );

        // ASCII eye (minimalist)
        svg = string.concat(
            svg,
            "<text x='210' y='155' class='m' font-size='9' fill='#fff' text-anchor='middle'>.---------.</text>",
            "<text x='210' y='166' class='m' font-size='9' fill='#fff' text-anchor='middle'>(     O     )</text>",
            "<text x='210' y='177' class='m' font-size='9' fill='#fff' text-anchor='middle'>'---------'</text>",
            "<line x1='40' y1='220' x2='380' y2='220' stroke='#fff' stroke-width='1'/>"
        );

        // data section
        svg = string.concat(
            svg,
            "<text x='60' y='255' class='g' font-size='10' fill='#aaa' letter-spacing='1'>ID</text>",
            "<text x='60' y='272' class='m' font-size='9' fill='#fff'>",
            Display.shortDec4(id), // decimal "1234...5678" if long
            "</text>"
        );

        // snapshot data (only if opened)
        if (opened) {
            svg = string.concat(
                svg,
                "<text x='60' y='305' class='g' font-size='10' fill='#aaa' letter-spacing='1'>Snapshot</text>",
                "<text x='60' y='322' class='m' font-size='9' fill='#fff'>Block ",
                Display.toString(snap),
                "</text>",
                "<text x='60' y='335' class='m' font-size='9' fill='#fff'>Supply ",
                Display.fmtComma(dao.supplySnapshot(id) / 1e18),
                "</text>"
            );
        }

        // tally section (only if votes exist)
        if (touchedTallies) {
            svg = string.concat(
                svg,
                "<text x='60' y='368' class='g' font-size='10' fill='#aaa' letter-spacing='1'>Tally</text>",
                "<text x='60' y='385' class='m' font-size='9' fill='#fff'>For      ",
                Display.fmtComma(t.forVotes / 1e18),
                "</text>",
                "<text x='60' y='398' class='m' font-size='9' fill='#fff'>Against  ",
                Display.fmtComma(t.againstVotes / 1e18),
                "</text>",
                "<text x='60' y='411' class='m' font-size='9' fill='#fff'>Abstain  ",
                Display.fmtComma(t.abstainVotes / 1e18),
                "</text>"
            );
        }

        // status
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

    function _receiptURI(IMoloch dao, uint256 id) internal view returns (string memory) {
        uint8 s = dao.receiptSupport(id); // 0 = NO, 1 = YES, 2 = ABSTAIN

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

        string memory svg = Display.svgCardBase();
        string memory orgName = Display.esc(dao.name(0));

        // title
        svg = string.concat(
            svg,
            "<text x='210' y='55' class='gb' font-size='18' fill='#fff' text-anchor='middle' letter-spacing='3'>",
            orgName,
            "</text>",
            "<text x='210' y='75' class='g' font-size='11' fill='#fff' text-anchor='middle' letter-spacing='2'>VOTE RECEIPT</text>",
            "<line x1='40' y1='90' x2='380' y2='90' stroke='#fff' stroke-width='1'/>"
        );

        // ASCII symbol based on vote type
        if (s == 1) {
            // YES - pointing up hand
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
            // NO - X symbol
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
            // ABSTAIN - circle
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

        // data
        svg = string.concat(
            svg,
            "<text x='60' y='275' class='g' font-size='10' fill='#aaa' letter-spacing='1'>Proposal</text>",
            "<text x='60' y='292' class='m' font-size='9' fill='#fff'>",
            Display.shortDec4(proposalId_), // e.g. 1234...5678
            "</text>",
            "<text x='60' y='325' class='g' font-size='10' fill='#aaa' letter-spacing='1'>Stance</text>",
            "<text x='60' y='345' class='gb' font-size='14' fill='#fff'>",
            stance,
            "</text>",
            "<text x='60' y='378' class='g' font-size='10' fill='#aaa' letter-spacing='1'>Weight</text>",
            "<text x='60' y='395' class='m' font-size='9' fill='#fff'>",
            Display.fmtComma(dao.totalSupply(id) / 1e18),
            " votes</text>"
        );

        // futarchy info (only if enabled)
        if (F.enabled) {
            svg = string.concat(
                svg,
                "<text x='60' y='428' class='g' font-size='10' fill='#aaa' letter-spacing='1'>Futarchy</text>",
                "<text x='60' y='445' class='m' font-size='9' fill='#fff'>Pool ",
                Display.fmtComma(F.pool / 1e18),
                F.rewardToken == address(0) ? " ETH" : " shares",
                "</text>"
            );

            if (F.resolved) {
                svg = string.concat(
                    svg,
                    "<text x='60' y='458' class='m' font-size='9' fill='#fff'>Payout ",
                    Display.fmtComma(F.payoutPerUnit / 1e18),
                    "/vote</text>"
                );
            }
        }

        // status
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

    function _permitCardURI(IMoloch dao, uint256 id) internal view returns (string memory) {
        string memory usesStr;
        uint256 supply = dao.totalSupply(id);

        usesStr = (supply == 0) ? "NONE" : Display.fmtComma(supply);

        string memory svg = Display.svgCardBase();
        string memory orgName = Display.esc(dao.name(0));

        // title
        svg = string.concat(
            svg,
            "<text x='210' y='55' class='gb' font-size='18' fill='#fff' text-anchor='middle' letter-spacing='3'>",
            orgName,
            "</text>",
            "<text x='210' y='75' class='g' font-size='11' fill='#fff' text-anchor='middle' letter-spacing='2'>PERMIT</text>",
            "<line x1='40' y1='90' x2='380' y2='90' stroke='#fff' stroke-width='1'/>"
        );

        // ASCII key
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

        // data
        svg = string.concat(
            svg,
            "<text x='60' y='280' class='g' font-size='10' fill='#aaa' letter-spacing='1'>Intent ID</text>",
            "<text x='60' y='297' class='m' font-size='9' fill='#fff'>",
            Display.shortDec4(id), // e.g. 1234...5678
            "</text>",
            "<text x='60' y='330' class='g' font-size='10' fill='#aaa' letter-spacing='1'>Total Supply</text>", // ← Changed label
            "<text x='60' y='350' class='gb' font-size='14' fill='#fff'>",
            usesStr,
            "</text>"
        );

        // status
        svg = string.concat(
            svg,
            "<text x='210' y='480' class='g' font-size='12' fill='#fff' text-anchor='middle' letter-spacing='2'>ACTIVE</text>",
            "<line x1='40' y1='520' x2='380' y2='520' stroke='#fff' stroke-width='1'/>",
            "</svg>"
        );

        return Display.jsonImage("Permit", "Pre-approved execution permit", svg);
    }

    /// @dev Top-256 badge (seat index; tokenId == seat, not sorted by balance):
    function badgeTokenURI(IMoloch dao, uint256 seatId) public view returns (string memory) {
        IMoloch badges = IMoloch(dao.badges());
        // reverts if the seat token isn't minted; guarantees we're seated
        address holder = badges.ownerOf(seatId);

        IMoloch sh = IMoloch(dao.shares());
        uint256 bal = sh.balanceOf(holder);
        uint256 balInTokens = bal / 1e18;
        uint256 ts = sh.totalSupply();

        // seat string comes straight from tokenId
        string memory addr = Display.shortAddr4(holder);
        string memory pct = Display.percent2(bal, ts);
        string memory seatStr = Display.toString(seatId);
        string memory svg = Display.svgCardBase();

        // title
        svg = string.concat(
            svg,
            "<text x='210' y='55' class='gb' font-size='18' fill='#fff' text-anchor='middle' letter-spacing='3'>",
            Display.esc(dao.name(0)),
            "</text>",
            "<text x='210' y='75' class='g' font-size='11' fill='#fff' text-anchor='middle' letter-spacing='2'>MEMBER BADGE</text>",
            "<line x1='40' y1='90' x2='380' y2='90' stroke='#fff' stroke-width='1'/>"
        );

        // ASCII crown
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

        // data
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

        // balance
        svg = string.concat(
            svg,
            "<text x='60' y='378' class='g' font-size='10' fill='#aaa' letter-spacing='1'>Balance</text>",
            "<text x='60' y='395' class='m' font-size='9' fill='#fff'>",
            Display.fmtComma(balInTokens), // 123,456,789
            " shares</text>"
        );

        // ownership
        svg = string.concat(
            svg,
            "<text x='60' y='428' class='g' font-size='10' fill='#aaa' letter-spacing='1'>Ownership</text>",
            "<text x='60' y='445' class='m' font-size='9' fill='#fff'>",
            pct,
            "</text>"
        );

        // status — token exists only for top-256, so always show the banner
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

/// @dev Display — Solady helpers for on-chain SVG / string rendering:
library Display {
    /*──────────────────────  DATA URIs  ─────────────────────*/

    function jsonDataURI(string memory raw) internal pure returns (string memory) {
        return string.concat("data:application/json;base64,", encode(bytes(raw)));
    }

    function svgDataURI(string memory raw) internal pure returns (string memory) {
        return string.concat("data:image/svg+xml;base64,", encode(bytes(raw)));
    }

    function jsonImage(string memory name_, string memory description_, string memory svg_)
        internal
        pure
        returns (string memory)
    {
        return jsonDataURI(
            string.concat(
                '{"name":"',
                name_,
                '","description":"',
                description_,
                '","image":"',
                svgDataURI(svg_),
                '"}'
            )
        );
    }

    /*──────────────────────  SVG BASE  ─────────────────────*/

    function svgCardBase() internal pure returns (string memory) {
        return string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' width='420' height='600'>",
            "<defs><style>",
            ".g{font-family:'EB Garamond',serif;}",
            ".gb{font-family:'EB Garamond',serif;font-weight:600;}",
            ".m{font-family:'Courier Prime',monospace;}",
            "</style></defs>",
            "<rect width='420' height='600' fill='#000'/>",
            "<rect x='20' y='20' width='380' height='560' fill='none' stroke='#fff' stroke-width='1'/>"
        );
    }

    /*──────────────────────  DECIMAL IDs  ─────────────────────*/

    /// @dev "1234...5678" from a big decimal id:
    function shortDec4(uint256 v) internal pure returns (string memory) {
        string memory s = toString(v);
        uint256 n = bytes(s).length;
        if (n <= 11) return s;
        unchecked {
            return string.concat(slice(s, 0, 4), "...", slice(s, n - 4, n));
        }
    }

    /*──────────────────────  ADDRESSES  ─────────────────────*/

    /// @dev EIP-55 "0xAbCd...1234" (0x + 4 nibbles ... 4 nibbles):
    function shortAddr4(address a) internal pure returns (string memory) {
        string memory full = toHexStringChecksummed(a);
        uint256 n = bytes(full).length;
        unchecked {
            return string.concat(slice(full, 0, 6), "...", slice(full, n - 4, n));
        }
    }

    /*──────────────────────  NUMBERS  ─────────────────────*/

    /// @dev Decimal with commas: 123_456_789 => "123,456,789":
    function fmtComma(uint256 n) internal pure returns (string memory) {
        if (n == 0) return "0";
        uint256 temp = n;
        uint256 digits;
        while (temp != 0) {
            unchecked {
                ++digits;
                temp /= 10;
            }
        }
        uint256 commas = (digits - 1) / 3;
        bytes memory buf = new bytes(digits + commas);
        uint256 i = buf.length;
        uint256 dcount;
        while (n != 0) {
            if (dcount != 0 && dcount % 3 == 0) {
                unchecked {
                    buf[--i] = ",";
                }
            }
            unchecked {
                buf[--i] = bytes1(uint8(48 + (n % 10)));
                n /= 10;
                ++dcount;
            }
        }
        return string(buf);
    }

    /// @dev Percent with 2 decimals from a/b, e.g. 1234/10000 => "12.34%":
    function percent2(uint256 a, uint256 b) internal pure returns (string memory) {
        if (b == 0) return "0.00%";
        uint256 p = (a * 10000) / b; // basis points
        uint256 whole = p / 100;
        uint256 frac = p % 100;
        return string.concat(toString(whole), ".", (frac < 10) ? "0" : "", toString(frac), "%");
    }

    /*──────────────────────  ESCAPE  ─────────────────────*/

    function esc(string memory s) internal pure returns (string memory result) {
        assembly ("memory-safe") {
            result := mload(0x40)
            let end := add(s, mload(s))
            let o := add(result, 0x20)
            mstore(0x1f, 0x900094)
            mstore(0x08, 0xc0000000a6ab)
            mstore(0x00, shl(64, 0x2671756f743b26616d703b262333393b266c743b2667743b))
            for {} iszero(eq(s, end)) {} {
                s := add(s, 1)
                let c := and(mload(s), 0xff)
                if iszero(and(shl(c, 1), 0x500000c400000000)) {
                    mstore8(o, c)
                    o := add(o, 1)
                    continue
                }
                let t := shr(248, mload(c))
                mstore(o, mload(and(t, 0x1f)))
                o := add(o, shr(5, t))
            }
            mstore(o, 0)
            mstore(result, sub(o, add(result, 0x20)))
            mstore(0x40, add(o, 0x20))
        }
    }

    /*──────────────────────  MINI STRING PRIMS  ─────────────────────*/

    function toString(uint256 value) internal pure returns (string memory result) {
        assembly ("memory-safe") {
            result := add(mload(0x40), 0x80)
            mstore(0x40, add(result, 0x20))
            mstore(result, 0)
            let end := result
            let w := not(0)
            for { let temp := value } 1 {} {
                result := add(result, w)
                mstore8(result, add(48, mod(temp, 10)))
                temp := div(temp, 10)
                if iszero(temp) { break }
            }
            let n := sub(end, result)
            result := sub(result, 0x20)
            mstore(result, n)
        }
    }

    function slice(string memory subject, uint256 start, uint256 end)
        internal
        pure
        returns (string memory result)
    {
        assembly ("memory-safe") {
            let l := mload(subject)
            if iszero(gt(l, end)) { end := l }
            if iszero(gt(l, start)) { start := l }
            if lt(start, end) {
                result := mload(0x40)
                let n := sub(end, start)
                let i := add(subject, start)
                let w := not(0x1f)
                for { let j := and(add(n, 0x1f), w) } 1 {} {
                    mstore(add(result, j), mload(add(i, j)))
                    j := add(j, w)
                    if iszero(j) { break }
                }
                let o := add(add(result, 0x20), n)
                mstore(o, 0)
                mstore(0x40, add(o, 0x20))
                mstore(result, n)
            }
        }
    }

    /*──────────────────────  MINI HEX PRIMS  ─────────────────────*/

    function toHexStringChecksummed(address value) internal pure returns (string memory result) {
        assembly ("memory-safe") {
            result := mload(0x40)
            mstore(0x40, add(result, 0x80))
            mstore(0x0f, 0x30313233343536373839616263646566)
            result := add(result, 2)
            mstore(result, 40)
            let o := add(result, 0x20)
            mstore(add(o, 40), 0)
            value := shl(96, value)
            for { let i := 0 } 1 {} {
                let p := add(o, add(i, i))
                let temp := byte(i, value)
                mstore8(add(p, 1), mload(and(temp, 15)))
                mstore8(p, mload(shr(4, temp)))
                i := add(i, 1)
                if eq(i, 20) { break }
            }
            mstore(result, 0x3078)
            result := sub(result, 2)
            mstore(result, 42)
            let mask := shl(6, div(not(0), 255))
            o := add(result, 0x22)
            let hashed := and(keccak256(o, 40), mul(34, mask))
            let t := shl(240, 136)
            for { let i := 0 } 1 {} {
                mstore(add(i, i), mul(t, byte(i, hashed)))
                i := add(i, 1)
                if eq(i, 20) { break }
            }
            mstore(o, xor(mload(o), shr(1, and(mload(0x00), and(mload(o), mask)))))
            o := add(o, 0x20)
            mstore(o, xor(mload(o), shr(1, and(mload(0x20), and(mload(o), mask)))))
        }
    }

    /*──────────────────────  MINI BASE64  ─────────────────────*/

    function encode(bytes memory data) internal pure returns (string memory result) {
        assembly ("memory-safe") {
            let dataLength := mload(data)
            if dataLength {
                let encodedLength := shl(2, div(add(dataLength, 2), 3))
                result := mload(0x40)
                mstore(0x1f, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef")
                mstore(0x3f, "ghijklmnopqrstuvwxyz0123456789+/")
                let ptr := add(result, 0x20)
                let end := add(ptr, encodedLength)
                let dataEnd := add(add(0x20, data), dataLength)
                let dataEndValue := mload(dataEnd)
                mstore(dataEnd, 0x00)
                for {} 1 {} {
                    data := add(data, 3)
                    let input := mload(data)
                    mstore8(0, mload(and(shr(18, input), 0x3F)))
                    mstore8(1, mload(and(shr(12, input), 0x3F)))
                    mstore8(2, mload(and(shr(6, input), 0x3F)))
                    mstore8(3, mload(and(input, 0x3F)))
                    mstore(ptr, mload(0x00))
                    ptr := add(ptr, 4)
                    if iszero(lt(ptr, end)) { break }
                }
                mstore(dataEnd, dataEndValue)
                mstore(0x40, add(end, 0x20))
                let o := div(2, mod(dataLength, 3))
                mstore(sub(ptr, o), shl(240, 0x3d3d))
                mstore(ptr, 0)
                mstore(result, encodedLength)
            }
        }
    }
}
