---
name: orchestrate-task
description: "Breaks down complex development tasks into parallel sub-tasks for coder agents, coordinating a single feature branch and final PR creation."
---

# Orchestrate Task

## Steps

### 1. Determine Project Context
- Check `/workspace/` for git repos.
- If exactly one → set project = that directory name.
- If multiple → ask which project matches the task.
- If workspace is empty → report "No project found. Create one with `/project add`."

### 2. Detect Project Type
Before decomposing, identify the project type:
- **frontend**: package.json with React/Vue/Svelte/Angular → use Atomic Design decomposition
- **backend**: package.json + Express/Fastify/Nest, or go.mod, requirements.txt, Cargo.toml → use layered architecture decomposition
- **fullstack**: Monorepo or both markers → combine approaches
- **CLI/lib**: package.json with bin/main, or Makefile + src/ → use module decomposition
- **infra**: docker-compose.yml, Dockerfile, .github/workflows → use infrastructure decomposition
- **content**: Markdown-heavy, no code → use content decomposition

### 3. Load Project Rules
- Navigate to `/workspace/<project>`.
- Pull latest: `git pull origin dev` (or `main` if `dev` doesn't exist).
- Get git hash: `git rev-parse HEAD` → `rules_hash`.
- Read `AGENTS.md` and `SOUL.md` if they exist.
- Extract key rule sections relevant to the project type.

### 4. Recall Past Experience
- Use `mcp__dense-mem__recall_memory` to find similar past plans, decisions, or patterns.
- Recall anti-patterns: `mcp__dense-mem__recall_memory(query="<goal>", filter={tags: ["anti-pattern", "project:<project>"]})`.
- Include as advisory hints — project rules always take precedence.
- Graceful degradation: if MCP fails, continue without it.

### 5. Decompose the Task

#### For frontend projects (Atomic Design):
1. atom / molecule / organism / template / page
2. Functional purpose (hero, feature-grid, lead-form)
3. Behavioral requirements (scroll-triggered, animated, responsive)

#### For backend projects (Layered Architecture):
1. route/endpoint → handler → service → repository → model
2. Data flow, validation, error handling
3. Database schema changes, migrations

#### For fullstack projects:
Combine frontend and backend decompositions, link by API contract.

#### For CLI/lib projects:
1. Module/function decomposition
2. Public API surface, internal implementation
3. Tests, documentation

#### For infra projects:
1. Service configuration changes
2. CI/CD pipeline modifications
3. Environment/config management

#### For content projects:
1. Structure (sections, headings, flow)
2. Content blocks (prose, code examples, tables)
3. Cross-references, navigation

#### For refactoring tasks (any type):
1. Identify target files
2. Read current code, understand structure
3. Plan targeted sub-tasks (1-3 files each, edit not rewrite)

### 6. Generate Branch Name
- `feature/<task_id>-<sanitized_title>`

### 7. Delegate Sub-Tasks
- Use the `subagent` tool to delegate each component to a `worker` agent.
- Pass: description, acceptance_criteria, project context, branch name, rules_hash.

### 8. Create PR Task
- After all components complete, delegate PR creation to a `worker` agent.

### 9. Quality Check
- Every criterion traces to the original task description
- At least one criterion is verifiable via lint/test/build
- Behavioral requirements are specific (not "looks good")

## Verification
- All sub-tasks delegated to workers
- PR task created and delegated
- No task remains in intermediate state
