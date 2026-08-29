---
name: execute-qa-task
description: "Executes a single QA task — dispatches to create-github-release (release), the push-to-main (push), deploy-ftp/deploy-vercel (deploy), or the reviewer subagent (review)."
---

# Execute QA Task

The task arrives as a **JSON string** — parse it and read fields via
`task.type`, `task.project`, `task.branch`, `task.metadata.*`, etc.

## Steps

### 1. Fetch the task
- Parse the `task` JSON string: extract `title`, `description`, `metadata`
  (`project`, `branch`).

### 2. Dispatch by task type
- **`type == "release"`** → load and run `create-github-release`
- **`type == "push"`** → run the push-to-main steps (section 3)
- **`type == "deploy"`** → load and run `deploy-ftp` (production) or
  `deploy-vercel` (staging)
- **Otherwise (review task)** → continue with step 4

### 3. Push to main (delegated by the orchestrator)
The orchestrator delegates the direct push. For **complex tasks**
(`task.metadata.pro_invoked == true`) the reviewer must pass first — delegate
the review (step 4) and only push after `decision: merge`. For simple tasks,
push directly.

1. Review gate (complex only):
   - If `task.metadata.pro_invoked == true` → delegate the reviewer (step 4),
     wait for its decision.
   - `decision: merge` → continue. `bounce` / `explore` → do NOT push; return
     the reviewer result to the orchestrator.
   - `decision: skip_review` → continue.
2. Fast-forward the branch into `main`:
   ```
   cd /workspace/<project>
   git fetch origin main <branch>
   git switch main && git merge --ff-only origin/<branch>
   git push origin main
   ```
   - Not fast-forwardable → load `resolve-merge-conflict` (rebase the branch on
     `main` first), then retry once.
   - Push rejected → `git pull --ff-only` then retry once.
3. Post-push: load and run `cleanup-branch` for `branch` (drop feature branch
   and worktrees). Trigger Vercel staging per `deploy-vercel` (main branch build).
4. Run `memory-gc`.
5. Report: push commit + staging URL (if any).

### 4. Review task — delegate to the reviewer subagent

The reviewer runs **only for complex tasks where the orchestrator invoked the
Pro model** (`task.metadata.pro_invoked == true`). Simple (Flash-only) tasks
skip the reviewer entirely and push straight to `main`.

1. **`task.metadata.pro_invoked` is not `true`** → skip the reviewer:
   - Return: `decision: skip_review`. The orchestrator/Qa push to `main` without
     waiting on a reviewer.
2. **Otherwise** → full review. `task` is a **string** — build the reviewer
   task as its own JSON string (never an object):
```
subagent({
  agent: "reviewer",
  task: `{"type":"review","project":"<project>","branch":"<branch>","metadata":{"acceptance_criteria":["<...>"],"review_iterations":<n>,"exploration_triggered":<bool>,"pro_invoked":true}}`,
  skill: "execute-review"
})
```

Pass (inside the JSON): `project`, `branch`, and the
`metadata` fields `acceptance_criteria`, `review_iterations`,
`exploration_triggered`.

The reviewer reviews the **branch diff against `main`** (local git) and returns
a structured result. This agent does not call `pr-judge` or
`resolve-merge-conflict` directly — only the reviewer owns the judge rubric.

### 5. Handle the reviewer's result

**decision: `skip_review`** (simple task, `task.metadata.pro_invoked` not set)
- The branch needs no reviewer. For a `push` task, continue to section 3
  step 2. No review memory is written.

**decision: `merge`** (complex task, reviewer passed)
- The reviewer validated the branch but did NOT push. For a `push` task, push
  it to `main` (section 3). Do NOT push for a task that was review-only — return
  `decision: merge` to the orchestrator, which delegates the push.

**decision: `bounce`**
- Forward `findings` to the orchestrator. The orchestrator routes back to coder.
  Do not push the branch.

**decision: `explore`**
- Forward `exploration_flag: true` and the summary. The orchestrator
  re-decomposes the task. Do NOT bounce to coder a 4th time.

### 5.5. Run memory-gc
After any successful review/release/push/deploy, load and run the `memory-gc`
skill. It retires dense-mem evidence whose `valid_until` has passed.
Best-effort, never blocks the flow. If it fails, the next QA iteration retries.

### 6. Complete
- Forward the result. No memory writes from this skill (reviewer owns review
  memory; release/push outcomes can be stored as verified patterns best-effort).
- This skill is the dispatcher. It does not write rules, scores, or anti-patterns.

## Verification

- Review tasks delegate to `reviewer` only when `task.metadata.pro_invoked == true`;
  otherwise they return `decision: skip_review` (no score, no memory writes).
- `type == "push"` runs only after the reviewer's `decision: merge` (complex) or
  a `skip_review` (simple); the branch is fast-forwarded into `main`;
  branch cleaned up; `memory-gc` attempted.
- Release and deploy tasks still work via their own skills.
- No memory writes happen here (except best-effort verified outcomes).