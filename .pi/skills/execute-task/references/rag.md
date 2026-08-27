# Experience Memory via dense-mem

Loaded by `execute-task` for `component` and `review` flows. Provides recall over past solutions, patterns, and decisions across sessions. The dense-mem server is reached through MCP; Pi exposes its tools with the `mcp__dense-mem__` prefix (e.g. `mcp__dense-mem__recall_memory`).

## Batched recall (orchestrator → workers)

The orchestrator does **one** batched recall per task and passes the result to each sub-task via `metadata.memory_context`. Workers should NOT recall again — they read the context they were given. The `component.md` step 3 enforces this.

```
// In orchestrate-task step 4.5:
results = mcp__dense-mem__recall_memory(query="<main goal> project:<project> type:<project_type>", limit=10)
// Pass to each sub-task in step 7:
metadata.memory_context = summarize(results)
metadata.anti_patterns = mcp__dense-mem__recall_memory(query="<main goal> project:<project> anti-pattern", limit=3)
```

For ad-hoc tasks that bypass `orchestrate-task` (e.g. `simple-task-executor` calls), `component.md` falls back to its own recall.

## Principles

- Memory is **experiential and advisory** — never authoritative. Project rules in `AGENTS.md` are the source of truth. dense-mem caches them.
- The memory is **append-only**. Updates go through `supersedes_evidence_ids` on `remember`, `retract_evidence`, or `correct_relationship`. Never delete or rewrite.
- **Ownership**: dense-mem enforces that each profile can only `retract_evidence` / `correct_relationship` on records it owns. Coder owns its task evidence; orchestrator owns rule cache; reviewer owns review evidence.
- **Graceful degradation**: a failed or unavailable memory call must never block the task. Wrap every MCP call as best-effort; on error, continue without context.
- Store only compressed, structured outcomes — never raw full-source dumps.

## Recall (when batched context is absent)

- `mcp__dense-mem__recall_memory(query="<concise goal of the work>")`
- Use a short goal-oriented query (e.g. `react-hook-form + zod auth form with MUI for <project>`) rather than a long paste.
- Filter via query, not via API. Embed tags into the query string: `query="project:my-project anti-pattern auth"` so the embedding match is precise.
- Treat the top results as context hints. Even high-confidence results must still pass validation (lint / test / build) before commit.
- **Anti-pattern recall**: `mcp__dense-mem__recall_memory(query="<goal> project:<project> anti-pattern")` — use the project's prior failures to avoid repeating them.
- **Exploration anti-patterns**: `mcp__dense-mem__recall_memory(query="<goal> project:<project> anti-pattern exploration")` — these are decomposition strategies that failed after ≥3 review iterations. Do not repeat.
- Graceful degradation: on failure or empty results, proceed without context.

## Remember (after a successful task)

`mcp__dense-mem__remember` writes durable evidence. Real dense-mem shape:

```
mcp__dense-mem__remember({
  evidence: [{
    content: "project: <project>\ntype: <type>\ntags: project:<project>,<type>,<relevant-concepts>\nconfidence: medium\nvalid_until: <YYYY-MM-DD, today + 90 days>\n\n<concise summary, under 200 chars>",
    source_type: "task_outcome"
  }],
  idempotency_key: "<type>:<project>:<task_id>:<hash-of-content>"
})
```

Notes:
- `claims`, `tags`, `filter` are not in dense-mem's `remember` API. Tags go inside the content (structured prefix), filters go inside the query.
- `confidence` is a field of the **evidence item**, not a top-level argument.
- `valid_until` is the TTL date for decay. Format: ISO `YYYY-MM-DD`. The `memory-gc` skill retires evidence after this date. See `.pi/skills/memory-gc/SKILL.md` for the policy.
- `idempotency_key` is required. Use a hash of the content so retried writes don't duplicate.
- `remember` is asynchronous: it returns a `submission_id`. Poll `mcp__dense-mem__get_submission_status` once; do not block the task on it.
- Only call `remember` AFTER success (validation passed / task completed) — never for work in progress.
- Cap `content` at one sentence (~200 chars) for ordinary tasks. Use longer content only for review verdicts and exploration anti-patterns.

## Corrections

- If QA proves a recalled solution was wrong, find the offending record with `mcp__dense-mem__trace_memory(...)`.
- If the coder profile owns the record, retire it with `mcp__dense-mem__retract_evidence(evidence_ids=[...], reason="...", idempotency_key="...")`.
- dense-mem enforces ownership: you can only correct/retract evidence your own profile submitted. Reviewer-owned records are corrected by the reviewer.
- For relationship corrections, use `mcp__dense-mem__correct_relationship(...)` (only if the caller owns the active Relationship).
