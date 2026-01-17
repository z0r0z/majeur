1. Always run `biome lint dapp` after completed code changes to Majeur.html or DAICO.html; do not run lint commands in any other way!

2. The frontend server runs in a tmux session named "dapp". When you need to check logs or debug issues, tail the logs from this tmux session rather than restarting the server.

3. v1 vs v2 ViewHelper ABIs differ in `getUserDAOsFullState` parameter order: v1 has `treasuryTokens` as the LAST parameter; v2 has it before the `PaginationParams` struct. See `docs/v1-v2-contract-differences.md` for full API differences.
