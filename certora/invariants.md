**Protocol Invariants**

## Moloch (Core DAO)

### ERC-6909 receipt token accounting

1. For every receipt token id, `totalSupply[id]` equals the sum of all `balanceOf[user][id]` across all users
2. `_burn6909` reverts if `balanceOf[from][id] < amount`
3. ERC-6909 `transfer` and `transferFrom` revert when `isPermitReceipt[id]` is true

### Proposal state machine — monotonicity and immutability

4. `executed[id]` is a one-way latch: once set to `true`, it never becomes `false`
5. `createdAt[id]` is write-once: once set to a non-zero value, it never changes
6. `snapshotBlock[id]` is write-once: once set to a non-zero value, it never changes
7. `supplySnapshot[id]` is write-once: once set to a non-zero value, it never changes
8. `queuedAt[id]` is write-once: once set to a non-zero value, it never changes
9. For any proposal id, if `executed[id]` is true then `state(id)` returns `Executed`
10. A proposal in state `Executed` cannot transition to any other state
11. `config` is monotonically non-decreasing: it only changes via `bumpConfig` which increments by one
12. Proposal and permit IDs include `config` in their hash, so incrementing `config` invalidates all pre-existing unhashed IDs

### Voting integrity

13. `castVote` reverts if `executed[id]` is true
14. `castVote` reverts if `hasVoted[id][msg.sender]` is non-zero
15. `castVote` only accepts `support` values in `{0, 1, 2}`
16. After a successful `castVote`, `hasVoted[id][msg.sender]` equals `support + 1` and `voteWeight[id][msg.sender]` equals the voter's past voting power at the proposal's snapshot block
17. For any proposal id, the sum `tallies[id].forVotes + tallies[id].againstVotes + tallies[id].abstainVotes` cannot exceed `supplySnapshot[id]`
18. `castVote` uses `getPastVotes(msg.sender, snapshotBlock[id])` where `snapshotBlock[id] < block.number`, so tokens acquired in the current block have zero voting power

### Futarchy

19. Once `futarchy[id].resolved` is true, it never becomes false
20. Once `futarchy[id].payoutPerUnit` is set to a non-zero value during `_finalizeFutarchy`, it never changes
21. `cashOutFutarchy` reverts if `futarchy[id].resolved` is false
22. `fundFutarchy` reverts if `futarchy[id].resolved` is true
23. For a resolved futarchy, the winning receipt token's `totalSupply[rid]` at resolution equals `futarchy[id].finalWinningSupply`

### Ragequit conservation

24. For each token processed by ragequit, the payout `mulDiv(pool, amt, total)` is at most `pool` because `amt <= total`
25. Ragequit computes `total = shares.totalSupply() + loot.totalSupply()` before burning, ensuring the denominator is constant throughout the token distribution loop
26. Ragequit reverts if the caller-supplied token array is not in strictly ascending order, preventing duplicate token claims
27. Ragequit reverts if `sharesToBurn == 0 && lootToBurn == 0`
28. Ragequit reverts if `ragequittable` is false
29. Ragequit reverts if any token in the array is `address(shares)`, `address(loot)`, `address(this)`, or `address(1007)`

### State variable modification authorization

30. `proposalThreshold` only changes via `setProposalThreshold`; no other function modifies it
31. `proposalTTL` only changes via `setProposalTTL`; no other function modifies it
32. `timelockDelay` only changes via `setTimelockDelay`; no other function modifies it
33. `quorumAbsolute` only changes via `setQuorumAbsolute`; no other function modifies it
34. `minYesVotesAbsolute` only changes via `setMinYesVotesAbsolute`; no other function modifies it
35. `quorumBps` only changes via `setQuorumBps` or `init`; no other function modifies it
36. `ragequittable` only changes via `setRagequittable` or `init`; no other function modifies it
37. `renderer` only changes via `setRenderer` or `init`; no other function modifies it
38. `autoFutarchyParam` and `autoFutarchyCap` only change via `setAutoFutarchy`; no other function modifies them
39. `rewardToken` only changes via `setFutarchyRewardToken`; no other function modifies it
40. `isPermitReceipt[id]` only changes via `setPermit`; no other function sets it to true

### Access control

41. All governance parameter setters (`setProposalThreshold`, `setProposalTTL`, `setTimelockDelay`, `setQuorumAbsolute`, `setMinYesVotesAbsolute`, `setQuorumBps`, `setRagequittable`, `setTransfersLocked`, `setSale`, `setAllowance`, `setPermit`, `setAutoFutarchy`, `setFutarchyRewardToken`, `setMetadata`, `setRenderer`, `bumpConfig`, `batchCalls`) revert if `msg.sender != address(this)`
42. After `init` completes, there are no admin keys or privileged roles; `onlyDAO` (`msg.sender == address(this)`) is the sole access control mechanism

### Sale

43. `buyShares` reverts if `sales[payToken].active` is false
44. `buyShares` reverts if `shareAmount == 0`
45. `setSale` reverts if `pricePerShare == 0`
46. After a successful `buyShares` with non-zero cap, `sales[payToken].cap` decreases by exactly `shareAmount`
47. `buyShares` reverts if `maxPay != 0 && cost > maxPay`, providing slippage protection

### Allowance

48. `spendAllowance` decreases `allowance[token][msg.sender]` by exactly `amount` via checked subtraction
49. `spendAllowance` reverts if `allowance[token][msg.sender] < amount`

### Execution

50. `executeByVotes` sets `executed[id]` to true before calling `_execute`, following the checks-effects-interactions pattern
51. `executeByVotes` reverts if `state(id)` is not `Succeeded` or `Queued`
52. When `timelockDelay != 0`, `executeByVotes` auto-queues on first call and reverts with `Timelocked` on subsequent calls until the delay has elapsed

### Reentrancy protection

53. All state-changing functions that make external calls (`ragequit`, `buyShares`, `spendAllowance`, `cashOutFutarchy`, `fundFutarchy`, `executeByVotes`, `spendPermit`) are protected by `nonReentrant` using EIP-1153 transient storage
54. `multicall` uses `delegatecall` which preserves the transient storage context, so the reentrancy guard cannot be bypassed through batched sub-calls
55. `multicall` is not payable, so `msg.value` is always zero within sub-calls preventing `msg.value` reuse

---

## Shares (ERC-20 + Voting)

### ERC-20 accounting

56. `Shares.totalSupply` equals the sum of all `Shares.balanceOf[user]` across all users
57. `Shares.transfer` decreases sender balance and increases receiver balance by exactly `amount`, preserving total supply
58. `Shares.transfer` and `Shares.transferFrom` revert when `transfersLocked` is true and neither `from` nor `to` is the DAO address
59. Only `mintFromMoloch` and `burnFromMoloch` change `Shares.totalSupply`; transfers conserve it

### Delegation

60. For any account with a split delegation configuration, the BPS values across all entries sum to exactly 10000
61. Split delegation allows at most `MAX_SPLITS` (4) delegates
62. No split delegation entry has `address(0)` as delegate
63. No split delegation configuration has duplicate delegate addresses
64. `_targetAlloc` returns an array of values that sum to exactly the input balance `bal`

### Checkpoint integrity

65. The sum of voting power across all delegates' latest checkpoint values equals `Shares.totalSupply` at the current block
66. For any account, checkpoint entries have non-decreasing `fromBlock` values; same-block updates overwrite rather than append
67. `getPastVotes` reverts if `blockNumber >= block.number`
68. `getPastTotalSupply` reverts if `blockNumber >= block.number`

### Voting power conservation

69. `_applyVotingDelta` is path-independent: it computes old and new target allocations from old and new balances respectively, so the net voting power change is exactly `|delta|` regardless of delegation configuration
70. `_repointVotesForHolder` moves voting power from old distribution to new distribution without creating or destroying any aggregate voting power

### Initialization

71. `Shares.DAO` is set exactly once during `init` and never changes thereafter
72. `Shares.init` reverts if `DAO` is already non-zero

### Minting and burning authorization

73. `Shares.totalSupply` only increases via `mintFromMoloch` (which requires `msg.sender == DAO`) and only decreases via `burnFromMoloch` (which requires `msg.sender == DAO`)

---

## Loot (ERC-20)

### ERC-20 accounting

74. `Loot.totalSupply` equals the sum of all `Loot.balanceOf[user]` across all users
75. `Loot.transfer` and `Loot.transferFrom` revert when `transfersLocked` is true and neither `from` nor `to` is the DAO address
76. Only `mintFromMoloch` and `burnFromMoloch` change `Loot.totalSupply`; transfers conserve it

### Initialization

77. `Loot.DAO` is set exactly once during `init` and never changes thereafter
78. `Loot.init` reverts if `DAO` is already non-zero

### Minting and burning authorization

79. `Loot.totalSupply` only increases via `mintFromMoloch` (which requires `msg.sender == DAO`) and only decreases via `burnFromMoloch` (which requires `msg.sender == DAO`)

---

## Badges (ERC-721 Soulbound)

### Soulbound enforcement

80. `Badges.transferFrom` always reverts unconditionally, enforcing soulbound non-transferability
81. `Badges.balanceOf[address]` is always 0 or 1

### Bidirectional mapping consistency

82. For any address `a`, if `Badges.balanceOf[a] == 1` then `seatOf[a]` is in the range `[1, 256]`
83. For any address `a`, if `seatOf[a] != 0` then `_ownerOf[seatOf[a]] == a`
84. For any seat id `s` in `[1, 256]`, if `_ownerOf[s] != address(0)` then `seatOf[_ownerOf[s]] == s`

### Bitmap consistency

85. The number of set bits in `occupied` equals the number of seat ids in `[1, 256]` for which `_ownerOf[id] != address(0)`
86. `minBal` equals zero when no seats are occupied, and otherwise equals the minimum `seats[slot].bal` across all occupied slots

### Seat management

87. `mintSeat` requires `seat >= 1 && seat <= 256`
88. `mintSeat` requires `_ownerOf[seat] == address(0)` (seat must be vacant)
89. `mintSeat` requires `balanceOf[to] == 0` (recipient must not already hold a badge)
90. `mintSeat` and `burnSeat` can only be called by the DAO (`msg.sender == DAO`)

### Initialization

91. `Badges.DAO` is set exactly once during `init` and never changes thereafter
92. `Badges.init` reverts if `DAO` is already non-zero

---

## Cross-contract (Moloch, Shares, Loot, Badges)

### DAO binding

93. After initialization, `Shares.DAO`, `Loot.DAO`, and `Badges.DAO` all point to the same Moloch contract address
94. `Moloch.shares`, `Moloch.loot`, and `Moloch.badges` are set during `init` and never change

### Aggregation

95. The ragequit denominator `total = Shares.totalSupply + Loot.totalSupply` accurately reflects total economic claim weight at the moment of ragequit

### Badge-Share synchronization

96. `Badges.onSharesChanged` can only be called by the DAO, and the DAO only calls it via `Moloch.onSharesChanged` which requires `msg.sender == address(shares)`

---

## Tribute (Peripheral)

### Escrow integrity

97. `proposeTribute` reverts if an offer already exists for the `(msg.sender, dao, tribTkn)` triple (no overwrites)
98. After a successful `cancelTribute`, the `tributes[msg.sender][dao][tribTkn]` entry is deleted (all fields zeroed)
99. After a successful `claimTribute`, the `tributes[proposer][dao][tribTkn]` entry is deleted (all fields zeroed)
100. `cancelTribute` reverts if no offer exists (`tribAmt == 0`) for the given key
101. `claimTribute` reverts if no offer exists (`tribAmt == 0`) for the given key
102. Only the original proposer can cancel their own tribute via `cancelTribute`
103. Only the DAO (`msg.sender`) can claim a tribute directed at itself via `claimTribute`

### Discovery array monotonicity

104. `daoTributeRefs[dao].length` is monotonically non-decreasing (entries are pushed but never removed)
105. `proposerTributeRefs[proposer].length` is monotonically non-decreasing (entries are pushed but never removed)

---

## DAICO (Peripheral)

### Sale configuration authorization

106. `DAICO.setSale`, `setSaleWithTap`, `setSaleWithLP`, `setSaleWithLPAndTap`, `setLPConfig`, `setTapOps`, and `setTapRate` all record `msg.sender` as the DAO; only the DAO itself can configure its own sales and taps

### Buy integrity

107. `DAICO.buy` reverts if no active sale exists for the given `(dao, tribTkn)` pair
108. `DAICO.buy` reverts if the sale deadline has passed (`block.timestamp > deadline` when `deadline != 0`)
109. `DAICO.buy` reverts if `payAmt == 0`
110. `DAICO.buy` reverts if `buyAmt` (computed output) would be zero
111. `DAICO.buy` reverts if `minBuyAmt != 0 && buyAmt < minBuyAmt`, providing slippage protection
112. `DAICO.buyExactOut` reverts if `maxPayAmt != 0 && payAmt > maxPayAmt`, providing slippage protection

### Tap mechanism

113. `claimTap` reverts if `taps[dao].ratePerSec == 0`
114. `claimTap` reverts if `taps[dao].ops == address(0)`
115. `claimTap` reverts if elapsed time since `lastClaim` is zero
116. The amount claimed by `claimTap` is at most `min(owed, allowance, daoBalance)` where `owed = ratePerSec * elapsed`
117. After a successful `claimTap`, `taps[dao].lastClaim` is set to `block.timestamp`

### LP configuration

118. `setLPConfig` reverts if `lpBps > 9999`

---

## SafeSummoner (Peripheral)

### Deployment validation

119. `safeSummon` reverts if `quorumBps > 10000`
120. `safeSummon` reverts if `proposalThreshold == 0`
121. `safeSummon` reverts if `proposalTTL == 0`
122. `safeSummon` reverts if `initHolders.length == 0`
123. `safeSummon` reverts if `timelockDelay > 0 && proposalTTL <= timelockDelay`
124. `safeSummon` reverts if futarchy is enabled (`autoFutarchyParam > 0`) and both `quorumBps == 0` and `quorumAbsolute == 0`
125. `safeSummon` reverts if `saleActive && saleMinting && quorumBps > 0 && quorumAbsolute == 0` (minting sale with dynamic-only quorum)
126. `safeSummon` reverts if `saleActive && salePricePerShare == 0`
