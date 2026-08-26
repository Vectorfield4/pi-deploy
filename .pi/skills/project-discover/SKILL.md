---
name: project-discover
description: "Scans the workspace for projects and reads their context files."
---

# Project Discover

Scans `/workspace` for Git repos, reads context files, saves to memory.

## Instructions

1. Run `ls /workspace` and get directories.
2. For each directory, check for `.git` (skip worktrees where `.git` is a file).
3. Read context files in priority: `.hermes.md` → `AGENTS.md` → `CLAUDE.md` → `.cursorrules`
4. Extract: tech stack, dev rules, env vars, validation commands.
5. Save to memory via `mcp__dense-mem__remember` with key `project:<name>`.
6. Update periodically or on user command.

## Tools
- `read`, `bash`, `grep`, `find`
- `mcp__dense-mem__remember`
