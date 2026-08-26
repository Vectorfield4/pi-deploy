# pi-deploy

Deployment + instruction repo for a Pi-based AI development system. No application code — just Pi skills (Markdown), agent configs, and bash scripts.

## Layout

```
.pi/
├── settings.json        # Pi configuration
├── mcp.json             # MCP servers (dense-mem)
├── skill-profiles.json  # Skill-to-agent mapping
├── agents/              # Agent definitions (orchestrator/coder/qa)
└── skills/              # Skill packages (24 skills)
scripts/                 # Bash scripts (init, memory-bootstrap, etc.)
docker-compose.yml       # Pi + dense-mem stack (4 services)
Dockerfile.pi            # Pi container
AGENTS.md                # This file — global instructions
.env                     # Secrets (gitignored)
```

## How it runs

One Pi process (interactive mode) + 3 memory stack containers:

| Container | Role |
|---|---|
| pi | Pi agent (interactive) + subagents (orchestrator/coder/qa) + telegram bridge |
| memory-db | PostgreSQL + pgvector |
| embedding | TEI (all-MiniLM-L6-v2) |
| dense-mem | RAG MCP server |

The Pi container runs in interactive mode with a PTY. Telegram messages come in via `@bytesbrains/pi-telegram-bridge` extension (background listener polls Telegram). Pi's session stays active — no human at the terminal needed.

The orchestrator receives natural language messages, detects intent (task, question, feedback, deploy, etc.), detects the project type, decomposes tasks into sub-tasks, and delegates to worker subagents. QA reviews, merges, and deploys.

No slash commands — users write naturally: "Add login page", "Why is the API slow?", "Deploy to production".

## Project types

The system is project-agnostic. The orchestrator detects the project type from the codebase and routes to appropriate skills:

| Type | Detection | Primary skills |
|------|-----------|----------------|
| **frontend** | package.json + React/Vue/Svelte | ui-architect, ui-implementer, integration-specialist, threejs-scene-builder |
| **backend** | package.json + Express/Fastify/Nest or go.mod, requirements.txt | technical-planner, execute-task |
| **fullstack** | Monorepo or both frontend + backend markers | Combination of above |
| **CLI/lib** | package.json with bin/main, or Makefile + src/ | execute-task, create-pr |
| **infra** | docker-compose.yml, Dockerfile, .github/workflows | setup-ci, execute-task |
| **content** | Markdown-heavy, no code | content-strategist, narrative-designer |

Frontend-specific skills (ui-architect, ui-implementer, threejs-scene-builder, integration-specialist) are only loaded when the project is detected as frontend.

## Memory layer

dense-mem RAG via MCP (`pi-mcp-adapter`). Single server, project tags. Ownership-based: each agent can only modify its own records.

## Documentation

Context7 (`@upstash/context7-pi`) — up-to-date library docs. Agents use `resolve-library-id` → `query-docs` tools when working with external libraries. No training data assumptions.

## Task flow

Telegram → Orchestrator → Subagents (coder) → PR → QA → Pass/Fail → Deploy

## Commands

```bash
make init              # Create .env + directories
make setup             # Full stack bootstrap (init + services + packages)
make up                # Start all services
make down              # Stop all services
make logs              # Tail logs
make restart           # Restart Pi agent
make backup            # Backup databases
make install-packages  # Install Pi packages inside container
make update-skills     # Restart Pi to pick up skill changes
```

## Skills catalog

### Universal (all project types)
- intent-router — classifies natural language → task/question/feedback/deploy/etc.
- orchestrate-task — decomposes tasks into parallel sub-tasks
- prioritize-tasks — composite scoring for task ordering
- execute-task — main task dispatcher (init/pr/review)
- create-pr — commit, push, open PR
- setup-ci — GitHub Actions CI pipeline
- technical-planner — break work into subtasks
- content-strategist — content plan with anti-AI-pattern checks
- narrative-designer — story/narrative design
- project-discover — scan workspace for projects
- simple-task-executor — quick tasks (forms, tables, components, scripts)

### Frontend-specific (loaded only for frontend projects)
- ui-architect — Atomic Design page architecture
- ui-implementer — React+MUI component implementation
- integration-specialist — assemble components into app
- threejs-scene-builder — 3D scenes with Three.js/R3F

### QA (all project types)
- execute-qa-task — main QA dispatcher (review/release/deploy)
- review-and-merge — CI check, merge to dev
- release-to-main — dev→main PR, HITL approval, GitHub Release
- deploy-vercel — build and deploy to Vercel staging
- deploy-ftp — download release zip, upload to production
- pr-judge — score PRs 1-10 on quality rubric
- resolve-merge-conflict — merge conflict resolution
- cleanup-branch — delete worktrees and branches

## Frontend stack (when project is frontend)

React 19, Vite 7, TypeScript 5, MUI 7, Zustand 5, TanStack Query 5, React Router 7, GSAP 3, Three.js/R3F 9, Vitest 3, MSW 2, Biome 2, Storybook 9

## Deploy

- **Staging**: Vercel (auto-deploy on merge to dev)
- **Production**: FTP (manual via "deploy to production")
