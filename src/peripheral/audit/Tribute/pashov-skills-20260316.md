# Security Review — Tribute

---

## Scope

|                                  |                                                        |
| -------------------------------- | ------------------------------------------------------ |
| **Mode**                         | `src/peripheral/Tribute.sol`                           |
| **Files reviewed**               | `src/peripheral/Tribute.sol`                           |
| **Confidence threshold (1-100)** | 80                                                     |

---

## Findings

[85] **1. Fee-on-Transfer Token Permanently Locks Tribute Funds**

`Tribute.proposeTribute` · Confidence: 85

**Description**

`proposeTribute` records `offer.tribAmt = tribAmt` (the parameter) without measuring actual received amount, so when `tribTkn` is a fee-on-transfer token the contract holds `tribAmt - fee` but stores `tribAmt`; both `claimTribute` and `cancelTribute` attempt to send the full `tribAmt` via `safeTransfer`, which reverts on insufficient balance — permanently trapping the tribute with no recovery path.

**Resolution:** Won't fix — documented as unsupported. Natspec added to contract: fee-on-transfer and rebasing tokens must not be used. Consistent with Moloch.sol's transfer patterns and standard minimal escrow design (Uniswap V2/V3, Solady).

---

[80] **2. Proposer with Reverting Receive Blocks DAO from Claiming ETH-Consideration Tribute**

`Tribute.claimTribute` · Confidence: 80

**Description**

When `forTkn == address(0)`, `claimTribute` pushes ETH to the proposer via `safeTransferETH(proposer, offer.forAmt)` before delivering the tribute to the DAO; if the proposer is a contract whose `receive()` reverts, the entire claim reverts — permanently preventing the DAO from completing the swap, while the proposer retains the ability to cancel and recover their tribute at any time.

**Resolution:** Won't fix — not applicable to production integration. Moloch DAOs (the intended `dao` caller) have `receive() external payable {}` and will always accept ETH. A pull pattern was considered and rejected as unnecessary friction for this use case.

---

| # | Confidence | Title | Resolution |
|---|---|---|---|
| 1 | [85] | Fee-on-Transfer Token Permanently Locks Tribute Funds | Won't fix (documented) |
| 2 | [80] | Proposer with Reverting Receive Blocks DAO from Claiming | Won't fix (N/A to Moloch) |
| | | **Below Confidence Threshold** | |
| 3 | [80] | Rebasing Token Downward Rebase Locks Tribute Funds | Won't fix (same root cause as #1) |
| 4 | [75] | Unbounded Ref Arrays Enable View-Function DoS | Mitigated (pagination added) |

### False Positives Rejected

- **FMP corruption in `safeTransfer`** — Agent flagged `mstore(0x34, 0)` as zeroing the free memory pointer. This is a Solady-standard pattern: only the high bytes of the FMP word (0x40–0x53) are zeroed; the actual pointer value resides in bytes 0x54–0x5F which are never touched. FMP is correctly restored.

---

> This review was performed by an AI assistant. AI analysis can never verify the complete absence of vulnerabilities and no guarantee of security is given. Team security reviews, bug bounty programs, and on-chain monitoring are strongly recommended. For a consultation regarding your projects' security, visit [https://www.pashov.com](https://www.pashov.com)
