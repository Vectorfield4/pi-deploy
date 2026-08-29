---
name: dense-mem
description: dense-mem MCP call syntax. Dense-mem is reached through the `mcp` proxy tool; the right call shape is `mcp({ tool: "<server>_<tool>", args: {...} })`.
---

# Dense-mem call syntax (pi-subagents@0.58.0)

Workers and the orchestrator reach dense-mem through the `mcp` proxy tool,
not through direct `mcp__dense_mem__*` namespace tools (the direct tools
are not registered for these agents — the `mcp` meta-tool is). The
`syntax` in skill prose that says `mcp__dense_mem__recall_memory(query=...)`
does not work as written; it produced 4 failed `mcp({...})` attempts per
`remember` in the last task. Use the shape below instead.

## Connect (idempotent — once per session)

```
mcp({ connect: "dense_mem" })
```

If the server is already connected, this is a no-op. Do it once at the
start of the task; subsequent calls reuse the live connection.

## Recall

```
mcp({
  tool: "dense_mem_recall_memory",
  args: { query: "<query>", limit: 10 }
})
```

- `query` is required; embed project/feature tags directly in the string
  (e.g. `"project:my-app anti-pattern auth"`). The v2.6 API has no
  top-level `tags` or `filter` field — filtering happens in the query.
- `limit` defaults to 10, max 50. Response items are
  `{ evidence_id, context, space_kind }` — read `context` (the bounded
  stored content, ≤ 2000 chars); never `content`.

## Remember (v2.6 contract — `evidence` + `relationships` + `idempotency_key`)

```
mcp({
  tool: "dense_mem_remember",
  args: {
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
  }
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

## Other tools (same `mcp({ tool: ... })` shape)

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

If `mcp({ tool: "dense_mem_*" })` returns an error or the server is
"not connected", continue without memory. Disk `AGENTS.md` / `SOUL.md`
remain the source of truth. Never block the task on a memory call.
