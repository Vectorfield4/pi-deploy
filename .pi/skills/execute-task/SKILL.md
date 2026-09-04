---
name: execute-task
description: "Executes a single development sub-task (UI, content, integration) or initializes a new project."
---

# Execute Task

The task arrives as a **JSON string** — parse it and read fields via
`task.type`, `task.cwd`, `task.project`, `task.branch`, `task.metadata.*`, etc.

## Steps

### 1. Setup worktree
- Extract `project` and `branch` from the task.
- Skip worktree for `type: init` tasks.
- Create worktree: `git worktree add /workspace/<project>-<task_id> <branch>`

### 1.5. Memory contract (mandatory for `component` and `review`)

Before dispatching step 2, honor the orchestrator's pre-batched memory:

- If `task.metadata.memory_context` is present and non-empty, use it. Do not recall again.
- If `task.metadata.anti_patterns` is present and non-empty, treat each entry as a hard warning (apply to avoid repeating the failure). Project `AGENTS.md` still overrides on conflict.
- If both fields are absent or empty, the orchestrator did not pre-batch (ad-hoc path). One `pgvec_recall_memory({ query:"<concise goal> <project>" })` only. Never two parallel calls.

### 2. Dispatch by task type
- `type == "init"` → load `references/init.md`
- `component == true` → load `references/memory.md` → `references/rag.md` → `references/component.md`
- `type == "review"` → load `references/memory.md` → `references/rag.md` → `references/review-fix.md`
- Otherwise → report "Unknown task type"

Work on the branch, commit and push it.

## Conventions

- Failure → report error with details to the orchestrator
- Success → return summary to the orchestrator
- Workspace: `/workspace/<project>-<task_id>` (worktree)
- Comments: short, inline (same line where practical), only "why" (non-obvious intent/ordering/tolerance); never restate the code, no banners/section headers/attribution

## Final-message contract

The final message is the only text the user reads as your result.

- ≤ 6 lines, plain prose, no fenced code, no JSON.
- Format: `✅ <one-line outcome>. <commit/branch + 1-line what changed>.`
- Long output → `artifacts/<task_id>-report.md`. Reference by path or omit.

## Tool-call discipline

- `telegram_notify(kind="task", …)` at most twice per turn: once at
  `status="started"`, once at `status="complete"`.
- `telegram_send` is for one-off notes only. Status pings between
  subagent handoffs are not notes.

## Quality Targets

| Dimension | Weight | Target |
|-----------|--------|--------|
| Code quality | 25% | DRY, clear naming, separation of concerns |
| Tests | 25% | Cover new logic, edge cases |
| Security | 25% | No hardcoded secrets, input validation |
| Docs | 25% | Follow AGENTS.md conventions |

## Content Quality Overlay (`type == content`)

Load `references/prose-quality.md`. Apply AFTER standard quality check:
1. Grep for banned words/phrases
2. Every benefit claim must have a number/constraint
3. CTA must describe the actual next step
4. Copy-paste test: could it appear on a competitor's site?

## Verification
- Worktree exists on correct branch
- Task completed or blocked with details
- No task remains in intermediate state
