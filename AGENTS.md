# pi-deploy

Deployment + instruction repo for a Pi-based AI development system. No application code — just Pi skills (Markdown), agent configs, and bash scripts.

## Layout

```
.pi/
├── settings.json     # Pi config: model default, compaction, subagent model scope
├── mcp.json          # MCP servers (empty; memory served by the pgvec extension)
├── models.json       # Provider + model registry (timeweb)
├── agents/           # Agent definitions; skills listed per agent in frontmatter
└── skills/           # Skill packages (24 skills)
scripts/              # Bash scripts (init, setup, cloud-init, backup, setup-cron-jobs, update-on-push)
docker-compose.yml    # Pi + memory stack (3 services; embeddings remote)
Dockerfile.pi         # Pi container image
AGENTS.md             # This file — interactive-session instructions
.env                  # Secrets (gitignored)
```

## How it runs

One Pi process (interactive, PTY, Telegram via `@bytesbrains/pi-telegram-bridge`) + 2 memory containers (PostgreSQL+pgvector, `pi-pgvector-api-embeddings` RAG; embeddings via remote API). No slash commands — users write naturally. The interactive session routes every message to the `orchestrator` subagent (intent: task/question/feedback/deploy/...), which delegates to workers (`frontend-architect`/`frontend-implementer` for frontend, `coder` otherwise). Execution models are flash; tasks that need the architecture gate set `metadata.complex: true`. The `reviewer` (score decision) runs on **every** coding task as the quality loop — it returns deficient work via `bounce` before anything is pushed. Work lands on a feature branch and is pushed to `main` directly — no PR, no human approval gate. Released/deployed by `qa`.

Single responsibility: each agent owns its one job and never narrates another's.
Skills/agents describe only the actor's own workflow — never "X is done by Y" or
"when Z happens, Y does Q". Delegate, don't instruct.

No prose: skills/agents state rules as terse, imperative bullets — no narrative
filler, no context-less meta-commentary ("as noted", "for clarity"), no repeated
A-not-B phrasing. Say it once, plainly. Model/config specifics live in headers
(frontmatter `model:`) and config files, not body text.

"Why" discipline: drop procedural why — anything restating the mechanism
("so the embedding match is precise", "to repeat the earlier step"). Keep
decision why only — terse rationale at a constraint or decision point
("for isolation", "kept write-less so it cannot answer directly",
"so the complex gate reuses it instead of re-running the architect"). If the
"why" does not gate a choice, omit it.

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

## Bridge output contract (what the user sees in Telegram)

The user sees Telegram, not the agent's stdout. Three independent channels
feed the chat, and each has its own rules. A line in chat can come from any
of them, and they are not deduplicated by the bridge.

### 1. Bridge auto-ack (extension, not yours)

`@bytesbrains/pi-telegram-bridge@1.4.1` (`src/index.ts:101-105`) sends
`👂 Got it! Working on: <text>` to chat the moment it forwards a user
message into the session. There is no env flag, skill, or prompt rule that
turns it off — it is in the extension's source. Design the conversation
around it: it always lands first, on every user message. Do not try to
"explain" it, do not re-send a similar message, do not promise the user you
will suppress it.

### 2. Worker `telegram_notify` / `telegram_send` calls (tool calls, not text)

The `telegram-first` skill exposes `telegram_notify(kind="task", status=…)`
and `telegram_send(message=…)`. A worker calling these mid-run is what
produces the `✅ pi finished a task in /workspace: …` cards. This is the
spammiest channel. Rules, enforced in every skill that owns a turn:

- `telegram_notify(kind="task")` — at most **twice** per worker turn:
  once at `status="started"`, once at `status="complete"`. Never per
  sub-step, never per subagent handoff.
- `telegram_send` — only for genuine one-off status (e.g. "deploy needs
  human approval" with `telegram_ask`). Not for "передаю оркестратору,
  сообщу результат" — the bridge already acked.

### 3. Final assistant message (text streamed to chat)

The Pi runtime streams the worker's final message text into chat. If the
final message is 200 lines of raw `[ARCHITECTURE_RESULT]` JSON or
`acceptance-report`, the user reads that as "the result".

- **Final message ≤ 4–6 lines**, plain prose, no fenced code, no JSON.
  Format: `✅ <one-line outcome>. <files/branch + 1-line what changed>.`
- **Detail to disk.** Specs, criterion matrices, diffs, long findings
  → `artifacts/<task_id>-*.md`. Reference by path, do not paste.
- **Enforced per skill.** `execute-task`, `ui-architect`, `ui-implementer`,
  `execute-qa-task` each carry a "Final-message contract" + "Tool-call
  discipline" section that restates this for the agent that owns the turn.
- **Router (main session)** must also obey it: when forwarding a worker
  result, paraphrase to one line, do not paste the worker's last message
  verbatim.

### Why the three channels exist

The bridge auto-ack gives the user instant feedback that the message was
received. `telegram_notify` is a structured status card. The final message
is the actual deliverable. Each one answers a different question —
"received?", "where is it?", "what's the answer?" — and only the third is
under worker control.

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

Telegram → Orchestrator → workers (frontend-architect, frontend-implementer, coder) on a feature branch → Reviewer on every coding task (score decision / quality loop; `bounce` returns deficient work) → QA (push branch into main + release/deploy)

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
  a `metadata` object (`memory_context`, `anti_patterns`, `complex`, plus
  review/target-file fields). See `orchestrate-task` step 7.
- Finalize/branch-push → `qa`: `{"type":"push","project":...,"branch":...,"metadata":{"complex":...}}`.

Read-side: every delegated agent parses its incoming task string as JSON and
reads fields via `task.type`, `task.metadata.*`, etc. Do not pass `task` as an
object anywhere.

## Memory layer

**pi-pgvector-api-embeddings** — self-hosted lightweight RAG memory (PostgreSQL + pgvector; embeddings via remote API), reached via the `pgvec` extension. Stores flat records: free-text `content`, `tags` array, `source_type`, `valid_until`, `confidence`, `owner`, and an `idempotency_key` for dedupe. `source_type` enum is `conversation|document|observation|manual`; `content` and `idempotency_key` and `source_type` are required, unknown keys are rejected (`additionalProperties: false`) — no `predicate`/`entity`/`polarity`. Recall is cosine-similarity over the embedding with an optional `tag` filter; returns `{ evidence_id, content, tags, space_kind, valid_until, confidence }` — read `content`, never a partial view.

Usage patterns (tag drives the recall filter; `source_type: observation` for experiential, `manual` for metadata):
- **Task outcomes** (workers): tag `project:<project>`,`<type>`, `source_type: observation`, TTL 90d.
- **Design decisions** (orchestrator, after frontend architecture): tag `design-decision`, idempotency `design:<project>:<feature>:<hash>`, TTL 90d. The complex frontend gate recalls it (tag `design-decision`) first — if a matching decision exists, the architect is skipped.
- **Review verdicts** (reviewer): tag `verified`, `source_type: observation`, TTL 90d.
- **Bounce findings** (reviewer): tag `review-bounce`, keyed on idempotency `review-bounce:<project>:<task_id>:<n>`, 7-day TTL — lets the re-review check the fix delta instead of re-scoring from scratch.
- **Exploration anti-patterns** (reviewer): tag `anti-pattern`, TTL 30d.
- **Memory GC** (QA): `pgvec_gc` retires records whose `valid_until` has passed (meta never, task/verified/design 90d, feedback 60d, exploration 30d).

Tags live in both the content prefix and the flat `tags` array; recall filters on the array via `tag`. Ownership: retract only on own records (coder↔task, reviewer↔reviews). Session memory (orchestrator scratchpad) is separate — `pi-memory`. Rules and docs caches live as plain on-disk files.

## Skills catalog

### Universal
- intent-router, orchestrate-task, execute-task, setup-ci, project-init, content-strategist, narrative-designer, project-discover
- docs-lookup — Context7 with 7-day file cache; use instead of `resolve-library-id`/`query-docs` directly

### Frontend (loaded only for frontend projects)
- ui-architect, ui-implementer, integration-specialist, threejs-scene-builder

### QA
- execute-qa-task — dispatcher; delegates review to `reviewer` on every coding task (quality loop), pushes branches into `main` and bounces deficient work back (no PR), runs `memory-gc` after each iteration
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