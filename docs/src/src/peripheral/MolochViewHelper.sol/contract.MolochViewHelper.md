# MolochViewHelper
[Git Source](https://github.com/z0r0z/SAW/blob/5b287591f19dce0ac310dc192604a613e25f6e34/src/peripheral/MolochViewHelper.sol)


## State Variables
### SUMMONER

```solidity
ISummoner public constant SUMMONER = ISummoner(0x0000000000330B8df9E3bc5E553074DA58eE9138)
```


### DAICO

```solidity
IDAICO public constant DAICO = IDAICO(0x000000000033e92DB97B4B3beCD2c255126C60aC)
```


## Functions
### getDaos

Get a slice of DAOs created by the Summoner.


```solidity
function getDaos(uint256 start, uint256 count) public view returns (address[] memory out);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`start`|`uint256`| Index into Summoner.daos[]|
|`count`|`uint256`| Max number of DAOs to return|


### getDAOFullState

Full state for a single DAO: meta, config, supplies, members,
proposals & votes, futarchy, treasury, messages.


```solidity
function getDAOFullState(
    address dao,
    uint256 proposalStart,
    uint256 proposalCount,
    uint256 messageStart,
    uint256 messageCount,
    address[] calldata treasuryTokens
) public view returns (DAOLens memory out);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`dao`|`address`|The DAO address|
|`proposalStart`|`uint256`|Starting index for proposals|
|`proposalCount`|`uint256`|Number of proposals to fetch|
|`messageStart`|`uint256`|Starting index for messages|
|`messageCount`|`uint256`|Number of messages to fetch|
|`treasuryTokens`|`address[]`|Array of token addresses to check balances for (address(0) = native ETH)|


### getDAOsFullState

One-shot fetch of multiple DAOs' state for the UI.
For each DAO in [daoStart, daoStart+daoCount), returns:
- meta (name, symbol, contractURI, token addresses)
- governance config
- token supplies + DAO-held shares/loot
- members (badge seats) + voting power + delegation splits
- proposals [proposalStart .. proposalStart+proposalCount)
- per-proposal tallies, state, per-member votes
- per-proposal futarchy config
- treasury balances for specified tokens
- messages [messageStart .. messageStart+messageCount)


```solidity
function getDAOsFullState(
    uint256 daoStart,
    uint256 daoCount,
    uint256 proposalStart,
    uint256 proposalCount,
    uint256 messageStart,
    uint256 messageCount,
    address[] calldata treasuryTokens
) public view returns (DAOLens[] memory out);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`daoStart`|`uint256`||
|`daoCount`|`uint256`||
|`proposalStart`|`uint256`||
|`proposalCount`|`uint256`||
|`messageStart`|`uint256`||
|`messageCount`|`uint256`||
|`treasuryTokens`|`address[]`|Array of token addresses to check balances for (address(0) = native ETH)|


### getUserDAOs

Find all DAOs (within a slice) where `user` has shares, loot, or a badge seat.

Lightweight summary: no proposals/messages; intended for wallet dashboards.


```solidity
function getUserDAOs(
    address user,
    uint256 daoStart,
    uint256 daoCount,
    address[] calldata treasuryTokens
) public view returns (UserMemberView[] memory out);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`||
|`daoStart`|`uint256`||
|`daoCount`|`uint256`||
|`treasuryTokens`|`address[]`|Array of token addresses to check balances for (address(0) = native ETH)|


### getUserDAOsFullState

Full DAO state (like getDAOsFullState) but filtered to DAOs where `user` is a member.

This is the heavy "one-shot" user-dashboard view: use small daoCount / proposalCount / messageCount.


```solidity
function getUserDAOsFullState(
    address user,
    uint256 daoStart,
    uint256 daoCount,
    uint256 proposalStart,
    uint256 proposalCount,
    uint256 messageStart,
    uint256 messageCount,
    address[] calldata treasuryTokens
) public view returns (UserDAOLens[] memory out);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`||
|`daoStart`|`uint256`||
|`daoCount`|`uint256`||
|`proposalStart`|`uint256`||
|`proposalCount`|`uint256`||
|`messageStart`|`uint256`||
|`messageCount`|`uint256`||
|`treasuryTokens`|`address[]`|Array of token addresses to check balances for (address(0) = native ETH)|


### getDAOMessages

Paginated fetch of DAO messages (chat).

Only message text + index is available on-chain with current Moloch storage.


```solidity
function getDAOMessages(address dao, uint256 start, uint256 count)
    public
    view
    returns (MessageView[] memory out);
```

### _buildDAOFullState


```solidity
function _buildDAOFullState(
    address dao,
    uint256 proposalStart,
    uint256 proposalCount,
    uint256 messageStart,
    uint256 messageCount,
    address[] calldata treasuryTokens
) internal view returns (DAOLens memory out);
```

### _getMembers

Enumerate members as "badge seats" (top-256 by shares, sticky).


```solidity
function _getMembers(address sharesToken, address lootToken, address badgesToken)
    internal
    view
    returns (MemberView[] memory mv);
```

### _getProposals


```solidity
function _getProposals(IMoloch M, MemberView[] memory members, uint256 start, uint256 count)
    internal
    view
    returns (ProposalView[] memory pv);
```

### _getMessagesInternal


```solidity
function _getMessagesInternal(address dao, uint256 start, uint256 count)
    internal
    view
    returns (MessageView[] memory out);
```

### _getTreasury

Fetches balances for specified tokens. Uses staticcall to gracefully handle
missing contracts (returns 0 balance if call fails).


```solidity
function _getTreasury(address dao, address[] calldata tokens)
    internal
    view
    returns (DAOTreasury memory t);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`dao`|`address`|The DAO address to check balances for|
|`tokens`|`address[]`|Array of token addresses (address(0) = native ETH)|


### scanDAICOs

Scan all DAOs for active DAICO sales in a single call.

Checks each DAO against the provided tribute tokens for active sales.
Returns only DAOs with at least one active sale (non-zero terms).


```solidity
function scanDAICOs(uint256 daoStart, uint256 daoCount, address[] calldata tribTokens)
    public
    view
    returns (DAICOView[] memory daicos);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`daoStart`|`uint256`|Starting index for DAO pagination|
|`daoCount`|`uint256`|Number of DAOs to scan|
|`tribTokens`|`address[]`|Array of tribute tokens to check for sales (ETH = address(0))|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`daicos`|`DAICOView[]`|Array of DAICOView structs for DAOs with active sales|


### getDAICO

Get DAICO data for a single DAO.


```solidity
function getDAICO(address dao, address[] calldata tribTokens)
    public
    view
    returns (DAICOView memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`dao`|`address`|The DAO address|
|`tribTokens`|`address[]`|Array of tribute tokens to check for sales|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`DAICOView`|view DAICO data including sales and tap info|


### getDAOWithDAICO

Full DAO state + DAICO data in one call.


```solidity
function getDAOWithDAICO(
    address dao,
    uint256 proposalStart,
    uint256 proposalCount,
    uint256 messageStart,
    uint256 messageCount,
    address[] calldata treasuryTokens,
    address[] calldata tribTokens
) public view returns (DAICOLens memory out);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`dao`|`address`|The DAO address|
|`proposalStart`|`uint256`|Starting index for proposals|
|`proposalCount`|`uint256`|Number of proposals to fetch|
|`messageStart`|`uint256`|Starting index for messages|
|`messageCount`|`uint256`|Number of messages to fetch|
|`treasuryTokens`|`address[]`|Tokens to check for treasury balances|
|`tribTokens`|`address[]`|Tribute tokens to check for DAICO sales|


### getDAOsWithDAICO

Scan multiple DAOs and return full state + DAICO data.

Combines getDAOsFullState functionality with DAICO scanning.


```solidity
function getDAOsWithDAICO(
    uint256 daoStart,
    uint256 daoCount,
    uint256 proposalStart,
    uint256 proposalCount,
    uint256 messageStart,
    uint256 messageCount,
    address[] calldata treasuryTokens,
    address[] calldata tribTokens
) public view returns (DAICOLens[] memory out);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`daoStart`|`uint256`|Starting index for DAO pagination|
|`daoCount`|`uint256`|Number of DAOs to fetch|
|`proposalStart`|`uint256`|Starting index for proposals (per DAO)|
|`proposalCount`|`uint256`|Number of proposals to fetch (per DAO)|
|`messageStart`|`uint256`|Starting index for messages (per DAO)|
|`messageCount`|`uint256`|Number of messages to fetch (per DAO)|
|`treasuryTokens`|`address[]`|Tokens to check for treasury balances|
|`tribTokens`|`address[]`|Tribute tokens to check for DAICO sales|


### _hasAnySale

Check if DAO has any sale with non-zero terms for given tribute tokens.


```solidity
function _hasAnySale(address dao, address[] calldata tribTokens) internal view returns (bool);
```

### _getSales

Get all sales for a DAO across given tribute tokens.


```solidity
function _getSales(address dao, address[] calldata tribTokens)
    internal
    view
    returns (SaleView[] memory);
```

### _getTap

Get tap info for a DAO.


```solidity
function _getTap(address dao) internal view returns (TapView memory tap);
```

### _getMeta

Get minimal DAO metadata for DAICO views.


```solidity
function _getMeta(address dao) internal view returns (DAOMeta memory meta);
```

### _safeBalanceOf

Safe balanceOf that returns 0 on failure.


```solidity
function _safeBalanceOf(address token, address account) internal view returns (uint256);
```

### _safeTotalSupply

Safe totalSupply that returns 0 on failure.


```solidity
function _safeTotalSupply(address token) internal view returns (uint256);
```

### _safeAllowance

Safe ERC20 allowance that returns 0 on failure.


```solidity
function _safeAllowance(address token, address owner, address spender)
    internal
    view
    returns (uint256);
```

### _safeMolochAllowance

Safe Moloch treasury allowance that returns 0 on failure.
Moloch.allowance(token, spender) is different from ERC20 allowance.


```solidity
function _safeMolochAllowance(address dao, address token, address spender)
    internal
    view
    returns (uint256);
```

### _safeSale

Safe DAICO.sales() call that returns zeros on failure.


```solidity
function _safeSale(address dao, address tribTkn)
    internal
    view
    returns (uint256 tribAmt, uint256 forAmt, address forTkn, uint40 deadline);
```

### _safeTap

Safe DAICO.taps() call that returns zeros on failure.


```solidity
function _safeTap(address dao)
    internal
    view
    returns (address ops, address tribTkn, uint128 ratePerSec, uint64 lastClaim);
```

### _safeLPConfig

Safe DAICO.lpConfigs() call that returns zeros on failure.


```solidity
function _safeLPConfig(address dao, address tribTkn)
    internal
    view
    returns (uint16 lpBps, uint16 maxSlipBps, uint256 feeOrHook);
```

