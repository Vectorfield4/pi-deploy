# Experience Memory (E-pool) via dense-mem

Loaded by `execute-task` for `component` and `review` flows. Provides RAG over past solutions, patterns, and decisions across sessions. The dense-mem server is reached through MCP; Hermes exposes its tools with the `mcp_dense_mem_` prefix (e.g. `mcp_dense_mem_recall_memory`).

## Principles

- The E-pool is **experiential and advisory** — never authoritative.
- Project rules (AGENTS.md / SOUL.md, loaded via `references/memory.md`) are themselves stored in the E-pool as tagged records (`project-rules:<project>`) and always win over untagged experience hints. Rule records are written only by the orchestrator; the coder recalls them but never writes rules.
- Any recalled template is only a starting point: it must still pass validation (lint / test / build) before it can be committed.
- **Graceful degradation**: a failed or unavailable memory call must never block the task. Wrap every MCP call as best-effort; on error, continue without context.
- Store only compressed, structured outcomes — never raw full-source dumps.

## Recall (before executing)

- Call `mcp_dense_mem_recall_memory(query="<concise goal of the work>")`.
- Use a short goal-oriented query (e.g. `react-hook-form + zod auth form with MUI for <project>`) rather than a long paste.
- Distinguish rules from experience: rule records are tagged `project-rules:<project>` (recalled via `references/memory.md`); everything else is advisory experience.
- Treat the top results as context hints (patterns, prior decisions, known pitfalls). If a result carries high confidence and a verified source, you may reuse it as a template — but still validate.
- **Recall anti-patterns**: call `mcp_dense_mem_recall_memory(query="<goal>", filter={tags: ["anti-pattern", "project:<project>"]})`. If recalled, these are known failures — use a different approach.
- **Recall exploration anti-patterns**: call `mcp_dense_mem_recall_memory(query="<goal>", filter={tags: ["anti-pattern", "exploration", "project:<project>"]})`. These are decomposition strategies that failed after ≥3 review iterations. Do NOT repeat the same approach.
- Graceful degradation: on failure or empty results, proceed without context.

## Remember (after a successful task)

- Call `mcp_dense_mem_remember(...)` with:
  - `evidence` — a concise, structured summary of what was done and the key decisions (keep each item under ~1000 characters).
  - optional typed claims describing the key facts (follow the tool's JSON schema; include confidence where supported).
  - tags covering `project:<project>`, the task `type` (ui / content / integration), and reusable concepts (e.g. `auth`, `forms`, `threejs`).
- `remember` is asynchronous: it returns a `submission_id`. You may poll `mcp_dense_mem_get_submission_status` once; do not block the task on it.
- Only call `remember` AFTER success (validation passed / task completed) — never for work in progress.
- Never store rule text via `remember`: rules records are owned by the orchestrator (see `references/memory.md`). Store experience / decisions only.

## Corrections

- If QA later proves a recalled solution was wrong, find the offending record with `mcp_dense_mem_trace_memory(...)`.
- If YOU (the coder profile) own it, retire it best-effort with `mcp_dense_mem_retract_evidence(...)` (or `mcp_dense_mem_correct_relationship`) so the bad pattern is not recalled again.
- dense-mem enforces ownership: you can only correct/retract evidence your own profile submitted. QA-owned records are corrected by QA.
