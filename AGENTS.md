# pi-deploy

Deployment + instruction repo for a Pi-based AI development system. No application code — just Pi skills (Markdown), agent configs, and bash scripts.

## Layout

```
.pi/
├── settings.json     # Pi config: model default, compaction, subagent model scope
├── mcp.json          # MCP servers (empty; memory served by the pgvec extension)
├── models.json       # Provider + model registry (timeweb)
├── agents/           # Agent definitions; skills listed per agent in frontmatter
└── skills/           # Skill packages (25 skills)
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
> 1. `/root/.pi/agent/SYSTEM.md` is present in the container (seeded from the
>    repo skel on boot) — without it the session falls back to a bare model
>    prompt.
> 2. `.pi/settings.json` `subagents.modelScope.allow` uses the full
>    `provider/model` id (`timeweb/deepseek/...`) — a provider-less pattern
>    makes every subagent launch fail with a modelScope error.
> 3. Delegation uses `task` as a **string**, never an object — an object fails
>    validation with `task: must be string` (pi-subagents@0.58.x).
> 4. If a session previously hit errors, the model may have "learned" that
>    delegation fails and answer directly — start a fresh session
>    (rename the session file under `/root/.pi/agent/sessions/--workspace--/`
>    and let Pi start a new one).

## Telegram output contract (what the user sees in chat)

The user reads Telegram, not the agent's stdout. Two extensions and the
Pi runtime itself write to the chat. The chat is not deduplicated. A line
in chat can come from any of them.

### The two extensions

- **`@bytesbrains/pi-telegram-bridge@1.4.1`** — Telegram ↔ Pi transport.
  Pulls updates from Telegram, forwards them into the pi session, streams
  pi's stdout back. Lives at `src/index.ts`. Registers the `telegram_*`
  tools (`telegram_notify`, `telegram_send`, `telegram_ask`,
  `telegram_status`, …) via `pi.registerTool` and ships the `telegram-first`
  skill (its own `skills/telegram-first/SKILL.md`). Configures only via the
  bot token.
- **`ping-a-human-pi@0.1.1`** — HITL channel. Pi package embedding a tiny
  MCP stdio client that wires the `ping-a-human` MCP server into the session
  (spawned as `npx -y ping-a-human`), registering `notify_human` /
  `ask_human` as model-callable tools plus an approval gate for risky
  bash. Registered in `.pi/settings.json:30`. pings via Telegram on
  `agent_end` (`✅ pi finished a task …`).

Bridge moves messages and owns the `telegram_*` tools. ping-a-human lets the
model `notify_human` / `ask_human`, and gates risky bash.

### Channel 1 — bridge auto-ack (transport, not yours)

`pi-telegram-bridge` (`src/index.ts:101-105`) sends
`👂 Got it! Working on: <text>` the moment it forwards a user message into
the session. The auto-ack lives in the extension's source, so env flags,
skills, and prompt rules cannot turn it off. It always lands first, on
every user message. The right response is to work around it: do not
explain it, do not re-send a similar message, do not promise suppression.

### Channel 2 — worker `telegram_notify` / `telegram_send` calls (tool calls, not text)

These are the bridge's `telegram_*` tools, invoked by a worker mid-run
(`telegram-first` skill). The `✅ pi finished a task in /workspace: …`
cards on `agent_end` are ping-a-human's, not these. Rules live per-skill
("Final-message contract" + "Tool-call discipline" in each skill that owns a
turn); this channel is the spammiest one under worker control.

### Channel 3 — final assistant message (text streamed to chat)

The Pi runtime streams the worker's final message text into chat. If the
final message is 200 lines of raw `[ARCHITECTURE_RESULT]` JSON or
`acceptance-report`, the user reads that as "the result". The final-message
contract (≤ 4–6 lines, detail to disk) is enforced per-skill — see
`execute-task`, `ui-architect`, `ui-implementer`, `drawer-image`,
`execute-qa-task`. The router must also obey it: when forwarding a worker
result, paraphrase to one line, do not paste the worker's last message
verbatim.

### Why the three channels exist

The bridge auto-ack gives the user instant feedback that the message was
received. `telegram_notify` is a structured status card. The final message
is the actual deliverable. Each one answers a different question —
"received?", "where is it?", "what's the answer?" — and only the third is
under worker control.

## Code comments

In this repo (configs, Makefile, compose, scripts):
- Short — one line or less, never multi-line prose.
- Inline — on the same line as the code where practical.
- Only "why" — non-obvious intent/ordering/tolerance; never restate the code.
- No banners, section headers, or attribution.

When editing, trim any comment that breaks these rules.