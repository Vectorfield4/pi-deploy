# Review Fix (`type == "review"`)

Loaded by `execute-task` when QA moved the task back for fixes. Same branch and PR are reused.

## Steps

1. **Load project rules** — run load procedure from `references/memory.md`.

2. **Read QA findings**
   - `kanban_get_task({{ env.HERMES_KANBAN_TASK }})`.
   - Extract issues from description / latest comment.
   - If none → `kanban_block --reason "No QA findings in task"`.

3. **Trace recalled anti-patterns** (best-effort)
   - If the failing code came from E-pool recall → `mcp_dense_mem_trace_memory(...)` to find provenance.
   - If you stored evidence that proved wrong → `mcp_dense_mem_retract_evidence(...)`.

4. **Exploration check** (iteration ≥ 3)
   - If `metadata.review_iterations >= 3` AND `exploration_triggered != true`:
     - Store anti-pattern (best-effort): `mcp_dense_mem_remember(evidence="EXPLORATION: Task '<title>' failed <N> iterations. Recurring: <pattern>. Orchestrator must re-decompose.", tags=["anti-pattern", "exploration", "project:<project>"], confidence=high)`
     - Flag and hand to QA: `kanban_move --status ready --assignee qa --comment "EXPLORATION NEEDED: <N> iterations failed."` with `exploration_flag: true`.
     - Return — do not attempt another fix.
   - If `exploration_triggered == true` → hand to QA immediately. Return.

5. **Apply fixes**
   - `cd /workspace/<project>-{{ env.HERMES_KANBAN_TASK }}`
   - `git fetch origin <branch> && git rebase origin/<branch>`
   - Fix each reported issue per project `AGENTS.md` and relevant stack references.
   - `kanban_heartbeat` before long operations.

6. **Validate** — run project validation (lint/test/build). Fix failures before pushing.

7. **Push** — commit and push to same branch. Load retry protocol for push.

8. **Hand back to QA**
   - `kanban_move --status ready --assignee qa --comment "Fixed: <summary>"`
   - Do NOT `kanban_complete` — task stays in review loop until QA passes.
   - On failure: `kanban_block --reason "<error>"` + cleanup worktree.
