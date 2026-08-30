---
name: dense-mem
description: Native Pi tool syntax for dense-mem (pi-dense-mem extension). Tools are registered as `dense_mem_*` at session start; call them directly. No MCP proxy, no `mcp({ tool: ... })` wrapping.
---

# Dense-mem call syntax (pi-dense-mem@0.1.0)

Workers and the orchestrator call dense-mem tools **directly by name**. The
pi-dense-mem extension registers them as native Pi tools at session start;
there is no `mcp` proxy, no `connect` step, and no `mcp({ tool: ... })`
wrapper. The previous `mcp__dense_mem__*` namespace tools and the
`mcp({ tool: "<server>_<tool>", args: {...} })` shape are gone.

## Recall

```
dense_mem_recall_memory({ query: "<query>", limit: 10 })
```

- `query` is required; embed project/feature tags directly in the string
  (e.g. `"project:my-app anti-pattern auth"`). The v2.6 API has no
  top-level `tags` or `filter` field — filtering happens in the query.
- `limit` defaults to 10, max 50. Response items are
  `{ evidence_id, context, space_kind }` — read `context` (the bounded
  stored content, ≤ 2000 chars); never `content`.

## Remember (v2.6 contract — `evidence` + `relationships` + `idempotency_key`)

```
dense_mem_remember({
    evidence: [{
      authority: "authoritative" | "primary" | "secondary" | "inferred" | "unknown",
      content: "<verbatim evidence text, ≤ 2000 chars>"
    }],
    relationships: [{
      ref: "<relationship ref, e.g. 'task:my-app:frontend:42'>",
      subject: { name: "<project or entity name>", entity_kind: "<entity_kind>" },
      predicate: { proposed_key: "<predicate, e.g. 'project:task:outcome'>" },
      object: { entity: { name: "<object name>", entity_kind: "<entity_kind>" } },
      polarity: "+" | "-",
      evidence_indices: [0]
    }],
    idempotency_key: "<key, e.g. 'task:my-app:frontend:42'>"
  })
```

- `relationships` is **required** by the v2.6 schema — a submission
  without it is rejected. `supersedes_evidence_ids` is an evidence-item
  field, not a top-level one.
- `source_type` is an enum (`conversation`, `document`, `observation`,
  `manual`); older `task_outcome` / `review_outcome` / `tool_output`
  values are rejected.
- Tags/confidence/valid_until are content lines, not API fields.
- `remember` is async (returns `submission_id`); poll
  `dense_mem_get_submission_status` once if you need confirmation, but
  do not block the task on it.

## Other tools (same direct call shape)

- `dense_mem_trace_memory({ evidence_id })` — find provenance of a
  recalled record.
- `dense_mem_retract_evidence({ evidence_ids: [...], reason: "...",
  idempotency_key: "..." })` — retire evidence you own.
- `dense_mem_correct_relationship({ relationship_id, ... })` — correct
  an active relationship you own.
- `dense_mem_get_submission_status({ submission_id })` — one-shot check
  on an async `remember`.
- `dense_mem_export_memory_pack(...)` — full memory dump; **do not** call
  this in the orchestrator or worker flow — it is heavy and not needed
  for normal operation.

## Graceful degradation

If any `dense_mem_*` tool call returns an error or the server is
"not connected", continue without memory. Disk `AGENTS.md` / `SOUL.md`
remain the source of truth. Never block the task on a memory call.
