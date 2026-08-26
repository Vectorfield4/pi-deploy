# Component Execution (`component == true`)

Loaded by `execute-task` after project rules are loaded (see `references/memory.md`).

## Steps

0. **Check task type**
   - `metadata.type == "refactoring"` → skip to **Refactoring path** below.
   - Otherwise → standard flow.

## Standard flow (feature/bugfix/ui/content/integration)

1. **Validate acceptance criteria**
   - Read `metadata.acceptance_criteria`. For each: does it trace to `description`? If invented → drop. If not verifiable via lint/test → note "manual review only".
   - Missing entirely → add comment: `"No acceptance_criteria — QA will review against description only"`.

2. **Identify component type** — from `metadata.type`, else infer from `title`/`description`.

3. **Recall experience (RAG)** — load `references/rag.md` if not loaded. Call `mcp_dense_mem_recall_memory(query="<concise goal>")`. On failure → continue without context.

4. **Fetch latest and rebase**
   ```
   cd /workspace/<project>-{{ env.HERMES_KANBAN_TASK }}
   git fetch origin <branch> && git rebase origin/<branch>
   ```
   If conflict → resolve via `resolve-merge-conflict` or abort and report.

5. **Discover and invoke the right skill**
   - Collect tags from `metadata.tags`, `metadata.type`, and title/description keywords.
   - `skill_discover(tags)` → pick highest match.
   - Load stack references based on skill type:
     - UI/layout → `references/mui.md`, `references/react.md`
     - 3D → `references/threejs-r3f.md`
     - Animation → `references/gsap.md`
     - State/forms → `references/zustand.md`, `references/react-hook-form.md`, `references/zod.md`
     - Data → `references/tanstack-query.md`
   - `skill_run(<discovered_skill>, project, branch, description, rules_context)`.
   - Fallback: `skill_run(simple-task-executor, ...)` if no match.

6. **Quality check and commit**
   - Verify against judge rubric (see `execute-task` → Quality Targets). Fix deficient dimensions.
   - `git add . && git commit -m "Task #<task_id>: <description>" && git push origin <branch>`
   - Push conflict → fetch → rebase → push. Load retry: `skill_view("create-pr", "references/retry.md")`.

7. **Complete**
   - Success: `kanban_complete --comment "Component implemented."` + store experience in E-pool (best-effort, don't block).
   - Failure: `kanban_block --reason "<error>"`.
   - Cleanup: `cd /workspace/<project> && git worktree remove --force /workspace/<project>-{{ env.HERMES_KANBAN_TASK }} 2>/dev/null || true`

## Refactoring path (`metadata.type == "refactoring"`)

Applies targeted edits to existing code instead of generating new components.

1. **Validate criteria** — same as standard step 1. Also read `metadata.target_files`.

2. **Fetch and rebase** — same as standard step 4.

3. **Read current code** — navigate to worktree, read each file in `metadata.target_files`. Understand current structure.

4. **Apply targeted edits**
   - Use `edit` tool per `change_description`. Preserve external behavior.
   - Do NOT regenerate from scratch. Edit only what needs to change.
   - Complex changes (>3 files or >100 lines diff) → split into smaller edits, commit incrementally.

5. **Validate** — run `npm run lint`, `npm run test`, `npm run build`. Verify existing tests pass, no API changes.

6. **Commit and push** — `git commit -m "Task #<task_id>: <description>" && git push origin <branch>`

7. **Complete** — same as standard step 7.
