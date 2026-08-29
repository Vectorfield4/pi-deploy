# Experience Memory via dense-mem

Loaded by `execute-task` for `component` and `review` flows. Provides recall over past solutions, patterns, and decisions across sessions. The dense-mem server is reached through MCP; Pi exposes its tools with the `mcp__dense_mem__` prefix (e.g. `mcp__dense_mem__recall_memory`).

## Batched recall (orchestrator → workers)

The orchestrator does **one** batched recall per task and passes the result to each sub-task via `task.metadata.memory_context` (inside the task JSON string). Workers should NOT recall again — they read the context they were given. The `component.md` step 3 enforces this.

```
// In orchestrate-task step 4.5:
results = mcp({ tool: "dense_mem_recall_memory", args: { query="<main goal> project:<project> type:<project_type>", limit=10 } })
// Pass to each sub-task in step 7, inside the task JSON string:
metadata.memory_context = summarize(results)
metadata.anti_patterns = mcp({ tool: "dense_mem_recall_memory", args: { query="<main goal> project:<project> anti-pattern", limit=3 } })
```

For ad-hoc tasks that bypass `orchestrate-task`, `component.md` falls back to its own recall.

## Principles

- Memory is **experiential and advisory** — never authoritative. Project rules in `AGENTS.md` are the source of truth. dense-mem caches them.
- The memory is **append-only**. Updates go through `supersedes_evidence_ids` on `remember`, `retract_evidence`, or `correct_relationship`. Never delete or rewrite.
- **Ownership**: dense-mem enforces that each profile can only `retract_evidence` / `correct_relationship` on records it owns. Coder owns its task evidence; orchestrator owns rule cache; reviewer owns review evidence.
- **Graceful degradation**: a failed or unavailable memory call must never block the task. Wrap every MCP call as best-effort; on error, continue without context.
- Store only compressed, structured outcomes — never raw full-source dumps.

## Recall (when batched context is absent)

- `mcp({ tool: "dense_mem_recall_memory", args: { query="<concise goal of the work>" } })`
- Use a short goal-oriented query (e.g. `react-hook-form + zod auth form with MUI for <project>`) rather than a long paste.
- Filter via query, not via API. Embed tags into the query string: `query="project:my-project anti-pattern auth"` so the embedding match is precise.
- Results are `{ evidence_id, context, space_kind }` — read the `context` field (the stored content, bounded at 2000 chars), never `content`. A recalled record's structured prefix (first lines) is the discriminator: `rules_hash:`, `project:`, `valid_until:`, etc.
- Treat the top results as context hints. Even high-confidence results must still pass validation (lint / test / build) before commit.
- **Anti-pattern recall**: `mcp({ tool: "dense_mem_recall_memory", args: { query="<goal> project:<project> anti-pattern" } })` — use the project's prior failures to avoid repeating them.
- **Exploration anti-patterns**: `mcp({ tool: "dense_mem_recall_memory", args: { query="<goal> project:<project> anti-pattern exploration" } })` — these are decomposition strategies that failed after ≥3 review iterations. Do not repeat.
- Graceful degradation: on failure or empty results, proceed without context.

## Remember (after a successful task)

`mcp__dense_mem__remember` writes durable evidence anchored by relationships. dense-mem v2.6 contract (`dense-mem.v2.6`, the `:latest` image): every submission requires `evidence`, `relationships`, and `idempotency_key` — a submission without `relationships` is rejected. Each relationship cites the evidence it supports via `evidence_indices` (0-based indexes into the `evidence` array).

```
mcp({ tool: "dense_mem_remember", args: {
  evidence: [{
    content: "project: <project>\ntype: <type>\ntags: project:<project>,<type>,<relevant-concepts>\nconfidence: medium\nvalid_until: <YYYY-MM-DD, today + 90 days>\n\n<concise summary, under 200 chars>",
    source_type: "observation"
  }],
  relationships: [{
    ref: "<type>:<project>:<task_id>",
    subject: { name: "<project>", entity_kind: "project" },
    predicate: { proposed_key: "project:<type>:outcome" },
    object: { entity: { name: "task:<task_id>", entity_kind: "concept" } },
    polarity: "+",
    evidence_indices: [0]
  }],
  idempotency_key: "<type>:<project>:<task_id>:<hash-of-content>"
} })
```

Notes:
- `relationships` is **required**. Keep `subject` as the project entity, pick a stable `proposed_key` per record type (`project:task:outcome`, `project:review:verified`, `project:exploration:anti-pattern`, `project:user:feedback`, `project:rules:<key>`, `library:docs:cache`), and cite `evidence_indices: [0]` for single-evidence submissions.
- `source_type` is an enum: `conversation`, `document`, `observation`, `manual`. Older values `task_outcome`, `review_outcome`, `tool_output` no longer exist and are rejected. Map: experiential outcomes (task, review, exploration, feedback) → `observation`; rules caches and project metadata → `manual`; docs cache → `document`.
- `supersedes_evidence_ids` lives **inside an evidence item**, not at the top level. Top-level fields other than `evidence`, `relationships`, `idempotency_key` are rejected (`additionalProperties: false`).
- `claims`, `tags`, `filter` are not in dense-mem's `remember` API. Tags go inside the content (structured prefix), filters go inside the query.
- `confidence` and `valid_until` are not API fields; keep them as lines in `content`.
- `valid_until` is the TTL date for decay. Format: ISO `YYYY-MM-DD`. The `memory-gc` skill retires evidence after this date. See `.pi/skills/memory-gc/SKILL.md` for the policy.
- `idempotency_key` is required. Use a hash of the content so retried writes don't duplicate.
- `remember` is **asynchronous**: it validates the submission, then queues graph verification. It returns a `submission_id`; poll `get_submission_status(submission_id)` once, but do not block the task on it.
- Only call `remember` AFTER success (validation passed / task completed) — never for work in progress.
- Cap `content` at one sentence (~200 chars) for ordinary tasks. Use longer content only for review verdicts and exploration anti-patterns.
- Recall only returns evidence supported by an **active relationship**; the relationship above is what makes a record recallable.

## Corrections

- If QA proves a recalled solution was wrong, find the offending record with `mcp({ tool: "dense_mem_trace_memory", args: { ... } })`.
- If the coder profile owns the record, retire it with `mcp({ tool: "dense_mem_retract_evidence", args: { evidence_ids=[...], reason="...", idempotency_key="..." } })`.
- dense-mem enforces ownership: you can only correct/retract evidence your own profile submitted. Reviewer-owned records are corrected by the reviewer.
- For relationship corrections, use `mcp({ tool: "dense_mem_correct_relationship", args: { ... } })` (only if the caller owns the active Relationship).
