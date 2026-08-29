# Review Fix (`type == "review"`)

Loaded by `execute-task` when QA moved the task back for fixes. Same branch is reused.

## Steps

1. **Load project rules** — run load procedure from `references/memory.md`.

2. **Read QA findings**
   - Extract issues from the task description / latest comment passed by the orchestrator.
   - If none → return "No QA findings in task" to the orchestrator.

3. **Trace recalled anti-patterns** (best-effort)
   - If the failing code came from memory recall → `mcp({ tool: "dense_mem_trace_memory", args: { ... } })` to find provenance.
   - If you stored evidence that proved wrong → `mcp({ tool: "dense_mem_retract_evidence", args: { ... } })`.

4. **Apply fixes**
   - `cd /workspace/<project>-<task_id>`
   - `git fetch origin <branch> && git rebase origin/<branch>`
   - Fix each reported issue per project `AGENTS.md` and relevant stack references.
   - QA owns the exploration trigger. Do not write exploration anti-patterns from this skill. If `review_iterations >= 3` and you get a `review` task back, apply the best fix you can — QA will trigger exploration on its side if needed.

5. **Validate** — run project validation (lint/test/build). Fix failures before pushing.

6. **Push** — commit and push to same branch. Apply retry protocol on push failure.

7. **Hand back to QA**
   - Return to orchestrator: "Fixed: <summary>" — the orchestrator re-delegates to QA.
   - Do NOT mark as complete — task stays in review loop until QA passes.
   - On failure: return error details + cleanup worktree.
