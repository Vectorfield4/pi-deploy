---
name: execute-qa-task
description: "Executes a single QA task — dispatches to release-to-main, deploy-ftp/deploy-vercel, or the reviewer subagent based on task type."
---

# Execute QA Task

## Steps

### 1. Fetch the task
- Extract `title`, `description`, `metadata`.

### 2. Dispatch by task type
- **`type == "release"`** → load and run `release-to-main`
- **`type == "deploy"`** → load and run `deploy-ftp` (or `deploy-vercel` if target is staging)
- **Otherwise (review task)** → continue with step 3

### 3. Load project rules
- Recall rules from dense-mem by key, verify `rules_hash` matches.
- Fallback: read from `/workspace/<project>/AGENTS.md`.

### 4. Delegate review to the reviewer subagent
```
subagent({ agent: "reviewer", task: <review task>, skill: "execute-review" })
```

Pass: `project`, `branch`, `pr_number` (if known), `metadata.acceptance_criteria`, `metadata.review_iterations`, `metadata.exploration_triggered`.

The reviewer runs the full PR pipeline and returns a structured result. This agent does not call `pr-judge`, `review-and-merge`, or `resolve-merge-conflict` directly anymore — those skills are owned by the reviewer.

### 5. Handle the reviewer's result

**decision: `merge`**
- The reviewer already merged the PR and triggered Vercel staging.
- Forward the staging URL (if any) to the user. Complete.

**decision: `bounce`**
- Forward `findings` to the orchestrator. The orchestrator routes back to coder.

**decision: `explore`**
- Forward `exploration_flag: true` and the summary. The orchestrator re-decomposes the task.
- Do NOT bounce to coder a 4th time. Exploration is the only escalation.

### 5.5. Run memory-gc
After any successful review/release/deploy, load and run the `memory-gc` skill. It retires dense-mem evidence whose `valid_until` has passed. Best-effort, never blocks the flow. Do not check the return value. If it fails, the next QA iteration retries.

For release and deploy tasks, memory-gc runs in addition to the dispatcher's own completion.

### 6. Complete
- Forward the result. No memory writes from this skill (reviewer owns them).
- This skill is the dispatcher. It does not write rules, scores, or anti-patterns.

## Verification

- Review tasks delegate to `reviewer` and propagate the result.
- Release and deploy tasks still work via their own skills.
- No memory writes happen here.
