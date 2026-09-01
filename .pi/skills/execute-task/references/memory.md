# Project Rules (read from disk)

Loaded by `execute-task` before component flows. Project rules in `AGENTS.md` (and `SOUL.md` if present) are read from disk — the deterministic source of truth. There is no dense-mem rules cache; `rules_hash` (from `git rev-parse HEAD`) signals freshness.

The task arrives as a **JSON string** (the `subagent` tool accepts only a
string). Parse it as `task` and read fields via `task.project`,
`task.metadata.rules_hash`, etc.

## Load procedure (for component tasks)

1. Navigate to `/workspace/<project>`.
2. `read` `/workspace/<project>/AGENTS.md` (and `/workspace/<project>/SOUL.md` if present).
3. Extract the sections relevant to `task.type` / the work at hand.
4. `task.metadata.rules_hash` is informational only — it confirms the files you read match the commit the orchestrator based the task on. No memory call verifies it; the disk read is authoritative.

## Ownership

Only the orchestrator discovers/reads rules for routing. Workers read the
specific sections they need. No worker writes rules anywhere.

## Cost

`read` of `AGENTS.md`/`SOUL.md` only — no recall, no remember, no embedding call.
