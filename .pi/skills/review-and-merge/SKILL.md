---
name: review-and-merge
description: "Checks CI status, merges the PR to dev, and triggers Vercel staging deployment."
---

# Review and Merge

Verifies CI, merges to `dev`, deploys to Vercel staging.

## Steps

### 1. Input
- Receive `project` and `branch` from task metadata.
- If `pr_number` missing → `gh pr list --head <branch>` to find it.

### 2. Check CI status
- `gh pr view <pr> --json statusCheckRollup`
- If running → wait and retry every 30s (max 10 min)
- If failed → bounce to coder with error log

### 3. Merge to dev
- `gh pr merge --squash --base dev`
- If merge conflict → delegate to `resolve-merge-conflict` subagent

### 4. Deploy to Vercel staging
- Delegate to `deploy-vercel` subagent
- Success → complete with staging URL
- Failure → block with error
