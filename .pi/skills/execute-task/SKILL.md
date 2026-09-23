---
name: execute-task
description: "Executes a single development sub-task (UI, content, integration) or initializes a new project."
---

# Execute Task

The task arrives as a **JSON string** — read `task.type` first. Payloads
carry the full bundle (`task.project`, `task.branch`, `task.metadata.*`).
Parse per your task type; do not assume absent keys.

## Steps

### 1. Place (inherit the single worktree)
- Work inside `task.cwd`; the branch is already checked out there.
- Verify placement: `git -C <cwd> branch --show-current` equals `task.branch`.
- Do NOT create a worktree; run NO git network ops (fetch/pull/rebase/push).
- Skip the placement check for `type: init`.

### 1.5. Memory contract (mandatory for `component` and `review`)

Before step 2, consume the memory payload:

- `task.metadata.memory_context` is the only memory context. Do not recall.
- Treat each `task.metadata.anti_patterns` entry as a hard warning (apply to avoid repeating the failure). Project `AGENTS.md` still overrides on conflict.
- If both fields are absent, proceed without memory — workers never run ad-hoc recall; the owning architect fills both fields for task runs.

### 2. Dispatch by task type
- `type == "init"` → load `references/init.md`
- `type == "content"` → load `references/memory.md` → `references/rag.md` → `references/content.md`
- `component == true` → load `references/memory.md` → `references/rag.md` → `references/component.md`
- `type == "review"` → load `references/memory.md` → `references/rag.md` → `references/review-fix.md`
- Otherwise → report "Unknown task type"

Work in the worktree: `git add <changed files>` and
`git commit -m "..." -- <same files>`.

## Code reads (AST tools)

- `list_symbols` / `get_symbol_body` for structural reads; `read` only the
  resolved target after locating it.
- Before changing a signature or shared type: `find_callers` to enumerate
  impact, update every call site.
- `find_definition` when the definition site is unknown. `find_callees` to
  map what a symbol depends on.

## Conventions

- Failure → report error with details
- Success → return summary
- Workspace: `task.cwd` — the single worktree
  (`/workspace/<project>-<task_id>`); the branch is checked out there
- Git: local commits only — `git add <paths>` + `git commit -- <paths>`; no
  `worktree add`, fetch, pull, rebase, push. Sibling workers share the
  worktree; if the index is locked, wait briefly and retry the commit.
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
- TASK (`type: "task"` / `component` / `content` / `review`): the single
  worktree at `task.cwd` holds the branch; task completed or blocked; no task
  remains in intermediate state
