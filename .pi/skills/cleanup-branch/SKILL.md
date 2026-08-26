---
name: cleanup-branch
description: "Deletes the local and remote branch."
---

# Cleanup Branch

1. Operate in shared repo: `cd /workspace/<project>`
2. Remove all worktrees for this branch:
   ```
   git worktree list | grep "<branch>" | awk '{print $1}' | xargs -I {} git worktree remove {}
   ```
3. Switch to another branch (e.g., `main`)
4. Delete local: `git branch -d <branch>`
5. Delete remote: `git push origin --delete <branch>`
