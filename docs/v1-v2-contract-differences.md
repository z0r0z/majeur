# Majeur v1 vs v2 Contract Differences

This document details the differences between v1 and v2 of the Majeur (Moloch) contracts, intended for developers building dapps that need to support both versions.

## Commits That Changed v1 to v2

| Commit | Description | Key Change |
|--------|-------------|------------|
| `d4717aa` | Fix premature proposal resolution during voting period | Prevents vote-snipe exploits |
| `1b613cc` | Fix ragequit flash loan vulnerability | Adds 7-day ragequit timelock |
| `aafe5fc` | Add ragequitTimelock to ViewHelper | Exposes timelock in view helper |
| `f2e368e` | Add reverse pagination to ViewHelper | Adds `PaginationParams` struct, `reverseOrder` flags |
| `c06b759` | Add messageSenders mapping for on-chain chat | Stores sender address per message |
| `aff4b5f` | Expose implementation addresses via public getters | Adds `molochImpl`, `sharesImpl`, `badgesImpl`, `lootImpl` |
| `e42d14f` | Exclude DAO-held shares from quorum calculation | Prevents governance deadlocks when DAO holds treasury shares |
| `b30c227` | Unanimous consent early execution | 100% FOR votes bypass TTL and timelock |
| `d486f52` | Refactor Renderer into router + 5 sub-renderers | Splits monolith into independently deployable contracts |
| `2d18c28` | Pin Solidity 0.8.33, safe contractURI, idempotent deploys | ViewHelper resilience + compiler upgrade |
| `cbb8652` | Add governance events, NatSpec, and _ffs verification | Full event-driven observability for all setter + ragequit |

---

## Key Differences Table

| Feature | v1 | v2 |
|---------|----|----|
| **Ragequit** | Immediate | 7-day timelock after token acquisition |
| **Proposal state** | Can resolve during voting | Protected until TTL expires |
| **Unanimous consent** | Must wait for TTL + timelock | 100% FOR bypasses TTL and timelock |
| **Quorum calculation** | Uses total supply | Excludes DAO-held voting power |
| **DAO self-voting** | Possible via proposal execution | Blocked (reverts with `Unauthorized`) |
| **Chat messages** | Sender via events only | `messageSenders` mapping + ViewHelper |
| **Pagination** | Forward only | Forward + reverse ordering |
| **DAOGovConfig struct** | No ragequitTimelock field | Has `ragequitTimelock` field |
| **MessageView struct** | No sender field | Has `sender` field |
| **Impl addresses** | Internal visibility | Public getters on Summoner and Moloch |
| **Renderer** | Single monolith (~24KB) | Router + 5 sub-renderers (largest ~10KB) |
| **ViewHelper contractURI** | Direct call (reverts poison batch) | Safe wrapper (returns "" on failure) |
| **Governance events** | No setter/ragequit events | `ConfigUpdated` + 6 individual + `Ragequit` events |
| **Solidity version** | 0.8.30 | 0.8.33 |

---

## Contract Addresses

### v1 Contracts (Mainnet, Arbitrum, Base, etc.)
- **Summoner**: `0x0000000000330B8df9E3bc5E553074DA58eE9138`
- **ViewHelper**: `0x00000000006631040967E58e3430e4B77921a2db`
- **Renderer**: `0x000000000011C799980827F52d3137b4abD6E654`

### v2 Contracts (Sepolia + localhost fork)
- **Summoner**: `0x227a87bf254393c1559252C19050817ED5608777`
- **ViewHelper**: `0x512C15620F3f4eD0A632B3cFc5dfd31Aad871655`
- **Renderer**: `0x635E5BB4916C4D9C0E120e13bab63Be3867155f6`

### v2 Implementation Contracts
These are deployed by the Summoner and can be queried via public getters:
- **Moloch Impl**: `0x9a9da57b22DE850fFD0665dAcFfE42279406b333` (`summoner.molochImpl()`)
- **Shares Impl**: `0xC7581D1331023d4CfD011Cb2BfB54F5552818eBb` (`molochImpl.sharesImpl()`)
- **Badges Impl**: `0x7AB362323267E7E30B718216f30B336057B3De24` (`molochImpl.badgesImpl()`)
- **Loot Impl**: `0x18065b9fb48367416BDCCAe2Bf10dD39e3165060` (`molochImpl.lootImpl()`)

### v2 Test DAOs (Sepolia)
| Name | Address | Purpose |
|------|---------|---------|
| 40 messages | `0xadB86294698a5A21379B5E00f72B1f659348341C` | Chat testing, ETH share sale |
| All gov proposals | `0x9F870012cD88434F00D78513285D064A7A3100a1` | 24 proposal types, USDF loot sale |
| Various tributes | `0x0F3921Cc97960F591DbB834Bb4B9f6D370e8Cc3F` | Tribute offers, DAICO sale |
| DAICO Loot Sale | `0x364EAE5269809F386A16BFB5574E45797424D73a` | DAICO with tap, auto-futarchy |
| Full DAICO Test | `0xb6AF02286E63380d9F31AA4bf5041759b7CA0572` | Fast governance, ETH DAICO |

---

## New v2 Contract State Variables

### Moloch.sol

```solidity
// Ragequit timelock - default 7 days
uint64 public ragequitTimelock = 7 days;

// Message sender storage (indexed by message index)
mapping(uint256 => address) public messageSenders;
```

### Shares.sol / Loot.sol

```solidity
// Tracks when tokens were last acquired (transferred in or minted)
mapping(address => uint256) public lastAcquisitionTimestamp;
```

---

## New v2 Functions

### Summoner.sol

```solidity
/// @dev Public getter for the Moloch implementation address
function molochImpl() public view returns (Moloch);
```

### Moloch.sol

```solidity
/// @dev Public getters for token implementation addresses
function sharesImpl() public view returns (address);
function badgesImpl() public view returns (address);
function lootImpl() public view returns (address);

/// @dev Configure the ragequit delay period
/// @param s The timelock duration in seconds (0 to disable)
function setRagequitTimelock(uint64 s) public payable onlyDAO {
    ragequitTimelock = s;
}

/// @dev Get the sender of a chat message by index
/// @param index The message index
/// @return The sender's address
function messageSenders(uint256 index) public view returns (address);
```

### IMoloch Interface (ViewHelper)

```solidity
// New in v2
function ragequitTimelock() external view returns (uint64);
function messageSenders(uint256) external view returns (address);
function sharesImpl() external view returns (address);
function badgesImpl() external view returns (address);
function lootImpl() external view returns (address);
```

---

## New v2 Errors

```solidity
// Thrown when ragequit is attempted before timelock expires
error TooEarly();
```

---

## Changed Behavior: Ragequit

### v1 Ragequit
```solidity
// v1: Immediate ragequit, no timelock check
function ragequit(address[] calldata tokens, uint256 sharesToBurn, uint256 lootToBurn) public {
    // ... burn tokens and distribute treasury pro-rata
}
```

### v2 Ragequit
```solidity
// v2: Timelock check added
function ragequit(address[] calldata tokens, uint256 sharesToBurn, uint256 lootToBurn)
    public
    nonReentrant
{
    // ...

    // Timelock check: tokens must be held for ragequitTimelock before ragequit
    uint64 _ragequitTimelock = ragequitTimelock;
    if (sharesToBurn != 0 && block.timestamp < _shares.lastAcquisitionTimestamp(msg.sender) + _ragequitTimelock) {
        revert TooEarly();
    }
    if (lootToBurn != 0 && block.timestamp < _loot.lastAcquisitionTimestamp(msg.sender) + _ragequitTimelock) {
        revert TooEarly();
    }

    // ... burn tokens and distribute treasury pro-rata
}
```

---

## Changed Behavior: Proposal State

### v1 State Function
```solidity
// v1: Could return terminal states (Succeeded/Defeated) during voting period
function state(uint256 id) public view returns (ProposalState) {
    // ... evaluate votes immediately
}
```

### v2 State Function
```solidity
// v2: Guards against premature resolution, with unanimous consent exception
function state(uint256 id) public view returns (ProposalState) {
    // ...

    if (ttl != 0 && block.timestamp < t0 + ttl) {
        // Unanimous consent: 100% FOR votes allows early execution
        if (tallies[id].forVotes < supplySnapshot[id]) return ProposalState.Active;
        // Fall through to quorum/majority checks (which will trivially pass)
    }

    // Vote evaluation runs after TTL expires OR with unanimous consent
    // ...
}
```

---

## Changed Behavior: Unanimous Consent Early Execution

### v1 Execution
```solidity
// v1: Must always wait for TTL to expire, then wait for timelock
// Even if everyone votes YES immediately, still wait for full TTL + timelock
```

### v2 Execution
```solidity
// v2: 100% FOR votes bypass both TTL and timelock
function executeByVotes(...) {
    // ...

    // Unanimous consent bypasses timelock
    bool unanimous = tallies[id].forVotes == supplySnapshot[id] && supplySnapshot[id] != 0;

    if (!unanimous && timelockDelay != 0) {
        // Normal timelock logic applies for non-unanimous proposals
        if (queuedAt[id] == 0) {
            queuedAt[id] = uint64(block.timestamp);
            emit Queued(id, queuedAt[id]);
            return (true, "");
        }
        uint64 untilWhen = queuedAt[id] + timelockDelay;
        if (block.timestamp < untilWhen) revert Timelocked(untilWhen);
    }
    // Unanimous proposals execute immediately
}
```

**Why this is safe:**
- **No minority to protect**: If everyone agrees, there's no one who needs time to ragequit
- **Flash loan resistant**: Snapshot at block N-1 prevents instant token acquisition
- **Self-limiting**: As DAO grows, unanimous consent becomes naturally harder to achieve

**Use case:** Early-stage DAOs with few founders can move quickly when everyone agrees. A 2-person DAO with a 7-day TTL and 2-day timelock can now execute immediately if both vote YES.

**Edge cases:**
- `supplySnapshot = 0`: No early execution (prevents vacuous truth)
- Abstain votes: Don't count toward unanimous — must be explicit FOR votes
- 99% FOR: Still requires full TTL + timelock (not unanimous)

---

## Changed Behavior: Quorum Calculation

### v1 Quorum
```solidity
// v1: Quorum uses total supply (includes DAO-held shares)
function openProposal(uint256 id) public {
    // ...
    supply = _shares.getPastTotalSupply(snap);
    supplySnapshot[id] = supply;  // Total supply used for quorum denominator
}
```

**Problem:** When DAOs mint shares to their treasury (e.g., for DAICO sales), those shares inflate `totalSupply` but the DAO contract cannot vote. This creates governance deadlocks where members cannot reach quorum.

**Example (DAICO scenario):**
- Members: 100 shares (can vote)
- DAO treasury: 100,000 shares (cannot vote)
- Quorum 1% = 1,001 shares needed
- **Result: Permanent governance deadlock**

### v2 Quorum
```solidity
// v2: Quorum excludes DAO-held voting power
function openProposal(uint256 id) public {
    // ...
    supply = _shares.getPastTotalSupply(snap);
    if (supply == 0) revert TooEarly();

    // Exclude DAO's voting power from supply (can't vote, shouldn't inflate quorum)
    supply -= _shares.getPastVotes(address(this), snap);
    supplySnapshot[id] = supply;
}

function castVote(uint256 id, uint8 support) public {
    // ...
    if (msg.sender == address(this)) revert Unauthorized(); // DAO can't vote
    // ...
}
```

**Why `getPastVotes` instead of `balanceOf`:**
- Uses same snapshot block (N-1) as supply snapshot for consistency
- Captures both DAO's own shares AND any voting power delegated TO the DAO
- Both are unusable for voting, so both should be excluded

**Edge cases handled:**
- DAO has 0 shares: No change to behavior
- DAO has ALL shares: Effective supply = 0, quorum auto-passes (no one can vote anyway)
- Shares delegated TO the DAO: Correctly excluded from quorum denominator
- DAO tries to vote: Reverts with `Unauthorized()`

---

## Changed Behavior: DAO Self-Voting

### v1 Self-Voting
```solidity
// v1: No guard - DAO could vote on proposals via executeByVotes
function castVote(uint256 id, uint8 support) public {
    // No check for msg.sender == address(this)
    // ...
}
```

**Attack vector:** A malicious proposal could make the DAO vote on other proposals:
```solidity
// Malicious proposal: op=0, to=address(this), data=abi.encodeCall(castVote, (targetId, 1))
// Execution path: executeByVotes() → _execute() → to.call(data) → castVote()
// Result: DAO votes with its own shares (which shouldn't count)
```

### v2 Self-Voting
```solidity
// v2: Explicit guard prevents DAO from voting
function castVote(uint256 id, uint8 support) public {
    if (executed[id]) revert AlreadyExecuted();
    if (support > 2) revert NotOk();
    if (msg.sender == address(this)) revert Unauthorized(); // DAO can't vote
    // ...
}
```

With v2, any attempt for the DAO to vote (directly or via proposal execution) reverts with `Unauthorized()`.

---

## Updated Structs

### PaginationParams (New in v2 ViewHelper)

```solidity
/// @notice Parameters for paginated queries with optional reverse ordering.
/// @dev Use this struct to avoid "stack too deep" errors in complex view functions.
struct PaginationParams {
    uint256 proposalStart;
    uint256 proposalCount;
    uint256 messageStart;
    uint256 messageCount;
    bool reverseProposals;    // NEW: fetch from newest first
    bool reverseMessages;     // NEW: fetch from newest first
}
```

### MessageView (Updated in v2)

```solidity
// v1
struct MessageView {
    uint256 index;
    string text;
}

// v2
struct MessageView {
    uint256 index;
    address sender;  // NEW: message sender address
    string text;
}
```

### DAOGovConfig (Updated in v2)

```solidity
// v1
struct DAOGovConfig {
    uint96 proposalThreshold;
    uint96 minYesVotesAbsolute;
    uint96 quorumAbsolute;
    uint64 proposalTTL;
    uint64 timelockDelay;
    uint16 quorumBps;
    bool ragequittable;
    uint256 autoFutarchyParam;
    uint256 autoFutarchyCap;
    address rewardToken;
}

// v2
struct DAOGovConfig {
    uint96 proposalThreshold;
    uint96 minYesVotesAbsolute;
    uint96 quorumAbsolute;
    uint64 proposalTTL;
    uint64 timelockDelay;
    uint16 quorumBps;
    bool ragequittable;
    uint64 ragequitTimelock;  // NEW: ragequit delay period
    uint256 autoFutarchyParam;
    uint256 autoFutarchyCap;
    address rewardToken;
}
```

---

## Changed ViewHelper Function Signatures

### getUserDAOsFullState

```solidity
// v1
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

// v2
function getUserDAOsFullState(
    address user,
    uint256 daoStart,
    uint256 daoCount,
    address[] calldata treasuryTokens,
    PaginationParams calldata pagination  // NEW: struct with reverse flags
) public view returns (UserDAOLens[] memory out);
```

### getDAOsFullState

```solidity
// v1
function getDAOsFullState(
    uint256 daoStart,
    uint256 daoCount,
    uint256 proposalStart,
    uint256 proposalCount,
    uint256 messageStart,
    uint256 messageCount,
    address[] calldata treasuryTokens
) public view returns (DAOLens[] memory out);

// v2
function getDAOsFullState(
    uint256 daoStart,
    uint256 daoCount,
    uint256 proposalStart,
    uint256 proposalCount,
    uint256 messageStart,
    uint256 messageCount,
    address[] calldata treasuryTokens,
    bool reverseProposals,   // NEW
    bool reverseMessages     // NEW
) public view returns (DAOLens[] memory out);
```

### getDAOFullState

```solidity
// v1
function getDAOFullState(
    address dao,
    uint256 proposalStart,
    uint256 proposalCount,
    uint256 messageStart,
    uint256 messageCount,
    address[] calldata treasuryTokens
) public view returns (DAOLens memory out);

// v2
function getDAOFullState(
    address dao,
    uint256 proposalStart,
    uint256 proposalCount,
    uint256 messageStart,
    uint256 messageCount,
    address[] calldata treasuryTokens,
    bool reverseProposals,   // NEW
    bool reverseMessages     // NEW
) public view returns (DAOLens memory out);
```

### getDAOMessages

```solidity
// v1
function getDAOMessages(
    address dao,
    uint256 start,
    uint256 count
) public view returns (MessageView[] memory out);

// v2
function getDAOMessages(
    address dao,
    uint256 start,
    uint256 count,
    bool reverseOrder  // NEW
) public view returns (MessageView[] memory out);
```

---

## Changed Architecture: Renderer

### v1 Renderer
Single monolithic contract containing all SVG rendering logic (~24KB, near the EVM size limit):
```
Renderer (monolith)
├── daoContractURI()   — DUNA covenant card
├── daoTokenURI()      — proposal / receipt / permit card (routing + rendering)
├── badgeTokenURI()    — member badge card
└── Display library    — SVG/string helpers (inlined)
```

### v2 Renderer
Thin router with 5 immutable sub-renderer addresses. Each sub-renderer is an independent contract:
```
Renderer (router, 1.8KB)
├── daoContractURI()  → CovenantRenderer.render()   (10KB)
├── daoTokenURI()     → routing logic, then:
│   ├── receipt?      → ReceiptRenderer.render()     (8.4KB)
│   ├── permit?       → PermitRenderer.render()      (4.8KB)
│   └── default       → ProposalRenderer.render()    (6.4KB)
└── badgeTokenURI()   → BadgeRenderer.render()       (6.6KB)
```

**External interface is identical** — `daoContractURI`, `daoTokenURI`, and `badgeTokenURI` have the same signatures. Moloch.sol requires no changes; DAOs upgrade via the existing `setRenderer(address)` governance function.

### v2 Renderer Sub-Contracts (Sepolia + localhost)
| Contract | Address |
|----------|---------|
| CovenantRenderer | `0xf97237D19046e8F9dde54E0d01AE57CD91F1FD84` |
| ProposalRenderer | `0x355EdB155cE76B34C2a379B594d3cBba9C84C76e` |
| ReceiptRenderer | `0xdd8389B1176c94e80900d2d1008cFC0C597Bc14c` |
| PermitRenderer | `0x1a561EdE77d34bA0bC87508Fd613f1e55d3Ba7f6` |
| BadgeRenderer | `0x1C19B3b6417e56e2943eCBB4f0243506371048c2` |

### Constructor Change
```solidity
// v1: no constructor arguments
new Renderer();

// v2: 5 immutable sub-renderer addresses
new Renderer(covenant, proposal, receipt, permit, badge);
```

### Deployment
All 6 contracts (5 sub-renderers + router) are deployed via CREATE2 with fixed salts for deterministic addresses across chains. See `script/DeployRenderer.s.sol`.

---

## Changed Behavior: ViewHelper Safe contractURI

### v1 ViewHelper
```solidity
// v1: Direct call to contractURI() — reverts if renderer is invalid
function _getMeta(...) internal view returns (DAOMeta memory meta) {
    IMoloch M = IMoloch(dao);
    meta.contractURI = M.contractURI(); // Calls Renderer externally — can revert
    // ...
}
```

**Problem:** `contractURI()` on Moloch delegates to `IMajeurRenderer(renderer).daoContractURI(this)`. If a DAO's renderer address is invalid (zero, EOA, or broken contract), the call reverts and poisons the entire batch query. One bad DAO in `getUserDAOsFullState()` kills the response for all DAOs.

### v2 ViewHelper
```solidity
// v2: Safe wrapper returns "" on failure — batch queries never revert
function _safeContractURI(address dao) internal view returns (string memory) {
    (bool success, bytes memory data) =
        dao.staticcall(abi.encodeWithSelector(IMoloch.contractURI.selector));
    if (success && data.length >= 64) {
        return abi.decode(data, (string));
    }
    return "";
}
```

All 3 call sites (`getUserDAOs`, `_buildDAOFullState`, `_getMeta`) use `_safeContractURI()`. This follows the same pattern as the existing `_safeName()`, `_safeSymbol()`, `_safeLPConfig()` and other safe wrappers in the ViewHelper.

**Why `contractURI` is uniquely dangerous:** All other ViewHelper calls (`name(0)`, `symbol(0)`, `shares()`, etc.) are direct storage reads on the Moloch contract itself — they cannot revert. But `contractURI()` delegates to an external Renderer contract that may not exist or may be broken.

---

## Governance Configuration Events (v2)

v2 adds comprehensive event emissions for all governance parameter changes and ragequit, enabling full observability for indexers and off-chain monitoring.

### Generic Config Event

```solidity
event ConfigUpdated(bytes32 indexed param, uint256 oldValue, uint256 newValue);
```

Emitted by the 8 scalar governance setters. The `param` field is an indexed `bytes32` string literal, filterable by topic1:

| Setter | `param` value |
|--------|--------------|
| `setQuorumBps(uint16)` | `"quorumBps"` |
| `setMinYesVotesAbsolute(uint96)` | `"minYesVotesAbsolute"` |
| `setQuorumAbsolute(uint96)` | `"quorumAbsolute"` |
| `setProposalTTL(uint64)` | `"proposalTTL"` |
| `setTimelockDelay(uint64)` | `"timelockDelay"` |
| `setRagequittable(bool)` | `"ragequittable"` (bool→uint: 0/1) |
| `setRagequitTimelock(uint64)` | `"ragequitTimelock"` |
| `setProposalThreshold(uint96)` | `"proposalThreshold"` |
| `bumpConfig()` | `"config"` |

### Individual Setter Events

```solidity
event AllowanceSet(address indexed spender, address indexed token, uint256 amount);
event TransfersLockSet(bool sharesLocked, bool lootLocked);
event MetadataSet(string name, string symbol, string uri);
event RendererSet(address indexed oldRenderer, address indexed newRenderer);
event AutoFutarchySet(uint256 param, uint256 cap);
event FutarchyRewardTokenSet(address indexed oldToken, address indexed newToken);
```

### Ragequit Event

```solidity
event Ragequit(address indexed member, uint256 sharesBurned, uint256 lootBurned, address[] tokens);
```

Emitted at the end of `ragequit()` after all token payouts complete.

### v1 vs v2 Comparison

v1 had **no events** for governance parameter changes or ragequit. Indexers had to poll storage or parse transaction calldata. v2 provides full event-driven observability for all state-changing governance functions.

---

## Code Examples: Supporting Both Versions

### 1. Version Detection

```javascript
// Contract addresses by version
const CONTRACTS = {
  v1: {
    summoner: '0x0000000000330B8df9E3bc5E553074DA58eE9138',
    viewHelper: '0x00000000006631040967E58e3430e4B77921a2db',
    renderer: '0x000000000011C799980827F52d3137b4abD6E654'
  },
  v2: {
    summoner: '0x227a87bf254393c1559252C19050817ED5608777',
    viewHelper: '0x512C15620F3f4eD0A632B3cFc5dfd31Aad871655',
    renderer: '0x635E5BB4916C4D9C0E120e13bab63Be3867155f6'
  }
};

// Detect version by checking if ragequitTimelock exists on DAO
async function detectVersion(daoAddress, provider) {
  const molochInterface = new ethers.Interface([
    'function ragequitTimelock() view returns (uint64)'
  ]);

  try {
    const dao = new ethers.Contract(daoAddress, molochInterface, provider);
    await dao.ragequitTimelock();
    return 'v2';
  } catch {
    return 'v1';
  }
}

// Or detect by summoner address
function getVersionBySummoner(summonerAddress) {
  if (summonerAddress.toLowerCase() === CONTRACTS.v1.summoner.toLowerCase()) {
    return 'v1';
  }
  if (summonerAddress.toLowerCase() === CONTRACTS.v2.summoner.toLowerCase()) {
    return 'v2';
  }
  return 'unknown';
}
```

### 2. Conditional ABI Selection

```javascript
// v1 ViewHelper ABI (partial)
const VIEW_HELPER_V1_ABI = [
  'function getDAOFullState(address dao, uint256 proposalStart, uint256 proposalCount, uint256 messageStart, uint256 messageCount, address[] treasuryTokens) view returns (tuple)',
  'function getDAOMessages(address dao, uint256 start, uint256 count) view returns (tuple[])'
];

// v2 ViewHelper ABI (partial)
const VIEW_HELPER_V2_ABI = [
  'function getDAOFullState(address dao, uint256 proposalStart, uint256 proposalCount, uint256 messageStart, uint256 messageCount, address[] treasuryTokens, bool reverseProposals, bool reverseMessages) view returns (tuple)',
  'function getDAOMessages(address dao, uint256 start, uint256 count, bool reverseOrder) view returns (tuple[])'
];

// v2 MessageView includes sender
const MESSAGE_VIEW_V2 = 'tuple(uint256 index, address sender, string text)[]';
const MESSAGE_VIEW_V1 = 'tuple(uint256 index, string text)[]';

function getViewHelperContract(version, provider) {
  const address = version === 'v2'
    ? CONTRACTS.v2.viewHelper
    : CONTRACTS.v1.viewHelper;
  const abi = version === 'v2'
    ? VIEW_HELPER_V2_ABI
    : VIEW_HELPER_V1_ABI;

  return new ethers.Contract(address, abi, provider);
}
```

### 3. Conditional Parameter Passing

```javascript
async function fetchDAOState(daoAddress, version, provider) {
  const viewHelper = getViewHelperContract(version, provider);

  const proposalStart = 0;
  const proposalCount = 10;
  const messageStart = 0;
  const messageCount = 50;
  const treasuryTokens = [ethers.ZeroAddress]; // ETH

  if (version === 'v2') {
    // v2: Pass reverse ordering flags
    return viewHelper.getDAOFullState(
      daoAddress,
      proposalStart,
      proposalCount,
      messageStart,
      messageCount,
      treasuryTokens,
      true,  // reverseProposals - get newest first
      true   // reverseMessages - get newest first
    );
  } else {
    // v1: No reverse flags
    return viewHelper.getDAOFullState(
      daoAddress,
      proposalStart,
      proposalCount,
      messageStart,
      messageCount,
      treasuryTokens
    );
  }
}

async function fetchMessages(daoAddress, version, provider) {
  const viewHelper = getViewHelperContract(version, provider);

  if (version === 'v2') {
    // v2: Messages include sender, support reverse ordering
    const messages = await viewHelper.getDAOMessages(
      daoAddress,
      0,     // start
      100,   // count
      true   // reverseOrder - get newest first
    );
    // messages[i].sender is available
    return messages;
  } else {
    // v1: No sender field, no reverse ordering
    const messages = await viewHelper.getDAOMessages(
      daoAddress,
      0,
      100
    );
    // For v1, you must fetch sender from events
    return messages;
  }
}
```

### 4. Handling Ragequit Timelock

```javascript
async function checkRagequitEligibility(daoAddress, userAddress, version, provider) {
  if (version === 'v1') {
    // v1: No timelock, always eligible (if ragequittable)
    return { eligible: true, waitTime: 0 };
  }

  // v2: Check timelock
  const molochAbi = [
    'function ragequitTimelock() view returns (uint64)',
    'function shares() view returns (address)',
    'function loot() view returns (address)'
  ];
  const tokenAbi = [
    'function lastAcquisitionTimestamp(address) view returns (uint256)',
    'function balanceOf(address) view returns (uint256)'
  ];

  const dao = new ethers.Contract(daoAddress, molochAbi, provider);
  const [timelockDuration, sharesAddr, lootAddr] = await Promise.all([
    dao.ragequitTimelock(),
    dao.shares(),
    dao.loot()
  ]);

  const shares = new ethers.Contract(sharesAddr, tokenAbi, provider);
  const loot = new ethers.Contract(lootAddr, tokenAbi, provider);

  const [sharesBalance, lootBalance, sharesTimestamp, lootTimestamp] = await Promise.all([
    shares.balanceOf(userAddress),
    loot.balanceOf(userAddress),
    shares.lastAcquisitionTimestamp(userAddress),
    loot.lastAcquisitionTimestamp(userAddress)
  ]);

  const now = Math.floor(Date.now() / 1000);
  let waitTime = 0;

  if (sharesBalance > 0n) {
    const sharesUnlockTime = Number(sharesTimestamp) + Number(timelockDuration);
    if (now < sharesUnlockTime) {
      waitTime = Math.max(waitTime, sharesUnlockTime - now);
    }
  }

  if (lootBalance > 0n) {
    const lootUnlockTime = Number(lootTimestamp) + Number(timelockDuration);
    if (now < lootUnlockTime) {
      waitTime = Math.max(waitTime, lootUnlockTime - now);
    }
  }

  return {
    eligible: waitTime === 0,
    waitTime,
    timelockDuration: Number(timelockDuration)
  };
}
```

### 5. Version-Agnostic Message Fetching with Sender

```javascript
async function fetchMessagesWithSenders(daoAddress, version, provider) {
  const viewHelper = getViewHelperContract(version, provider);

  if (version === 'v2') {
    // v2: Sender included in response
    const messages = await viewHelper.getDAOMessages(daoAddress, 0, 100, true);
    return messages.map(m => ({
      index: m.index,
      sender: m.sender,
      text: m.text
    }));
  } else {
    // v1: Must fetch senders from Message events
    const messages = await viewHelper.getDAOMessages(daoAddress, 0, 100);

    // Fetch senders via events (expensive!)
    const molochAbi = ['event Message(address indexed from, uint256 indexed index, string text)'];
    const dao = new ethers.Contract(daoAddress, molochAbi, provider);

    const filter = dao.filters.Message();
    const events = await dao.queryFilter(filter);

    const sendersByIndex = {};
    for (const event of events) {
      sendersByIndex[event.args.index.toString()] = event.args.from;
    }

    return messages.map(m => ({
      index: m.index,
      sender: sendersByIndex[m.index.toString()] || ethers.ZeroAddress,
      text: m.text
    }));
  }
}
```

### 6. Fetching Implementation Addresses (v2 only)

```javascript
async function getImplementationAddresses(summonerAddress, provider) {
  const summonerAbi = [
    'function molochImpl() view returns (address)'
  ];
  const molochAbi = [
    'function sharesImpl() view returns (address)',
    'function badgesImpl() view returns (address)',
    'function lootImpl() view returns (address)'
  ];

  const summoner = new ethers.Contract(summonerAddress, summonerAbi, provider);
  const molochImplAddr = await summoner.molochImpl();

  const molochImpl = new ethers.Contract(molochImplAddr, molochAbi, provider);
  const [sharesImpl, badgesImpl, lootImpl] = await Promise.all([
    molochImpl.sharesImpl(),
    molochImpl.badgesImpl(),
    molochImpl.lootImpl()
  ]);

  return {
    molochImpl: molochImplAddr,
    sharesImpl,
    badgesImpl,
    lootImpl
  };
}

// Usage
const impls = await getImplementationAddresses(CONTRACTS.v2.summoner, provider);
console.log('Moloch impl:', impls.molochImpl);
console.log('Shares impl:', impls.sharesImpl);
console.log('Badges impl:', impls.badgesImpl);
console.log('Loot impl:', impls.lootImpl);
```

---

## Migration Considerations

### For DAOs
- Existing v1 DAOs continue to work normally
- New DAOs created by v2 Summoner have ragequit timelock enabled by default (7 days)
- DAOs can disable timelock by calling `setRagequitTimelock(0)` via governance
- DAOs can upgrade to the v2 Renderer via `setRenderer(0x635E5BB4916C4D9C0E120e13bab63Be3867155f6)` governance proposal — no ABI change, SVG output is identical

### For Dapps
1. **Check which ViewHelper to use** based on which Summoner created the DAO
2. **Update ABI definitions** to include new parameters
3. **Handle MessageView.sender** being undefined for v1 (fetch from events if needed)
4. **Display ragequit timelock info** for v2 DAOs
5. **Use reverse pagination** for better UX when fetching recent proposals/messages
6. **Use public impl getters** (v2) to discover implementation addresses programmatically
7. **Renderer is transparent** — dapps call `contractURI()` / `tokenURI()` on the DAO, which delegates to the Renderer internally; no dapp changes needed for the Renderer upgrade

### Gas Considerations
- v2 `chat()` costs ~20k more gas due to storing sender address
- Token transfers track `lastAcquisitionTimestamp` (minimal gas impact)
- v2 Renderer adds cross-contract call overhead (~2.6k gas per `CALL`) for routing to sub-renderers; negligible since these are view-only functions

---

## Security Notes

### Ragequit Flash Loan Protection (v2)
The 7-day timelock prevents the following attack:
1. Attacker flash-loans DAO shares when treasury has unexpected value spike
2. Immediately ragequits to extract pro-rata treasury value
3. Repays flash loan, keeps profit

With v2, the attacker must hold shares for 7 days before ragequiting, giving market time to reprice shares.

### Proposal State Protection (v2)
The proposal state guard prevents:
1. **No-vote snipe**: Vote AGAINST, immediately call `resolveFutarchyNo()` to drain futarchy pool
2. **Yes-vote snipe**: Vote FOR, immediately execute malicious proposal

With v2, proposals remain `Active` until TTL expires, preventing premature resolution.

### Quorum Deadlock Prevention (v2)
The quorum exclusion prevents governance deadlocks when DAOs hold treasury shares:

**Problem scenario:**
- DAO mints 100,000 shares to treasury for DAICO sale
- Members hold only 100 shares
- Quorum at 1% requires 1,001 votes
- Members can never reach quorum → permanent deadlock

**Solution:** v2 subtracts the DAO's voting power from `supplySnapshot` when proposals open. This ensures quorum is calculated against *votable* supply, not *total* supply.

### DAO Self-Voting Prevention (v2)
The `castVote()` guard prevents the DAO from voting on its own proposals:

**Attack vector (v1):**
```solidity
// Malicious proposal makes DAO vote on another proposal
executeByVotes(0, address(this), 0, abi.encodeCall(castVote, (targetId, 1)), nonce)
```

With v2, any `castVote()` call where `msg.sender == address(this)` reverts with `Unauthorized()`, closing this attack vector.

### Batch Query Poisoning Prevention (v2)
The `_safeContractURI()` wrapper prevents a single DAO with an invalid renderer from breaking batch queries:

**Attack surface (v1):**
- A DAO sets its renderer to `address(0)` or a broken contract via `setRenderer()`
- Any `getUserDAOsFullState()` call that includes this DAO reverts entirely
- All other DAOs in the batch become unreachable

**Mitigation (v2):** `staticcall` + success check returns `""` on failure. The batch completes, and the bad DAO simply has an empty `contractURI`. This is the only external delegation in ViewHelper batch queries — all other calls are direct storage reads that cannot revert.

### Unanimous Consent Early Execution (v2)
The unanimous consent feature allows 100% FOR votes to bypass both TTL and timelock:

**Why this is safe:**
- **No minority to protect**: Unanimous means everyone agreed — no one needs ragequit time
- **Flash loan resistant**: Snapshot at block N-1 already prevents vote manipulation
- **Self-limiting**: As DAO grows, achieving unanimity becomes exponentially harder

**Guards against abuse:**
- `supplySnapshot != 0` required — can't use on zero-supply proposals
- Must be explicit FOR votes — abstain doesn't count toward unanimous
- Still requires quorum (trivially met with 100% participation)
