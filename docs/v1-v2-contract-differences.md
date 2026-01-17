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

---

## Key Differences Table

| Feature | v1 | v2 |
|---------|----|----|
| **Ragequit** | Immediate | 7-day timelock after token acquisition |
| **Proposal state** | Can resolve during voting | Protected until TTL expires |
| **Chat messages** | Sender via events only | `messageSenders` mapping + ViewHelper |
| **Pagination** | Forward only | Forward + reverse ordering |
| **DAOGovConfig struct** | No ragequitTimelock field | Has `ragequitTimelock` field |
| **MessageView struct** | No sender field | Has `sender` field |
| **Impl addresses** | Internal visibility | Public getters on Summoner and Moloch |

---

## Contract Addresses

### v1 Contracts
- **Summoner**: `0x0000000000330B8df9E3bc5E553074DA58eE9138`
- **ViewHelper**: `0x00000000006631040967E58e3430e4B77921a2db`

### v2 Contracts
- **Summoner**: `0xC1fE5F7163A3fe20b40f0410Dbdea1D0e4AE0d2A`
- **ViewHelper**: `0x851D78aeE76329A0e8E0B8896214976A4059B37c`

### v2 Implementation Contracts
These are deployed by the Summoner and can be queried via public getters:
- **Moloch Impl**: `0xAFB72C54658f7332f695EbFfd9797C4eC1DAC863` (`summoner.molochImpl()`)
- **Shares Impl**: `0x50621b4d32F91e9F2d38c7E498F45D0A8b79444E` (`molochImpl.sharesImpl()`)
- **Badges Impl**: `0xF376f0066084a4b1739FC784D53b2aaC90dC173d` (`molochImpl.badgesImpl()`)
- **Loot Impl**: `0x8af18386Bff7fD3549c6c8520CB86F271CdA6999` (`molochImpl.lootImpl()`)

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
// v2: Guards against premature resolution during voting period
function state(uint256 id) public view returns (ProposalState) {
    // ...

    // While the voting window is open, the proposal is ALWAYS Active.
    // This prevents both "No-vote" pot snipes and "Yes-vote" treasury snipes.
    if (ttl != 0 && block.timestamp < t0 + ttl) return ProposalState.Active;

    // Vote evaluation only runs after TTL expires
    // ...
}
```

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

## Code Examples: Supporting Both Versions

### 1. Version Detection

```javascript
// Contract addresses by version
const CONTRACTS = {
  v1: {
    summoner: '0x0000000000330B8df9E3bc5E553074DA58eE9138',
    viewHelper: '0x00000000006631040967E58e3430e4B77921a2db'
  },
  v2: {
    summoner: '0xC1fE5F7163A3fe20b40f0410Dbdea1D0e4AE0d2A',
    viewHelper: '0x851D78aeE76329A0e8E0B8896214976A4059B37c'
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

### For Dapps
1. **Check which ViewHelper to use** based on which Summoner created the DAO
2. **Update ABI definitions** to include new parameters
3. **Handle MessageView.sender** being undefined for v1 (fetch from events if needed)
4. **Display ragequit timelock info** for v2 DAOs
5. **Use reverse pagination** for better UX when fetching recent proposals/messages
6. **Use public impl getters** (v2) to discover implementation addresses programmatically

### Gas Considerations
- v2 `chat()` costs ~20k more gas due to storing sender address
- Token transfers track `lastAcquisitionTimestamp` (minimal gas impact)

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
