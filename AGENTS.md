# pi-deploy

Deployment + instruction repo for a Pi-based AI development system. No application code — just Pi skills (Markdown), agent configs, and bash scripts.

## Layout

```
.pi/
├── settings.json     # Pi config: model default, compaction, subagent model scope
├── mcp.json          # dense-mem MCP server
├── models.json       # Provider + model registry (timeweb)
├── agents/           # Agent definitions; skills listed per agent in frontmatter
└── skills/           # Skill packages (24 skills)
scripts/              # Bash scripts (init, setup, cloud-init, backup, setup-cron-jobs, update-on-push)
docker-compose.yml    # Pi + memory stack (4 services)
Dockerfile.pi         # Pi container image
AGENTS.md             # This file — interactive-session instructions
.env                  # Secrets (gitignored)
```

## How it runs

One Pi process (interactive, PTY, Telegram via `@bytesbrains/pi-telegram-bridge`) + 3 memory containers (PostgreSQL+pgvector, TEI embeddings, dense-mem RAG). No slash commands — users write naturally. The interactive session routes every message to the `orchestrator` subagent (intent: task/question/feedback/deploy/...), which delegates to workers (`frontend-architect`/`frontend-implementer` for frontend, `coder` otherwise). The Pro model is a cold path, invoked only for complex tasks (`metadata.pro_invoked`), and the `reviewer` (CI/score decision) runs **only** for those tasks. Every PR targeting main then gets a zero-token human approval (`pr_watch`) before `qa` merges/releases/deploys.

## How the main session works (router)

The main session's actual system prompt lives in **`.pi/SYSTEM.md`** — Pi loads
it for the project and replaces the default system prompt, so the router rules
reach the session even though this file is not mounted in the container.

The contract here is documentation of that prompt. Summary: you (this session)
are a thin router, not the actor. Every message is routed to the `orchestrator`
subagent and its output is followed. Two things you do yourself, without
delegating:

1. **PR watch markers.** When the orchestrator's final message contains a line
   that is exactly `WATCH <url>` (or `UNWATCH`), call the `pr_watch` tool on the
   same URL (`{ action: "watch", url }` / `{ action: "unwatch" }`). This starts
   the zero-token PR poller. When a watch wakes this session with feedback,
   route the feedback to the orchestrator like any other message.
2. **Confirmation echo.** For confirmed deploys/releases, just delegate; the
   orchestrator owns the confirmation flow.

Subagents cannot run slash commands or hold the watch — only you can.

> If this contract is not being followed on the running system (the agent
> replies to Telegram directly instead of delegating), check in order:
> 1. `/workspace/.pi/SYSTEM.md` is present in the container — without it the
>    session falls back to a bare model prompt.
> 2. `.pi/settings.json` `subagents.modelScope.allow` uses the full
>    `provider/model` id (`timeweb/deepseek/...`) — a provider-less pattern
>    makes every subagent launch fail with a modelScope error.
> 3. Delegation uses `task` as a **string**, never an object — an object fails
>    validation with `task: must be string` (pi-subagents@0.58.x).
> 4. If a session previously hit errors, the model may have "learned" that
>    delegation fails and answer directly — start a fresh session
>    (rename the session file under `/root/.pi/agent/sessions/--workspace--/`
>    and let Pi start a new one).

## Project types

| Type | Detection | Primary agent | Primary skills |
|------|-----------|---------------|----------------|
| **frontend** | package.json + React/Vue/Svelte | frontend-architect + frontend-implementer | ui-architect, ui-implementer, integration-specialist, threejs-scene-builder |
| **backend** | package.json + Express/Fastify/Nest or go.mod, requirements.txt | coder | execute-task |
| **fullstack** | Monorepo or both frontend + backend markers | frontend-architect + frontend-implementer + coder | combination |
| **CLI/lib** | package.json with bin/main, or Makefile + src/ | coder | execute-task, create-pr |
| **infra** | docker-compose.yml, Dockerfile, .github/workflows | coder | setup-ci, execute-task |
| **content** | Markdown-heavy, no code | coder | content-strategist, narrative-designer |

Frontend skills load only when the project is detected as frontend.

## Task flow

Telegram → Orchestrator → workers (frontend-architect, frontend-implementer, coder) → PR (base main) → Reviewer only for complex/Pro tasks (CI/score decision; simple tasks skip) → human approval (`pr_watch`) → QA (merge + release/deploy)

## Subagent task contract (`task` is a JSON string)

pi-subagents (package `pi-subagents@0.58.x`) accepts the `subagent` tool's
`task` as a **string only** — an object fails validation with
`task: must be string`. The child receives the string verbatim as its opening
message (`Task: <text>`); there is no structured channel. All context carriers
therefore serialize into the string as JSON:

- Router → orchestrator: `task` is the raw user message. Orchestrator does
  intent detection itself.
- Orchestrator → workers (coder / frontend-architect / frontend-implementer /
  qa / reviewer): `task` is a JSON string carrying `type`, `task_id`,
  `description`, `acceptance_criteria`, `project`, `branch`, `rules_hash`, and
  a `metadata` object (`memory_context`, `anti_patterns`, `pro_invoked`, plus
  review/target-file/pr fields). See `orchestrate-task` step 7.
- Merge → `qa`: `{"type":"merge","project":...,"pr_number":...,"branch":...}`.

Read-side: every delegated agent parses its incoming task string as JSON and
reads fields via `task.type`, `task.metadata.*`, etc. Do not pass `task` as an
object anywhere.

## Memory layer

**dense-mem** — self-hosted RAG memory (PostgreSQL + pgvector + TEI), contract `dense-mem.v2.6`, reached via MCP through `pi-mcp-adapter`. Stores durable append-only **evidence anchored by relationships**: `relationships` and `idempotency_key` required, `supersedes_evidence_ids` goes inside the evidence item, lifecycle via `retract_evidence`/`correct_relationship`. `source_type` enum: conversation/document/observation/manual. Recall is support-path gated and returns `{ evidence_id, context, space_kind }` — read `context`, never `content`.

Usage patterns:
- **Rule cache** (orchestrator writes, workers read): AGENTS.md sections as evidence, `idempotency_key: rules:<project>:<key>:<hash>`, `source_type: manual`, predicate `project:rules:<key>`.
- **Task outcomes** (workers): `source_type: observation`, predicate `project:task:outcome`, keyed on `task_id`.
- **Design decisions** (orchestrator, after frontend architecture): `source_type: observation`, predicate `project:design:decision`, idempotency `design:<project>:<feature>:<hash>`, TTL 90d. The complex frontend gate recalls it first — if a matching decision exists, the architect is skipped.
- **Review verdicts** (reviewer): `source_type: observation`, predicate `project:review:verified`, `confidence` in content.
- **Exploration anti-patterns** (reviewer): `source_type: observation`, predicate `project:exploration:anti-pattern`, polarity `-`, TTL 30d.
- **Docs cache** (docs-lookup): `source_type: document`, predicate `library:docs:cache`, 7-day TTL, ≤2000 chars.
- **Memory GC** (QA): parses `valid_until` from `context`, `retract_evidence` on expiry (rules/meta never, task/verified/design 90d, feedback 60d, exploration 30d).

No top-level `tags`/`filter`/`claims` — tags live in content, selection in the query. Ownership: retract/correct only on own records (coder↔task, orchestrator↔rules, reviewer↔reviews). Session memory (orchestrator scratchpad) is separate — `pi-memory`, not dense-mem.

## Skills catalog

### Universal
- intent-router, orchestrate-task, execute-task, create-pr, setup-ci, project-init, content-strategist, narrative-designer, project-discover
- docs-lookup — Context7 with 7-day dense-mem cache; use instead of `resolve-library-id`/`query-docs` directly
- pr-approval-watch — zero-token HITL: orchestrator hands a passed PR to the router via a `WATCH <url>` marker; the router starts `pr_watch` (main session only)

### Frontend (loaded only for frontend projects)
- ui-architect, ui-implementer, integration-specialist, threejs-scene-builder

### QA
- execute-qa-task — dispatcher; delegates review to `reviewer`, runs approval merges and `memory-gc` after each iteration
- create-github-release — single-phase: build from main + publish artifact to GitHub Releases (no PR, no watch)
- deploy-vercel, deploy-ftp — staging (auto on merge to main) / production (manual HITL)
- memory-gc — retire evidence with expired `valid_until`

### Reviewer
- execute-review — CI wait, validate, score, decide (merge decision is gated on human approval, never executed here)
- pr-judge, resolve-merge-conflict, cleanup-branch