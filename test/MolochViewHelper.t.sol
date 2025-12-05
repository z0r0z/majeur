// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "../lib/forge-std/src/Test.sol";
import {Renderer} from "../src/Renderer.sol";
import {Moloch, Shares, Loot, Badges, Summoner, Call} from "../src/Moloch.sol";
import {
    ISummoner,
    IBadges,
    IShares,
    ILoot,
    IERC20,
    IMoloch,
    IDAICO,
    Seat,
    DAOLens,
    DAOMeta,
    DAOGovConfig,
    DAOTokenSupplies,
    DAOTreasury,
    TokenBalance,
    MemberView,
    ProposalView,
    MessageView,
    UserMemberView,
    UserDAOLens,
    FutarchyView,
    VoterView,
    SaleView,
    TapView,
    DAICOView,
    DAICOLens
} from "../src/peripheral/MolochViewHelper.sol";

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract Target {
    uint256 public value;

    function setValue(uint256 _value) public payable {
        value = _value;
    }

    fallback() external payable {}
    receive() external payable {}
}

/// @dev Mock DAICO for testing view helper
contract MockDAICO {
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

    // Test helpers to set state
    function setSale(
        address dao,
        address tribTkn,
        uint256 tribAmt,
        uint256 forAmt,
        address forTkn,
        uint40 deadline
    ) external {
        sales[dao][tribTkn] = TributeOffer({
            tribAmt: tribAmt, forAmt: forAmt, forTkn: forTkn, deadline: deadline
        });
    }

    function setTap(address dao, address ops, address tribTkn, uint128 ratePerSec, uint64 lastClaim)
        external
    {
        taps[dao] = Tap({ops: ops, tribTkn: tribTkn, ratePerSec: ratePerSec, lastClaim: lastClaim});
    }

    function setLPConfig(
        address dao,
        address tribTkn,
        uint16 lpBps,
        uint16 maxSlipBps,
        uint256 feeOrHook
    ) external {
        lpConfigs[dao][tribTkn] = LPConfig({
            lpBps: lpBps, maxSlipBps: maxSlipBps, feeOrHook: feeOrHook
        });
    }

    function claimableTap(address dao) external view returns (uint256) {
        Tap memory tap = taps[dao];
        if (tap.ops == address(0) || tap.ratePerSec == 0) return 0;
        uint64 elapsed = uint64(block.timestamp) - tap.lastClaim;
        return uint256(tap.ratePerSec) * uint256(elapsed);
    }

    function pendingTap(address dao) external view returns (uint256) {
        Tap memory tap = taps[dao];
        if (tap.ratePerSec == 0) return 0;
        uint64 elapsed = uint64(block.timestamp) - tap.lastClaim;
        return uint256(tap.ratePerSec) * uint256(elapsed);
    }
}

/// @dev Test version of MolochViewHelper with configurable Summoner and DAICO
contract TestViewHelper {
    ISummoner public immutable SUMMONER;
    IDAICO public immutable DAICO;

    constructor(address _summoner, address _daico) {
        SUMMONER = ISummoner(_summoner);
        DAICO = IDAICO(_daico);
    }

    function getDaos(uint256 start, uint256 count) public view returns (address[] memory out) {
        uint256 total = SUMMONER.getDAOCount();
        if (start >= total) {
            return new address[](0);
        }

        uint256 end = start + count;
        if (end > total) end = total;

        uint256 len = end - start;
        out = new address[](len);

        for (uint256 i; i < len; ++i) {
            out[i] = SUMMONER.daos(start + i);
        }
    }

    function getDAOFullState(
        address dao,
        uint256 proposalStart,
        uint256 proposalCount,
        uint256 messageStart,
        uint256 messageCount,
        address[] calldata treasuryTokens
    ) public view returns (DAOLens memory out) {
        out = _buildDAOFullState(
            dao, proposalStart, proposalCount, messageStart, messageCount, treasuryTokens
        );
    }

    function getDAOsFullState(
        uint256 daoStart,
        uint256 daoCount,
        uint256 proposalStart,
        uint256 proposalCount,
        uint256 messageStart,
        uint256 messageCount,
        address[] calldata treasuryTokens
    ) public view returns (DAOLens[] memory out) {
        uint256 total = SUMMONER.getDAOCount();
        if (daoStart >= total) {
            return new DAOLens[](0);
        }

        uint256 daoEnd = daoStart + daoCount;
        if (daoEnd > total) daoEnd = total;

        uint256 len = daoEnd - daoStart;
        out = new DAOLens[](len);

        for (uint256 i; i < len; ++i) {
            address dao = SUMMONER.daos(daoStart + i);
            out[i] = _buildDAOFullState(
                dao, proposalStart, proposalCount, messageStart, messageCount, treasuryTokens
            );
        }
    }

    function getUserDAOs(
        address user,
        uint256 daoStart,
        uint256 daoCount,
        address[] calldata treasuryTokens
    ) public view returns (UserMemberView[] memory out) {
        uint256 total = SUMMONER.getDAOCount();
        if (daoStart >= total) {
            return new UserMemberView[](0);
        }

        uint256 daoEnd = daoStart + daoCount;
        if (daoEnd > total) daoEnd = total;

        uint256 matchCount;
        for (uint256 i = daoStart; i < daoEnd; ++i) {
            address dao = SUMMONER.daos(i);
            IMoloch M = IMoloch(dao);

            address sharesToken = M.shares();
            address lootToken = M.loot();
            address badgesToken = M.badges();

            if (
                IShares(sharesToken).balanceOf(user) != 0 || ILoot(lootToken).balanceOf(user) != 0
                    || IBadges(badgesToken).seatOf(user) != 0
            ) {
                ++matchCount;
            }
        }

        out = new UserMemberView[](matchCount);
        uint256 k;

        for (uint256 i = daoStart; i < daoEnd; ++i) {
            address dao = SUMMONER.daos(i);
            IMoloch M = IMoloch(dao);

            address sharesToken = M.shares();
            address lootToken = M.loot();
            address badgesToken = M.badges();

            uint256 sharesBal = IShares(sharesToken).balanceOf(user);
            uint256 lootBal = ILoot(lootToken).balanceOf(user);
            uint256 seatId = IBadges(badgesToken).seatOf(user);

            if (sharesBal == 0 && lootBal == 0 && seatId == 0) {
                continue;
            }

            DAOMeta memory meta;
            meta.name = M.name(0);
            meta.symbol = M.symbol(0);
            meta.contractURI = M.contractURI();
            meta.sharesToken = sharesToken;
            meta.lootToken = lootToken;
            meta.badgesToken = badgesToken;
            meta.renderer = M.renderer();

            DAOGovConfig memory gov;
            gov.proposalThreshold = M.proposalThreshold();
            gov.minYesVotesAbsolute = M.minYesVotesAbsolute();
            gov.quorumAbsolute = M.quorumAbsolute();
            gov.proposalTTL = M.proposalTTL();
            gov.timelockDelay = M.timelockDelay();
            gov.quorumBps = M.quorumBps();
            gov.ragequittable = M.ragequittable();
            gov.autoFutarchyParam = M.autoFutarchyParam();
            gov.autoFutarchyCap = M.autoFutarchyCap();
            gov.rewardToken = M.rewardToken();

            DAOTokenSupplies memory supplies;
            supplies.sharesTotalSupply = IShares(sharesToken).totalSupply();
            supplies.lootTotalSupply = ILoot(lootToken).totalSupply();
            supplies.sharesHeldByDAO = IShares(sharesToken).balanceOf(dao);
            supplies.lootHeldByDAO = ILoot(lootToken).balanceOf(dao);

            DAOTreasury memory treasury = _getTreasury(dao, treasuryTokens);

            (address[] memory dels, uint32[] memory bps) =
                IShares(sharesToken).splitDelegationOf(user);
            uint256 votingPower = IShares(sharesToken).getVotes(user);

            MemberView memory memberView = MemberView({
                account: user,
                shares: sharesBal,
                loot: lootBal,
                seatId: uint16(seatId),
                votingPower: votingPower,
                delegates: dels,
                delegatesBps: bps
            });

            out[k] = UserMemberView({
                dao: dao,
                meta: meta,
                gov: gov,
                supplies: supplies,
                treasury: treasury,
                member: memberView
            });

            ++k;
        }
    }

    function getUserDAOsFullState(
        address user,
        uint256 daoStart,
        uint256 daoCount,
        uint256 proposalStart,
        uint256 proposalCount,
        uint256 messageStart,
        uint256 messageCount,
        address[] calldata treasuryTokens
    ) public view returns (UserDAOLens[] memory out) {
        uint256 total = SUMMONER.getDAOCount();
        if (daoStart >= total) {
            return new UserDAOLens[](0);
        }

        uint256 daoEnd = daoStart + daoCount;
        if (daoEnd > total) daoEnd = total;

        uint256 matchCount;
        for (uint256 i = daoStart; i < daoEnd; ++i) {
            address dao = SUMMONER.daos(i);
            IMoloch M = IMoloch(dao);

            address sharesToken = M.shares();
            address lootToken = M.loot();
            address badgesToken = M.badges();

            if (
                IShares(sharesToken).balanceOf(user) != 0 || ILoot(lootToken).balanceOf(user) != 0
                    || IBadges(badgesToken).seatOf(user) != 0
            ) {
                ++matchCount;
            }
        }

        out = new UserDAOLens[](matchCount);
        uint256 k;

        for (uint256 i = daoStart; i < daoEnd; ++i) {
            address daoAddr = SUMMONER.daos(i);
            IMoloch M = IMoloch(daoAddr);

            address sharesToken = M.shares();
            address lootToken = M.loot();
            address badgesToken = M.badges();

            uint256 sharesBal = IShares(sharesToken).balanceOf(user);
            uint256 lootBal = ILoot(lootToken).balanceOf(user);
            uint256 seatId = IBadges(badgesToken).seatOf(user);

            if (sharesBal == 0 && lootBal == 0 && seatId == 0) {
                continue;
            }

            DAOLens memory daoLens = _buildDAOFullState(
                daoAddr, proposalStart, proposalCount, messageStart, messageCount, treasuryTokens
            );

            (address[] memory dels, uint32[] memory bps) =
                IShares(sharesToken).splitDelegationOf(user);
            uint256 votingPower = IShares(sharesToken).getVotes(user);

            MemberView memory memberView = MemberView({
                account: user,
                shares: sharesBal,
                loot: lootBal,
                seatId: uint16(seatId),
                votingPower: votingPower,
                delegates: dels,
                delegatesBps: bps
            });

            out[k] = UserDAOLens({dao: daoLens, member: memberView});
            ++k;
        }
    }

    function getDAOMessages(address dao, uint256 start, uint256 count)
        public
        view
        returns (MessageView[] memory out)
    {
        out = _getMessagesInternal(dao, start, count);
    }

    function _buildDAOFullState(
        address dao,
        uint256 proposalStart,
        uint256 proposalCount,
        uint256 messageStart,
        uint256 messageCount,
        address[] calldata treasuryTokens
    ) internal view returns (DAOLens memory out) {
        IMoloch M = IMoloch(dao);

        DAOMeta memory meta;
        meta.name = M.name(0);
        meta.symbol = M.symbol(0);
        meta.contractURI = M.contractURI();
        meta.sharesToken = M.shares();
        meta.lootToken = M.loot();
        meta.badgesToken = M.badges();
        meta.renderer = M.renderer();

        DAOGovConfig memory gov;
        gov.proposalThreshold = M.proposalThreshold();
        gov.minYesVotesAbsolute = M.minYesVotesAbsolute();
        gov.quorumAbsolute = M.quorumAbsolute();
        gov.proposalTTL = M.proposalTTL();
        gov.timelockDelay = M.timelockDelay();
        gov.quorumBps = M.quorumBps();
        gov.ragequittable = M.ragequittable();
        gov.autoFutarchyParam = M.autoFutarchyParam();
        gov.autoFutarchyCap = M.autoFutarchyCap();
        gov.rewardToken = M.rewardToken();

        IShares sharesToken = IShares(meta.sharesToken);
        ILoot lootToken = ILoot(meta.lootToken);

        DAOTokenSupplies memory supplies;
        supplies.sharesTotalSupply = sharesToken.totalSupply();
        supplies.lootTotalSupply = lootToken.totalSupply();
        supplies.sharesHeldByDAO = sharesToken.balanceOf(dao);
        supplies.lootHeldByDAO = lootToken.balanceOf(dao);

        MemberView[] memory members =
            _getMembers(meta.sharesToken, meta.lootToken, meta.badgesToken);
        ProposalView[] memory proposals = _getProposals(M, members, proposalStart, proposalCount);
        MessageView[] memory messages = _getMessagesInternal(dao, messageStart, messageCount);

        DAOTreasury memory treasury = _getTreasury(dao, treasuryTokens);

        out.dao = dao;
        out.meta = meta;
        out.gov = gov;
        out.supplies = supplies;
        out.treasury = treasury;
        out.members = members;
        out.proposals = proposals;
        out.messages = messages;
    }

    function _getMembers(address sharesToken, address lootToken, address badgesToken)
        internal
        view
        returns (MemberView[] memory mv)
    {
        IBadges badges = IBadges(badgesToken);
        Seat[] memory seats = badges.getSeats();
        uint256 len = seats.length;

        mv = new MemberView[](len);
        IShares shares = IShares(sharesToken);
        ILoot loot = ILoot(lootToken);

        for (uint256 i; i < len; ++i) {
            address account = seats[i].holder;
            uint256 seatId = badges.seatOf(account);
            (address[] memory dels, uint32[] memory bps) = shares.splitDelegationOf(account);

            mv[i] = MemberView({
                account: account,
                shares: uint256(seats[i].bal),
                loot: loot.balanceOf(account),
                seatId: uint16(seatId),
                votingPower: shares.getVotes(account),
                delegates: dels,
                delegatesBps: bps
            });
        }
    }

    function _getProposals(IMoloch M, MemberView[] memory members, uint256 start, uint256 count)
        internal
        view
        returns (ProposalView[] memory pv)
    {
        uint256 total = M.getProposalCount();
        if (start >= total) {
            return new ProposalView[](0);
        }

        uint256 end = start + count;
        if (end > total) end = total;
        uint256 len = end - start;

        pv = new ProposalView[](len);
        uint256 memberCount = members.length;

        for (uint256 i; i < len; ++i) {
            uint256 idx = start + i;
            uint256 pid = M.proposalIds(idx);

            (uint96 forV, uint96 againstV, uint96 abstainV) = M.tallies(pid);

            ProposalView memory P;
            P.id = pid;
            P.proposer = M.proposerOf(pid);
            P.state = M.state(pid);
            P.snapshotBlock = M.snapshotBlock(pid);
            P.createdAt = M.createdAt(pid);
            P.queuedAt = M.queuedAt(pid);
            P.supplySnapshot = M.supplySnapshot(pid);

            P.forVotes = forV;
            P.againstVotes = againstV;
            P.abstainVotes = abstainV;

            (
                bool fEnabled,
                address fToken,
                uint256 fPool,
                bool fResolved,
                uint8 fWinner,
                uint256 fFinalSupply,
                uint256 fPayoutPerUnit
            ) = M.futarchy(pid);

            P.futarchy = FutarchyView({
                enabled: fEnabled,
                rewardToken: fToken,
                pool: fPool,
                resolved: fResolved,
                winner: fWinner,
                finalWinningSupply: fFinalSupply,
                payoutPerUnit: fPayoutPerUnit
            });

            if (memberCount != 0) {
                uint8[] memory votedCache = new uint8[](memberCount);
                uint256 nVoters;

                for (uint256 j; j < memberCount; ++j) {
                    address voterAddr = members[j].account;
                    uint8 hv = M.hasVoted(pid, voterAddr);
                    votedCache[j] = hv;
                    if (hv != 0) {
                        unchecked {
                            ++nVoters;
                        }
                    }
                }

                VoterView[] memory voters = new VoterView[](nVoters);
                uint256 k;

                for (uint256 j; j < memberCount; ++j) {
                    uint8 hv = votedCache[j];
                    if (hv != 0) {
                        address voterAddr = members[j].account;
                        uint96 weight96 = M.voteWeight(pid, voterAddr);

                        voters[k] = VoterView({
                            voter: voterAddr, support: hv - 1, weight: uint256(weight96)
                        });
                        unchecked {
                            ++k;
                        }
                    }
                }

                P.voters = voters;
            }

            pv[i] = P;
        }
    }

    function _getMessagesInternal(address dao, uint256 start, uint256 count)
        internal
        view
        returns (MessageView[] memory out)
    {
        IMoloch M = IMoloch(dao);
        uint256 total = M.getMessageCount();
        if (start >= total) {
            return new MessageView[](0);
        }

        uint256 end = start + count;
        if (end > total) end = total;
        uint256 len = end - start;

        out = new MessageView[](len);
        for (uint256 i; i < len; ++i) {
            uint256 idx = start + i;
            out[i] = MessageView({index: idx, text: M.messages(idx)});
        }
    }

    function _getTreasury(address dao, address[] calldata tokens)
        internal
        view
        returns (DAOTreasury memory t)
    {
        uint256 len = tokens.length;
        t.balances = new TokenBalance[](len);

        for (uint256 i; i < len; ++i) {
            address token = tokens[i];
            uint256 bal;

            if (token == address(0)) {
                bal = dao.balance;
            } else {
                (bool success, bytes memory data) =
                    token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, dao));
                if (success && data.length >= 32) {
                    bal = abi.decode(data, (uint256));
                }
            }

            t.balances[i] = TokenBalance({token: token, balance: bal});
        }
    }

    /* ---------------------------------------------------------------------- */
    /*                           DAICO SCAN FUNCTIONS                         */
    /* ---------------------------------------------------------------------- */

    function scanDAICOs(uint256 daoStart, uint256 daoCount, address[] calldata tribTokens)
        public
        view
        returns (DAICOView[] memory daicos)
    {
        uint256 total = SUMMONER.getDAOCount();
        if (daoStart >= total) {
            return new DAICOView[](0);
        }

        uint256 daoEnd = daoStart + daoCount;
        if (daoEnd > total) daoEnd = total;
        uint256 len = daoEnd - daoStart;

        // First pass: count DAOs with sales
        uint256 matchCount;
        for (uint256 i; i < len; ++i) {
            address dao = SUMMONER.daos(daoStart + i);
            if (_hasAnySale(dao, tribTokens)) {
                ++matchCount;
            }
        }

        daicos = new DAICOView[](matchCount);
        uint256 k;

        // Second pass: build views for DAOs with sales
        for (uint256 i; i < len; ++i) {
            address dao = SUMMONER.daos(daoStart + i);

            SaleView[] memory sales = _getSales(dao, tribTokens);
            if (sales.length == 0) continue;

            TapView memory tap = _getTap(dao);
            DAOMeta memory meta = _getMeta(dao);

            daicos[k] = DAICOView({dao: dao, meta: meta, sales: sales, tap: tap});
            ++k;
        }
    }

    function getDAICO(address dao, address[] calldata tribTokens)
        public
        view
        returns (DAICOView memory)
    {
        return DAICOView({
            dao: dao, meta: _getMeta(dao), sales: _getSales(dao, tribTokens), tap: _getTap(dao)
        });
    }

    function getDAOWithDAICO(
        address dao,
        uint256 proposalStart,
        uint256 proposalCount,
        uint256 messageStart,
        uint256 messageCount,
        address[] calldata treasuryTokens,
        address[] calldata tribTokens
    ) public view returns (DAICOLens memory out) {
        out.dao = _buildDAOFullState(
            dao, proposalStart, proposalCount, messageStart, messageCount, treasuryTokens
        );
        out.sales = _getSales(dao, tribTokens);
        out.tap = _getTap(dao);
    }

    function getDAOsWithDAICO(
        uint256 daoStart,
        uint256 daoCount,
        uint256 proposalStart,
        uint256 proposalCount,
        uint256 messageStart,
        uint256 messageCount,
        address[] calldata treasuryTokens,
        address[] calldata tribTokens
    ) public view returns (DAICOLens[] memory out) {
        uint256 total = SUMMONER.getDAOCount();
        if (daoStart >= total) {
            return new DAICOLens[](0);
        }

        uint256 daoEnd = daoStart + daoCount;
        if (daoEnd > total) daoEnd = total;
        uint256 len = daoEnd - daoStart;

        out = new DAICOLens[](len);

        for (uint256 i; i < len; ++i) {
            address dao = SUMMONER.daos(daoStart + i);
            out[i].dao = _buildDAOFullState(
                dao, proposalStart, proposalCount, messageStart, messageCount, treasuryTokens
            );
            out[i].sales = _getSales(dao, tribTokens);
            out[i].tap = _getTap(dao);
        }
    }

    /* ---------------------------------------------------------------------- */
    /*                        DAICO INTERNAL HELPERS                          */
    /* ---------------------------------------------------------------------- */

    function _hasAnySale(address dao, address[] calldata tribTokens) internal view returns (bool) {
        uint256 len = tribTokens.length;
        for (uint256 i; i < len; ++i) {
            (uint256 tribAmt, uint256 forAmt, address forTkn,) = _safeSale(dao, tribTokens[i]);
            if (tribAmt != 0 && forAmt != 0 && forTkn != address(0)) {
                return true;
            }
        }
        return false;
    }

    function _getSales(address dao, address[] calldata tribTokens)
        internal
        view
        returns (SaleView[] memory)
    {
        uint256 len = tribTokens.length;

        // First pass: count active sales
        uint256 saleCount;
        for (uint256 i; i < len; ++i) {
            (uint256 tribAmt, uint256 forAmt, address forTkn,) = _safeSale(dao, tribTokens[i]);
            if (tribAmt != 0 && forAmt != 0 && forTkn != address(0)) {
                ++saleCount;
            }
        }

        SaleView[] memory sales = new SaleView[](saleCount);
        uint256 k;

        // Second pass: populate sales
        for (uint256 i; i < len; ++i) {
            address tribTkn = tribTokens[i];
            (uint256 tribAmt, uint256 forAmt, address forTkn, uint40 deadline) =
                _safeSale(dao, tribTkn);

            if (tribAmt == 0 || forAmt == 0 || forTkn == address(0)) continue;

            // Get LP config
            (uint16 lpBps, uint16 maxSlipBps, uint256 feeOrHook) = _safeLPConfig(dao, tribTkn);

            // Get remaining supply (forTkn balance in DAO)
            uint256 remainingSupply = _safeBalanceOf(forTkn, dao);

            // Get total supply of forTkn
            uint256 totalSupply = _safeTotalSupply(forTkn);

            // Get treasury balance (tribTkn in DAO = funds raised)
            uint256 treasuryBalance;
            if (tribTkn == address(0)) {
                treasuryBalance = dao.balance;
            } else {
                treasuryBalance = _safeBalanceOf(tribTkn, dao);
            }

            // Get allowance (forTkn approved to DAICO for sale)
            uint256 saleAllowance = _safeAllowance(forTkn, dao, address(DAICO));

            sales[k] = SaleView({
                tribTkn: tribTkn,
                tribAmt: tribAmt,
                forAmt: forAmt,
                forTkn: forTkn,
                deadline: deadline,
                remainingSupply: remainingSupply,
                totalSupply: totalSupply,
                treasuryBalance: treasuryBalance,
                allowance: saleAllowance,
                lpBps: lpBps,
                maxSlipBps: maxSlipBps,
                feeOrHook: feeOrHook
            });
            ++k;
        }

        return sales;
    }

    function _getTap(address dao) internal view returns (TapView memory tap) {
        (address ops, address tribTkn, uint128 ratePerSec, uint64 lastClaim) = _safeTap(dao);

        // Only populate if tap is configured
        if (ops != address(0) && ratePerSec != 0) {
            uint256 claimable;
            uint256 pending;

            // Use staticcall for claimable/pending as they can revert
            (bool successClaimable, bytes memory dataClaimable) =
                address(DAICO).staticcall(abi.encodeWithSelector(IDAICO.claimableTap.selector, dao));
            if (successClaimable && dataClaimable.length >= 32) {
                claimable = abi.decode(dataClaimable, (uint256));
            }

            (bool successPending, bytes memory dataPending) =
                address(DAICO).staticcall(abi.encodeWithSelector(IDAICO.pendingTap.selector, dao));
            if (successPending && dataPending.length >= 32) {
                pending = abi.decode(dataPending, (uint256));
            }

            // Get treasury balance for tap token
            uint256 treasuryBalance;
            if (tribTkn == address(0)) {
                treasuryBalance = dao.balance;
            } else {
                treasuryBalance = _safeBalanceOf(tribTkn, dao);
            }

            // Get Moloch treasury allowance to DAICO for tribTkn (tap budget)
            uint256 tapAllowance = _safeMolochAllowance(dao, tribTkn, address(DAICO));

            tap = TapView({
                ops: ops,
                tribTkn: tribTkn,
                ratePerSec: ratePerSec,
                lastClaim: lastClaim,
                claimable: claimable,
                pending: pending,
                treasuryBalance: treasuryBalance,
                tapAllowance: tapAllowance
            });
        }
    }

    function _getMeta(address dao) internal view returns (DAOMeta memory meta) {
        IMoloch M = IMoloch(dao);
        meta.name = M.name(0);
        meta.symbol = M.symbol(0);
        meta.contractURI = M.contractURI();
        meta.sharesToken = M.shares();
        meta.lootToken = M.loot();
        meta.badgesToken = M.badges();
        meta.renderer = M.renderer();
    }

    function _safeBalanceOf(address token, address account) internal view returns (uint256) {
        (bool success, bytes memory data) =
            token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, account));
        if (success && data.length >= 32) {
            return abi.decode(data, (uint256));
        }
        return 0;
    }

    function _safeTotalSupply(address token) internal view returns (uint256) {
        (bool success, bytes memory data) =
            token.staticcall(abi.encodeWithSelector(IERC20.totalSupply.selector));
        if (success && data.length >= 32) {
            return abi.decode(data, (uint256));
        }
        return 0;
    }

    function _safeAllowance(address token, address owner, address spender)
        internal
        view
        returns (uint256)
    {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(bytes4(keccak256("allowance(address,address)")), owner, spender)
        );
        if (success && data.length >= 32) {
            return abi.decode(data, (uint256));
        }
        return 0;
    }

    function _safeMolochAllowance(address dao, address token, address spender)
        internal
        view
        returns (uint256)
    {
        (bool success, bytes memory data) =
            dao.staticcall(abi.encodeWithSelector(IMoloch.allowance.selector, token, spender));
        if (success && data.length >= 32) {
            return abi.decode(data, (uint256));
        }
        return 0;
    }

    function _safeSale(address dao, address tribTkn)
        internal
        view
        returns (uint256 tribAmt, uint256 forAmt, address forTkn, uint40 deadline)
    {
        (bool success, bytes memory data) =
            address(DAICO).staticcall(abi.encodeWithSelector(IDAICO.sales.selector, dao, tribTkn));
        if (success && data.length >= 128) {
            (tribAmt, forAmt, forTkn, deadline) =
                abi.decode(data, (uint256, uint256, address, uint40));
        }
    }

    function _safeTap(address dao)
        internal
        view
        returns (address ops, address tribTkn, uint128 ratePerSec, uint64 lastClaim)
    {
        (bool success, bytes memory data) =
            address(DAICO).staticcall(abi.encodeWithSelector(IDAICO.taps.selector, dao));
        if (success && data.length >= 128) {
            (ops, tribTkn, ratePerSec, lastClaim) =
                abi.decode(data, (address, address, uint128, uint64));
        }
    }

    function _safeLPConfig(address dao, address tribTkn)
        internal
        view
        returns (uint16 lpBps, uint16 maxSlipBps, uint256 feeOrHook)
    {
        (bool success, bytes memory data) = address(DAICO)
            .staticcall(abi.encodeWithSelector(IDAICO.lpConfigs.selector, dao, tribTkn));
        if (success && data.length >= 96) {
            (lpBps, maxSlipBps, feeOrHook) = abi.decode(data, (uint16, uint16, uint256));
        }
    }
}

contract MolochViewHelperTest is Test {
    Summoner internal summoner;
    Moloch internal moloch;
    Moloch internal moloch2;
    Shares internal shares;
    Loot internal loot;
    Badges internal badges;
    TestViewHelper internal viewHelper;
    MockDAICO internal mockDaico;

    address internal renderer;

    address internal alice = address(0xA11CE);
    address internal bob = address(0x0B0B);
    address internal charlie = address(0xCAFE);
    address internal dave = address(0xDAD);

    MockERC20 internal usdc;
    MockERC20 internal dai;
    MockERC20 internal saleToken; // Token being sold in DAICO sales
    Target internal target;

    function setUp() public {
        vm.label(alice, "ALICE");
        vm.label(bob, "BOB");
        vm.label(charlie, "CHARLIE");
        vm.label(dave, "DAVE");

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
        vm.deal(dave, 100 ether);

        // Deploy Summoner normally
        summoner = new Summoner();

        renderer = address(new Renderer());

        // Create the first DAO
        address[] memory initialHolders = new address[](0);
        uint256[] memory initialAmounts = new uint256[](0);

        moloch = summoner.summon(
            "Test DAO",
            "TEST",
            "ipfs://QmTest123",
            5000, // 50% quorum
            true, // ragequit enabled
            renderer,
            bytes32(0),
            initialHolders,
            initialAmounts,
            new Call[](0)
        );

        shares = moloch.shares();
        loot = moloch.loot();
        badges = moloch.badges();

        // Mint shares to test users
        vm.startPrank(address(moloch));
        shares.mintFromMoloch(alice, 60e18);
        shares.mintFromMoloch(bob, 40e18);
        loot.mintFromMoloch(charlie, 20e18);
        vm.stopPrank();

        // Create a second DAO
        moloch2 = summoner.summon(
            "Second DAO",
            "DAO2",
            "ipfs://QmSecond",
            3000, // 30% quorum
            false, // ragequit disabled
            renderer,
            bytes32(uint256(1)),
            initialHolders,
            initialAmounts,
            new Call[](0)
        );

        // Mint shares in second DAO
        vm.startPrank(address(moloch2));
        Shares(address(moloch2.shares())).mintFromMoloch(alice, 100e18);
        Shares(address(moloch2.shares())).mintFromMoloch(dave, 50e18);
        vm.stopPrank();

        // Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        dai = new MockERC20("Dai Stablecoin", "DAI", 18);
        saleToken = new MockERC20("Sale Token", "SALE", 18);

        // Fund the DAO treasury
        vm.deal(address(moloch), 10 ether);
        usdc.mint(address(moloch), 1000e6);
        dai.mint(address(moloch), 500e18);

        // Deploy mock DAICO
        mockDaico = new MockDAICO();

        // Deploy the test view helper with our summoner and mock DAICO
        viewHelper = new TestViewHelper(address(summoner), address(mockDaico));

        target = new Target();
        vm.roll(block.number + 1);
    }

    /*//////////////////////////////////////////////////////////////
                             DAO PAGINATION
    //////////////////////////////////////////////////////////////*/

    function test_GetDaos() public view {
        address[] memory daos = viewHelper.getDaos(0, 10);
        assertEq(daos.length, 2);
        assertEq(daos[0], address(moloch));
        assertEq(daos[1], address(moloch2));
    }

    function test_GetDaos_Pagination() public view {
        address[] memory daos = viewHelper.getDaos(0, 1);
        assertEq(daos.length, 1);
        assertEq(daos[0], address(moloch));

        daos = viewHelper.getDaos(1, 1);
        assertEq(daos.length, 1);
        assertEq(daos[0], address(moloch2));
    }

    function test_GetDaos_StartBeyondTotal() public view {
        address[] memory daos = viewHelper.getDaos(100, 10);
        // Fixed in test helper - should return empty array
        assertEq(daos.length, 0);
    }

    /*//////////////////////////////////////////////////////////////
                          SINGLE DAO FULL STATE
    //////////////////////////////////////////////////////////////*/

    function test_GetDAOFullState_Meta() public view {
        address[] memory treasuryTokens = new address[](0);
        DAOLens memory lens =
            viewHelper.getDAOFullState(address(moloch), 0, 10, 0, 10, treasuryTokens);

        assertEq(lens.dao, address(moloch));
        assertEq(lens.meta.name, "Test DAO");
        assertEq(lens.meta.symbol, "TEST");
        assertEq(lens.meta.contractURI, "ipfs://QmTest123");
        assertEq(lens.meta.sharesToken, address(shares));
        assertEq(lens.meta.lootToken, address(loot));
        assertEq(lens.meta.badgesToken, address(badges));
        assertEq(lens.meta.renderer, renderer);
    }

    function test_GetDAOFullState_GovConfig() public view {
        address[] memory treasuryTokens = new address[](0);
        DAOLens memory lens =
            viewHelper.getDAOFullState(address(moloch), 0, 10, 0, 10, treasuryTokens);

        assertEq(lens.gov.quorumBps, 5000);
        assertTrue(lens.gov.ragequittable);
        assertEq(lens.gov.proposalThreshold, 0);
        assertEq(lens.gov.timelockDelay, 0);
    }

    function test_GetDAOFullState_Supplies() public view {
        address[] memory treasuryTokens = new address[](0);
        DAOLens memory lens =
            viewHelper.getDAOFullState(address(moloch), 0, 10, 0, 10, treasuryTokens);

        assertEq(lens.supplies.sharesTotalSupply, 100e18);
        assertEq(lens.supplies.lootTotalSupply, 20e18);
        assertEq(lens.supplies.sharesHeldByDAO, 0);
        assertEq(lens.supplies.lootHeldByDAO, 0);
    }

    function test_GetDAOFullState_Members() public view {
        address[] memory treasuryTokens = new address[](0);
        DAOLens memory lens =
            viewHelper.getDAOFullState(address(moloch), 0, 10, 0, 10, treasuryTokens);

        // Should have members from badge seats
        assertTrue(lens.members.length >= 2);
    }

    /*//////////////////////////////////////////////////////////////
                           TREASURY BALANCE VIEW
    //////////////////////////////////////////////////////////////*/

    function test_GetDAOFullState_Treasury_ETH() public view {
        address[] memory treasuryTokens = new address[](1);
        treasuryTokens[0] = address(0); // Native ETH

        DAOLens memory lens =
            viewHelper.getDAOFullState(address(moloch), 0, 10, 0, 10, treasuryTokens);

        assertEq(lens.treasury.balances.length, 1);
        assertEq(lens.treasury.balances[0].token, address(0));
        assertEq(lens.treasury.balances[0].balance, 10 ether);
    }

    function test_GetDAOFullState_Treasury_ERC20() public view {
        address[] memory treasuryTokens = new address[](2);
        treasuryTokens[0] = address(usdc);
        treasuryTokens[1] = address(dai);

        DAOLens memory lens =
            viewHelper.getDAOFullState(address(moloch), 0, 10, 0, 10, treasuryTokens);

        assertEq(lens.treasury.balances.length, 2);
        assertEq(lens.treasury.balances[0].token, address(usdc));
        assertEq(lens.treasury.balances[0].balance, 1000e6);
        assertEq(lens.treasury.balances[1].token, address(dai));
        assertEq(lens.treasury.balances[1].balance, 500e18);
    }

    function test_GetDAOFullState_Treasury_MixedTokens() public view {
        address[] memory treasuryTokens = new address[](3);
        treasuryTokens[0] = address(0); // Native ETH
        treasuryTokens[1] = address(usdc);
        treasuryTokens[2] = address(dai);

        DAOLens memory lens =
            viewHelper.getDAOFullState(address(moloch), 0, 10, 0, 10, treasuryTokens);

        assertEq(lens.treasury.balances.length, 3);
        assertEq(lens.treasury.balances[0].token, address(0));
        assertEq(lens.treasury.balances[0].balance, 10 ether);
        assertEq(lens.treasury.balances[1].token, address(usdc));
        assertEq(lens.treasury.balances[1].balance, 1000e6);
        assertEq(lens.treasury.balances[2].token, address(dai));
        assertEq(lens.treasury.balances[2].balance, 500e18);
    }

    function test_GetDAOFullState_Treasury_NonExistentToken() public view {
        address[] memory treasuryTokens = new address[](1);
        treasuryTokens[0] = address(0xDEAD); // Non-existent token

        DAOLens memory lens =
            viewHelper.getDAOFullState(address(moloch), 0, 10, 0, 10, treasuryTokens);

        // Should gracefully return 0 balance for non-existent token
        assertEq(lens.treasury.balances.length, 1);
        assertEq(lens.treasury.balances[0].token, address(0xDEAD));
        assertEq(lens.treasury.balances[0].balance, 0);
    }

    function test_GetDAOFullState_Treasury_EmptyArray() public view {
        address[] memory treasuryTokens = new address[](0);

        DAOLens memory lens =
            viewHelper.getDAOFullState(address(moloch), 0, 10, 0, 10, treasuryTokens);

        assertEq(lens.treasury.balances.length, 0);
    }

    /*//////////////////////////////////////////////////////////////
                          MULTI-DAO FULL STATE
    //////////////////////////////////////////////////////////////*/

    function test_GetDAOsFullState() public view {
        address[] memory treasuryTokens = new address[](1);
        treasuryTokens[0] = address(0);

        DAOLens[] memory lenses = viewHelper.getDAOsFullState(0, 10, 0, 10, 0, 10, treasuryTokens);

        assertEq(lenses.length, 2);
        assertEq(lenses[0].dao, address(moloch));
        assertEq(lenses[0].meta.name, "Test DAO");
        assertEq(lenses[1].dao, address(moloch2));
        assertEq(lenses[1].meta.name, "Second DAO");
    }

    function test_GetDAOsFullState_Pagination() public view {
        address[] memory treasuryTokens = new address[](0);

        DAOLens[] memory lenses = viewHelper.getDAOsFullState(0, 1, 0, 10, 0, 10, treasuryTokens);

        assertEq(lenses.length, 1);
        assertEq(lenses[0].meta.name, "Test DAO");

        lenses = viewHelper.getDAOsFullState(1, 1, 0, 10, 0, 10, treasuryTokens);

        assertEq(lenses.length, 1);
        assertEq(lenses[0].meta.name, "Second DAO");
    }

    /*//////////////////////////////////////////////////////////////
                          USER DAO PORTFOLIO
    //////////////////////////////////////////////////////////////*/

    function test_GetUserDAOs() public view {
        address[] memory treasuryTokens = new address[](1);
        treasuryTokens[0] = address(0);

        UserMemberView[] memory userDaos = viewHelper.getUserDAOs(alice, 0, 10, treasuryTokens);

        // Alice has shares in both DAOs
        assertEq(userDaos.length, 2);
        assertEq(userDaos[0].dao, address(moloch));
        assertEq(userDaos[0].member.shares, 60e18);
        assertEq(userDaos[1].dao, address(moloch2));
        assertEq(userDaos[1].member.shares, 100e18);
    }

    function test_GetUserDAOs_OnlyLoot() public view {
        address[] memory treasuryTokens = new address[](0);

        UserMemberView[] memory userDaos = viewHelper.getUserDAOs(charlie, 0, 10, treasuryTokens);

        // Charlie only has loot in first DAO
        assertEq(userDaos.length, 1);
        assertEq(userDaos[0].dao, address(moloch));
        assertEq(userDaos[0].member.shares, 0);
        assertEq(userDaos[0].member.loot, 20e18);
    }

    function test_GetUserDAOs_NoMembership() public view {
        address[] memory treasuryTokens = new address[](0);
        address nonMember = address(0x1234);

        UserMemberView[] memory userDaos = viewHelper.getUserDAOs(nonMember, 0, 10, treasuryTokens);

        assertEq(userDaos.length, 0);
    }

    function test_GetUserDAOs_WithTreasury() public view {
        address[] memory treasuryTokens = new address[](2);
        treasuryTokens[0] = address(0);
        treasuryTokens[1] = address(usdc);

        UserMemberView[] memory userDaos = viewHelper.getUserDAOs(alice, 0, 10, treasuryTokens);

        assertEq(userDaos.length, 2);
        // First DAO has treasury
        assertEq(userDaos[0].treasury.balances.length, 2);
        assertEq(userDaos[0].treasury.balances[0].balance, 10 ether);
        assertEq(userDaos[0].treasury.balances[1].balance, 1000e6);
    }

    /*//////////////////////////////////////////////////////////////
                        USER DAO FULL STATE
    //////////////////////////////////////////////////////////////*/

    function test_GetUserDAOsFullState() public view {
        address[] memory treasuryTokens = new address[](1);
        treasuryTokens[0] = address(0);

        UserDAOLens[] memory userDaos =
            viewHelper.getUserDAOsFullState(alice, 0, 10, 0, 10, 0, 10, treasuryTokens);

        assertEq(userDaos.length, 2);
        assertEq(userDaos[0].dao.dao, address(moloch));
        assertEq(userDaos[0].member.shares, 60e18);
        assertEq(userDaos[1].dao.dao, address(moloch2));
        assertEq(userDaos[1].member.shares, 100e18);
    }

    /*//////////////////////////////////////////////////////////////
                             PROPOSALS
    //////////////////////////////////////////////////////////////*/

    function test_GetDAOFullState_WithProposals() public {
        // Create a proposal
        bytes memory data = abi.encodeWithSelector(Target.setValue.selector, 123);
        uint256 id = moloch.proposalId(0, address(target), 0, data, bytes32(0));

        vm.prank(alice);
        moloch.openProposal(id);

        // Cast a vote
        vm.prank(alice);
        moloch.castVote(id, 1); // Vote FOR

        vm.prank(bob);
        moloch.castVote(id, 0); // Vote AGAINST

        address[] memory treasuryTokens = new address[](0);
        DAOLens memory lens =
            viewHelper.getDAOFullState(address(moloch), 0, 10, 0, 10, treasuryTokens);

        assertEq(lens.proposals.length, 1);
        assertEq(lens.proposals[0].id, id);
        assertEq(lens.proposals[0].proposer, alice);
        assertEq(lens.proposals[0].forVotes, 60e18);
        assertEq(lens.proposals[0].againstVotes, 40e18);
        assertEq(lens.proposals[0].abstainVotes, 0);

        // Check voters
        assertTrue(lens.proposals[0].voters.length >= 2);
    }

    function test_GetDAOFullState_ProposalPagination() public {
        // Create multiple proposals
        for (uint256 i = 0; i < 5; i++) {
            bytes memory data = abi.encodeWithSelector(Target.setValue.selector, i);
            uint256 id = moloch.proposalId(0, address(target), 0, data, bytes32(i));
            vm.prank(alice);
            moloch.openProposal(id);
        }

        address[] memory treasuryTokens = new address[](0);

        // Get first 2 proposals
        DAOLens memory lens =
            viewHelper.getDAOFullState(address(moloch), 0, 2, 0, 10, treasuryTokens);
        assertEq(lens.proposals.length, 2);

        // Get next 2 proposals
        lens = viewHelper.getDAOFullState(address(moloch), 2, 2, 0, 10, treasuryTokens);
        assertEq(lens.proposals.length, 2);

        // Get last proposal
        lens = viewHelper.getDAOFullState(address(moloch), 4, 2, 0, 10, treasuryTokens);
        assertEq(lens.proposals.length, 1);
    }

    /*//////////////////////////////////////////////////////////////
                              MESSAGES
    //////////////////////////////////////////////////////////////*/

    function test_GetDAOMessages() public {
        // Post some messages (need to be a badge holder)
        vm.prank(alice);
        moloch.chat("Hello world!");

        vm.prank(bob);
        moloch.chat("Second message");

        MessageView[] memory messages = viewHelper.getDAOMessages(address(moloch), 0, 10);

        assertEq(messages.length, 2);
        assertEq(messages[0].index, 0);
        assertEq(messages[0].text, "Hello world!");
        assertEq(messages[1].index, 1);
        assertEq(messages[1].text, "Second message");
    }

    function test_GetDAOMessages_Pagination() public {
        // Post multiple messages
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(alice);
            moloch.chat(string(abi.encodePacked("Message ", bytes1(uint8(48 + i)))));
        }

        MessageView[] memory messages = viewHelper.getDAOMessages(address(moloch), 0, 2);
        assertEq(messages.length, 2);
        assertEq(messages[0].index, 0);
        assertEq(messages[1].index, 1);

        messages = viewHelper.getDAOMessages(address(moloch), 2, 2);
        assertEq(messages.length, 2);
        assertEq(messages[0].index, 2);
        assertEq(messages[1].index, 3);
    }

    function test_GetDAOFullState_WithMessages() public {
        vm.prank(alice);
        moloch.chat("Test message");

        address[] memory treasuryTokens = new address[](0);
        DAOLens memory lens =
            viewHelper.getDAOFullState(address(moloch), 0, 10, 0, 10, treasuryTokens);

        assertEq(lens.messages.length, 1);
        assertEq(lens.messages[0].text, "Test message");
    }

    /*//////////////////////////////////////////////////////////////
                         DELEGATION & VOTING POWER
    //////////////////////////////////////////////////////////////*/

    function test_GetDAOFullState_VotingPower() public {
        // Alice delegates to Bob
        vm.prank(alice);
        shares.delegate(bob);

        address[] memory treasuryTokens = new address[](0);
        DAOLens memory lens =
            viewHelper.getDAOFullState(address(moloch), 0, 10, 0, 10, treasuryTokens);

        // Find Alice and Bob in members
        for (uint256 i = 0; i < lens.members.length; i++) {
            if (lens.members[i].account == alice) {
                assertEq(lens.members[i].shares, 60e18);
                assertEq(lens.members[i].votingPower, 0); // Delegated away
            }
            if (lens.members[i].account == bob) {
                assertEq(lens.members[i].shares, 40e18);
                assertEq(lens.members[i].votingPower, 100e18); // Has Alice's delegation
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                         MULTICHAIN TREASURY TEST
    //////////////////////////////////////////////////////////////*/

    function test_Treasury_DifferentTokensPerChain() public {
        // Simulate different chains having different tokens
        MockERC20 arbitrumUsdc = new MockERC20("USDC", "USDC", 6);
        MockERC20 arbitrumArb = new MockERC20("Arbitrum", "ARB", 18);

        arbitrumUsdc.mint(address(moloch), 2000e6);
        arbitrumArb.mint(address(moloch), 1000e18);

        // Query with Arbitrum tokens
        address[] memory arbitrumTokens = new address[](3);
        arbitrumTokens[0] = address(0); // ETH
        arbitrumTokens[1] = address(arbitrumUsdc);
        arbitrumTokens[2] = address(arbitrumArb);

        DAOLens memory lens =
            viewHelper.getDAOFullState(address(moloch), 0, 10, 0, 10, arbitrumTokens);

        assertEq(lens.treasury.balances.length, 3);
        assertEq(lens.treasury.balances[0].balance, 10 ether);
        assertEq(lens.treasury.balances[1].balance, 2000e6);
        assertEq(lens.treasury.balances[2].balance, 1000e18);
    }

    function test_Treasury_ZeroBalanceTokens() public {
        MockERC20 emptyToken = new MockERC20("Empty", "EMPTY", 18);

        address[] memory treasuryTokens = new address[](1);
        treasuryTokens[0] = address(emptyToken);

        DAOLens memory lens =
            viewHelper.getDAOFullState(address(moloch), 0, 10, 0, 10, treasuryTokens);

        assertEq(lens.treasury.balances.length, 1);
        assertEq(lens.treasury.balances[0].balance, 0);
    }

    /*//////////////////////////////////////////////////////////////
                           EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_GetDAOFullState_EmptyDAO() public {
        // Create an empty DAO with no members
        address[] memory holders = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        Moloch emptyMoloch = summoner.summon(
            "Empty DAO",
            "EMPTY",
            "",
            0,
            false,
            renderer,
            bytes32(uint256(999)),
            holders,
            amounts,
            new Call[](0)
        );

        address[] memory treasuryTokens = new address[](0);
        DAOLens memory lens =
            viewHelper.getDAOFullState(address(emptyMoloch), 0, 10, 0, 10, treasuryTokens);

        assertEq(lens.dao, address(emptyMoloch));
        assertEq(lens.meta.name, "Empty DAO");
        assertEq(lens.supplies.sharesTotalSupply, 0);
    }

    function test_GetDAOsFullState_StartBeyondTotal() public view {
        address[] memory treasuryTokens = new address[](0);

        DAOLens[] memory lenses = viewHelper.getDAOsFullState(100, 10, 0, 10, 0, 10, treasuryTokens);

        // Fixed in test helper - returns empty array
        assertEq(lenses.length, 0);
    }

    /*//////////////////////////////////////////////////////////////
                             DAICO SCAN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ScanDAICOs_NoSales() public view {
        // No sales configured, should return empty array
        address[] memory tribTokens = new address[](2);
        tribTokens[0] = address(0); // ETH
        tribTokens[1] = address(usdc);

        DAICOView[] memory daicos = viewHelper.scanDAICOs(0, 10, tribTokens);
        assertEq(daicos.length, 0);
    }

    function test_ScanDAICOs_WithSale() public {
        // Set up a sale for moloch: selling saleToken for ETH
        saleToken.mint(address(moloch), 1000e18); // DAO has tokens to sell

        mockDaico.setSale(
            address(moloch),
            address(0), // ETH as tribute
            1 ether, // tribAmt: 1 ETH
            100e18, // forAmt: 100 tokens
            address(saleToken), // token being sold
            uint40(block.timestamp + 30 days) // deadline
        );

        mockDaico.setLPConfig(
            address(moloch),
            address(0),
            500, // 5% LP
            100, // 1% max slip
            0 // no hook
        );

        address[] memory tribTokens = new address[](2);
        tribTokens[0] = address(0); // ETH
        tribTokens[1] = address(usdc);

        DAICOView[] memory daicos = viewHelper.scanDAICOs(0, 10, tribTokens);

        assertEq(daicos.length, 1);
        assertEq(daicos[0].dao, address(moloch));
        assertEq(daicos[0].meta.name, "Test DAO");
        assertEq(daicos[0].sales.length, 1);
        assertEq(daicos[0].sales[0].tribTkn, address(0));
        assertEq(daicos[0].sales[0].tribAmt, 1 ether);
        assertEq(daicos[0].sales[0].forAmt, 100e18);
        assertEq(daicos[0].sales[0].forTkn, address(saleToken));
        assertEq(daicos[0].sales[0].remainingSupply, 1000e18);
        assertEq(daicos[0].sales[0].totalSupply, 1000e18);
        assertEq(daicos[0].sales[0].treasuryBalance, 10 ether); // DAO's ETH balance
        assertEq(daicos[0].sales[0].lpBps, 500);
        assertEq(daicos[0].sales[0].maxSlipBps, 100);
    }

    function test_ScanDAICOs_MultipleTribTokens() public {
        // Set up sales for both ETH and USDC
        saleToken.mint(address(moloch), 1000e18);

        // ETH sale
        mockDaico.setSale(
            address(moloch),
            address(0),
            1 ether,
            100e18,
            address(saleToken),
            uint40(block.timestamp + 30 days)
        );

        // USDC sale (different terms)
        mockDaico.setSale(
            address(moloch),
            address(usdc),
            100e6, // 100 USDC
            50e18, // 50 tokens
            address(saleToken),
            uint40(block.timestamp + 60 days)
        );

        address[] memory tribTokens = new address[](2);
        tribTokens[0] = address(0);
        tribTokens[1] = address(usdc);

        DAICOView[] memory daicos = viewHelper.scanDAICOs(0, 10, tribTokens);

        assertEq(daicos.length, 1);
        assertEq(daicos[0].sales.length, 2);

        // Verify both sales
        assertEq(daicos[0].sales[0].tribTkn, address(0));
        assertEq(daicos[0].sales[0].tribAmt, 1 ether);
        assertEq(daicos[0].sales[1].tribTkn, address(usdc));
        assertEq(daicos[0].sales[1].tribAmt, 100e6);
        assertEq(daicos[0].sales[1].treasuryBalance, 1000e6); // DAO's USDC balance
    }

    function test_ScanDAICOs_MultipleDAOs() public {
        saleToken.mint(address(moloch), 500e18);
        saleToken.mint(address(moloch2), 500e18);

        // Sale for first DAO
        mockDaico.setSale(
            address(moloch),
            address(0),
            1 ether,
            100e18,
            address(saleToken),
            uint40(block.timestamp + 30 days)
        );

        // Sale for second DAO
        mockDaico.setSale(
            address(moloch2),
            address(0),
            2 ether,
            200e18,
            address(saleToken),
            uint40(block.timestamp + 30 days)
        );

        address[] memory tribTokens = new address[](1);
        tribTokens[0] = address(0);

        DAICOView[] memory daicos = viewHelper.scanDAICOs(0, 10, tribTokens);

        assertEq(daicos.length, 2);
        assertEq(daicos[0].dao, address(moloch));
        assertEq(daicos[0].meta.name, "Test DAO");
        assertEq(daicos[1].dao, address(moloch2));
        assertEq(daicos[1].meta.name, "Second DAO");
    }

    function test_ScanDAICOs_Pagination() public {
        saleToken.mint(address(moloch), 500e18);
        saleToken.mint(address(moloch2), 500e18);

        // Sales for both DAOs
        mockDaico.setSale(
            address(moloch),
            address(0),
            1 ether,
            100e18,
            address(saleToken),
            uint40(block.timestamp + 30 days)
        );
        mockDaico.setSale(
            address(moloch2),
            address(0),
            2 ether,
            200e18,
            address(saleToken),
            uint40(block.timestamp + 30 days)
        );

        address[] memory tribTokens = new address[](1);
        tribTokens[0] = address(0);

        // Get first DAO only
        DAICOView[] memory daicos = viewHelper.scanDAICOs(0, 1, tribTokens);
        assertEq(daicos.length, 1);
        assertEq(daicos[0].dao, address(moloch));

        // Get second DAO only
        daicos = viewHelper.scanDAICOs(1, 1, tribTokens);
        assertEq(daicos.length, 1);
        assertEq(daicos[0].dao, address(moloch2));
    }

    function test_ScanDAICOs_StartBeyondTotal() public view {
        address[] memory tribTokens = new address[](1);
        tribTokens[0] = address(0);

        DAICOView[] memory daicos = viewHelper.scanDAICOs(100, 10, tribTokens);
        assertEq(daicos.length, 0);
    }

    function test_ScanDAICOs_EmptyTribTokens() public view {
        address[] memory tribTokens = new address[](0);

        DAICOView[] memory daicos = viewHelper.scanDAICOs(0, 10, tribTokens);
        assertEq(daicos.length, 0);
    }

    function test_GetDAICO_SingleDAO() public {
        saleToken.mint(address(moloch), 1000e18);

        mockDaico.setSale(
            address(moloch),
            address(0),
            1 ether,
            100e18,
            address(saleToken),
            uint40(block.timestamp + 30 days)
        );

        address[] memory tribTokens = new address[](1);
        tribTokens[0] = address(0);

        DAICOView memory daico = viewHelper.getDAICO(address(moloch), tribTokens);

        assertEq(daico.dao, address(moloch));
        assertEq(daico.meta.name, "Test DAO");
        assertEq(daico.meta.symbol, "TEST");
        assertEq(daico.sales.length, 1);
        assertEq(daico.sales[0].forTkn, address(saleToken));
    }

    function test_GetDAICO_NoSales() public view {
        address[] memory tribTokens = new address[](1);
        tribTokens[0] = address(0);

        DAICOView memory daico = viewHelper.getDAICO(address(moloch), tribTokens);

        assertEq(daico.dao, address(moloch));
        assertEq(daico.sales.length, 0);
    }

    function test_GetDAICO_WithTap() public {
        // Warp to a reasonable timestamp to avoid underflow
        vm.warp(1000000);

        saleToken.mint(address(moloch), 1000e18);

        mockDaico.setSale(
            address(moloch),
            address(0),
            1 ether,
            100e18,
            address(saleToken),
            uint40(block.timestamp + 30 days)
        );

        // Set up a tap
        mockDaico.setTap(
            address(moloch),
            alice, // ops (beneficiary)
            address(0), // ETH
            uint128(0.1 ether), // 0.1 ETH per second
            uint64(block.timestamp - 100) // last claim 100 seconds ago
        );

        address[] memory tribTokens = new address[](1);
        tribTokens[0] = address(0);

        DAICOView memory daico = viewHelper.getDAICO(address(moloch), tribTokens);

        assertEq(daico.tap.ops, alice);
        assertEq(daico.tap.tribTkn, address(0));
        assertEq(daico.tap.ratePerSec, 0.1 ether);
        assertTrue(daico.tap.claimable > 0); // Should have accumulated
        assertEq(daico.tap.treasuryBalance, 10 ether); // DAO's ETH balance from setUp
    }

    function test_GetDAICO_NoTap() public view {
        address[] memory tribTokens = new address[](1);
        tribTokens[0] = address(0);

        DAICOView memory daico = viewHelper.getDAICO(address(moloch), tribTokens);

        // Empty tap
        assertEq(daico.tap.ops, address(0));
        assertEq(daico.tap.ratePerSec, 0);
    }

    function test_GetDAOWithDAICO() public {
        saleToken.mint(address(moloch), 1000e18);

        mockDaico.setSale(
            address(moloch),
            address(0),
            1 ether,
            100e18,
            address(saleToken),
            uint40(block.timestamp + 30 days)
        );

        address[] memory treasuryTokens = new address[](1);
        treasuryTokens[0] = address(0);

        address[] memory tribTokens = new address[](1);
        tribTokens[0] = address(0);

        DAICOLens memory lens = viewHelper.getDAOWithDAICO(
            address(moloch),
            0,
            10, // proposals
            0,
            10, // messages
            treasuryTokens,
            tribTokens
        );

        // Verify DAO data
        assertEq(lens.dao.dao, address(moloch));
        assertEq(lens.dao.meta.name, "Test DAO");
        assertEq(lens.dao.supplies.sharesTotalSupply, 100e18);
        assertEq(lens.dao.treasury.balances.length, 1);
        assertEq(lens.dao.treasury.balances[0].balance, 10 ether);

        // Verify DAICO data
        assertEq(lens.sales.length, 1);
        assertEq(lens.sales[0].tribAmt, 1 ether);
    }

    function test_GetDAOsWithDAICO() public {
        saleToken.mint(address(moloch), 500e18);
        saleToken.mint(address(moloch2), 500e18);

        mockDaico.setSale(
            address(moloch),
            address(0),
            1 ether,
            100e18,
            address(saleToken),
            uint40(block.timestamp + 30 days)
        );
        mockDaico.setSale(
            address(moloch2),
            address(0),
            2 ether,
            200e18,
            address(saleToken),
            uint40(block.timestamp + 30 days)
        );

        address[] memory treasuryTokens = new address[](1);
        treasuryTokens[0] = address(0);

        address[] memory tribTokens = new address[](1);
        tribTokens[0] = address(0);

        DAICOLens[] memory lenses = viewHelper.getDAOsWithDAICO(
            0,
            10,
            0,
            5, // proposals
            0,
            5, // messages
            treasuryTokens,
            tribTokens
        );

        assertEq(lenses.length, 2);

        // First DAO
        assertEq(lenses[0].dao.dao, address(moloch));
        assertEq(lenses[0].sales.length, 1);
        assertEq(lenses[0].sales[0].tribAmt, 1 ether);

        // Second DAO
        assertEq(lenses[1].dao.dao, address(moloch2));
        assertEq(lenses[1].sales.length, 1);
        assertEq(lenses[1].sales[0].tribAmt, 2 ether);
    }

    function test_GetDAOsWithDAICO_StartBeyondTotal() public view {
        address[] memory treasuryTokens = new address[](0);
        address[] memory tribTokens = new address[](1);
        tribTokens[0] = address(0);

        DAICOLens[] memory lenses =
            viewHelper.getDAOsWithDAICO(100, 10, 0, 5, 0, 5, treasuryTokens, tribTokens);

        assertEq(lenses.length, 0);
    }

    function test_ScanDAICOs_PartialSaleTerms_Ignored() public {
        // Set up a sale with only partial terms (missing forTkn)
        // This tests that sales with tribAmt/forAmt but no forTkn are ignored
        mockDaico.setSale(
            address(moloch),
            address(0),
            1 ether,
            100e18,
            address(0), // No forTkn - should be ignored
            uint40(block.timestamp + 30 days)
        );

        address[] memory tribTokens = new address[](1);
        tribTokens[0] = address(0);

        DAICOView[] memory daicos = viewHelper.scanDAICOs(0, 10, tribTokens);
        assertEq(daicos.length, 0); // Should not match because forTkn is zero
    }

    function test_ScanDAICOs_ZeroAmounts_Ignored() public {
        // Set up a sale with zero amounts
        mockDaico.setSale(
            address(moloch),
            address(0),
            0, // Zero tribAmt
            0, // Zero forAmt
            address(saleToken),
            uint40(block.timestamp + 30 days)
        );

        address[] memory tribTokens = new address[](1);
        tribTokens[0] = address(0);

        DAICOView[] memory daicos = viewHelper.scanDAICOs(0, 10, tribTokens);
        assertEq(daicos.length, 0); // Should not match because amounts are zero
    }

    function test_GetDAICO_NoDeadline() public {
        saleToken.mint(address(moloch), 1000e18);

        // Sale with no deadline (perpetual)
        mockDaico.setSale(
            address(moloch),
            address(0),
            1 ether,
            100e18,
            address(saleToken),
            0 // No deadline
        );

        address[] memory tribTokens = new address[](1);
        tribTokens[0] = address(0);

        DAICOView memory daico = viewHelper.getDAICO(address(moloch), tribTokens);

        assertEq(daico.sales.length, 1);
        assertEq(daico.sales[0].deadline, 0);
    }

    function test_GetDAICO_TreasuryBalance_ERC20() public {
        saleToken.mint(address(moloch), 1000e18);

        // Sale with USDC as tribute
        mockDaico.setSale(
            address(moloch),
            address(usdc),
            100e6, // 100 USDC
            100e18,
            address(saleToken),
            uint40(block.timestamp + 30 days)
        );

        address[] memory tribTokens = new address[](1);
        tribTokens[0] = address(usdc);

        DAICOView memory daico = viewHelper.getDAICO(address(moloch), tribTokens);

        assertEq(daico.sales.length, 1);
        assertEq(daico.sales[0].tribTkn, address(usdc));
        assertEq(daico.sales[0].treasuryBalance, 1000e6); // DAO's USDC balance from setUp
    }

    function test_Tap_ZeroRate_NotReturned() public {
        // Set tap with zero rate (frozen)
        mockDaico.setTap(
            address(moloch),
            alice,
            address(0),
            0, // Zero rate
            uint64(block.timestamp)
        );

        address[] memory tribTokens = new address[](0);

        DAICOView memory daico = viewHelper.getDAICO(address(moloch), tribTokens);

        // Tap should be empty because rate is zero
        assertEq(daico.tap.ops, address(0));
        assertEq(daico.tap.ratePerSec, 0);
    }

    function test_DAICO_SafeCalls_NoRevert() public {
        // Test with a view helper pointing to a non-existent DAICO contract
        TestViewHelper brokenHelper = new TestViewHelper(address(summoner), address(0xDEAD));

        address[] memory tribTokens = new address[](2);
        tribTokens[0] = address(0);
        tribTokens[1] = address(usdc);

        // These should NOT revert, just return empty results
        DAICOView[] memory daicos = brokenHelper.scanDAICOs(0, 10, tribTokens);
        assertEq(daicos.length, 0);

        DAICOView memory daico = brokenHelper.getDAICO(address(moloch), tribTokens);
        assertEq(daico.sales.length, 0);
        assertEq(daico.tap.ops, address(0));

        address[] memory treasuryTokens = new address[](0);
        DAICOLens memory lens =
            brokenHelper.getDAOWithDAICO(address(moloch), 0, 5, 0, 5, treasuryTokens, tribTokens);
        assertEq(lens.sales.length, 0);
        assertEq(lens.tap.ops, address(0));
        // But DAO data should still work
        assertEq(lens.dao.meta.name, "Test DAO");
    }

    function test_GetDAICO_WithAllowance() public {
        // Set up a sale for moloch: selling saleToken for ETH
        saleToken.mint(address(moloch), 1000e18); // DAO has tokens

        // DAO approves DAICO to sell 500 tokens
        vm.prank(address(moloch));
        saleToken.approve(address(mockDaico), 500e18);

        mockDaico.setSale(
            address(moloch),
            address(0), // ETH as tribute
            1 ether,
            100e18,
            address(saleToken),
            uint40(block.timestamp + 30 days)
        );

        address[] memory tribTokens = new address[](1);
        tribTokens[0] = address(0); // ETH

        DAICOView memory daico = viewHelper.getDAICO(address(moloch), tribTokens);

        assertEq(daico.sales.length, 1);
        assertEq(daico.sales[0].remainingSupply, 1000e18); // DAO balance
        assertEq(daico.sales[0].allowance, 500e18); // Approved amount to DAICO
    }

    function test_GetDAICO_WithTapAllowance() public {
        // Warp to a reasonable timestamp to avoid underflow
        vm.warp(1000000);

        // Set up a tap with USDC as the tap token
        mockDaico.setTap(
            address(moloch),
            alice, // ops (beneficiary)
            address(usdc), // USDC as tap token
            uint128(100e6), // 100 USDC per second
            uint64(block.timestamp - 100) // last claim 100 seconds ago
        );

        // Give DAO some USDC treasury balance
        usdc.mint(address(moloch), 10000e6);

        // DAO sets Moloch treasury allowance for DAICO to pull USDC for tap
        vm.prank(address(moloch));
        moloch.setAllowance(address(mockDaico), address(usdc), 5000e6);

        address[] memory tribTokens = new address[](0);

        DAICOView memory daico = viewHelper.getDAICO(address(moloch), tribTokens);

        assertEq(daico.tap.ops, alice);
        assertEq(daico.tap.tribTkn, address(usdc));
        assertEq(daico.tap.treasuryBalance, 11000e6); // USDC balance in DAO (1000e6 from setUp + 10000e6)
        assertEq(daico.tap.tapAllowance, 5000e6); // Moloch treasury allowance to DAICO
    }
}
