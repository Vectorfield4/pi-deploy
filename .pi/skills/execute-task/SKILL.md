---
name: execute-task
description: "Executes a single development sub-task (UI, content, integration) or initializes a new project."
---

# Execute Task

The task arrives as a **JSON string** — parse it and read fields via
`task.type`, `task.project`, `task.branch`, `task.metadata.*`, etc.

## Steps

### 1. Setup worktree
- Extract `project` and `branch` from the task.
- Skip worktree for `type: init` tasks.
- Create worktree: `git worktree add /workspace/<project>-<task_id> <branch>`

### 2. Dispatch by task type
- `type == "init"` → load `references/init.md`
- `component == true` → load `references/memory.md` → `references/rag.md` → `references/component.md`
- `type == "review"` → load `references/memory.md` → `references/rag.md` → `references/review-fix.md`
- Otherwise → report "Unknown task type"

Work on the branch, commit and push it. Merging the branch into `main` is QA's
job (after the reviewer passes for complex tasks; directly for simple tasks) —
do not merge into `main` yourself.

## Conventions

- Failure → report error with details to the orchestrator
- Success → return summary to the orchestrator
- Workspace: `/workspace/<project>-<task_id>` (worktree)

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
