---
name: execute-qa-task
description: "Executes a single QA task — dispatches to create-github-release (release), the approval merge into main (merge), deploy-ftp/deploy-vercel (deploy), or the reviewer subagent (review)."
---

# Execute QA Task

## Steps

### 1. Fetch the task
- Extract `title`, `description`, `metadata` (`project`, `branch`, `pr_number`).

### 2. Dispatch by task type
- **`type == "release"`** → load and run `create-github-release`
- **`type == "merge"`** → run the approval-merge steps (section 3)
- **`type == "deploy"`** → load and run `deploy-ftp` (production) or
  `deploy-vercel` (staging)
- **Otherwise (review task)** → continue with step 4

### 3. Approval merge into main (delegated by the orchestrator on watch approval)
The orchestrator woke on human approval (`pr-approval-watch`) and delegated this
merge. QA executes the merge only after verifying the approval review exists —
it never decides itself whether to merge.

1. Verify approval: `gh pr view <pr_number> --json reviews,state`.
   - No `APPROVED` review → do NOT merge. Report that approval is still pending.
   - PR already merged/closed → report the final state and stop.
2. Merge: `gh pr merge <pr_number> --squash`.
   - Conflict → load the `resolve-merge-conflict` skill, then retry once.
3. Post-merge: load and run `cleanup-branch` for `branch` (drop feature branch
   and worktrees). Trigger Vercel staging per `deploy-vercel` (main branch build).
4. Run `memory-gc`.
5. Report: merge commit + staging URL (if any).

### 4. Review task — delegate to the reviewer subagent

The reviewer runs **only for complex tasks where the orchestrator invoked the
Pro model** (`metadata.pro_invoked == true`). Simple (Flash-only) tasks skip the
reviewer entirely — their PR goes straight to the human approval gate.

1. **`metadata.pro_invoked` is not `true`** → skip the reviewer:
   - Best-effort CI check: `gh pr checks <pr_number>` (wait up to `CI_TIMEOUT_S`).
     Blocked/red → report to the orchestrator so coder fixes it. This is a
     status check, not a review, and does not produce a score or memory writes.
   - Return: `decision: skip_review`, `pr_number`, `pr_url`. The orchestrator
     starts the human gate (`WATCH` marker) without waiting on a reviewer.
2. **Otherwise** → full review:
```
subagent({ agent: "reviewer", task: <review task>, skill: "execute-review" })
```

Pass: `project`, `branch`, `pr_number` (if known), `metadata.acceptance_criteria`,
`metadata.review_iterations`, `metadata.exploration_triggered`.

The reviewer runs the full PR pipeline and returns a structured result. This
agent does not call `pr-judge` or `resolve-merge-conflict` directly — only the
reviewer owns the judge rubric.

### 5. Handle the reviewer's result

**decision: `skip_review`** (simple task, `pro_invoked` not set)
- The PR needs no reviewer. Report `pr_number`/`pr_url` to the orchestrator;
  it emits the `WATCH <url>` marker for the human gate. No merge here.

**decision: `merge`** (complex task, reviewer passed)
- The reviewer validated the PR but did NOT merge (merge waits for human
  approval). Report to the orchestrator: `pr_number`, `pr_url`, `decision: merge`.
  The orchestrator emits the `WATCH <url>` marker for the router.
- Do NOT call `gh pr merge` here.

**decision: `bounce`**
- Forward `findings` to the orchestrator. The orchestrator routes back to coder.

**decision: `explore`**
- Forward `exploration_flag: true` and the summary. The orchestrator
  re-decomposes the task. Do NOT bounce to coder a 4th time.

### 5.5. Run memory-gc
After any successful review/release/merge/deploy, load and run the `memory-gc`
skill. It retires dense-mem evidence whose `valid_until` has passed.
Best-effort, never blocks the flow. If it fails, the next QA iteration retries.

### 6. Complete
- Forward the result. No memory writes from this skill (reviewer owns review
  memory; release/merge outcomes can be stored as verified patterns best-effort).
- This skill is the dispatcher. It does not write rules, scores, or anti-patterns.

## Verification

- Review tasks delegate to `reviewer` only when `metadata.pro_invoked == true`;
  otherwise they return `decision: skip_review` (no score, no memory writes).
- `type == "merge"` runs only with a verified `APPROVED` review; merge succeeded;
  branch cleaned up; `memory-gc` attempted.
- Release and deploy tasks still work via their own skills.
- No memory writes happen here (except best-effort verified outcomes).