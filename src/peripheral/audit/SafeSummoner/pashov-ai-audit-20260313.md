# Security Review — SafeSummoner

---

## Scope

|                                  |                                                        |
| -------------------------------- | ------------------------------------------------------ |
| **Mode**                         | `src/peripheral/SafeSummoner.sol`                      |
| **Files reviewed**               | `SafeSummoner.sol`                                     |
| **Confidence threshold (1-100)** | 75                                                     |
| **Tool**                         | Pashov Skills Solidity Auditor v1 (4-agent vector scan)|
| **Date**                         | 2026-03-13                                             |

---

## Findings

[85] **1. Silent `uint96` Truncation in `_defaultThreshold` Produces Near-Zero Proposal Threshold**

`SafeSummoner._defaultThreshold` · Confidence: 85

**Description**
When `initShares` entries sum to more than `100 * type(uint96).max` (~7.9e30), the expression `uint256 t = total / 100` overflows `uint96` and is silently truncated on cast `return uint96(t)`, producing a tiny `proposalThreshold` that bypasses the KF#11 spam-protection invariant enforced by `_validate`.

**Fix**

```diff
- return uint96(t);
+ require(t <= type(uint96).max, "threshold overflow");
+ return uint96(t);
```

---

[80] **2. Unrestricted `create2Deploy` Enables Front-Running of Module Address Deployments**

`SafeSummoner.create2Deploy` · Confidence: 80

**Description**
`create2Deploy` is a public permissionless function with no `msg.sender`-binding on the salt, so an attacker who observes a pending multicall can replay the same `(creationCode, salt)` pair in a higher-gas transaction, pre-deploying to the same CREATE2 address and causing the victim's transaction to revert with `Create2Failed`. Additionally, if the victim's multicall uses the predicted address as a hook/module singleton in `safeSummonDAICO`, the entire atomic deployment sequence reverts.

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

Note: `predictCreate2` must apply the same `msg.sender` binding:
```diff
- keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(creationCode)))
+ keccak256(abi.encodePacked(bytes1(0xff), address(this), keccak256(abi.encodePacked(msg.sender, salt)), keccak256(creationCode)))
```

---

## Findings List

| # | Confidence | Title | Status |
|---|---|---|---|
| 1 | [85] | Silent `uint96` truncation in `_defaultThreshold` | **Patched** — saturating cap added. Non-issue in practice: Moloch.sol uses uint96 throughout (vote tallies, quorum, threshold setter). Total shares > type(uint96).max breaks the entire governance system upstream of this function. |
| 2 | [80] | Unrestricted `create2Deploy` enables front-run DoS | **Accepted** — attacker deploys the victim's contract (correct bytecode) at the predicted address. Victim retries without the create2 step. No funds at risk, no code injection. Binding salt to msg.sender would break sender-independent address prediction. |
| | | **Below Confidence Threshold** | |

---

## Eliminated Vectors (Summary)

The following vector categories were evaluated and eliminated across 4 scanning agents (~168 vectors total):

- **Not applicable:** ERC721/1155/4626, AMM/oracle, proxy/upgrade, cross-chain/LayerZero, flash loan, signature replay, Diamond proxy, AA/ERC4337, lending/liquidation
- **Guarded:** Reentrancy (no persistent state in SafeSummoner), multicall msg.value reuse (documented, self-contained), unbounded loops (gas-bounded, caller-only impact), assembly memory safety (no allocations after assembly blocks)
- **Design decisions:** Hardcoded singleton addresses (documented as same-address cross-chain deployments), extraCalls executed by new DAO (not SafeSummoner context)

---

> This review was performed by an AI assistant. AI analysis can never verify the complete absence of vulnerabilities and no guarantee of security is given. Team security reviews, bug bounty programs, and on-chain monitoring are strongly recommended. For a consultation regarding your projects' security, visit [https://www.pashov.com](https://www.pashov.com)
