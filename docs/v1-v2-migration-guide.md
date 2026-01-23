# Majeur v1 → v2 Migration Guide

This guide helps developers **safely add v2 support to the existing v1 dapp** without introducing regressions.

---

## Before Modifying Code

### Existing Infrastructure

The dapp already has version-switching infrastructure in place:

```javascript
// These already exist - USE THEM, don't recreate
const currentContractVersion = localStorage.getItem('contractVersion') || 'v1';

const CONTRACT_VERSIONS = {
  v1: {
    summoner: '0x0000000000330B8df9E3bc5E553074DA58eE9138',
    viewHelper: '0x00000000006631040967E58e3430e4B77921a2db',
    tribute: '0x000000000066524fcf78Dc1E41E9D525d9ea73D0',
    daico: '0x000000000033e92DB97B4B3beCD2c255126C60aC'
  },
  v2: {
    summoner: '0xdB9aDc369424f08bBd2300571801A0ADAD0B4410',
    viewHelper: '0xe4022b04c55ca03ED91B0B666015bA29437B7026',
    tribute: '0x000000000066524fcf78Dc1E41E9D525d9ea73D0',  // same
    daico: '0x000000000033e92DB97B4B3beCD2c255126C60aC'    // same
  }
};

// Getter functions - use these throughout
function getSummonerAddress() { return CONTRACT_VERSIONS[currentContractVersion].summoner; }
function getViewHelperAddress() { return CONTRACT_VERSIONS[currentContractVersion].viewHelper; }
function getTributeAddress() { return CONTRACT_VERSIONS[currentContractVersion].tribute; }
function getDaicoAddress() { return CONTRACT_VERSIONS[currentContractVersion].daico; }

// ABI selection
function getViewHelperABI() {
  return currentContractVersion === 'v1' ? VIEW_HELPER_ABI_V1 : VIEW_HELPER_ABI_V2;
}
```

### Network Constraints

| Version | Available Networks |
|---------|-------------------|
| v1 | Mainnet, Sepolia, Arbitrum, Base, etc. |
| v2 | **localhost only** (Sepolia-forking anvil) |

When user selects v2, the dapp auto-switches to localhost.

---

## Version Detection

You can detect which contract version a DAO is running in several ways:

### Option 1: User Selection (Recommended for Dapps)
```javascript
const currentContractVersion = localStorage.getItem('contractVersion') || 'v1';
```
Let users explicitly choose which version they want to interact with.

### Option 2: Check `ragequitTimelock` on DAO
```javascript
// v2 DAOs have ragequitTimelock field in DAOGovConfig
// v1 DAOs return undefined for this field
async function detectVersion(daoAddress) {
  try {
    // Try v2 ViewHelper first
    const viewHelper = new ethers.Contract(V2_VIEW_HELPER, VIEW_HELPER_ABI_V2, provider);
    const state = await viewHelper.getDAOFullState(daoAddress, 0, 0, 0, 0, [], false, false);
    // If ragequitTimelock exists and is a valid number, it's v2
    if (state.gov.ragequitTimelock !== undefined) {
      return 'v2';
    }
  } catch (e) {
    // v2 call failed, likely v1
  }
  return 'v1';
}
```

### Option 3: Check Contract Bytecode
```javascript
// Different Summoner addresses have different bytecode
const code = await provider.getCode(SUMMONER_ADDRESS);
const isV2 = code.includes('specificV2Signature'); // implementation-specific
```

---

## What Needs Version Branching

Not everything needs branching. Here's what does and doesn't:

| Area | Needs branching? | Why |
|------|-----------------|-----|
| ViewHelper calls | **YES** | Different function signatures, different return types |
| Message sender display | **YES** | v1: fetch from events, v2: use `message.sender` |
| Ragequit UI | **YES** | v2 has timelock to display |
| DAOGovConfig parsing | **YES** | v2 has extra `ragequitTimelock` field |
| Moloch direct calls | Mostly no | Core functions unchanged |
| Tribute, DAICO calls | No | Same contracts both versions |
| Wallet connection | No | Unchanged |
| Network switching | No | Unchanged |

---

## Key Differences Summary

| Feature | v1 | v2 |
|---------|----|----|
| **Ragequit** | Immediate | 7-day timelock after token acquisition |
| **Proposal state** | Can resolve during voting | Protected until TTL expires |
| **Chat messages** | Sender via events only | `messageSenders` mapping on-chain |
| **Pagination** | Forward only | Supports `reverseOrder` for newest-first |
| **MessageView struct** | `{index, text}` | `{index, sender, text}` |
| **DAOGovConfig struct** | No ragequitTimelock | Has `ragequitTimelock` field |
| **Impl addresses** | Internal (not exposed) | Public getters: `molochImpl`, `sharesImpl`, etc. |

---

## Common Pitfalls (Breaking v1 When Adding v2)

### ❌ Pitfall 1: Using v2 ABI for v1 ViewHelper

```javascript
// WRONG - breaks v1
const messages = await viewHelper.getDAOMessages(daoAddress, 0, 50, true);
// v1 ViewHelper doesn't accept 4th parameter → call fails

// CORRECT
if (currentContractVersion === 'v2') {
  messages = await viewHelper.getDAOMessages(daoAddress, 0, 50, true);
} else {
  messages = await viewHelper.getDAOMessages(daoAddress, 0, 50);
}
```

### ❌ Pitfall 2: Assuming `message.sender` Exists

```javascript
// WRONG - breaks v1
const senderDisplay = message.sender.slice(0, 10);
// v1 MessageView has no sender field → TypeError

// CORRECT
const senderDisplay = message.sender
  ? message.sender.slice(0, 10)
  : null; // Handle missing sender gracefully
```

### ❌ Pitfall 3: Assuming `gov.ragequitTimelock` Exists

```javascript
// WRONG - breaks v1
const timelock = Number(daoState.gov.ragequitTimelock);
// v1 DAOGovConfig has no ragequitTimelock → undefined → NaN

// CORRECT
const timelock = daoState.gov.ragequitTimelock
  ? Number(daoState.gov.ragequitTimelock)
  : 0;

// Or check version first
if (currentContractVersion === 'v2') {
  // show timelock UI
}
```

### ❌ Pitfall 4: Changing Shared Code Without Version Check

```javascript
// WRONG - modifying a function used everywhere
function fetchDAOState(dao) {
  return viewHelper.getDAOFullState(dao, 0, 10, 0, 50, [], true, true);
  // Now ALL v1 calls fail
}

// CORRECT - add version check, keep v1 behavior as default
function fetchDAOState(dao) {
  if (currentContractVersion === 'v2') {
    return viewHelper.getDAOFullState(dao, 0, 10, 0, 50, [], true, true);
  }
  return viewHelper.getDAOFullState(dao, 0, 10, 0, 50, []);
}
```

### ❌ Pitfall 5: Forgetting to Update ABI Constants

```javascript
// WRONG - adding v2 params but not updating ABI
// If VIEW_HELPER_ABI doesn't include the v2 signature, ethers.js
// will use the old signature and ignore extra params silently,
// or fail to decode the response correctly.

// CORRECT - ensure VIEW_HELPER_ABI_V2 has the full v2 signatures
// with all parameters AND correct return tuple definitions
```

---

## Safe Modification Patterns

### Pattern 1: Version-First Check (Preferred)

```javascript
// Best for features that are completely different between versions
if (currentContractVersion === 'v2') {
  // v2-specific implementation
  const messages = await viewHelper.getDAOMessages(dao, 0, 50, true);
  renderMessagesWithSenders(messages);
} else {
  // v1 implementation (existing code, unchanged)
  const messages = await viewHelper.getDAOMessages(dao, 0, 50);
  renderMessagesWithoutSenders(messages);
}
```

### Pattern 2: Graceful Degradation (For Optional Features)

```javascript
// Best for features that enhance v2 but aren't critical
const ragequitTimelock = daoState.gov.ragequitTimelock ?? 0;
if (ragequitTimelock > 0) {
  showTimelockWarning(ragequitTimelock);
}
// v1: ragequitTimelock is undefined → 0 → no warning shown
// v2: ragequitTimelock exists → warning shown if non-zero
```

### Pattern 3: Wrapper Functions (For Repeated Patterns)

```javascript
// Create version-aware wrappers for common operations
async function getDAOMessagesCompat(viewHelper, dao, start, count, reverse = true) {
  if (currentContractVersion === 'v2') {
    return viewHelper.getDAOMessages(dao, start, count, reverse);
  }
  return viewHelper.getDAOMessages(dao, start, count);
}

// Now all callers just use the wrapper
const messages = await getDAOMessagesCompat(viewHelper, daoAddress, 0, 50);
```

### Pattern 4: Feature Flags for v2-Only UI

```javascript
// For entirely new v2 features, gate the entire UI
if (currentContractVersion === 'v2') {
  document.getElementById('ragequitTimelockSection').style.display = 'block';
} else {
  document.getElementById('ragequitTimelockSection').style.display = 'none';
}
```

---

## Changed ViewHelper Function Signatures

### getDAOMessages

```javascript
// v1: 3 parameters
viewHelper.getDAOMessages(dao, start, count)
// Returns: [{index, text}, ...]

// v2: 4 parameters
viewHelper.getDAOMessages(dao, start, count, reverseOrder)
// Returns: [{index, sender, text}, ...]
```

### getDAOFullState

```javascript
// v1: 6 parameters
viewHelper.getDAOFullState(dao, proposalStart, proposalCount, messageStart, messageCount, treasuryTokens)

// v2: 8 parameters
viewHelper.getDAOFullState(dao, proposalStart, proposalCount, messageStart, messageCount, treasuryTokens, reverseProposals, reverseMessages)
```

### getDAOsFullState

```javascript
// v1: 7 parameters
viewHelper.getDAOsFullState(daoStart, daoCount, proposalStart, proposalCount, messageStart, messageCount, treasuryTokens)

// v2: 9 parameters
viewHelper.getDAOsFullState(daoStart, daoCount, proposalStart, proposalCount, messageStart, messageCount, treasuryTokens, reverseProposals, reverseMessages)
```

### getUserDAOsFullState

```javascript
// v1: 8 parameters
viewHelper.getUserDAOsFullState(user, daoStart, daoCount, proposalStart, proposalCount, messageStart, messageCount, treasuryTokens)

// v2: 5 parameters with struct
viewHelper.getUserDAOsFullState(user, daoStart, daoCount, treasuryTokens, paginationParams)
// paginationParams = {proposalStart, proposalCount, messageStart, messageCount, reverseProposals, reverseMessages}
```

---

## Code Examples: Adding v2 Support

### Example 1: Fetching Messages

```javascript
async function fetchMessages(daoAddress) {
  const viewHelper = new ethers.Contract(
    getViewHelperAddress(),
    getViewHelperABI(),
    provider
  );

  if (currentContractVersion === 'v2') {
    // v2: Has sender, supports reverse ordering (newest first)
    const messages = await viewHelper.getDAOMessages(daoAddress, 0, 50, true);
    return messages.map(m => ({
      index: m.index,
      sender: m.sender,  // Available directly
      text: m.text
    }));
  } else {
    // v1: No sender in response, no reverse ordering
    const messages = await viewHelper.getDAOMessages(daoAddress, 0, 50);
    return messages.map(m => ({
      index: m.index,
      sender: null,  // Not available without event query
      text: m.text
    }));
  }
}
```

### Example 1b: Fetching Message Senders in v1 (Event Queries)

In v1, the `MessageView` struct doesn't include the sender. To display who sent each message, you must query the `Message` events:

```javascript
async function fetchMessagesWithSenders(daoAddress) {
  const viewHelper = new ethers.Contract(getViewHelperAddress(), getViewHelperABI(), provider);

  if (currentContractVersion === 'v2') {
    // v2: Sender is included directly in the response
    const messages = await viewHelper.getDAOMessages(daoAddress, 0, 50, true);
    return messages.map(m => ({
      index: Number(m.index),
      sender: m.sender,
      text: m.text
    }));
  }

  // v1: Fetch messages first, then query events for senders
  const messages = await viewHelper.getDAOMessages(daoAddress, 0, 50);

  // Query Message events from the DAO contract to get senders
  const moloch = new ethers.Contract(daoAddress, [
    'event Message(address indexed by, uint256 indexed id, string message)'
  ], provider);

  // Batch query all Message events (you can optimize with block ranges)
  const filter = moloch.filters.Message();
  const events = await moloch.queryFilter(filter);

  // Build a map of message index → sender address
  const senderMap = new Map();
  for (const event of events) {
    senderMap.set(Number(event.args.id), event.args.by);
  }

  // Merge senders into message objects
  return messages.map(m => ({
    index: Number(m.index),
    sender: senderMap.get(Number(m.index)) || null,
    text: m.text
  }));
}
```

**Performance tip:** For DAOs with many messages, cache the event data or query only the block range since the last known message.

### Example 2: Fetching DAO State

```javascript
async function fetchDAOState(daoAddress, treasuryTokens = [ethers.ZeroAddress]) {
  const viewHelper = new ethers.Contract(
    getViewHelperAddress(),
    getViewHelperABI(),
    provider
  );

  if (currentContractVersion === 'v2') {
    return viewHelper.getDAOFullState(
      daoAddress,
      0,    // proposalStart
      20,   // proposalCount
      0,    // messageStart
      50,   // messageCount
      treasuryTokens,
      true, // reverseProposals - newest first
      true  // reverseMessages - newest first
    );
  } else {
    return viewHelper.getDAOFullState(
      daoAddress,
      0, 20, 0, 50,
      treasuryTokens
      // No reverse params in v1
    );
  }
}
```

### Example 3: Displaying Ragequit Eligibility

```javascript
async function getRagequitStatus(daoAddress, userAddress) {
  // v1: No timelock concept
  if (currentContractVersion === 'v1') {
    return { eligible: true, waitTime: 0, hasTimelock: false };
  }

  // v2: Check timelock from DAOGovConfig
  const viewHelper = new ethers.Contract(getViewHelperAddress(), getViewHelperABI(), provider);
  const daoState = await viewHelper.getDAOFullState(daoAddress, 0, 0, 0, 0, [], false, false);

  const timelockSeconds = Number(daoState.gov.ragequitTimelock || 0);
  if (timelockSeconds === 0) {
    return { eligible: true, waitTime: 0, hasTimelock: false };
  }

  // Check user's token acquisition timestamps
  const sharesContract = new ethers.Contract(daoState.meta.sharesToken, [
    'function lastAcquisitionTimestamp(address) view returns (uint256)',
    'function balanceOf(address) view returns (uint256)'
  ], provider);

  const [balance, lastAcquired] = await Promise.all([
    sharesContract.balanceOf(userAddress),
    sharesContract.lastAcquisitionTimestamp(userAddress)
  ]);

  if (balance === 0n) {
    return { eligible: false, waitTime: 0, hasTimelock: true, reason: 'No shares' };
  }

  const unlockTime = Number(lastAcquired) + timelockSeconds;
  const now = Math.floor(Date.now() / 1000);
  const waitTime = Math.max(0, unlockTime - now);

  return {
    eligible: waitTime === 0,
    waitTime,
    hasTimelock: true,
    unlockDate: new Date(unlockTime * 1000)
  };
}
```

---

## ABI Tuple Definitions

### MessageView

```javascript
// v1
const MESSAGE_VIEW_V1 = 'tuple(uint256 index, string text)';

// v2
const MESSAGE_VIEW_V2 = 'tuple(uint256 index, address sender, string text)';
```

### DAOGovConfig

```javascript
// v1
const DAO_GOV_CONFIG_V1 = `tuple(
  uint96 proposalThreshold,
  uint96 minYesVotesAbsolute,
  uint96 quorumAbsolute,
  uint64 proposalTTL,
  uint64 timelockDelay,
  uint16 quorumBps,
  bool ragequittable,
  uint256 autoFutarchyParam,
  uint256 autoFutarchyCap,
  address rewardToken
)`;

// v2 - note ragequitTimelock after ragequittable
const DAO_GOV_CONFIG_V2 = `tuple(
  uint96 proposalThreshold,
  uint96 minYesVotesAbsolute,
  uint96 quorumAbsolute,
  uint64 proposalTTL,
  uint64 timelockDelay,
  uint16 quorumBps,
  bool ragequittable,
  uint64 ragequitTimelock,
  uint256 autoFutarchyParam,
  uint256 autoFutarchyCap,
  address rewardToken
)`;
```

---

## Testing Checklist

Before merging any changes, test BOTH versions:

### v1 Testing (Production contracts)
- [ ] Select "v1" in version dropdown
- [ ] Connect to mainnet or Sepolia
- [ ] Load a DAO → verify proposals/messages load
- [ ] Check chatroom → messages display (sender may be missing, that's OK)
- [ ] Check ragequit → no timelock warning shown
- [ ] Submit a vote → transaction succeeds
- [ ] No console errors related to undefined properties

### v2 Testing (Development contracts)
- [ ] Select "v2" in version dropdown (auto-switches to localhost)
- [ ] Ensure anvil is running with v2 contracts deployed
- [ ] Load a DAO → verify proposals/messages load with reverse ordering
- [ ] Check chatroom → messages display WITH sender addresses
- [ ] Check ragequit → timelock warning shown if applicable
- [ ] Submit a vote → transaction succeeds
- [ ] No console errors

### Regression Checks
- [ ] After testing v2, switch back to v1 and verify it still works
- [ ] Check browser console for any new warnings/errors
- [ ] Verify localStorage isn't corrupted between switches

---

## Security Notes

### Ragequit Flash Loan Protection (v2 only)
The 7-day timelock prevents:
1. Attacker flash-loans DAO shares when treasury spikes in value
2. Immediately ragequits to extract pro-rata treasury
3. Repays flash loan, keeps profit

### Proposal State Protection (v2 only)
Proposals remain `Active` until TTL expires, preventing:
1. **No-vote snipe**: Vote AGAINST, immediately call `resolveFutarchyNo()`
2. **Yes-vote snipe**: Vote FOR, immediately execute malicious proposal
