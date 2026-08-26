# Project Rules via RAG (dense-mem E-pool)

Loaded by `execute-task` before component / PR flows. Project rules (AGENTS.md / SOUL.md sections) are cached in the RAG E-pool as tagged records and keyed by the project rules hash. The disk files remain the deterministic fallback.

## Load procedure (for component / PR tasks)

For each key in `rules_keys_needed`:
- Recall the rule record: `mcp_dense_mem_recall_memory(query="project rules for <project>: <key>", filter={tags: ["project-rules:<project>", "rules:<key>"]} where the tool supports filters)`.
- If found AND its `rules_hash` claim equals the metadata `rules_hash` → use it as authoritative.
- If not found OR hash mismatch → read `/workspace/<project>/AGENTS.md` and `/workspace/<project>/SOUL.md` (if exist) and extract the section for this key directly. The disk fallback is deterministic and authoritative.
- Do **not** store or replace rule records from the coder profile: rule records are owned by the orchestrator (dispatcher), which re-stores them on the next orchestration when the hash changes.
- Block only if the rule is also missing on disk and cannot be extracted → `kanban_block`.

## Record schema (E-pool, written by the orchestrator)

**Index record**:
`mcp_dense_mem_remember(evidence={"keys": ["ui-conventions", "api-standards", "testing-patterns"], "rules_hash": "a1b2c3d4..."}, tags=["project-rules:<project>", "rules-index"], confidence=high)`

**Rule record**:
`mcp_dense_mem_remember(evidence="<section content>", tags=["project-rules:<project>", "rules:<key>"], claims=[<rules_hash claim>], confidence=high)`

## Cache invalidation logic

- `rules_hash` in task metadata (set by the orchestrator) is authoritative.
- If a recalled record's `rules_hash` != the current `rules_hash` → treat it as stale, fall back to disk, and let the orchestrator re-store on its next run.
