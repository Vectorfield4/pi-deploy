# Experience Memory via pgvec

Loaded by `execute-task` for `component` and `review` flows. Provides recall over past solutions, patterns, and decisions across sessions. The pi-pgvector-api-embeddings extension registers memory tools as native Pi tools under the `pgvec_` prefix; call them directly (e.g. `pgvec_recall_memory({ query: "..." })`).

## Batched recall (orchestrator → workers)

The orchestrator does **one** batched recall per task and passes the result to each sub-task via `task.metadata.memory_context` (inside the task JSON string). Workers should NOT recall again — they read the context they were given. The `component.md` step 3 enforces this.

```
// In orchestrate-task step 4.5:
results = pgvec_recall_memory({ query:"<main goal> <project>", limit:10 })
// Pass to each sub-task in step 7, inside the task JSON string:
metadata.memory_context = summarize(results)
metadata.anti_patterns = pgvec_recall_memory({ query:"<main goal> <project>", tag:"anti-pattern", limit:3 })
```

For ad-hoc tasks that bypass `orchestrate-task`, `component.md` falls back to its own recall.

## Principles

- Memory is **experiential and advisory** — never authoritative. Project rules in `AGENTS.md` are the source of truth, read from disk.
- The memory is **append-only**. Updates go through `pgvec_remember` (idempotency_key) or `pgvec_retract_evidence`. Never delete or rewrite.
- **Ownership**: each profile can only `pgvec_retract_evidence` on records it owns. Coder owns its task evidence; reviewer owns review evidence.
- **Graceful degradation**: a failed or unavailable memory call must never block the task. On error, continue without context.
- Store only compressed, structured outcomes — never raw full-source dumps.
- **Value gate on writes**: `remember` costs an LLM turn to compose the
  evidence. Write only when the outcome is a reusable lesson — a non-obvious
  approach, a pitfall, or a decision a future task should reuse. Skip
  routine/mechanical tasks and mere "passed" verdicts; composing trivial
  evidence is wasted cost. Bounce, explore, design-decision, and feedback
  writes always write. Rules and docs caches are plain on-disk files, not
  memory.

## Recall (when batched context is absent)

- `pgvec_recall_memory({ query:"<concise goal of the work>" })`
- Use a short goal-oriented query (e.g. `react-hook-form + zod auth form with MUI for <project>`) rather than a long paste.
- Filter by record type via the `tag` param, not by stuffing tokens in the query: `pgvec_recall_memory({ query:"auth form", tag:"anti-pattern" })`.
- Results are `{ evidence_id, context, space_kind }` — read the `context` field (stored content, bounded at 2000 chars), never `content`. A recalled record's structured prefix (first lines) is the discriminator: `project:`, `valid_until:`, `type:`, etc.
- Treat the top results as context hints. Even high-confidence results must still pass validation (lint / test / build) before commit.
- **Anti-pattern recall**: `pgvec_recall_memory({ query:"<goal> <project>", tag:"anti-pattern" })`.
- **Exploration anti-patterns**: `pgvec_recall_memory({ query:"<goal> <project>", tag:"anti-pattern" })` and check the content for an exploration flag — decomposition strategies that failed after ≥3 review iterations, do not repeat.
- Graceful degradation: on failure or empty results, proceed without context.

## Remember (after a successful task)

`pgvec_remember` writes a flat record: `content` text plus `tags` /
`source_type` / `valid_until` / `confidence` / `idempotency_key`.

```
pgvec_remember({
  content: "project: <project>\ntype: <type>\ntags: project:<project>,<type>,<relevant-concepts>\nconfidence: medium\nvalid_until: <YYYY-MM-DD, today + 90 days>\n\n<concise summary, under 200 chars>",
  tags: ["project:<project>", "<type>", "<relevant-concepts>"],
  source_type: "observation",
  valid_until: "<YYYY-MM-DD, today + 90 days>",
  confidence: "medium",
  idempotency_key: "<type>:<project>:<task_id>"
})
```

Notes:
- `content`, `source_type` (enum `conversation|document|observation|manual`),
  and `idempotency_key` are required. Unknown keys are rejected
  (`additionalProperties: false`) — no `predicate`/`entity`/`polarity`.
- `tags` is the query filter; recall `tag` must equal a stored tag.
- Record types (tags): `anti-pattern`, `review-bounce`, `design-decision`,
  `verified`, `user-feedback`, plus `project:<name>`.
- `source_type`: experiential outcomes (task/review/feedback/anti-pattern) →
  `observation`; project metadata → `manual`.
- The structured prefix stays in `content` (self-describing); the flat
  `tags` array drives the recall `tag` filter.
- `valid_until` is the TTL date (ISO `YYYY-MM-DD`); `memory-gc` retires
  evidence after it. See `.pi/skills/memory-gc/SKILL.md` for policy.
- `idempotency_key` dedupes re-sent writes; use a stable key per record.
- `remember` is **asynchronous** (fire-and-forget): returns a `submission_id`; do not poll in the task flow — a failed async write is harmless.
- Only call `remember` AFTER success (validation passed / task completed) — never for work in progress.
- Cap `content` at one sentence (~200 chars) for ordinary tasks. Use longer content only for review verdicts and exploration anti-patterns.

## Corrections

- If QA proves a recalled solution was wrong, retire the bad record with
  `pgvec_retract_evidence({ evidence_ids:["<evidence_id from recall>"], reason:"..." })` — the recall result supplies the `evidence_id`, so this is the actionable bug-fix path.
- Ownership: you can only retract evidence your own profile submitted. Reviewer-owned records are corrected by the reviewer.
