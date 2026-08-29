---
name: create-pr
description: "Creates a commit, pushes the shared branch, and opens a Pull Request."
---

# Create PR

Called for the PR task. Validates, commits, pushes, opens PR.

## Steps

### 1. Input
- Receive `project` and `branch` from task metadata.
- Navigate to worktree: `cd /workspace/<project>-<task_id>`.

### 2. Validate
- Read validation commands from project AGENTS.md.
- Run each command (e.g. `npm run lint`, `npm run test`).
- If any fails → return error. Do not proceed.

### 3. Commit and push
- Ensure on correct branch.
- `git add . && git commit -m "Task #<task_id>: <description>"`
- `git push origin <branch>` — retry on transient errors.

### 4. Create PR
- `gh pr create --title "Task #<task_id>: <description>" --body "<summary>" --base main`
- PRs always target `main`. Merge into `main` is gated on human approval by the
  orchestrator's zero-token watch (`pr-approval-watch`), not done here.
- Retry on transient errors.

### 5. Cleanup worktrees
- Remove all worktrees for this branch:
  ```
  cd /workspace/<project>
  git worktree list | grep "<branch>" | awk '{print $1}' | xargs -I {} git worktree remove {}
  ```

### 6. Return
- Return PR number and URL.

## Verification
- `gh pr view` returns the PR URL
- All worktrees for this branch are removed
