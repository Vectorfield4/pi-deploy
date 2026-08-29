# Skills & Agents Audit — recommended changes

Status: opened 2026-08-29. Audit applied 2026-08-29: sections **A**, **B**, **C**, **E**, **F** done and committed; **D** deferred (see below); **G** code-side done, server verification pending.

## A. Dead / duplicate skills to remove — DONE

Removed (24 skills remain, catalog + counts updated in `AGENTS.md`):

| Skill | Reason | Cleaned from |
|-------|--------|--------------|
| `review-and-merge` | Replaced by the human-approval gate: the reviewer now only decides, QA merges after `pr_watch` approval. | `reviewer.md` frontmatter, `AGENTS.md` catalog, `qa.md`/`execute-qa-task` prose |
| `technical-planner` | Duplicates `orchestrate-task`; wired to `coder` which has no `subagent` tool. | `coder.md` frontmatter, `AGENTS.md` (catalog + backend row) |
| `simple-task-executor` | Duplicates `ui-implementer`; fallback agent `worker` does not exist. | `frontend-implementer.md` frontmatter, `AGENTS.md` catalog, `rag.md` |
| `prioritize-tasks` | Task-queue infra does not exist; one message → one task. | `orchestrator.md` frontmatter, `AGENTS.md` catalog |

## B. Orphan to wire: `docs-lookup` — DONE

- Added `docs-lookup` to `skills:` in `coder.md`, `reviewer.md`, `frontend-implementer.md` (was never loadable).
- `execute-task/references/component.md` step 5 now loads `docs-lookup` instead of raw Context7 calls; `coder.md` stack-detection bullet updated the same way.
- `docs-lookup/SKILL.md` "When to use": `frontender` → `frontend-implementer`.

## C. Stale agent name "frontender" — DONE

Replaced with `frontend-implementer` (or `frontend-architect`/`frontend-implementer`) in:
`README.md` (task flow, mcp-adapter row, context7 row), `docs-lookup/SKILL.md`,
`orchestrate-task` fullstack section, `execute-task/references/component.md`,
`references/memory.md` (×2). `coder.md` was already correct.

## D. Agent body vs skill separation (token reduction) — DEFERRED

Still worth doing: slim `orchestrator.md`, `qa.md`, `reviewer.md`,
`frontend-architect.md`, `coder.md` to role + hard constraints + output
envelope + "load skill X". Highest value: `orchestrator` (main session,
`keepRecentTokens: 16000`) and `frontend-architect` (Pro, ×10 cost).
Deferred to avoid destabilizing the pipeline right before a server roll-out;
do it after server verification confirms current config behaves.

## E. PR-flow wiring gaps — MOSTLY DONE

- `orchestrate-task` step 7 now has the explicit `subagent({ agent, task, skill })`
  spawn form + per-worker mapping table (coder→execute-task, pro-override for
  complex, architect→ui-architect, implementer→ui-implementer, qa→execute-qa-task).
- Cleanup/merge ownership moved with the PR rework: `cleanup-branch` +
  `resolve-merge-conflict` live in `qa.md` (merge path after approval); removed
  from `reviewer` (it never merges). `execute-qa-task` merge steps load
  `resolve-merge-conflict` directly (no bogus "delegate to subagent").
- `deploy-vercel` in reviewer: resolved by the rework — reviewer no longer
  references it; staging is QA's job after merge.

## F. Cosmetic — DONE

`AGENTS.md` says 24 skills; actual is 24.

## G. HITL / PR-to-main polling flow — CODE DONE, SERVER VERIFICATION PENDING

Root cause found and fixed in the earlier rework (commit `deae1d4` + pi-prs fork):
subagents cannot run `/pr watch`; the watch must be started by the main routing
session. Fixed with the `pr_watch` LLM tool (pi-prs 0.1.1) + the `WATCH <url>`
marker protocol in `orchestrator.md` / `pr-approval-watch` / `AGENTS.md`; the
release path became single-phase `create-github-release`. Review now runs only
for complex/Pro tasks (`metadata.pro_invoked`).

Still open — verify on the server (`make update` after SSH):
- `@vectorfield/pi-prs@0.1.1` installs and `pr_watch` registers on the main session.
- steer-wake (approval/comment/reject) reaches the router and routes back to the orchestrator.
- `pro_invoked` gating behaves: complex → reviewer runs, simple → `skip_review`.
- `docs-lookup` loads from the updated agent frontmatters.
- feature branches land in `main` via `gh pr merge --squash` after approval.

## Open questions / follow-ups

- `subagent({ model: "deepseek/deepseek-v4-pro", ... })` override on delegation
  is only described in docs — confirm pi-subagents honors a per-call model pick
  (its README claims "model overrides per role").
- Decide whether release builds belong on the server (local zip → `gh release`)
  or in a workspace CI pipeline (`create-github-release` degrades to "push tag").