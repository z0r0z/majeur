# SafeSummoner
[Git Source](https://github.com/z0r0z/majeur/blob/13360a942bd5f358d43ac5a53ba3981007990305/src/peripheral/SafeSummoner.sol)

**Title:**
SafeSummoner

Safe wrapper around the deployed Summoner that enforces audit-derived
configuration guidance and builds initCalls from a typed struct.

Audit findings addressed:
KF#11  — Enforces proposalThreshold > 0 (prevents front-run cancel, proposal spam)
KF#17  — Enforces non-zero quorum when futarchy is configured (prevents premature NO-resolution)
KF#3   — Enforces autoFutarchyCap > 0 when futarchy enabled (bounds per-proposal earmarks,
prevents unbounded minted-loot farming via NO-coalition repeated defeats)
KF#2   — Blocks quorumBps + minting sale combo (supply manipulation via buy -> ragequit)
KF#12  — Validates quorumBps range at summon time (init skips this check)
Config — Requires proposalTTL > 0 (prevents proposals lingering indefinitely)
Config — Requires proposalTTL > timelockDelay (prevents proposals expiring in queue)


## Functions
### constructor


```solidity
constructor() payable;
```

### multicall

Batch multiple SafeSummoner calls in a single transaction.

Uses delegatecall so msg.sender is preserved. msg.value is shared
across all calls — callers sending ETH must ensure only one sub-call
consumes it, or that the total is sufficient.


```solidity
function multicall(bytes[] calldata data) public payable returns (bytes[] memory results);
```

### create2Deploy

Deploy an arbitrary contract via CREATE2.

Useful for deploying peripheral contracts (hooks, modules) as part
of a multicall summoning sequence with deterministic addresses.


```solidity
function create2Deploy(bytes calldata creationCode, bytes32 salt)
    public
    payable
    returns (address deployed);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`creationCode`|`bytes`|Contract creation bytecode (with constructor args appended if any)|
|`salt`|`bytes32`|        CREATE2 salt|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`deployed`|`address`|   The deployed contract address|


### predictCreate2

Predict the address of a contract deployed via create2Deploy.


```solidity
function predictCreate2(bytes calldata creationCode, bytes32 salt)
    public
    view
    returns (address);
```

### safeSummon

Deploy a new DAO with validated configuration.


```solidity
function safeSummon(
    string calldata orgName,
    string calldata orgSymbol,
    string calldata orgURI,
    uint16 quorumBps,
    bool ragequittable,
    address renderer,
    bytes32 salt,
    address[] calldata initHolders,
    uint256[] calldata initShares,
    uint256[] calldata initLoot,
    SafeConfig calldata config,
    Call[] calldata extraCalls
) public payable returns (address dao);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orgName`|`string`|     DAO display name|
|`orgSymbol`|`string`|   DAO token symbol|
|`orgURI`|`string`|      DAO metadata URI (empty = default)|
|`quorumBps`|`uint16`|   Quorum as basis points of snapshot supply (e.g. 2000 = 20%)|
|`ragequittable`|`bool`|Whether members can ragequit|
|`renderer`|`address`|    On-chain renderer address (address(0) = default)|
|`salt`|`bytes32`|        CREATE2 salt for deterministic addresses|
|`initHolders`|`address[]`| Initial share holders|
|`initShares`|`uint256[]`|  Initial share amounts (must match initHolders length)|
|`initLoot`|`uint256[]`|    Initial loot amounts per holder (empty = skip, else must match initHolders length)|
|`config`|`SafeConfig`|      Typed configuration struct|
|`extraCalls`|`Call[]`|  Additional raw initCalls appended after config (advanced use)|


### summonStandard

Standard DAO: 7-day voting, 2-day timelock, 10% quorum, ragequittable.
Suitable for treasuries, protocol governance, and grants committees.


```solidity
function summonStandard(
    string calldata orgName,
    string calldata orgSymbol,
    string calldata orgURI,
    bytes32 salt,
    address[] calldata initHolders,
    uint256[] calldata initShares,
    bool lockShares
) public payable returns (address);
```

### summonFast

Fast DAO: 3-day voting, 1-day timelock, 5% quorum, ragequittable.
Suitable for agile teams, working groups, and sub-DAOs.


```solidity
function summonFast(
    string calldata orgName,
    string calldata orgSymbol,
    string calldata orgURI,
    bytes32 salt,
    address[] calldata initHolders,
    uint256[] calldata initShares,
    bool lockShares
) public payable returns (address);
```

### summonFounder

Founder-mode DAO: single owner with 10M shares, 1-day voting, no timelock, 10% quorum.
Designed for solo founders who want fast unilateral control with ragequit enabled.


```solidity
function summonFounder(
    string calldata orgName,
    string calldata orgSymbol,
    string calldata orgURI,
    bytes32 salt
) public payable returns (address);
```

### safeSummonDAICO

Deploy a DAO with full config + modular sale/tap/seed.

Combines SafeConfig governance with standalone peripheral singletons.
Cannot use SafeConfig.saleActive simultaneously with SaleModule.


```solidity
function safeSummonDAICO(
    string calldata orgName,
    string calldata orgSymbol,
    string calldata orgURI,
    uint16 quorumBps,
    bool ragequittable,
    address renderer,
    bytes32 salt,
    address[] calldata initHolders,
    uint256[] calldata initShares,
    uint256[] calldata initLoot,
    SafeConfig calldata config,
    SaleModule calldata sale,
    TapModule calldata tap,
    SeedModule calldata seed,
    Call[] calldata extraCalls
) public payable returns (address dao);
```

### summonStandardDAICO

Standard DAO (7d voting, 2d timelock, 10% quorum) + modular DAICO.


```solidity
function summonStandardDAICO(
    string calldata orgName,
    string calldata orgSymbol,
    string calldata orgURI,
    bytes32 salt,
    address[] calldata initHolders,
    uint256[] calldata initShares,
    bool lockShares,
    SaleModule calldata sale,
    TapModule calldata tap,
    SeedModule calldata seed
) public payable returns (address);
```

### summonFastDAICO

Fast DAO (3d voting, 1d timelock, 5% quorum) + modular DAICO.


```solidity
function summonFastDAICO(
    string calldata orgName,
    string calldata orgSymbol,
    string calldata orgURI,
    bytes32 salt,
    address[] calldata initHolders,
    uint256[] calldata initShares,
    bool lockShares,
    SaleModule calldata sale,
    TapModule calldata tap,
    SeedModule calldata seed
) public payable returns (address);
```

### _summonDAICOPreset


```solidity
function _summonDAICOPreset(
    string calldata orgName,
    string calldata orgSymbol,
    string calldata orgURI,
    uint16 quorumBps,
    bool ragequittable,
    bytes32 salt,
    address[] calldata initHolders,
    uint256[] calldata initShares,
    SafeConfig memory config,
    SaleModule calldata sale,
    TapModule calldata tap,
    SeedModule calldata seed
) internal returns (address);
```

### _summonPreset


```solidity
function _summonPreset(
    string calldata orgName,
    string calldata orgSymbol,
    string calldata orgURI,
    uint16 quorumBps,
    bool ragequittable,
    bytes32 salt,
    address[] calldata initHolders,
    uint256[] calldata initShares,
    SafeConfig memory config
) internal returns (address);
```

### previewCalls

Preview the initCalls that safeSummon would generate for off-chain inspection.

Uses address(0) as DAO placeholder since the address isn't known yet.


```solidity
function previewCalls(SafeConfig calldata config) public pure returns (Call[] memory);
```

### previewModuleCalls

Preview the module initCalls that safeSummonDAICO would generate.

Uses address(0) as DAO placeholder. Sentinel tokens resolve to predicted addresses.


```solidity
function previewModuleCalls(
    SaleModule calldata sale,
    TapModule calldata tap,
    SeedModule calldata seed
) public pure returns (Call[] memory);
```

### predictDAO

Predict the DAO address that would be deployed with the given parameters.


```solidity
function predictDAO(bytes32 salt, address[] calldata initHolders, uint256[] calldata initShares)
    public
    pure
    returns (address);
```

### predictShares

Predict the Shares token address for a given DAO.


```solidity
function predictShares(address dao) public pure returns (address);
```

### predictLoot

Predict the Loot token address for a given DAO.


```solidity
function predictLoot(address dao) public pure returns (address);
```

### _validate


```solidity
function _validate(uint16 quorumBps, SafeConfig memory c, uint256 holderCount) internal pure;
```

### _validateModules

Validate module-specific constraints.


```solidity
function _validateModules(
    uint16 quorumBps,
    uint96 quorumAbsolute,
    SaleModule memory sale,
    SeedModule memory seed
) internal pure;
```

### _buildCalls


```solidity
function _buildCalls(address dao, SafeConfig memory c, Call[] memory extra)
    internal
    pure
    returns (Call[] memory calls);
```

### burnPermitCall

Generate the setPermit Call for ShareBurner inclusion in initCalls or proposals.

Useful for DAOs that want to add burn-after-deadline outside of SafeSummoner presets.


```solidity
function burnPermitCall(
    bytes32 salt,
    address[] calldata initHolders,
    uint256[] calldata initShares,
    uint256 deadline,
    address singleton
) public pure returns (Call memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`salt`|`bytes32`||
|`initHolders`|`address[]`||
|`initShares`|`uint256[]`||
|`deadline`|`uint256`||
|`singleton`|`address`|ShareBurner address (address(0) = use default SHARE_BURNER)|


### _buildModuleCalls

Build initCalls for ShareSale, TapVest, and LPSeedSwapHook modules.
Order: SaleModule → TapModule → SeedModule (mints → allowances → configure).


```solidity
function _buildModuleCalls(
    address dao,
    SaleModule memory sale,
    TapModule memory tap,
    SeedModule memory seed
) internal pure returns (Call[] memory calls);
```

### _isSeedSentinel

Returns true for LPSeedSwapHook sentinel tokens that require minting.
address(1) = DAO shares, address(2) = DAO loot.


```solidity
function _isSeedSentinel(address token) internal pure returns (bool);
```

### _resolveSaleToken

Resolve SaleModule token to Moloch allowance sentinel or predicted ERC20 address.
Minting path: address(dao) for shares, address(1007) for loot.
Transfer path: predicted shares/loot ERC20 address.


```solidity
function _resolveSaleToken(address dao, SaleModule memory sale)
    internal
    pure
    returns (address);
```

### _resolveSeedToken

Resolve SeedModule token sentinel to predicted ERC20 address.
address(1) → shares, address(2) → loot, otherwise pass-through.


```solidity
function _resolveSeedToken(address dao, address token) internal pure returns (address);
```

### _resolveSeedAllowanceToken

Resolve SeedModule token to Moloch allowance token.
Sentinels use Moloch mint sentinels: address(1) → address(dao) for shares,
address(2) → address(1007) for loot. Non-sentinels use real ERC20 address.


```solidity
function _resolveSeedAllowanceToken(address dao, address token)
    internal
    pure
    returns (address);
```

### _buildLootMints

Build mintFromMoloch calls for initial loot distribution.
Skips zero-amount entries. Returns empty array if initLoot is empty.


```solidity
function _buildLootMints(address dao, address[] calldata holders, uint256[] calldata loot)
    internal
    pure
    returns (Call[] memory calls);
```

### _mergeExtra

Concatenate a memory array with a calldata array.


```solidity
function _mergeExtra(Call[] memory a, Call[] calldata b)
    internal
    pure
    returns (Call[] memory merged);
```

### _defaultThreshold

1% of total initial shares, floored at 1. Ensures proposalThreshold
scales with supply so any single holder of ≥1% can propose.


```solidity
function _defaultThreshold(uint256[] calldata initShares) internal pure returns (uint96);
```

### _predictDAO


```solidity
function _predictDAO(
    bytes32 salt,
    address[] calldata initHolders,
    uint256[] calldata initShares
) internal pure returns (address);
```

### _predictToken

Predict a token proxy address deployed via CREATE2 from the DAO.
All token proxies (shares, loot, badges) use salt = bytes32(bytes20(dao))
and differ only by implementation address in the minimal proxy creation code.


```solidity
function _predictToken(address dao, address impl) internal pure returns (address);
```

### _predictShares


```solidity
function _predictShares(address dao) internal pure returns (address);
```

### _predictLoot


```solidity
function _predictLoot(address dao) internal pure returns (address);
```

## Errors
### Create2Failed

```solidity
error Create2Failed();
```

### NoInitialHolders

```solidity
error NoInitialHolders();
```

### SalePriceRequired

```solidity
error SalePriceRequired();
```

### TimelockExceedsTTL

```solidity
error TimelockExceedsTTL();
```

### ModuleSaleConflict

```solidity
error ModuleSaleConflict();
```

### FutarchyCapRequired

```solidity
error FutarchyCapRequired();
```

### ProposalTTLRequired

```solidity
error ProposalTTLRequired();
```

### QuorumBpsOutOfRange

```solidity
error QuorumBpsOutOfRange();
```

### SeedGateWithoutSale

```solidity
error SeedGateWithoutSale();
```

### InitLootLengthMismatch

```solidity
error InitLootLengthMismatch();
```

### ProposalThresholdRequired

```solidity
error ProposalThresholdRequired();
```

### QuorumRequiredForFutarchy

```solidity
error QuorumRequiredForFutarchy();
```

### RollbackSingletonRequired

```solidity
error RollbackSingletonRequired();
```

### MintingSaleWithDynamicQuorum

```solidity
error MintingSaleWithDynamicQuorum();
```

## Structs
### SafeConfig
Typed configuration for safe DAO deployment.
Zero values mean "skip" (use Moloch defaults) except where validation requires otherwise.


```solidity
struct SafeConfig {
    // ── Governance (validated) ──
    uint96 proposalThreshold; // Must be > 0. Prevents KF#11 griefing.
    uint64 proposalTTL; // Must be > 0. Prevents indefinite proposals.
    // ── Governance (optional) ──
    uint64 timelockDelay; // 0 = no timelock
    uint96 quorumAbsolute; // 0 = rely on quorumBps from summon params
    uint96 minYesVotes; // 0 = no absolute YES floor
    // ── Transfers ──
    bool lockShares; // true = shares non-transferable at launch
    bool lockLoot; // true = loot non-transferable at launch
    // ── Futarchy ──
    uint256 autoFutarchyParam; // 0 = off. 1..10000 = BPS of supply; >10000 = absolute
    uint256 autoFutarchyCap; // Per-proposal cap. Must be > 0 when futarchy enabled (KF#3).
    address futarchyRewardToken; // Only checked if autoFutarchyParam > 0
    // ── Sale ──
    bool saleActive;
    address salePayToken; // address(0) = ETH
    uint256 salePricePerShare; // Required if saleActive
    uint256 saleCap; // 0 = unlimited (non-minting sales are naturally capped by DAO balance)
    bool saleMinting; // true = mint new, false = transfer from DAO
    bool saleIsLoot; // true = sell loot instead of shares
    // ── ShareBurner ──
    address burnSingleton; // ShareBurner contract address (address(0) = use default SHARE_BURNER)
    uint256 saleBurnDeadline; // 0 = no auto-burn. >0 = timestamp after which unsold shares are burnable
    // ── RollbackGuardian ──
    address rollbackGuardian; // address(0) = skip. EOA or multisig that can emergency-bump config
    address rollbackSingleton; // RollbackGuardian singleton address (required if rollbackGuardian set)
    uint40 rollbackExpiry; // 0 = no expiry. Unix timestamp after which rollback is disabled
}
```

### SaleModule
ShareSale module config. singleton = address(0) to skip.
Uses Moloch allowance sentinels: address(dao) = mint shares, address(1007) = mint loot.


```solidity
struct SaleModule {
    address singleton; // ShareSale contract address (0 = skip)
    address payToken; // address(0) = ETH
    uint40 deadline; // unix timestamp after which buys revert (0 = no deadline)
    uint256 price; // per-token price (1e18 scaled)
    uint256 cap; // sale cap (allowance amount)
    bool sellLoot; // true = sell loot, false = sell shares
    bool minting; // true = mint on buy (sentinel), false = transfer from DAO balance
}
```

### TapModule
TapVest module config. singleton = address(0) to skip.


```solidity
struct TapModule {
    address singleton; // TapVest contract address (0 = skip)
    address token; // vested token (address(0) = ETH)
    uint256 budget; // total budget (allowance)
    address beneficiary; // tap recipient
    uint128 ratePerSec; // vesting rate in smallest-unit/sec
}
```

### SeedModule
LPSeedSwapHook module config. singleton = address(0) to skip.
Token sentinels: address(1) = DAO shares, address(2) = DAO loot.
When a sentinel is used, the allowance is set on the Moloch mint sentinel
(address(dao) for shares, address(1007) for loot) so that spendAllowance
triggers mint-on-spend instead of requiring pre-minted tokens.
LPSeedSwapHook acts as a ZAMM hook — the pool's feeOrHook is always derived
from the LPSeedSwapHook singleton address, preventing frontrun pool creation.


```solidity
struct SeedModule {
    address singleton; // LPSeedSwapHook contract address (0 = skip)
    address tokenA; // first token (address(0)=ETH, address(1)=shares, address(2)=loot)
    uint128 amountA; // amount of tokenA to seed
    address tokenB; // second token (address(1)=shares, address(2)=loot, or ERC20)
    uint128 amountB; // amount of tokenB to seed
    uint40 deadline; // time gate (0 = none)
    bool gateBySale; // if true, gate LP seeding on SaleModule completion
    uint128 minSupply; // balance gate (0 = none)
}
```

