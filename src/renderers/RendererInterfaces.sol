// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

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

interface ICovenantRenderer {
    function render(IMoloch dao) external view returns (string memory);
}

interface ICardRenderer {
    function render(IMoloch dao, uint256 id) external view returns (string memory);
}
