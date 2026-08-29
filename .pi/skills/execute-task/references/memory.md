# Project Rules via dense-mem Memory

Loaded by `execute-task` before component / PR flows. Project rules from `AGENTS.md` (and `SOUL.md` if present) are cached in dense-mem as durable evidence, keyed by project and `rules_hash`. The disk files remain the deterministic source of truth.

## dense-mem as the cache

`remember` writes evidence with `idempotency_key` so retried writes are safe, and anchors each record with a supporting `relationship` (required by the v2.6 contract — a submission without `relationships` is rejected). `supersedes_evidence_ids` (an **evidence-item** field) advances a record to a new content version without losing lineage. `recall_memory(query=...)` is evidence-first and support-path gated: only active evidence with eligible support returns — which is exactly what our per-record relationships provide.

We do not invent tags or filter parameters that don't exist in the API. Tags are encoded in the content (see schema below). Filtering happens in the query string.

## Load procedure (for component / PR tasks)

For each `rules_key` in `metadata.rules_keys_needed` (default keys: `["ui-conventions", "api-standards", "testing-patterns", "build-deploy", "content-voice"]` chosen by project type in `orchestrate-task` step 3.5):

1. `mcp__dense-mem__recall_memory(query="project-rules project:<project> key:<rules_key>")`.
2. Parse the top result's `context` (results are `{ evidence_id, context, space_kind }`). Extract the first-line `rules_hash: <hash>`.
3. If `rules_hash == metadata.rules_hash` → use it as authoritative.
4. If hash mismatch or recall returns nothing → read `/workspace/<project>/AGENTS.md` and `/workspace/<project>/SOUL.md` (if present) directly and extract the section for this key. The disk fallback is deterministic and authoritative.
5. Never write rule cache from the coder or frontend-implementer profile. Orchestrator owns the rule cache.

## Record schema (orchestrator writes, others recall)

Each rule is a single evidence item. Tags and hash live in the content as a structured prefix so dense-mem's embedding match finds them on `recall_memory(query=...)`:

```
mcp__dense-mem__remember({
  evidence: [{
    content: "rules_hash: a1b2c3d4\nkey: ui-conventions\nproject: my-app\ntags: project-rules,ui-conventions,my-app\n\n<actual section content from AGENTS.md>",
    source_type: "manual"
  }],
  relationships: [{
    ref: "rules:my-app:ui-conventions:a1b2c3d4",
    subject: { name: "my-app", entity_kind: "project" },
    predicate: { proposed_key: "project:rules:ui-conventions" },
    object: { entity: { name: "ui-conventions", entity_kind: "concept" } },
    polarity: "+",
    evidence_indices: [0]
  }],
  idempotency_key: "rules:my-app:ui-conventions:a1b2c3d4"
})
```

Notes:
- `idempotency_key` is a function of `project + key + rules_hash`. Re-running with the same hash reuses the existing record. Re-running with a new hash creates a new record and supersedes the old one.
- `source_type` is an enum (`conversation`, `document`, `observation`, `manual`); rules caches use `manual`. The older values `task_outcome`, `review_outcome`, `tool_output` no longer exist and are rejected — do not use them.
- Tags are inside the content as a comma-separated list on the `tags:` line. They are not a real dense-mem field.
- `confidence` is not a separate top-level field. If needed, embed it in the content: `confidence: high`.
- The `relationship` is what makes the record eligible for recall under support-path gating. Subject stays the project entity; predicate key is `project:rules:<rules_key>`.

## Cache invalidation

`metadata.rules_hash` (set by the orchestrator from `git rev-parse HEAD` of the project) is the authority.

- A recalled record's `rules_hash` (first line of `context`) matches → fresh, use the cached content.
- Hash mismatch → treat as stale. The orchestrator writes a new record with a new `idempotency_key` and lists the old evidence in `supersedes_evidence_ids` **on the new evidence item** (top-level supersession is not part of the v2.6 contract).
- Coder/frontend-implementer never supersede rules. They only read.

## Supersession example

When `AGENTS.md` changes and `git rev-parse HEAD` returns a new hash:

```
mcp__dense-mem__remember({
  evidence: [{
    content: "rules_hash: 9z9z9z9z\nkey: ui-conventions\nproject: my-app\ntags: project-rules,ui-conventions,my-app\n\n<new section content>",
    source_type: "manual",
    supersedes_evidence_ids: ["<old-evidence-uuid-from-prior-batch>"]
  }],
  relationships: [{
    ref: "rules:my-app:ui-conventions:9z9z9z9z",
    subject: { name: "my-app", entity_kind: "project" },
    predicate: { proposed_key: "project:rules:ui-conventions" },
    object: { entity: { name: "ui-conventions", entity_kind: "concept" } },
    polarity: "+",
    evidence_indices: [0]
  }],
  idempotency_key: "rules:my-app:ui-conventions:9z9z9z9z"
})
```

dense-mem appends a lifecycle event and the new record becomes active. The old record is retired for recall but preserved in lineage for traceability.
