---
name: release-to-main
description: "Opens a PR from dev to main, blocks for human approval, merges, then creates a GitHub Release."
---

# Release to Main

Opens PR from dev to main, blocks for HITL, merges, builds, creates GitHub Release.

**Important: Idempotent** — check for existing PR before creating a new one.

## Instructions

### 1. Check for existing PR (idempotency guard)
- `gh pr list --head dev --base main --json number,state,url,mergeable`
- If PR exists and is OPEN → resume after approval (skip to step 4)
- If no PR exists → fresh run

### 2. Create PR (fresh runs only)
- `gh pr create --base main --head dev --title "Release: <project>" --body "Release PR. Merge after human approval."`

### 3. Block for approval (fresh runs only)
- Generate diff stat: `git log main..dev --oneline --no-merges`
- Generate security checklist (sensitive files changed?)
- Use `ask_human` to block for approval
- **Stop here** — task is parked

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
