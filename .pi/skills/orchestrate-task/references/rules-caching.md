# Rules Caching (orchestrator, step 3.5)

Project rules are cached in dense-mem as durable evidence keyed by the project
rules hash. The disk files remain the deterministic fallback.

## Rule keys by project type

- frontend: `ui-conventions`, `testing-patterns`
- backend: `api-standards`, `testing-patterns`
- fullstack: `ui-conventions`, `api-standards`, `testing-patterns`
- CLI/lib: `cli-conventions`, `testing-patterns`
- infra: `infra-conventions`, `build-deploy`
- content: `content-voice`
- (always) the `rules-index` record

## Procedure

For each `rules_key` you read from disk:

1. Recall the existing record: `dense_mem_recall_memory({ query:"project-rules project:<project> key:<rules_key>" })`.
2. If found → parse `rules_hash:` from the first line of the result's `context` (results are `{ evidence_id, context, space_kind }`). If it matches the current `rules_hash` → skip, the cache is fresh.
3. If not found OR hash mismatch → write a new record (the `relationship` is required by the v2.6 contract and makes the record recallable):
   ```
   dense_mem_remember({
     evidence: [{
       content: "rules_hash: <hash>\nkey: <rules_key>\nproject: <project>\ntags: project-rules,<rules_key>,<project>\n\n<actual section content from disk>",
       source_type: "manual",
       supersedes_evidence_ids: ["<old-uuid-if-superseding>"]
     }],
     relationships: [{
       ref: "rules:<project>:<rules_key>:<hash>",
       subject: { name: "<project>", entity_kind: "project" },
       predicate: { proposed_key: "project:rules:<rules_key>" },
       object: { entity: { name: "<rules_key>", entity_kind: "concept" } },
       polarity: "+",
       evidence_indices: [0]
     }],
     idempotency_key: "rules:<project>:<rules_key>:<hash>"
   })
   ```
4. After all rule records → write the index record once:
   ```
   dense_mem_remember({
     evidence: [{
       content: "rules_index: <hash>\nproject: <project>\ntags: project-rules,index,<project>\nkeys: <comma-separated-list>",
       source_type: "manual"
     }],
     relationships: [{
       ref: "rules-index:<project>:<hash>",
       subject: { name: "<project>", entity_kind: "project" },
       predicate: { proposed_key: "project:rules:index" },
       object: { entity: { name: "rules-index", entity_kind: "concept" } },
       polarity: "+",
       evidence_indices: [0]
     }],
     idempotency_key: "rules-index:<project>:<hash>"
   })
   ```
5. On any MCP failure → log and continue. Never block orchestration on the cache write; disk is the source of truth.

This step makes the read-side `execute-task/references/memory.md` load procedure actually find records. Without it, every worker task falls back to disk.
