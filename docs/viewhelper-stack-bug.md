# MolochViewHelper Stack-Too-Deep Bug

## Summary

The `MolochViewHelper.sol` contract fails to compile due to a "stack too deep" error in the `getUserDAOsFullState` function. This is a pre-existing bug that was introduced in commit `3ca543f` (Add v1/v2 dual version support).

## Error Message

```
Error: Variable var_messageStart is 1 too deep in the stack
[ var_out_54455_mpos RET var_messageStart var_treasuryTokens_54450_offset var_user
  var_daoEnd var_i_1 memPtr_4 var_messageCount var_proposalStart
  var_treasuryTokens_54450_length _53 var_k expr_15 _46 _44 expr_14 _52 expr_10 ]
memoryguard was present.
```

## Root Cause

The EVM has a stack limit of 16 slots. The `getUserDAOsFullState` function has:

1. **Function parameters** (5 params, but `PaginationParams` struct and `treasuryTokens` array expand to ~10 stack slots):
   - `user`
   - `daoStart`
   - `daoCount`
   - `treasuryTokens` (offset + length = 2 slots)
   - `pagination` struct (6 fields accessed individually)

2. **Local variables in the loop**:
   - `daoEnd`
   - `matchCount`
   - `k` (output index)
   - `i` (loop counter)
   - `dao`, `M`, `sharesToken`, `lootToken`, `badgesToken`
   - Various balances and intermediate values

3. **Return value pointer** (`out`)

Combined, these exceed the 16-slot limit when the compiler generates IR code with `via_ir = true`.

## Why `via_ir = true` is Required

The project requires `via_ir = true` because:
1. The ZAMM library (AMM dependency) uses complex stack operations that fail without IR
2. IR enables better optimization for the large ViewHelper contract

## Affected Function

```solidity
function getUserDAOsFullState(
    address user,
    uint256 daoStart,
    uint256 daoCount,
    address[] calldata treasuryTokens,
    PaginationParams calldata pagination  // 6 fields
) public view returns (UserDAOLens[] memory out)
```

## Potential Fixes

1. **Split the function**: Break into multiple smaller functions that each stay under the stack limit
2. **Use memory structs**: Copy calldata to memory early to reduce calldata slot overhead
3. **Reduce parameters**: Pack pagination into a single `uint256` bitmask
4. **Scoped blocks**: Use `{}` blocks to limit variable lifetime and allow stack slot reuse

## Impact

- Cannot deploy a new ViewHelper with updated SUMMONER address when using immutable pattern
- Immutable variables consume stack slots in functions that reference them

## Resolution

The issue was resolved by:
1. Changing `optimizer_runs` from 200 to 500 (reduces code size while avoiding stack issues)
2. Using `constant` instead of `immutable` for SUMMONER and DAICO (no constructor params needed)

New ViewHelper deployed at `0x791150F1a264951ddD9698462a111eB04838D1F6` with SUMMONER set to `0xadc33cbf7715219D9DC0d3958020835AaE36c338`.
