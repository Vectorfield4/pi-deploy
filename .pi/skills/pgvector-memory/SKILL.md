---
name: pgvector-memory
description: Native Pi tool syntax for pi-pgvector-api-embeddings lightweight RAG. Tools are registered as `pgvec_*` at session start; call them directly. No MCP proxy, no `mcp({ tool: ... })` wrapping.
---

# pgvec memory call syntax (pi-pgvector-api-embeddings)

Workers and the orchestrator call memory tools **directly by name**. The
pi-pgvector-api-embeddings extension registers them as native Pi tools at
session start; there is no `mcp` proxy, no `connect` step, and no
`mcp({ tool: ... })` wrapper.

## Recall

```
pgvec_recall_memory({ query: "<query>", limit: 10, tag: "<tag>" })
```

- `query` is required; it is embedded and matched by cosine similarity.
  Keep it to the semantic goal — do not stuff filter tokens in the string.
- `tag` is optional; filter to a record type (e.g. `anti-pattern`,
  `review-bounce`, `design-decision`, `verified`, `user-feedback`).
  Omit to search across all records.
- `limit` defaults to 10, max 50. Response items are
  `{ evidence_id, context, space_kind }` — read `context` (bounded stored
  content, ≤ 2000 chars); never `content`.

## Remember

```
pgvec_remember({
    content: "<verbatim evidence text, ≤ 2000 chars>",
    tags: ["project:<project>", "<record-type>", "<relevant-concepts>"],
    source_type: "observation",
    valid_until: "<YYYY-MM-DD, today + N days>",
    confidence: "medium",
    idempotency_key: "<stable key, e.g. 'task:<project>:<task_id>'>"
})
```

- `content` and `idempotency_key` are **required**; `source_type` is required
  enum: `conversation` | `document` | `observation` | `manual`. Unknown keys
  are rejected (`additionalProperties: false`) — no `predicate`/`entity`/
  `polarity` fields.
- `tags` is the query filter (recall `tag` must equal a stored tag). Record
  types: `anti-pattern`, `review-bounce`, `design-decision`, `verified`,
  `user-feedback`, plus `project:<name>`.
- `valid_until` is the TTL date (ISO `YYYY-MM-DD`; `memory-gc` retires past it).
- `source_type`: map experiential outcomes (task/review/feedback/anti-pattern)
  to `observation`; project metadata to `manual`.
- `idempotency_key` dedupes re-sent writes.
- `remember` is async (fire-and-forget): returns a `submission_id`. A failed
  write is harmless (memory is advisory); do not poll in the task flow.
- The human-readable prefix (`project:`, `type:`, `tags:`, `confidence:`,
  `valid_until:`) goes in the `content` text; the flat `tags` array drives
  the recall `tag` filter.

## Other tools (same direct call shape)

- `pgvec_retract_evidence({ evidence_ids: [...], reason: "..." })` — retire
  evidence you own. The recall result supplies the `evidence_id`, so this
  is the actionable bug-fix correction path.
- `pgvec_gc({ })` — retire evidence whose `valid_until` has passed. Called
  by the QA skill `memory-gc`, not by workers.

## Graceful degradation

If a `pgvec_*` tool call errors or the server is "not connected", continue
without memory. Disk `AGENTS.md` / `SOUL.md` remain the source of truth.
Never block the task on a memory call.
