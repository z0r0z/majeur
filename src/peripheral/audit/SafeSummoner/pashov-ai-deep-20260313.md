# Security Review — SafeSummoner (DEEP)

---

## Scope

|                                  |                                                        |
| -------------------------------- | ------------------------------------------------------ |
| **Mode**                         | `DEEP` (4 vector scan agents + 1 adversarial reasoning agent) |
| **Files reviewed**               | `SafeSummoner.sol`                                     |
| **Confidence threshold (1-100)** | 75                                                     |
| **Tool**                         | Pashov Skills Solidity Auditor v1 (5-agent DEEP scan)  |
| **Date**                         | 2026-03-13                                             |

---

## Findings

[80] **1. `create2Deploy` Salt Not Bound to `msg.sender` Enables Front-Running DoS**

`SafeSummoner.create2Deploy` · Confidence: 80

**Description**
`create2Deploy(bytes calldata creationCode, bytes32 salt)` does not incorporate `msg.sender` into the salt, allowing an attacker to observe a victim's pending multicall (e.g., `[create2Deploy(moduleCode, salt), safeSummonDAICO(...)]`), front-run the `create2Deploy` step with the same parameters, and cause the victim's entire atomic multicall to revert — permanently blocking the intended module address for that salt.

**Fix**

```diff
  function create2Deploy(bytes calldata creationCode, bytes32 salt)
      public
      payable
      returns (address deployed)
  {
+     bytes32 boundSalt = keccak256(abi.encodePacked(msg.sender, salt));
      assembly ("memory-safe") {
          let ptr := mload(0x40)
          calldatacopy(ptr, creationCode.offset, creationCode.length)
-         deployed := create2(callvalue(), ptr, creationCode.length, salt)
+         deployed := create2(callvalue(), ptr, creationCode.length, boundSalt)
      }
      if (deployed == address(0)) revert Create2Failed();
  }
```

Note: `predictCreate2` must apply the same `msg.sender` binding.

> **Response — Accepted (no fix needed).** The frontrunning scenario is benign: attacker deploys the victim's contract (correct bytecode, CREATE2 address includes bytecode hash) at the predicted address, paying gas on the victim's behalf. Victim retries without the `create2Deploy` step or uses a different salt. No funds at risk, no code injection. Binding salt to `msg.sender` would break the useful property that predicted addresses are sender-independent, complicating cross-EOA and contract-based deployment flows. Previously identified by Pashov AI Audit #1 (conf 80), Archethect DT-01, Forefy #2, Grimoire I-01.

---

## Findings List

| # | Confidence | Title | Status |
|---|---|---|---|
| 1 | [80] | `create2Deploy` salt not bound to `msg.sender` | **Accepted** — benign frontrun, attacker deploys correct bytecode. Duplicate of Known Finding #2. |
| | | **Below Confidence Threshold** | |
| 2 | [65] | `multicall` delegatecall shares `msg.value` across sub-calls | **Accepted** — standard delegatecall-multicall pattern, documented in NatSpec. Duplicate of Known Finding #3. |

---

## Adversarial Reasoning Agent — Novel Hypotheses

The DEEP adversarial agent (Agent 5) generated two additional hypotheses:

### Hypothesis A: Multicall msg.value Theft via Pre-Existing ETH Balance [100 → Rejected]

**Claim:** An attacker could drain ETH accumulated in SafeSummoner by batching multiple value-forwarding calls in `multicall`, each seeing the same `msg.value`.

**Assessment:** False positive. SafeSummoner is a stateless factory with `constructor() payable {}` as a gas optimization. ETH sent via `msg.value` is forwarded atomically to `SUMMONER.summon{value: msg.value}()`. No mechanism exists for ETH to accumulate: (1) all summon functions forward the full `msg.value`, (2) `create2Deploy` forwards `callvalue()` to the deployed contract, (3) no `receive()` or `fallback()` exists to accept bare ETH transfers. The NatSpec at L203-205 documents the `msg.value` sharing behavior. This is the same design tradeoff as Uniswap V3 Router and Seaport. Analyzed and accepted in 6 prior audits.

### Hypothesis B: Minting Sale + Zero quorumBps Bypasses KF#2 Check [100 → Rejected]

**Claim:** Setting `quorumBps = 0` with `quorumAbsolute = 0` and a minting sale bypasses the `MintingSaleWithDynamicQuorum` check because the condition requires `quorumBps > 0`.

**Assessment:** False positive. KF#2 is specifically about supply inflation **manipulating a dynamic (BPS-based) quorum denominator**. When `quorumBps == 0`, there is no BPS-based quorum to manipulate — the attack vector does not exist. Zero quorum with zero absolute quorum means proposals pass with any votes regardless of supply; the minting sale adds no additional exploit surface because governance is already fully open. The `quorumBps > 0` condition correctly scopes the check to when a dynamic quorum exists and can be inflated away. Allowing zero-quorum DAOs is an intentional configuration choice (some DAOs rely solely on social consensus or external governance).

---

## Eliminated Vectors (Summary)

Across 5 agents (~170 vectors total + adversarial reasoning):

- **Not applicable:** ERC721/1155/4626, AMM/oracle, proxy/upgrade, cross-chain/LayerZero, flash loan, signature replay, Diamond proxy, AA/ERC4337, lending/liquidation, staking, Merkle proofs
- **Guarded:** Reentrancy (no persistent state), integer overflow (Solidity 0.8.30 checked + saturating cap), unsafe downcast (`_defaultThreshold` has explicit bounds check), unchecked returns (all checked), assembly memory safety (no allocation after assembly blocks), delegatecall target (hardcoded `address(this)`)
- **False positives dismissed:** Minting sale + zero quorum (KF#2 check correctly scoped), force-fed ETH (no balance accounting), array count/fill mismatch (conditions provably identical), sentinel collision (2^-160 probability), `memory-safe` annotation (create2 consumes data atomically)
- **Design decisions:** Hardcoded singleton addresses (documented same-address cross-chain deployments), `extraCalls` executed by new DAO (deployer configures own DAO), module parameter delegation (singletons validate own constraints)

---

> ⚠️ This review was performed by an AI assistant. AI analysis can never verify the complete absence of vulnerabilities and no guarantee of security is given. Team security reviews, bug bounty programs, and on-chain monitoring are strongly recommended. For a consultation regarding your projects' security, visit [https://www.pashov.com](https://www.pashov.com)
