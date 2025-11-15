# Moloch
[Git Source](https://github.com/z0r0z/SAW/blob/58989be3b007e6ed4d89f25206c3132a7dc08ab6/src/Moloch.sol)

ERC-20 shares (delegatable/split) & Loot + ERC-6909 receipts + ERC-721 badges.
Features: timelock, permits, futarchy, token sales, ragequit, SBT-gated chat.

Proposals pass when FOR > AGAINST and quorum met. Snapshots at block N-1.


## State Variables
### _orgName

```solidity
string _orgName
```


### _orgSymbol

```solidity
string _orgSymbol
```


### proposalThreshold
PROPOSAL STATE

Absolute vote thresholds (0 = disabled):


```solidity
uint256 public proposalThreshold
```


### minYesVotesAbsolute

```solidity
uint256 public minYesVotesAbsolute
```


### quorumAbsolute

```solidity
uint256 public quorumAbsolute
```


### proposalTTL
Time-based settings (seconds; 0 = off):


```solidity
uint64 public proposalTTL
```


### timelockDelay

```solidity
uint64 public timelockDelay
```


### config
Governance versioning / dynamic quorum / global flags:


```solidity
uint64 public config
```


### quorumBps

```solidity
uint16 public quorumBps
```


### ragequittable

```solidity
bool public ragequittable
```


### SUMMONER

```solidity
address immutable SUMMONER = msg.sender
```


### sharesImpl

```solidity
address immutable sharesImpl
```


### badgesImpl

```solidity
address immutable badgesImpl
```


### lootImpl

```solidity
address immutable lootImpl
```


### renderer

```solidity
address public renderer
```


### shares

```solidity
Shares public shares
```


### badges

```solidity
Badges public badges
```


### loot

```solidity
Loot public loot
```


### executed
Proposal id = keccak(address(this), op, to, value, keccak(data), nonce, config):


```solidity
mapping(uint256 id => bool) public executed
```


### createdAt

```solidity
mapping(uint256 id => uint64) public createdAt
```


### snapshotBlock

```solidity
mapping(uint256 id => uint48) public snapshotBlock
```


### supplySnapshot

```solidity
mapping(uint256 id => uint256) public supplySnapshot
```


### queuedAt

```solidity
mapping(uint256 id => uint64) public queuedAt
```


### tallies

```solidity
mapping(uint256 id => Tally) public tallies
```


### proposalIds

```solidity
uint256[] public proposalIds
```


### proposerOf

```solidity
mapping(uint256 id => address) public proposerOf
```


### hasVoted
hasVoted[id][voter] = 0 = not, 1 = FOR, 2 = AGAINST, 3 = ABSTAIN:


```solidity
mapping(uint256 id => mapping(address voter => uint8)) public hasVoted
```


### allowance

```solidity
mapping(address token => mapping(address spender => uint256 amount)) public allowance
```


### sales

```solidity
mapping(address payToken => Sale) public sales
```


### messages
MSG STATE


```solidity
string[] public messages
```


### _orgURI
The contract-level URI:


```solidity
string _orgURI
```


### balanceOf

```solidity
mapping(address owner => mapping(uint256 id => uint256)) public balanceOf
```


### totalSupply

```solidity
mapping(uint256 id => uint256) public totalSupply
```


### receiptSupport
FUTARCHY STATE

Decode helpers for SVGs & futarchy validation:


```solidity
mapping(uint256 id => uint8) public receiptSupport
```


### receiptProposal

```solidity
mapping(uint256 id => uint256) public receiptProposal
```


### futarchy

```solidity
mapping(uint256 id => FutarchyConfig) public futarchy
```


### autoFutarchyParam

```solidity
uint256 public autoFutarchyParam
```


### autoFutarchyCap

```solidity
uint256 public autoFutarchyCap
```


### rewardToken

```solidity
address public rewardToken
```


### isOperator

```solidity
mapping(address owner => mapping(address operator => bool)) public isOperator
```


### REENTRANCY_GUARD_SLOT

```solidity
uint256 constant REENTRANCY_GUARD_SLOT = 0x929eee149b4bd21268
```


## Functions
### onlyDAO


```solidity
modifier onlyDAO() ;
```

### name

META STATE

ERC6909 metadata: org name/symbol (shared across ids):


```solidity
function name(
    uint256 /*id*/
)
    public
    view
    returns (string memory);
```

### symbol


```solidity
function symbol(
    uint256 /*id*/
)
    public
    view
    returns (string memory);
```

### constructor


```solidity
constructor() payable;
```

### init


```solidity
function init(
    string calldata orgName,
    string calldata orgSymbol,
    string calldata orgURI,
    uint16 _quorumBps, // e.g. 5000 = 50% turnout of snapshot supply
    bool _ragequittable,
    address _renderer,
    address[] calldata initHolders,
    uint256[] calldata initShares,
    Call[] calldata initCalls
) public payable;
```

### _init


```solidity
function _init(address _implementation, bytes32 _salt) internal returns (address clone);
```

### proposalId


```solidity
function proposalId(uint8 op, address to, uint256 value, bytes calldata data, bytes32 nonce)
    public
    view
    returns (uint256);
```

### getProposalCount


```solidity
function getProposalCount() public view returns (uint256);
```

### openProposal

Explicitly open a proposal and fix the snapshot to the previous block,
ensuring Majeur ERC20Votes-style checkpoints can be queried safely:


```solidity
function openProposal(uint256 id) public;
```

### castVote

Cast a vote for a proposal:
always uses past checkpoints at the proposal’s snapshot block (no current-state fallback),
auto-opens the proposal on first vote (threshold uses current votes by design):


```solidity
function castVote(uint256 id, uint8 support) public;
```

### cancelVote


```solidity
function cancelVote(uint256 id) public;
```

### cancelProposal


```solidity
function cancelProposal(uint256 id) public;
```

### state


```solidity
function state(uint256 id) public view returns (ProposalState);
```

### queue

Queue a passing proposal (sets timelock countdown). If no timelock, no-op:


```solidity
function queue(uint256 id) public;
```

### executeByVotes

Execute when the proposal is ready (handles immediate or timelocked):


```solidity
function executeByVotes(
    uint8 op, // 0 = call, 1 = delegatecall
    address to,
    uint256 value,
    bytes calldata data,
    bytes32 nonce
) public payable nonReentrant returns (bool ok, bytes memory retData);
```

### fundFutarchy

FUTARCHY


```solidity
function fundFutarchy(uint256 id, address token, uint256 amount) public payable nonReentrant;
```

### resolveFutarchyNo


```solidity
function resolveFutarchyNo(uint256 id) public;
```

### cashOutFutarchy


```solidity
function cashOutFutarchy(uint256 id, uint256 amount)
    public
    nonReentrant
    returns (uint256 payout);
```

### _resolveFutarchyYes


```solidity
function _resolveFutarchyYes(uint256 id) internal;
```

### _finalizeFutarchy


```solidity
function _finalizeFutarchy(uint256 id, FutarchyConfig storage F, uint8 winner) internal;
```

### setPermit


```solidity
function setPermit(
    uint8 op,
    address to,
    uint256 value,
    bytes calldata data,
    bytes32 nonce,
    address spender,
    uint256 count
) public payable onlyDAO;
```

### spendPermit


```solidity
function spendPermit(uint8 op, address to, uint256 value, bytes calldata data, bytes32 nonce)
    public
    payable
    nonReentrant
    returns (bool ok, bytes memory retData);
```

### setAllowance

ALLOWANCE


```solidity
function setAllowance(address spender, address token, uint256 amount) public payable onlyDAO;
```

### spendAllowance


```solidity
function spendAllowance(address token, uint256 amount) public nonReentrant;
```

### setSale


```solidity
function setSale(
    address payToken,
    uint256 pricePerShare,
    uint256 cap,
    bool minting,
    bool active,
    bool isLoot
) public payable onlyDAO;
```

### buyShares


```solidity
function buyShares(address payToken, uint256 shareAmount, uint256 maxPay)
    public
    payable
    nonReentrant;
```

### ragequit


```solidity
function ragequit(address[] calldata tokens, uint256 sharesToBurn, uint256 lootToBurn)
    public
    nonReentrant;
```

### getMessageCount


```solidity
function getMessageCount() public view returns (uint256);
```

### chat


```solidity
function chat(string calldata message) public payable;
```

### setQuorumBps


```solidity
function setQuorumBps(uint16 bps) public payable onlyDAO;
```

### setMinYesVotesAbsolute


```solidity
function setMinYesVotesAbsolute(uint256 v) public payable onlyDAO;
```

### setQuorumAbsolute


```solidity
function setQuorumAbsolute(uint256 v) public payable onlyDAO;
```

### setProposalTTL


```solidity
function setProposalTTL(uint64 s) public payable onlyDAO;
```

### setTimelockDelay


```solidity
function setTimelockDelay(uint64 s) public payable onlyDAO;
```

### setRagequittable


```solidity
function setRagequittable(bool on) public payable onlyDAO;
```

### setTransfersLocked


```solidity
function setTransfersLocked(bool sharesLocked, bool lootLocked) public payable onlyDAO;
```

### setProposalThreshold


```solidity
function setProposalThreshold(uint256 v) public payable onlyDAO;
```

### setRenderer


```solidity
function setRenderer(address r) public payable onlyDAO;
```

### setMetadata


```solidity
function setMetadata(string calldata n, string calldata s, string calldata uri)
    public
    payable
    onlyDAO;
```

### setAutoFutarchy

Configure automatic futarchy earmark per proposal:

param: 0=off; 1..10_000=BPS of snapshot supply; >10_000=absolute (18 dp),
cap: hard per-proposal maximum after param calculation (0 = no cap):


```solidity
function setAutoFutarchy(uint256 param, uint256 cap) public payable onlyDAO;
```

### setFutarchyRewardToken

Default reward token for futarchy pools:


```solidity
function setFutarchyRewardToken(address _rewardToken) public payable onlyDAO;
```

### bumpConfig

Governance "bump" to invalidate pre-bump proposal hashes:


```solidity
function bumpConfig() public payable onlyDAO;
```

### batchCalls

Governance batch external call helper:


```solidity
function batchCalls(Call[] calldata calls) public payable onlyDAO;
```

### multicall

Execute sequence of calls to this Majeur contract:


```solidity
function multicall(bytes[] calldata data) public returns (bytes[] memory results);
```

### onSharesChanged


```solidity
function onSharesChanged(address a) public payable;
```

### transfer


```solidity
function transfer(address receiver, uint256 id, uint256 amount) public returns (bool);
```

### transferFrom


```solidity
function transferFrom(address sender, address receiver, uint256 id, uint256 amount)
    public
    returns (bool);
```

### setOperator


```solidity
function setOperator(address operator, bool approved) public returns (bool);
```

### _mint6909


```solidity
function _mint6909(address to, uint256 id, uint256 amount) internal;
```

### _burn6909


```solidity
function _burn6909(address from, uint256 id, uint256 amount) internal;
```

### _receiptId


```solidity
function _receiptId(uint256 id, uint8 support) internal pure returns (uint256);
```

### _intentHashId


```solidity
function _intentHashId(uint8 op, address to, uint256 value, bytes calldata data, bytes32 nonce)
    internal
    view
    returns (uint256);
```

### _execute


```solidity
function _execute(uint8 op, address to, uint256 value, bytes calldata data)
    internal
    returns (bool ok, bytes memory retData);
```

### _payout


```solidity
function _payout(address token, address to, uint256 amount) internal;
```

### nonReentrant


```solidity
modifier nonReentrant() virtual;
```

### contractURI


```solidity
function contractURI() public view returns (string memory);
```

### tokenURI


```solidity
function tokenURI(uint256 id) public view returns (string memory);
```

### receive


```solidity
receive() external payable;
```

### onERC721Received


```solidity
function onERC721Received(address, address, uint256, bytes calldata)
    public
    pure
    returns (bytes4);
```

### onERC1155Received


```solidity
function onERC1155Received(address, address, uint256, uint256, bytes calldata)
    public
    pure
    returns (bytes4);
```

## Events
### Opened

```solidity
event Opened(uint256 indexed id, uint48 snapshotBlock, uint256 supplyAtSnapshot);
```

### Voted

```solidity
event Voted(uint256 indexed id, address indexed voter, uint8 support, uint256 weight);
```

### VoteCancelled

```solidity
event VoteCancelled(uint256 indexed id, address indexed voter, uint8 support, uint256 weight);
```

### ProposalCancelled

```solidity
event ProposalCancelled(uint256 indexed id, address indexed by);
```

### Queued

```solidity
event Queued(uint256 indexed id, uint64 when);
```

### Executed

```solidity
event Executed(uint256 indexed id, address indexed by, uint8 op, address to, uint256 value);
```

### PermitSet
PERMIT STATE


```solidity
event PermitSet(address spender, uint256 indexed id, uint256 newCount);
```

### PermitSpent

```solidity
event PermitSpent(uint256 indexed id, address indexed by, uint8 op, address to, uint256 value);
```

### SaleUpdated

```solidity
event SaleUpdated(
    address indexed payToken, uint256 price, uint256 cap, bool minting, bool active, bool isLoot
);
```

### SharesPurchased

```solidity
event SharesPurchased(
    address indexed buyer, address indexed payToken, uint256 shares, uint256 paid
);
```

### Message

```solidity
event Message(address indexed from, uint256 indexed index, string text);
```

### Transfer
ERC6909 STATE


```solidity
event Transfer(
    address caller, address indexed from, address indexed to, uint256 indexed id, uint256 amount
);
```

### FutarchyOpened

```solidity
event FutarchyOpened(uint256 indexed id, address indexed rewardToken);
```

### FutarchyFunded

```solidity
event FutarchyFunded(uint256 indexed id, address indexed from, uint256 amount);
```

### FutarchyResolved

```solidity
event FutarchyResolved(
    uint256 indexed id, uint8 winner, uint256 pool, uint256 finalSupply, uint256 payoutPerUnit
);
```

### FutarchyClaimed

```solidity
event FutarchyClaimed(
    uint256 indexed id, address indexed claimer, uint256 burned, uint256 payout
);
```

### OperatorSet

```solidity
event OperatorSet(address indexed owner, address indexed operator, bool approved);
```

## Errors
### NotOk

```solidity
error NotOk();
```

### Expired

```solidity
error Expired();
```

### TooEarly

```solidity
error TooEarly();
```

### Reentrancy

```solidity
error Reentrancy();
```

### AlreadyVoted

```solidity
error AlreadyVoted();
```

### LengthMismatch

```solidity
error LengthMismatch();
```

### AlreadyExecuted

```solidity
error AlreadyExecuted();
```

### Timelocked

```solidity
error Timelocked(uint64 untilWhen);
```

## Structs
### Tally

```solidity
struct Tally {
    uint96 forVotes;
    uint96 againstVotes;
    uint96 abstainVotes;
}
```

### Sale
SALE STATE


```solidity
struct Sale {
    uint256 pricePerShare; // in payToken units (wei for ETH)
    uint256 cap; // remaining shares (0 = unlimited)
    bool minting; // true=mint, false=transfer Moloch-held
    bool active;
    bool isLoot;
}
```

### FutarchyConfig

```solidity
struct FutarchyConfig {
    bool enabled; // futarchy pot exists for this proposal
    address rewardToken; // 0 = ETH, this = minted shares, 1007 = minted loot, shares/loot = local
    uint256 pool; // funded amount (ETH or share units)
    bool resolved; // set on resolution
    uint8 winner; // 1=YES (For), 0=NO (Against)
    uint256 finalWinningSupply;
    uint256 payoutPerUnit; // pool / finalWinningSupply (floor)
}
```

## Enums
### ProposalState

```solidity
enum ProposalState {
    Unopened,
    Active,
    Queued,
    Succeeded,
    Defeated,
    Expired,
    Executed
}
```

