# DAICO
[Git Source](https://github.com/z0r0z/SAW/blob/5b287591f19dce0ac310dc192604a613e25f6e34/src/peripheral/DAICO.sol)

DAO-driven OTC sale contract with optional LP initialization:
- DAO calls setSale() to define a fixed price.
- Users can:
* buy()        : exact-in (pay exact tribTkn, get >= minBuyAmt forTkn)
* buyExactOut(): exact-out (get exact buyAmt forTkn, pay <= maxPayAmt tribTkn)
- DAO caps distribution by approving this contract to spend forTkn (ERC20 approve).
- Optional lpBps splits tribute between DAO treasury and ZAMM liquidity.


## State Variables
### sales
DAO => payment token (ERC20 or ETH=address(0)) => sale terms


```solidity
mapping(address dao => mapping(address tribTkn => TributeOffer)) public sales
```


### taps
DAO => tap config


```solidity
mapping(address dao => Tap) public taps
```


### lpConfigs
DAO => tribTkn => LP config (optional)


```solidity
mapping(address dao => mapping(address tribTkn => LPConfig)) public lpConfigs
```


### REENTRANCY_GUARD_SLOT

```solidity
uint256 constant REENTRANCY_GUARD_SLOT = 0x929eee149b4bd21268
```


## Functions
### constructor


```solidity
constructor() payable;
```

### nonReentrant


```solidity
modifier nonReentrant() ;
```

### setSale

Set or clear a sale for a given payment token.


```solidity
function setSale(
    address tribTkn,
    uint256 tribAmt,
    address forTkn,
    uint256 forAmt,
    uint40 deadline
) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tribTkn`|`address`| Token buyers pay in (ERC20, or address(0) for ETH).|
|`tribAmt`|`uint256`| Base pay amount in tribTkn units.|
|`forTkn`|`address`|  ERC20 token the DAO is selling (must be nonzero when setting).|
|`forAmt`|`uint256`|  Base receive amount in forTkn units.|
|`deadline`|`uint40`|Unix timestamp after which sale expires (0 = no deadline). Examples (off-chain encoding, assuming 18-dec shares): - "1 ETH for 1 share": tribTkn = ETH (0), tribAmt = 1e18, forTkn = SHARE, forAmt = 1e18 - "1 ETH for 1,000,000 shares": tribTkn = ETH (0), tribAmt = 1e18, forTkn = SHARE, forAmt = 1_000_000e18 - "100 USDC (6dec) for 1 share (18dec)": tribTkn = USDC, tribAmt = 100e6, forTkn = SHARE, forAmt = 1e18 To TURN OFF a sale for (dao, tribTkn), pass tribAmt == 0 or forAmt == 0.|


### setSaleWithTap

Set up a sale with an associated tap for the ops beneficiary.

The DAO must call Moloch.setAllowance(DAICO, tribTkn, amount) to fund the tap.


```solidity
function setSaleWithTap(
    address tribTkn,
    uint256 tribAmt,
    address forTkn,
    uint256 forAmt,
    uint40 deadline,
    address ops,
    uint128 ratePerSec
) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tribTkn`|`address`|   Payment token (ETH or ERC20 like USDC).|
|`tribAmt`|`uint256`|   Base pay amount.|
|`forTkn`|`address`|    Token being sold.|
|`forAmt`|`uint256`|    Base receive amount.|
|`deadline`|`uint40`|  Sale deadline (0 = none).|
|`ops`|`address`|       Beneficiary address for tap claims.|
|`ratePerSec`|`uint128`|Rate at which ops can claim tribTkn (smallest units/sec).|


### setTapOps

Update the ops beneficiary for an existing tap.

Only callable by the DAO (msg.sender must be the DAO that set the tap).


```solidity
function setTapOps(address newOps) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newOps`|`address`|New beneficiary address. Setting to address(0) disables claiming.|


### setTapRate

Update the tap rate for an existing tap (non-retroactive).

Only callable by the DAO. Per Vitalik's DAICO: token holders can vote to
raise the tap (give team more funds) or lower/freeze it (loss of confidence).
Rate changes are non-retroactive: unclaimed time at old rate is forfeited,
and new rate applies only from this moment forward.


```solidity
function setTapRate(uint128 newRate) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newRate`|`uint128`|New rate in smallest units per second. Setting to 0 freezes the tap.|


### setLPConfig

Set LP config for a sale. Portion of tribute goes to ZAMM liquidity.

If using LP, DAO must also approve DAICO to spend forTkn. LP shares go to DAO.


```solidity
function setLPConfig(address tribTkn, uint16 lpBps, uint16 maxSlipBps, uint256 feeOrHook)
    public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tribTkn`|`address`|  Payment token for the sale.|
|`lpBps`|`uint16`|    Basis points of tribute to LP (0-9999, 0 = disabled). NOTE: Buyers receive (10000 - lpBps) / 10000 of the quoted rate. E.g., lpBps=5000 means 50% to LP, buyer gets 50% of tokens.|
|`maxSlipBps`|`uint16`|Max slippage for LP adds (default 100 = 1%).|
|`feeOrHook`|`uint256`|Pool fee in bps or hook address.|


### setSaleWithLP

Convenience: set sale + LP config in one call.


```solidity
function setSaleWithLP(
    address tribTkn,
    uint256 tribAmt,
    address forTkn,
    uint256 forAmt,
    uint40 deadline,
    uint16 lpBps,
    uint16 maxSlipBps,
    uint256 feeOrHook
) public;
```

### setSaleWithLPAndTap

Convenience: set sale + LP config + tap in one call.


```solidity
function setSaleWithLPAndTap(
    address tribTkn,
    uint256 tribAmt,
    address forTkn,
    uint256 forAmt,
    uint40 deadline,
    uint16 lpBps,
    uint16 maxSlipBps,
    uint256 feeOrHook,
    address ops,
    uint128 ratePerSec
) public;
```

### _initLP

Initialize liquidity with a portion of tribute. Returns (tribUsed, forTknUsed, refund).
Handles pool drift: if spot > OTC rate, caps LP slice to prevent buyer underflow.


```solidity
function _initLP(
    address dao,
    address tribTkn,
    address forTkn,
    uint256 tribForLP,
    uint256 forTknRate, // forTkn per tribTkn (×1e18)
    LPConfig memory lp
) internal returns (uint256 tribUsed, uint256 forTknUsed, uint256 refund);
```

### buy

Exact-in buy:
- You specify exactly how much tribTkn to pay (`payAmt`).
- Contract computes how much forTkn you get.
- Optional slippage bound: if `minBuyAmt != 0`, you must receive at least `minBuyAmt`.
- If LP is configured, a portion goes to ZAMM liquidity (with drift protection).


```solidity
function buy(address dao, address tribTkn, uint256 payAmt, uint256 minBuyAmt)
    public
    payable
    nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`dao`|`address`|       DAO whose sale to use.|
|`tribTkn`|`address`|   Token you're paying in (must match sale's tribTkn).|
|`payAmt`|`uint256`|    How much tribTkn you are paying (in base units).|
|`minBuyAmt`|`uint256`| Minimum forTkn you are willing to receive (0 = no bound).|


### buyExactOut

Exact-out buy:
- You specify exactly how much forTkn you want (`buyAmt`).
- Contract computes how much tribTkn you must pay (including LP portion if configured).
- If LP is configured, gross forTkn = buyAmt * 10000 / (10000 - lpBps), and LP gets the difference.
- Optional bound: if `maxPayAmt != 0`, you will never pay more than `maxPayAmt`.


```solidity
function buyExactOut(address dao, address tribTkn, uint256 buyAmt, uint256 maxPayAmt)
    public
    payable
    nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`dao`|`address`|       DAO whose sale to use.|
|`tribTkn`|`address`|   Token you're paying in (must match sale's tribTkn).|
|`buyAmt`|`uint256`|    Exact amount of forTkn you want (in base units).|
|`maxPayAmt`|`uint256`| Max tribTkn you are willing to pay (0 = no bound).|


### quoteBuy

Quote how much forTkn you'd get for an exact-in trade (LP and drift-aware).

Returns 0 if sale is inactive or expired. Accounts for LP deduction with drift protection.


```solidity
function quoteBuy(address dao, address tribTkn, uint256 payAmt)
    public
    view
    returns (uint256 buyAmt);
```

### quotePayExactOut

Quote how much tribTkn you'd pay for an exact-out trade (LP-aware).

Returns 0 if sale is inactive or expired. Accounts for LP overhead if configured.
Note: exact-out guarantees buyAmt, so drift doesn't affect the quote.


```solidity
function quotePayExactOut(address dao, address tribTkn, uint256 buyAmt)
    public
    view
    returns (uint256 payAmt);
```

### _quoteLPUsed

Compute forTkn used for LP with drift protection (mirrors _initLP logic).


```solidity
function _quoteLPUsed(
    address tribTkn,
    address forTkn,
    uint256 payAmt,
    TributeOffer memory offer,
    LPConfig memory lp
) internal view returns (uint256 forTknLPUsed);
```

### claimTap

Claim accrued tap. Anyone can call; funds go to ops.

Pulls from DAO's Moloch allowance via spendAllowance, then forwards to ops.
Dynamically adjusts to min(owed, allowance, daoBalance) to handle ragequits/spending.


```solidity
function claimTap(address dao) public nonReentrant returns (uint256 claimed);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`dao`|`address`|The DAO whose tap to claim from.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`claimed`|`uint256`|Amount claimed.|


### pendingTap

View: how much is owed based on time (ignoring allowance/balance caps).


```solidity
function pendingTap(address dao) public view returns (uint256 owed);
```

### claimableTap

View: how much can actually be claimed (min of owed, allowance, and DAO balance).

Accounts for ragequits and other DAO spending that may reduce available funds.


```solidity
function claimableTap(address dao) public view returns (uint256);
```

### summonDAICO

Summon a DAO with DAICO sale pre-configured via initCalls.

Uses CREATE2 address prediction to build initCalls that the DAO executes.


```solidity
function summonDAICO(
    SummonConfig calldata summonConfig,
    string calldata orgName,
    string calldata orgSymbol,
    string calldata orgURI,
    uint16 quorumBps,
    bool ragequittable,
    address renderer,
    bytes32 salt,
    address[] calldata initHolders,
    uint256[] calldata initShares,
    bool sharesLocked,
    bool lootLocked,
    DAICOConfig calldata daicoConfig
) public payable returns (address dao);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`summonConfig`|`SummonConfig`|Summoner and implementation addresses.|
|`orgName`|`string`|     DAO name.|
|`orgSymbol`|`string`|   DAO symbol.|
|`orgURI`|`string`|      DAO metadata URI.|
|`quorumBps`|`uint16`|   Quorum in basis points (e.g., 5000 = 50%).|
|`ragequittable`|`bool`|Whether ragequit is enabled.|
|`renderer`|`address`|    Optional renderer address.|
|`salt`|`bytes32`|        Salt for CREATE2.|
|`initHolders`|`address[]`| Initial share holders.|
|`initShares`|`uint256[]`|  Initial share amounts.|
|`sharesLocked`|`bool`|Whether shares are non-transferable.|
|`lootLocked`|`bool`|  Whether loot is non-transferable.|
|`daicoConfig`|`DAICOConfig`| DAICO sale configuration.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`dao`|`address`|        The newly created DAO address.|


### summonDAICOCustom

Summon a DAO with DAICO sale + custom initCalls for additional setup.

Custom calls are appended after DAICO setup. Useful for ops team mints with
timelocks, vesting schedules, or any other post-initialization configuration.


```solidity
function summonDAICOCustom(
    SummonConfig calldata summonConfig,
    string calldata orgName,
    string calldata orgSymbol,
    string calldata orgURI,
    uint16 quorumBps,
    bool ragequittable,
    address renderer,
    bytes32 salt,
    address[] calldata initHolders,
    uint256[] calldata initShares,
    bool sharesLocked,
    bool lootLocked,
    DAICOConfig calldata daicoConfig,
    Call[] calldata customCalls
) public payable returns (address dao);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`summonConfig`|`SummonConfig`|Summoner and implementation addresses.|
|`orgName`|`string`|     DAO name.|
|`orgSymbol`|`string`|   DAO symbol.|
|`orgURI`|`string`|      DAO metadata URI.|
|`quorumBps`|`uint16`|   Quorum in basis points.|
|`ragequittable`|`bool`|Whether ragequit is enabled.|
|`renderer`|`address`|    Optional renderer address.|
|`salt`|`bytes32`|        Salt for CREATE2.|
|`initHolders`|`address[]`| Initial share holders.|
|`initShares`|`uint256[]`|  Initial share amounts.|
|`sharesLocked`|`bool`|Whether shares are non-transferable.|
|`lootLocked`|`bool`|  Whether loot is non-transferable.|
|`daicoConfig`|`DAICOConfig`| DAICO sale configuration.|
|`customCalls`|`Call[]`| Additional calls to execute after DAICO setup (e.g., ops mints, vesting).|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`dao`|`address`|        The newly created DAO address.|


### summonDAICOWithTap

Summon a DAO with DAICO sale + tap pre-configured.


```solidity
function summonDAICOWithTap(
    SummonConfig calldata summonConfig,
    string calldata orgName,
    string calldata orgSymbol,
    string calldata orgURI,
    uint16 quorumBps,
    bool ragequittable,
    address renderer,
    bytes32 salt,
    address[] calldata initHolders,
    uint256[] calldata initShares,
    bool sharesLocked,
    bool lootLocked,
    DAICOConfig calldata daicoConfig,
    TapConfig calldata tapConfig
) public payable returns (address dao);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`summonConfig`|`SummonConfig`|Summoner and implementation addresses.|
|`orgName`|`string`|     DAO name.|
|`orgSymbol`|`string`|   DAO symbol.|
|`orgURI`|`string`|      DAO metadata URI.|
|`quorumBps`|`uint16`|   Quorum in basis points.|
|`ragequittable`|`bool`|Whether ragequit is enabled.|
|`renderer`|`address`|    Optional renderer address.|
|`salt`|`bytes32`|        Salt for CREATE2.|
|`initHolders`|`address[]`| Initial share holders.|
|`initShares`|`uint256[]`|  Initial share amounts.|
|`sharesLocked`|`bool`|Whether shares are non-transferable.|
|`lootLocked`|`bool`|  Whether loot is non-transferable.|
|`daicoConfig`|`DAICOConfig`| DAICO sale configuration.|
|`tapConfig`|`TapConfig`|   Tap configuration.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`dao`|`address`|        The newly created DAO address.|


### summonDAICOWithTapCustom

Summon a DAO with DAICO sale + tap + custom initCalls.

Most flexible option: full DAICO setup with tap plus custom calls appended.


```solidity
function summonDAICOWithTapCustom(
    SummonConfig calldata summonConfig,
    string calldata orgName,
    string calldata orgSymbol,
    string calldata orgURI,
    uint16 quorumBps,
    bool ragequittable,
    address renderer,
    bytes32 salt,
    address[] calldata initHolders,
    uint256[] calldata initShares,
    bool sharesLocked,
    bool lootLocked,
    DAICOConfig calldata daicoConfig,
    TapConfig calldata tapConfig,
    Call[] calldata customCalls
) public payable returns (address dao);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`summonConfig`|`SummonConfig`|Summoner and implementation addresses.|
|`orgName`|`string`|     DAO name.|
|`orgSymbol`|`string`|   DAO symbol.|
|`orgURI`|`string`|      DAO metadata URI.|
|`quorumBps`|`uint16`|   Quorum in basis points.|
|`ragequittable`|`bool`|Whether ragequit is enabled.|
|`renderer`|`address`|    Optional renderer address.|
|`salt`|`bytes32`|        Salt for CREATE2.|
|`initHolders`|`address[]`| Initial share holders.|
|`initShares`|`uint256[]`|  Initial share amounts.|
|`sharesLocked`|`bool`|Whether shares are non-transferable.|
|`lootLocked`|`bool`|  Whether loot is non-transferable.|
|`daicoConfig`|`DAICOConfig`| DAICO sale configuration.|
|`tapConfig`|`TapConfig`|   Tap configuration.|
|`customCalls`|`Call[]`| Additional calls to execute after DAICO setup (e.g., ops mints, vesting).|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`dao`|`address`|        The newly created DAO address.|


### _buildInitCalls

Build the initCalls array for DAO initialization with DAICO setup.


```solidity
function _buildInitCalls(
    SummonConfig calldata summonConfig,
    bytes32 salt,
    address[] calldata initHolders,
    uint256[] calldata initShares,
    bool sharesLocked,
    bool lootLocked,
    DAICOConfig calldata daicoConfig,
    TapConfig memory tapConfig
) internal view returns (Call[] memory initCalls);
```

### setupDAICO

Callback from DAO's initCalls to complete DAICO setup.

Called by the newly summoned DAO during initialization.
Only stores config - minting/approval done via earlier initCalls.


```solidity
function setupDAICO(
    address dao,
    address forTkn,
    DAICOConfig calldata daicoConfig,
    TapConfig calldata tapConfig
) public;
```

### _predictDAO

Predict DAO address from Summoner's CREATE2.


```solidity
function _predictDAO(
    address summoner,
    address molochImpl,
    bytes32 salt,
    address[] calldata initHolders,
    uint256[] calldata initShares
) internal pure returns (address);
```

### _predictClone

Predict clone address from CREATE2 within the DAO.


```solidity
function _predictClone(address impl, bytes32 salt, address deployer)
    internal
    pure
    returns (address);
```

### receive

Accept ETH from Moloch.spendAllowance for ETH taps.


```solidity
receive() external payable;
```

## Events
### SaleSet

```solidity
event SaleSet(
    address indexed dao,
    address indexed tribTkn,
    uint256 tribAmt,
    address indexed forTkn,
    uint256 forAmt,
    uint40 deadline
);
```

### SaleBought

```solidity
event SaleBought(
    address indexed buyer,
    address indexed dao,
    address indexed tribTkn,
    uint256 payAmt,
    address forTkn,
    uint256 buyAmt
);
```

### TapSet

```solidity
event TapSet(
    address indexed dao, address indexed ops, address indexed tribTkn, uint128 ratePerSec
);
```

### TapClaimed

```solidity
event TapClaimed(address indexed dao, address indexed ops, address tribTkn, uint256 amount);
```

### TapOpsUpdated

```solidity
event TapOpsUpdated(address indexed dao, address indexed oldOps, address indexed newOps);
```

### TapRateUpdated

```solidity
event TapRateUpdated(address indexed dao, uint128 oldRate, uint128 newRate);
```

### LPConfigSet

```solidity
event LPConfigSet(
    address indexed dao, address indexed tribTkn, uint16 lpBps, uint256 feeOrHook
);
```

### LPInitialized

```solidity
event LPInitialized(
    address indexed dao,
    address indexed tribTkn,
    uint256 tribUsed,
    uint256 forTknUsed,
    uint256 liquidity
);
```

## Errors
### NoTap

```solidity
error NoTap();
```

### NoSale

```solidity
error NoSale();
```

### Expired

```solidity
error Expired();
```

### BadLPBps

```solidity
error BadLPBps();
```

### Unauthorized

```solidity
error Unauthorized();
```

### InvalidParams

```solidity
error InvalidParams();
```

### NothingToClaim

```solidity
error NothingToClaim();
```

### SlippageExceeded

```solidity
error SlippageExceeded();
```

## Structs
### TributeOffer

```solidity
struct TributeOffer {
    uint256 tribAmt; // base "pay" amount in tribTkn units
    uint256 forAmt; // base "receive" amount in forTkn units
    address forTkn; // ERC20 token being sold by DAO
    uint40 deadline; // unix timestamp after which sale expires (0 = no deadline)
}
```

### Tap

```solidity
struct Tap {
    address ops; // beneficiary who can receive tap claims
    address tribTkn; // token being tapped (ETH = address(0), or ERC20)
    uint128 ratePerSec; // smallest-unit/sec (handles 6-dec like USDC)
    uint64 lastClaim; // last claim timestamp
}
```

### LPConfig

```solidity
struct LPConfig {
    uint16 lpBps; // portion of tribTkn to LP (0-10000 bps, 0 = disabled)
    uint16 maxSlipBps; // max slippage for LP adds (default 100 = 1%)
    uint256 feeOrHook; // pool fee in bps or hook address
}
```

### DAICOConfig
DAICO sale configuration for summon wrappers


```solidity
struct DAICOConfig {
    address tribTkn; // Payment token (ETH = address(0))
    uint256 tribAmt; // Base pay amount
    uint256 saleSupply; // Amount to mint for sale
    uint256 forAmt; // Base receive amount
    uint40 deadline; // Sale deadline (0 = none)
    bool sellLoot; // true = sell loot, false = sell shares
    // LP config (optional - set lpBps=0 to disable)
    // NOTE: Buyers receive (10000 - lpBps) / 10000 of quoted rate
    uint16 lpBps; // Portion of tribute to LP (0-9999, 0 = disabled)
    uint16 maxSlipBps; // Max slippage for LP adds (0 = default 1%)
    uint256 feeOrHook; // Pool fee in bps or hook address
}
```

### TapConfig
Tap configuration for summon wrappers


```solidity
struct TapConfig {
    address ops; // Tap beneficiary
    uint128 ratePerSec; // Tap rate
    uint256 tapAllowance; // Total tap budget
}
```

### SummonConfig
Summon config containing implementation addresses for CREATE2 prediction.


```solidity
struct SummonConfig {
    address summoner; // Summoner contract
    address molochImpl; // Moloch implementation (for DAO address prediction)
    address sharesImpl; // Shares implementation (for shares address prediction)
    address lootImpl; // Loot implementation (for loot address prediction)
}
```

