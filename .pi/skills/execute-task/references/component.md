# Component Execution (`component == true`)

Loaded by `execute-task` after project rules are loaded (see `references/memory.md`).

The task arrives as a **JSON string** — parse it as `task` and read fields
via `task.type`, `task.description`, `task.metadata.*`, etc. (The
`subagent` tool only accepts `task` as a string; the orchestrator serializes
the context bundle into it.)

## Steps

0. **Check task type**
   - `task.metadata.type == "refactoring"` → skip to **Refactoring path** below.
   - Otherwise → standard flow.

## Standard flow (feature/bugfix/content/integration)

1. **Validate acceptance criteria**
   - Read the `acceptance_criteria` array from `task` (or
     `task.metadata.acceptance_criteria`). For each: does it trace to
     `task.description`? If invented → drop. If not verifiable via lint/test →
     note "manual review only".
   - Missing entirely → add comment: `"No acceptance_criteria — QA will review against description only"`.

2. **Identify component type** — from `task.type` / `task.metadata.type`,
   else infer from `title`/`description`.

3. **Recall experience (RAG)** — load `references/rag.md` if not loaded.
   - If `task.metadata.memory_context` is present and non-empty (orchestrator pre-batched): use it as context. Skip the recall call. Also read `task.metadata.anti_patterns` if present and apply as warnings.
   - If `task.metadata.memory_context` is absent or empty: call `mcp({ tool: "dense_mem_recall_memory", args: { query="<concise goal> project:<project>" } })`. On failure → continue without context.

4. **Fetch latest and rebase**
   ```
   cd /workspace/<project>-<task_id>
   git fetch origin <branch> && git rebase origin/<branch>
   ```
   If conflict → resolve via `resolve-merge-conflict` or abort and report.

5. **Implement the component**
   - Follow the skill instructions provided by the orchestrator for this task type.
   - For library docs: load the `docs-lookup` skill (Context7 with a 7-day dense-mem cache) — do not call `resolve-library-id`/`query-docs` directly.
   - Note: frontend tasks (UI components, 3D scenes, page assembly) are delegated to the `frontend-implementer` agent (complex ones also use `frontend-architect`) by the orchestrator. If you receive a frontend task, report it back.

6. **Quality check and commit**
   - Verify against judge rubric (see `execute-task` → Quality Targets). Fix deficient dimensions.
   - `git add . && git commit -m "Task #<task_id>: <description>" && git push origin <branch>`
   - Push conflict → fetch → rebase → push. On persistent failure, apply the retry protocol.

7. **Complete**
   - Success: store experience in memory (best-effort, don't block):
     ```
     mcp({ tool: "dense_mem_remember", args: {
       evidence: [{
         content: "project: <project>\ntype: <type>\ntags: project:<project>,<type>,<relevant-concepts>\nconfidence: medium\nvalid_until: <YYYY-MM-DD, today + 90 days>\n\n<what was done, key decisions, patterns used — under 200 chars>",
         source_type: "observation"
       }],
       relationships: [{
         ref: "task:<project>:<type>:<task_id>",
         subject: { name: "<project>", entity_kind: "project" },
         predicate: { proposed_key: "project:task:outcome" },
         object: { entity: { name: "task:<task_id>", entity_kind: "concept" } },
         polarity: "+",
         evidence_indices: [0]
       }],
       idempotency_key: "task:<project>:<type>:<task_id>"
     } })
     ```
   - Failure: return error details to the orchestrator.
   - Cleanup: `cd /workspace/<project> && git worktree remove --force /workspace/<project>-<task_id> 2>/dev/null || true`

## Refactoring path (`task.metadata.type == "refactoring"`)

Applies targeted edits to existing code instead of generating new components.

1. **Validate criteria** — same as standard step 1. Also read `task.metadata.target_files`.

2. **Fetch and rebase** — same as standard step 4.

3. **Read current code** — navigate to worktree, read each file in `task.metadata.target_files`. Understand current structure.

4. **Apply targeted edits**
   - Use `edit` tool per `change_description`. Preserve external behavior.
   - Do NOT regenerate from scratch. Edit only what needs to change.
   - Complex changes (>3 files or >100 lines diff) → split into smaller edits, commit incrementally.

5. **Validate** — run `npm run lint`, `npm run test`, `npm run build`. Verify existing tests pass, no API changes.

6. **Commit and push** — `git commit -m "Task #<task_id>: <description>" && git push origin <branch>`

7. **Complete** — same as standard step 7.
