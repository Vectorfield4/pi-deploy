---
name: project-discover
description: "Scans the workspace for projects and reads their context files."
---

# Project Discover

Scans `/workspace` for Git repos, reads context files, saves to memory.

## Instructions

1. Run `ls /workspace` and get directories.
2. For each directory, check for `.git` (skip worktrees where `.git` is a file).
3. Read context files in priority: `AGENTS.md` → `CLAUDE.md` → `.cursorrules`
4. Extract: tech stack, dev rules, env vars, validation commands.
5. Save to memory with a structured `mcp__dense-mem__remember` call: `evidence: [{ content: "project: <name>\ntype: project-meta\ntags: project-meta,<name>\n\n<stack>, <dev rules>, <env vars>, <validation commands>", source_type: "manual" }]`, `relationships: [{ ref: "project-meta:<name>:<git-hash>", subject: { name: "<name>", entity_kind: "project" }, predicate: { proposed_key: "project:meta" }, object: { entity: { name: "<name>", entity_kind: "project" } }, polarity: "+", evidence_indices: [0] }]`, `idempotency_key: "project-meta:<name>:<git-hash>"`. The `relationships` block is required by the v2.6 `remember` contract.
6. Update periodically or on user command.

## Tools
- `read`, `bash`, `grep`, `find`
- `mcp__dense-mem__remember` and `mcp__dense-mem__recall_memory` via `mcp:dense-mem` direct tool
