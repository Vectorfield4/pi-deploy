# pi-deploy

Deployment + instruction repo for a Pi-based AI development system. No application code — just Pi skills (Markdown), agent configs, and bash scripts.

## Layout

```
.pi/
├── settings.json     # Pi config: model default, compaction, subagent model scope
├── mcp.json          # MCP servers (empty by default; dense-mem served by pi-dense-mem)
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

One Pi process (interactive, PTY, Telegram via `@bytesbrains/pi-telegram-bridge`) + 3 memory containers (PostgreSQL+pgvector, TEI embeddings, dense-mem RAG). No slash commands — users write naturally. The interactive session routes every message to the `orchestrator` subagent (intent: task/question/feedback/deploy/...), which delegates to workers (`frontend-architect`/`frontend-implementer` for frontend, `coder` otherwise). The Pro model is a cold path, invoked only for complex tasks (`metadata.pro_invoked`), and the `reviewer` (score decision) runs **only** for those tasks. Work lands on a feature branch and is pushed to `main` directly — no PR, no human approval gate. Released/deployed by `qa`.

## How the main session works (router)

The main session's actual system prompt lives in **`.pi/SYSTEM.md`** — Pi loads
it for the project and replaces the default system prompt, so the router rules
reach the session even though this file is not mounted in the container.

The contract here is documentation of that prompt. Summary: you (this session)
are a thin router, not the actor. Every message is routed to the `orchestrator`
subagent and its output is followed.

The orchestrator's `systemPromptMode: replace` makes its system prompt the
cache anchor for the orchestrator's session. Every token the orchestrator
reads is replayed as cacheRead on every subsequent turn, so the orchestrator
stays thin: it inventories (`grep`/`find`/`ls`/`wc`) rather than reads, and
ships a `metadata.file_inventory` to workers so they do the heavy file reads.
See `.pi/agents/orchestrator.md` (Context Discipline) and
`.pi/skills/orchestrate-task/SKILL.md` (step 4.7).

One thing you do yourself, without delegating:

Subagents cannot run slash commands or hold tools only the main session loads —
a push/merge/release never happens on this session either. The orchestrator
delegates pushes to `qa`; the reviewer only decides, it never pushes.

The `orchestrator` subagent has **no `edit`/`write` tools** — it is physically
incapable of writing code and can only delegate. Never re-add those tools to
its frontmatter; that is the anti-failure guarantee: an orchestrator that
"learns" to implement answers directly exactly like a broken router.

The orchestrator's `tools` line keeps `subagent_wait` for the documented
exception path (e.g. `pi -p` non-interactive runs that have no next turn to
receive the notification). In the **main flow** the orchestrator relies on
the result-watcher's `<subagent_notification>` injection — launch a worker,
end the turn, and the next turn opens with the worker's outcome already
in context. `subagent({ action: "status" })` is a one-shot diagnostic,
never a wait loop. `subagent_wait` has a known race condition that returns
early with a false timeout while the child is still running, and treating
it as a strict block burned 13 status calls for 3 workers in a recent
task and produced duplicated acceptance reports. The wait discipline is
in `orchestrate-task` step 8.5.

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
| **CLI/lib** | package.json with bin/main, or Makefile + src/ | coder | execute-task |
| **infra** | docker-compose.yml, Dockerfile, .github/workflows | coder | setup-ci, execute-task |
| **content** | Markdown-heavy, no code | coder | content-strategist, narrative-designer |

Frontend skills load only when the project is detected as frontend.

## Task flow

Telegram → Orchestrator → workers (frontend-architect, frontend-implementer, coder) on a feature branch → Reviewer only for complex/Pro tasks (score decision; simple tasks skip) → QA (push branch into main + release/deploy)

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
  review/target-file fields). See `orchestrate-task` step 7.
- Finalize/branch-push → `qa`: `{"type":"push","project":...,"branch":...,"metadata":{"pro_invoked":...}}`.

Read-side: every delegated agent parses its incoming task string as JSON and
reads fields via `task.type`, `task.metadata.*`, etc. Do not pass `task` as an
object anywhere.

## Memory layer

**dense-mem** — self-hosted RAG memory (PostgreSQL + pgvector + TEI), contract `dense-mem.v2.6`, reached via the `pi-dense-mem` extension. Stores durable append-only **evidence anchored by relationships**: `relationships` and `idempotency_key` required, `supersedes_evidence_ids` goes inside the evidence item, lifecycle via `retract_evidence`/`correct_relationship`. `source_type` enum: conversation/document/observation/manual. Recall is support-path gated and returns `{ evidence_id, context, space_kind }` — read `context`, never `content`.

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
- intent-router, orchestrate-task, execute-task, setup-ci, project-init, content-strategist, narrative-designer, project-discover
- docs-lookup — Context7 with 7-day dense-mem cache; use instead of `resolve-library-id`/`query-docs` directly

### Frontend (loaded only for frontend projects)
- ui-architect, ui-implementer, integration-specialist, threejs-scene-builder

### QA
- execute-qa-task — dispatcher; delegates review to `reviewer` for complex tasks, pushes branches into `main` (no PR), runs `memory-gc` after each iteration
- create-github-release — single-phase: build from main + publish artifact to GitHub Releases (no PR, no watch)
- deploy-vercel, deploy-ftp — staging (auto on push to main) / production (manual HITL)
- memory-gc — retire evidence with expired `valid_until`

### Reviewer
- execute-review — validate, score the branch diff against `main`, decide (merge decision is a push-approval only — QA executes the push, never here)
- pr-judge, resolve-merge-conflict, cleanup-branch

## Code comments

In this repo (configs, Makefile, compose, scripts):
- Short — one line or less, never multi-line prose.
- Inline — on the same line as the code where practical.
- Only "why" — non-obvious intent/ordering/tolerance; never restate the code.
- No banners, section headers, or attribution.

When editing, trim any comment that breaks these rules.