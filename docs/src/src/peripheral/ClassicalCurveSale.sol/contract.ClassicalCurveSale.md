# ClassicalCurveSale
[Git Source](https://github.com/z0r0z/majeur/blob/376bbb9940915c61b80e913ec9f3094c9c5ef7bc/src/peripheral/ClassicalCurveSale.sol)

**Title:**
ClassicalCurveSale

Pump.fun-style bonding curve with virtual constant-product (XYK) pricing.
Holds tokens and ETH. Supports buying and selling. Graduates to ZAMM LP
when a configurable ETH target is reached (or all tokens sold).
Curve: price(x) = P₀ · T₀²/(T₀ − x)²
where P₀ = startPrice, T₀ = virtual token reserve, x = tokens sold.
Cost/proceeds for N tokens is the integral: P₀ · T₀² · N / ((T₀−x)(T₀−x−N))
Lifecycle:
1. Creator calls launch() (deploys ERC20 clone + configures curve atomically)
— or deploys token separately, approves this contract, calls configure()
2. Users buy() / sell() on the curve (fee charged both directions)
3. When raisedETH >= graduationTarget (or cap fully sold if no target), trading freezes
4. Anyone calls graduate() — seeds ZAMM LP with this contract as hook
Post-graduation this contract acts as a ZAMM hook for the graduated pool:
- Returns pool swap fee via beforeAction()
- Enforces routed swaps when creator fee is active (swapExactIn/swapExactOut)
- Creator can configure revenue fees on swaps via setCreatorFee()
Keyed by token address — one curve per token, but creators can launch many tokens.


## State Variables
### _curves
Keyed by token address. One curve per token.


```solidity
mapping(address token => CurveConfig) internal _curves
```


### creatorFees
Creator fee config per token.


```solidity
mapping(address token => CreatorFee) public creatorFees
```


### poolToken
Reverse lookup: ZAMM poolId -> token. Set during graduate().


```solidity
mapping(uint256 poolId => address token) public poolToken
```


### creatorVests
Creator vesting schedule per token.


```solidity
mapping(address token => CreatorVest) public creatorVests
```


### _observations
Packed trade observations for charting (1 slot per trade).
Bits: [price:128][volume:80][timestamp:40][flags:8]
price     = avg execution price (1e18 scaled, cost·1e18/amount)
volume    = ETH cost/proceeds in wei (max ~1.2M ETH per trade)
timestamp = block.timestamp
flags     = 0x01 = sell


```solidity
mapping(address token => uint256[]) internal _observations
```


### FLAG_BEFORE
Hook encoding flag — only beforeAction is used.


```solidity
uint256 constant FLAG_BEFORE = 1 << 255
```


### DEFAULT_POOL_FEE
Default pool swap fee when none configured (25 bps = 0.25%).


```solidity
uint16 constant DEFAULT_POOL_FEE = 25
```


### MAX_CREATOR_FEE_BPS
Maximum creator fee per direction (10%).


```solidity
uint16 constant MAX_CREATOR_FEE_BPS = 1000
```


### SEEDING_SLOT
Transient storage slot for seeding bypass in beforeAction.


```solidity
uint256 constant SEEDING_SLOT = 0x436c617373696353616c6553656564
```


### SWAP_LOCK_SLOT
Transient storage slot for swap reentrancy lock.


```solidity
uint256 constant SWAP_LOCK_SLOT = 0x436c617373696353616c654c6f636b
```


### tokenImplementation

```solidity
ERC20 public immutable tokenImplementation
```


## Functions
### constructor


```solidity
constructor() payable;
```

### launch

Deploy a new ERC20 clone and configure a bonding curve in one call.
Mints supply to this contract — cap + lpTokens for the curve, excess escrowed for vesting.


```solidity
function launch(
    address creator,
    string calldata name,
    string calldata symbol,
    string calldata uri,
    uint256 supply,
    bytes32 salt,
    uint256 cap,
    uint256 startPrice,
    uint256 endPrice,
    uint16 feeBps,
    uint256 graduationTarget,
    uint256 lpTokens,
    address lpRecipient,
    uint16 poolFeeBps,
    uint16 sniperFeeBps,
    uint16 sniperDuration,
    uint16 maxBuyBps,
    CreatorFee calldata creatorFee,
    uint40 vestCliff,
    uint40 vestDuration
) public returns (address token);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`creator`|`address`||
|`name`|`string`|            Token name|
|`symbol`|`string`|          Token symbol|
|`uri`|`string`|             Token contract URI (metadata)|
|`supply`|`uint256`|          Total supply to mint (must be >= cap + lpTokens)|
|`salt`|`bytes32`|            Salt for deterministic create2 deployment|
|`cap`|`uint256`|             Tokens available on the curve|
|`startPrice`|`uint256`|      Price at 0% sold (1e18 scaled), must be > 0|
|`endPrice`|`uint256`|        Price at 100% sold (1e18 scaled), must be >= startPrice|
|`feeBps`|`uint16`|          Bonding curve trading fee in basis points (max 10_000)|
|`graduationTarget`|`uint256`|ETH threshold to trigger graduation (0 = sell full cap)|
|`lpTokens`|`uint256`|        Max tokens reserved for LP seeding (0 = no pool). Actual amount used is computed at graduation to match the final curve price for seamless transition. Excess tokens are burned.|
|`lpRecipient`|`address`|     Who receives LP tokens on graduation (address(0) = burn)|
|`poolFeeBps`|`uint16`|      ZAMM pool swap fee post-graduation (0 = default 25 bps)|
|`sniperFeeBps`|`uint16`|   Elevated fee at launch, linearly decays to feeBps (0 = disabled)|
|`sniperDuration`|`uint16`| Seconds over which sniper fee decays to feeBps (0 = disabled)|
|`maxBuyBps`|`uint16`|      Max % of cap per single buy in bps (0 = unlimited)|
|`creatorFee`|`CreatorFee`||
|`vestCliff`|`uint40`|       Cliff before any creator tokens vest in seconds (0 = no cliff)|
|`vestDuration`|`uint40`|    Linear vesting period after cliff in seconds (0 = all at cliff)|


### configure

Configure a new bonding curve sale. Pulls cap + lpTokens from msg.sender.

Only use with standard ERC20 tokens. Fee-on-transfer, rebasing, or callback-enabled
tokens (ERC777, etc.) may cause accounting mismatches or reentrancy issues.
WARNING: Any token supply transferable outside this contract before graduation can be sold
into the curve, redeeming buyer ETH. Only use with tokens whose entire pre-graduation
supply is escrowed here. The launch() path enforces this automatically.


```solidity
function configure(
    address creator,
    address token,
    uint256 cap,
    uint256 startPrice,
    uint256 endPrice,
    uint16 feeBps,
    uint256 graduationTarget,
    uint256 lpTokens,
    address lpRecipient,
    uint16 poolFeeBps,
    uint16 sniperFeeBps,
    uint16 sniperDuration,
    uint16 maxBuyBps,
    CreatorFee calldata creatorFee
) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`creator`|`address`|         Who controls this curve (receives trading fees, LP recipient config, governance)|
|`token`|`address`|           ERC20 to sell (must have approved this contract for cap + lpTokens)|
|`cap`|`uint256`|             Tokens available on the curve|
|`startPrice`|`uint256`|      Price at 0% sold (1e18 scaled), must be > 0|
|`endPrice`|`uint256`|        Price at 100% sold (1e18 scaled), must be >= startPrice|
|`feeBps`|`uint16`|          Bonding curve trading fee in basis points (max 10_000)|
|`graduationTarget`|`uint256`|ETH threshold to trigger graduation (0 = sell full cap)|
|`lpTokens`|`uint256`|        Max tokens reserved for LP seeding (0 = no pool). Actual amount used is computed at graduation to match the final curve price for seamless transition. Excess tokens are burned.|
|`lpRecipient`|`address`|     Who receives LP tokens on graduation (address(0) = burn)|
|`poolFeeBps`|`uint16`|      ZAMM pool swap fee post-graduation (0 = default 25 bps)|
|`sniperFeeBps`|`uint16`|   Elevated fee at launch, decays to feeBps (0 = disabled)|
|`sniperDuration`|`uint16`| Seconds over which sniper fee decays (0 = disabled)|
|`maxBuyBps`|`uint16`|      Max % of cap per single buy in bps (0 = unlimited)|
|`creatorFee`|`CreatorFee`||


### _configure


```solidity
function _configure(
    address creator,
    address token,
    uint256 cap,
    uint256 startPrice,
    uint256 endPrice,
    uint16 feeBps,
    uint256 graduationTarget,
    uint256 lpTokens,
    address lpRecipient,
    uint16 poolFeeBps,
    uint16 sniperFeeBps,
    uint16 sniperDuration,
    uint16 maxBuyBps,
    CreatorFee calldata creatorFee
) internal;
```

### curves

Read curve state.


```solidity
function curves(address token)
    public
    view
    returns (
        address creator,
        uint256 cap,
        uint256 sold,
        uint256 virtualReserve,
        uint256 startPrice,
        uint256 endPrice,
        uint16 feeBps,
        uint16 poolFeeBps,
        uint256 raisedETH,
        uint256 graduationTarget,
        uint256 lpTokens,
        address lpRecipient,
        bool graduated,
        bool seeded,
        uint16 sniperFeeBps,
        uint16 sniperDuration,
        uint16 maxBuyBps,
        uint40 launchTime
    );
```

### effectiveFee

Get the current effective fee bps (accounts for sniper decay).


```solidity
function effectiveFee(address token) public view returns (uint256);
```

### quote

Compute the cost for buying `amount` tokens (before fee).


```solidity
function quote(address token, uint256 amount) public view returns (uint256 cost);
```

### quoteSell

Compute the proceeds for selling `amount` tokens (before fee).


```solidity
function quoteSell(address token, uint256 amount) public view returns (uint256 proceeds);
```

### graduable

Whether the curve has met its graduation target and is ready for graduate().


```solidity
function graduable(address token) public view returns (bool);
```

### hookFeeOrHook

Get the encoded feeOrHook value for pool keys using this contract as hook.


```solidity
function hookFeeOrHook() public view returns (uint256);
```

### poolKeyOf

Derive the ZAMM PoolKey and pool ID for a token's graduated pool.


```solidity
function poolKeyOf(address token)
    public
    view
    returns (IZAMM.PoolKey memory key, uint256 poolId);
```

### observationCount

Number of recorded observations for a token.


```solidity
function observationCount(address token) public view returns (uint256);
```

### observe

Read a range of packed observations. Use `decodeObservation` to unpack.


```solidity
function observe(address token, uint256 from, uint256 to)
    public
    view
    returns (uint256[] memory obs);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The token to query|
|`from`|`uint256`| Start index (inclusive)|
|`to`|`uint256`|   End index (exclusive, capped to length)|


### decodeObservation

Decode a packed observation into its components.


```solidity
function decodeObservation(uint256 packed)
    public
    pure
    returns (uint128 price, uint80 volume, uint40 timestamp, bool isSell);
```

### _recordObservation

Record a trade observation (1 SSTORE).


```solidity
function _recordObservation(address token, uint256 cost, uint256 amount, bool isSell) internal;
```

### buy

Buy tokens on the bonding curve (exact-out). Fee is added on top of cost.
Caps to remaining if amount exceeds available. Refunds excess ETH.


```solidity
function buy(address token, uint256 amount, uint256 minAmount, uint256 deadline)
    public
    payable
    lock;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|    The token to buy|
|`amount`|`uint256`|   Max tokens to buy (capped to remaining)|
|`minAmount`|`uint256`|Minimum tokens to receive (slippage protection)|
|`deadline`|`uint256`| Transaction deadline (block.timestamp)|


### buyExactIn

Buy tokens with exact ETH input. Fee is proportional to actual cost.


```solidity
function buyExactIn(address token, uint256 minAmountOut, uint256 deadline) public payable lock;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|       The token to buy|
|`minAmountOut`|`uint256`|Minimum tokens to receive (slippage protection)|
|`deadline`|`uint256`|    Transaction deadline (block.timestamp)|


### sell

Sell tokens back to the curve. Fee is deducted from proceeds.
Caller must have approved this contract to transferFrom the token.


```solidity
function sell(address token, uint256 amount, uint256 minProceeds, uint256 deadline)
    public
    lock;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|     The token to sell|
|`amount`|`uint256`|    Tokens to sell|
|`minProceeds`|`uint256`|Minimum net ETH to receive (slippage protection)|
|`deadline`|`uint256`|   Transaction deadline (block.timestamp)|


### sellExactOut

Sell tokens for an exact ETH output. Fee is added on top (more tokens sold).
Caller must have approved this contract to transferFrom the token.


```solidity
function sellExactOut(address token, uint256 ethOut, uint256 maxTokens, uint256 deadline)
    public
    lock;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|    The token to sell|
|`ethOut`|`uint256`|   Exact ETH to receive after fees|
|`maxTokens`|`uint256`|Maximum tokens to sell (slippage protection)|
|`deadline`|`uint256`||


### graduate

Seed ZAMM liquidity from graduated curve. Permissionless once graduated.
Seeds pool at the curve's final marginal price for seamless transition.
Uses up to lpTokens — excess burned. Unsold curve tokens burned.
LP tokens sent to lpRecipient (or burned if address(0)).
Pool is created with this contract as ZAMM hook for fee governance.


```solidity
function graduate(address token) public returns (uint256 liquidity);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The token whose curve has graduated|


### beforeAction

ZAMM hook: gate addLiquidity pre-seed, return fee on swaps.
Pre-seed: only graduate() can addLiquidity (blocks frontrun pool creation).
Post-seed: all LP operations allowed, swaps charged pool fee.
When creator fee is active, swaps must route through this contract.


```solidity
function beforeAction(bytes4 sig, uint256 poolId, address sender, bytes calldata)
    public
    payable
    returns (uint256 feeBps);
```

### setCreator

Transfer creator role to a new address. Only callable by current creator.

Setting a contract that rejects ETH as creator will DoS fee-bearing buys/sells.
Also transfers vesting claim rights — claim before transferring if needed.


```solidity
function setCreator(address token, address newCreator) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|     The token whose creator to update|
|`newCreator`|`address`|The new creator address (must not be address(0))|


### setLpRecipient

Update LP recipient for graduation. Only callable by creator.
Allows configuring locked LP (e.g. set to a lock contract) before graduation.


```solidity
function setLpRecipient(address token, address newRecipient) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|       The token whose LP recipient to update|
|`newRecipient`|`address`|New LP recipient (address(0) = burn LP tokens)|


### setCreatorFee

Configure creator revenue fee on post-graduation swaps.
When beneficiary is set, swaps must route through this contract's
swapExactIn/swapExactOut — direct ZAMM swaps are blocked by the hook.


```solidity
function setCreatorFee(
    address token,
    address beneficiary,
    uint16 buyBps,
    uint16 sellBps,
    bool buyOnInput,
    bool sellOnInput
) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|       The token whose fee to configure|
|`beneficiary`|`address`| Fee recipient (address(0) disables routing enforcement)|
|`buyBps`|`uint16`|      Fee bps when buying token (ETH -> token)|
|`sellBps`|`uint16`|     Fee bps when selling token (token -> ETH)|
|`buyOnInput`|`bool`|  true = buy fee from ETH input, false = from token output|
|`sellOnInput`|`bool`| true = sell fee from token input, false = from ETH output|


### claimVested

Claim vested creator tokens. Vesting clock starts at graduation.
Cliff only: nothing until cliff, then 100%.
Cliff + duration: nothing until cliff, then linear over duration.
Duration only: linear from graduation.


```solidity
function claimVested(address token) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The token to claim vested allocation for|


### _validatePool

Validate that poolKey matches the canonical graduated pool for token1.
Prevents arbitrary-pool attacks where a non-ETH pool drains contract ETH.


```solidity
function _validatePool(IZAMM.PoolKey calldata poolKey) internal view returns (address token);
```

### lock


```solidity
modifier lock() ;
```

### swapExactIn

Swap exact input through ZAMM with creator fee.
Required for pools with an active creator fee.


```solidity
function swapExactIn(
    IZAMM.PoolKey calldata poolKey,
    uint256 amountIn,
    uint256 amountOutMin,
    bool zeroForOne,
    address to,
    uint256 deadline
) public payable lock returns (uint256 amountOut);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`poolKey`|`IZAMM.PoolKey`|     ZAMM pool key (use poolKeyOf to derive)|
|`amountIn`|`uint256`|    Input amount (for ETH input, send as msg.value)|
|`amountOutMin`|`uint256`|Minimum output after all fees|
|`zeroForOne`|`bool`|  true = ETH -> token (buy), false = token -> ETH (sell)|
|`to`|`address`|          Recipient of output tokens/ETH|
|`deadline`|`uint256`|    Transaction deadline|


### swapExactOut

Swap exact output through ZAMM with creator fee.
`amountOut` is the net amount `to` receives after fees.


```solidity
function swapExactOut(
    IZAMM.PoolKey calldata poolKey,
    uint256 amountOut,
    uint256 amountInMax,
    bool zeroForOne,
    address to,
    uint256 deadline
) public payable lock returns (uint256 amountIn);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`poolKey`|`IZAMM.PoolKey`|     ZAMM pool key (use poolKeyOf to derive)|
|`amountOut`|`uint256`|   Desired net output amount|
|`amountInMax`|`uint256`| Maximum input (for ETH input, send as msg.value)|
|`zeroForOne`|`bool`|  true = ETH -> token (buy), false = token -> ETH (sell)|
|`to`|`address`|          Recipient of output tokens/ETH|
|`deadline`|`uint256`|    Transaction deadline|


### _checkGraduation

Check if graduation target is met and set the graduated flag.
Takes stack values to avoid re-SLOADing already-cached fields.


```solidity
function _checkGraduation(
    CurveConfig storage c,
    uint256 newSold,
    uint256 cap,
    uint256 newRaisedETH,
    uint256 graduationTarget
) internal;
```

### _effectiveFee

Compute effective fee bps, accounting for sniper decay.
Returns feeBps if no sniper guard or outside decay window.
Otherwise linearly interpolates from sniperFeeBps → feeBps over sniperDuration.


```solidity
function _effectiveFee(CurveConfig storage c) internal view returns (uint256);
```

### _cost

Compute cost for `amount` tokens starting at position `sold` on the XYK curve.
Pure with stack params to avoid redundant SLOADs — callers cache from storage once.
Integral: P₀ · T₀² · amount / ((T₀ − sold) · (T₀ − sold − amount))
Rounded up to prevent dust.


```solidity
function _cost(
    uint256 startPrice,
    uint256 endPrice,
    uint256 virtualReserve,
    uint256 sold,
    uint256 amount
) internal pure returns (uint256);
```

### multicall

Batch multiple calls into a single transaction (e.g. graduate + setCreatorFee).
Intentionally non-payable to prevent msg.value double-spend across delegatecalls.
Functions guarded by `lock` (buy, sell, swapExactIn, swapExactOut) cannot be
batched together — the second call will revert with Reentrancy().


```solidity
function multicall(bytes[] calldata data) public;
```

### receive

Accept ETH (for ZAMM refunds during graduation and fee-on-output swaps).


```solidity
receive() external payable;
```

## Events
### TokenCreated

```solidity
event TokenCreated(address indexed creator, address indexed token);
```

### Configured

```solidity
event Configured(
    address indexed creator,
    address indexed token,
    uint256 cap,
    uint256 startPrice,
    uint256 endPrice,
    uint256 graduationTarget,
    uint256 lpTokens
);
```

### Purchase

```solidity
event Purchase(
    address indexed token, address indexed buyer, uint256 amount, uint256 cost, uint256 fee
);
```

### Sold

```solidity
event Sold(
    address indexed token, address indexed seller, uint256 amount, uint256 proceeds, uint256 fee
);
```

### GraduationComplete

```solidity
event GraduationComplete(
    address indexed token, uint256 ethSeeded, uint256 tokensSeeded, uint256 liquidity
);
```

### CreatorUpdated

```solidity
event CreatorUpdated(address indexed token, address indexed newCreator);
```

### LpRecipientUpdated

```solidity
event LpRecipientUpdated(address indexed token, address indexed newRecipient);
```

### CreatorFeeUpdated

```solidity
event CreatorFeeUpdated(
    address indexed token, address beneficiary, uint16 buyBps, uint16 sellBps
);
```

### VestingClaimed

```solidity
event VestingClaimed(address indexed token, address indexed creator, uint256 amount);
```

## Errors
### Slippage

```solidity
error Slippage();
```

### Graduated

```solidity
error Graduated();
```

### NotSeeded

```solidity
error NotSeeded();
```

### ZeroAmount

```solidity
error ZeroAmount();
```

### InvalidPool

```solidity
error InvalidPool();
```

### NotGraduable

```solidity
error NotGraduable();
```

### Unauthorized

```solidity
error Unauthorized();
```

### InvalidParams

```solidity
error InvalidParams();
```

### NotConfigured

```solidity
error NotConfigured();
```

### DeadlineExpired

```solidity
error DeadlineExpired();
```

### AlreadyConfigured

```solidity
error AlreadyConfigured();
```

### InsufficientPayment

```solidity
error InsufficientPayment();
```

### InsufficientLiquidity

```solidity
error InsufficientLiquidity();
```

## Structs
### CurveConfig
Packed into 6 storage slots (down from 11) for gas-efficient trades.
Hot-path fields share slots to minimise cold SLOADs (~10k gas saved per trade).


```solidity
struct CurveConfig {
    // slot 0 (32 bytes): auth + flags + sniper + anti-whale — read first on every trade
    address creator; // 20 B — who configured this sale
    uint16 feeBps; //  2 B — bonding curve trading fee (bps)
    uint16 poolFeeBps; //  2 B — ZAMM pool swap fee post-graduation
    bool graduated; //  1 B — trading frozen, ready for graduate()
    bool seeded; //  1 B — LP has been seeded via graduate()
    uint16 sniperFeeBps; //  2 B — elevated fee at launch (0 = disabled)
    uint16 sniperDuration; //  2 B — seconds over which sniper fee decays to feeBps
    uint16 maxBuyBps; //  2 B — max % of cap per buy (0 = unlimited)
    // slot 1 (32 bytes): supply counters — read + written every trade
    uint128 cap; // 16 B — tokens available on the curve
    uint128 sold; // 16 B — tokens currently outstanding
    // slot 2 (32 bytes): pricing — read every trade (1 cold SLOAD for both)
    uint128 startPrice; // 16 B — P₀ (price at x=0), 1e18 scaled
    uint128 endPrice; // 16 B — price at x=cap, 1e18 scaled
    // slot 3 (32 bytes): ETH accounting — read + written every trade
    uint128 raisedETH; // 16 B — net ETH held from buys minus sells
    uint128 graduationTarget; // 16 B — ETH threshold for graduation (0 = sell full cap)
    // slot 4 (32 bytes): curve shape + LP reserve — read on non-flat trades / graduation
    uint128 virtualReserve; // 16 B — T₀ for XYK pricing
    uint128 lpTokens; // 16 B — tokens reserved for LP pairing
    // slot 5 (25 bytes): LP config + launch timestamp
    address lpRecipient; // 20 B — who receives LP tokens (address(0) = burn)
    uint40 launchTime; //  5 B — timestamp when curve was configured (for sniper decay)
}
```

### CreatorFee
Creator fee config for post-graduation routed swaps.
When beneficiary != address(0), swaps must route through this contract.


```solidity
struct CreatorFee {
    address beneficiary; // fee recipient (address(0) = disabled, direct ZAMM swaps allowed)
    uint16 buyBps; // fee bps when buying token (ETH -> token)
    uint16 sellBps; // fee bps when selling token (token -> ETH)
    bool buyOnInput; // true = buy fee from ETH input, false = from token output
    bool sellOnInput; // true = sell fee from token input, false = from ETH output
}
```

### CreatorVest
Creator token vesting (optional cliff + linear unlock).
cliff only (duration=0): all tokens unlock at start+cliff
cliff + duration: nothing until cliff, then linear over duration
duration only (cliff=0): linear from graduation over duration


```solidity
struct CreatorVest {
    uint128 total; // total tokens allocated
    uint128 claimed; // tokens already claimed
    uint40 start; // vesting start timestamp (set at graduation)
    uint40 cliff; // seconds before any tokens vest (0 = no cliff)
    uint40 duration; // linear vesting period after cliff (0 = all at cliff)
}
```

