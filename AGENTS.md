# pi-deploy

Deployment + instruction repo for a Pi-based AI development system. No application code — just Pi skills (Markdown), agent configs, and bash scripts.

## Layout

```
.pi/
├── settings.json        # Pi configuration
├── mcp.json             # MCP servers (dense-mem)
├── agents/              # Agent definitions (orchestrator/frontender/coder/qa/reviewer); skills listed per agent in frontmatter
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
| pi | Pi agent (interactive) + subagents (orchestrator/frontender/coder/qa/reviewer) + telegram bridge |
| memory-db | PostgreSQL + pgvector |
| embedding | TEI (all-MiniLM-L6-v2) |
| dense-mem | RAG MCP server |

The Pi container runs in interactive mode with a PTY. Telegram messages come in via `@bytesbrains/pi-telegram-bridge` extension (background listener polls Telegram). Pi's session stays active — no human at the terminal needed.

The orchestrator receives natural language messages, detects intent (task, question, feedback, deploy, etc.), detects the project type, and routes to the appropriate worker: `frontender` for frontend features, `coder` for backend/infra/content. The `reviewer` subagent runs the full PR review pipeline (CI check, scoring, merge/bounce). The `qa` agent handles releases and deploys.

No slash commands — users write naturally: "Add login page", "Why is the API slow?", "Deploy to production".

## Project types

The system is project-agnostic. The orchestrator detects the project type from the codebase and routes to appropriate skills:

| Type | Detection | Primary agent | Primary skills |
|------|-----------|---------------|----------------|
| **frontend** | package.json + React/Vue/Svelte | frontender | ui-architect, ui-implementer, integration-specialist, threejs-scene-builder |
| **backend** | package.json + Express/Fastify/Nest or go.mod, requirements.txt | coder | technical-planner, execute-task |
| **fullstack** | Monorepo or both frontend + backend markers | frontender + coder | Combination of above |
| **CLI/lib** | package.json with bin/main, or Makefile + src/ | coder | execute-task, create-pr |
| **infra** | docker-compose.yml, Dockerfile, .github/workflows | coder | setup-ci, execute-task |
| **content** | Markdown-heavy, no code | coder | content-strategist, narrative-designer |

Frontend-specific skills (ui-architect, ui-implementer, threejs-scene-builder, integration-specialist) are only loaded when the project is detected as frontend.

## Memory layer

**dense-mem** is a self-hosted MCP memory server (PostgreSQL + pgvector). It stores **durable, append-only evidence** with lifecycle hooks (`supersedes_evidence_ids`, `retract_evidence`, `correct_relationship`). Reach it through MCP via `pi-mcp-adapter`. The full tool catalog (`remember`, `recall_memory`, `get_submission_status`, `retract_evidence`, `correct_relationship`, `trace_memory`) is in the dense-mem repo.

Our usage patterns on top of the dense-mem API:

- **Rule cache** (orchestrator writes, workers read): section content from `AGENTS.md` written as evidence with `idempotency_key: rules:<project>:<key>:<hash>`. Supersession advances to a new hash. See `.pi/skills/orchestrate-task/SKILL.md` step 3.5 and `.pi/skills/execute-task/references/memory.md` for the read side.
- **Task outcomes** (coder writes): concise summary with `source_type: "task_outcome"`, idempotency keyed on `task_id`. See `.pi/skills/execute-task/references/component.md` step 7.
- **Review verdicts** (reviewer writes): `source_type: "review_outcome"`, includes `confidence` inside the content. See `.pi/skills/execute-review/SKILL.md` step 8.
- **Exploration anti-patterns** (reviewer writes, on 3+ failed iterations): typed content that signals the orchestrator to re-decompose. TTL 30 days, decays fast as practices evolve.
- **Batched recall**: orchestrator does one recall per task and passes results via `metadata.memory_context` to each sub-task. Workers read this context instead of recalling again. Saves N-1 embedding calls per N-component task.
- **Docs cache**: library documentation flows through the `docs-lookup` skill, which caches Context7 results in dense-mem for 7 days. Cap content at 2000 chars per call.
- **Memory GC**: every `remember` writes `valid_until: YYYY-MM-DD` in the content. The `memory-gc` skill (run by QA after each iteration) walks recall results, parses `valid_until`, and calls `retract_evidence` on expired records. TTL policy: rules/project-meta = never, task/verified = 90d, feedback = 60d, exploration = 30d.

**Important: dense-mem does not have top-level `tags`, `filter`, or `claims` parameters.** Tags are encoded in the content (structured prefix like `tags: project:<project>,ui-conventions`). Filter-style selection is done in the query string (`query="project:<project> anti-pattern"`). `confidence` lives inside the evidence item, not at the top level. The skill bodies reflect this shape; do not invent API fields.

**Ownership**: dense-mem enforces that each profile can only `retract_evidence` or `correct_relationship` on records it owns. Coder owns its task evidence. Orchestrator owns rule cache. Reviewer owns review evidence. Crossing ownership boundaries is rejected by the server.

**Session memory** (separate from dense-mem) is provided by the `pi-memory` extension, used by the orchestrator as a private scratchpad. It does not talk to dense-mem.

## Documentation

Context7 (`@upstash/context7-pi`) — up-to-date library docs. Agents use `resolve-library-id` → `query-docs` tools when working with external libraries. No training data assumptions.

## Task flow

Telegram → Orchestrator → Subagents (frontender/coder) → PR → Reviewer (CI/score/merge) → QA (release/deploy)

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
- release-approval-watch — orchestrator-side zero-token HITL: runs `/pr watch` for release PRs, re-delegates merge/release to QA on approval
- prioritize-tasks — composite scoring for task ordering
- execute-task — main task dispatcher (init/pr/review)
- create-pr — commit, push, open PR
- setup-ci — GitHub Actions CI pipeline
- project-init — initialize new project (clone, deps, lint, base structure)
- technical-planner — break work into subtasks
- content-strategist — content plan with anti-AI-pattern checks
- narrative-designer — story/narrative design
- project-discover — scan workspace for projects
- simple-task-executor — quick tasks (forms, tables, components, scripts)
- docs-lookup — Context7 library docs with 7-day dense-mem cache. Use instead of calling `resolve-library-id` / `query-docs` directly.

### Frontend-specific (loaded only for frontend projects)
- ui-architect — Atomic Design page architecture
- ui-implementer — React+MUI component implementation
- integration-specialist — assemble components into app
- threejs-scene-builder — 3D scenes with Three.js/R3F

### QA (all project types)
- execute-qa-task — main QA dispatcher (review/release/deploy). Delegates review tasks to the `reviewer` subagent. Calls `memory-gc` after each successful iteration.
- release-to-main — two-phase: open dev→main PR (return URL), then merge + build + GitHub Release after approval
- deploy-vercel — build and deploy to Vercel staging
- deploy-ftp — download release zip, upload to production
- memory-gc — retires dense-mem evidence whose `valid_until` has passed

### Reviewer (all project types)
- execute-review — full PR review pipeline (CI wait, validate, score, merge/bounce, memory)
- review-and-merge — CI check, merge to dev
- pr-judge — score PRs 1-10 on quality rubric
- resolve-merge-conflict — merge conflict resolution
- cleanup-branch — delete worktrees and branches

## Frontend stack (when project is frontend)

React 19, Vite 7, TypeScript 5, MUI 7, Zustand 5, TanStack Query 5, React Router 7, GSAP 3, Three.js/R3F 9, Vitest 3, MSW 2, Biome 2, Storybook 9

## Deploy

- **Staging**: Vercel (auto-deploy on merge to dev)
- **Production**: FTP (manual via "deploy to production")

## Packages

| Package | Purpose |
|---------|---------|
| pi-subagents | Multi-agent orchestration (orchestrator/frontender/coder/qa/reviewer) |
| pi-mcp-adapter | MCP client for dense-mem RAG server |
| @bytesbrains/pi-telegram-bridge | Telegram ↔ Pi interactive session bridge |
| ping-a-human-pi | Human-in-the-loop approval (HITL) for Telegram-only blocks (FTP deploys, destructive ops) |
| pi-memory | Session memory persistence |
| @upstash/context7-pi | Library docs lookup (Context7) |
| @vectorfield/pi-prs | GitHub PR watch. Zero-token release HITL: main-session `/pr watch <url>` polls and wakes Pi on approval, without blocking Telegram |
