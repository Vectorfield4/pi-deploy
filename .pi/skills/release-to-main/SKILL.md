---
name: release-to-main
description: "Opens a PR from dev to main, monitors for human approval, merges, then creates a GitHub Release."
---

# Release to Main

Opens PR from dev to main, monitors for human approval via `pi-monitor`, merges, builds, creates GitHub Release.

**Important: Idempotent** — check for existing PR before creating a new one.

## Instructions

### 1. Check for existing PR (idempotency guard)
- `gh pr list --head dev --base main --json number,state,url,mergeable`
- If PR exists and is OPEN → resume after approval (skip to step 4)
- If no PR exists → fresh run

### 2. Create PR (fresh runs only)
- `gh pr create --base main --head dev --title "Release: <project>" --body "Release PR. Merge after human approval."`

### 3. Monitor for approval (via `pi-monitor`)
- `pi-monitor start --pr <pr_number> --timeout 30m`
- Plugin polls GitHub every 30s checking PR status and comments
- **Triggers when**: 
  - PR receives approval (`approver` changes), OR
  - PR receives a comment containing "approved" / "LGTM" / "merge"
- On timeout → report error: "HITL approval timed out. No approval detected in 30 minutes."
- On approval detected → resume to step 4

### 4. Merge after approval (resume path)
- Verify PR is mergeable
- If mergeable → `gh pr merge <number> --squash`
- If conflict → delegate to `resolve-merge-conflict` subagent

### 5. Build and create GitHub Release
- Checkout main, pull
- Run build commands
- Create zip archive
- Determine version tag
- `gh release create <tag> /tmp/<project>-<version>.zip`

### 6. Complete
- Report release summary
- Best-effort: store verified experience in dense-mem

## Verification

- Checked for existing PR before creating
- PR merged successfully
- Build succeeds
- GitHub Release created with zip artifact