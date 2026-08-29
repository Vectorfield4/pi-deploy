# pi-deploy

Natural-language dev system on [Pi](https://pi.dev). Detects project type (frontend, backend, fullstack, CLI, infra, content) from the codebase and routes to the right skill. No slash commands, no menus, just text in, PR out.

## Features

### 🧠 Memory Stack

Long-term memory for the agents, self-hosted RAG via dense-mem (PostgreSQL + pgvector + TEI embeddings). Records are durable, append-only evidence anchored by relationships, with lifecycle hooks for replacement and removal.

Used for:
- Rule cache and library docs cache
- Task outcomes and review verdicts
- Exploration anti-patterns (TTL, cleaned by memory GC)

Session memory (the orchestrator's scratchpad) is separate — pi-memory.

### ⚡ Smart Updates

Auto-update from GitHub via a cron poller (every 2 min, installed by `make setup`/`make update`). Applies only while Pi is idle — no session-file writes for the last 10 min — and scales to the change:

- Dockerfile/compose/Makefile → full `make update` (rebuild + restart)
- `.pi/settings.json` → pull + reinstall packages + restart
- Skills/agents/mcp/models → pull + restart

## Quick start

```bash
make init          # Create .env + directories
# Fill in .env with your secrets
make setup         # Full stack bootstrap
make logs          # Check logs
```

## Architecture

| Container | Role |
|---|---|
| `pi` | Pi agent + subagents (orchestrator/coder/qa) |
| `memory-db` | PostgreSQL + pgvector |
| `embedding` | TEI (all-MiniLM-L6-v2) |
| `dense-mem` | RAG MCP server |

## Task flow

```
Telegram → Orchestrator → Subagents (frontender/coder) → PR → Reviewer (complex/Pro tasks only) → human approval (pr_watch) → QA (merge/release/deploy)
```

The Pro model (`deepseek/deepseek-v4-pro`) is a cold path: it runs only for
complex tasks (frontend via `frontend-architect`, other types via a model
override on `coder`). Simple (Flash-only) tasks skip the reviewer and go
straight to the human approval gate.

## Pi extensions

Versions pinned in `.pi/settings.json`. Makefile reads the list and installs via `pi install`.

| Extension | Version | Role | Used by | Why it's here |
|-----------|---------|------|---------|---------------|
| `pi-subagents` | 0.58.0 | Multi-agent orchestration with strict tool allowlists, async runs, model overrides per role | All agents under `.pi/agents/` | Reads `model` and `tools` from each agent's frontmatter. |
| `pi-mcp-adapter` | 2.29.0 | MCP client. `mcp` proxy tool plus per-server `directTools` registration | All agents (proxy `mcp`); coder and frontender get `mcp:dense-mem` direct | Connects Pi to the dense-mem RAG server. Proxy keeps orchestrator/QA context light, direct gives workers full tool schemas. |
| `@bytesbrains/pi-telegram-bridge` | 1.4.1 | Telegram bot bridge inside the Pi interactive session | Pi container entrypoint | The path from Telegram into Pi. Polls in the background. |
| `ping-a-human-pi` | 0.1.1 | Generic human-in-the-loop notifications | QA agent for FTP deploy blocks | Used where GitHub polling doesn't apply (FTP deploys, destructive ops). |
| `pi-memory` | 0.4.2 | Session memory with qmd semantic search across daily logs and scratchpad | Pi main session | Separate from dense-mem evidence. Orchestrator scratchpad lives here. |
| `@upstash/context7-pi` | 0.1.2 | Library docs via Context7 | coder, frontender, qa | Workers call `resolve-library-id` then `query-docs` instead of trusting training data. |
| `@vectorfield/pi-prs` | 0.1.1 | GitHub PR watch with explicit URL/number targeting. Zero-token PR approval (registers the `pr_watch` tool) | Pi main session | Orchestrators hand passed PRs to the router via a `WATCH <url>` marker; the router calls `pr_watch({action:"watch", url})`. `/pr watch` polls GitHub from the project root and wakes Pi on external feedback until the PR closes/merges — without blocking Telegram. |

### What is not installed

- `pi-context-cap` only caps `contextWindow` for models whose id contains `anthropic` or `claude`. We use deepseek, so it does nothing. Add it back if the model switches.

## Human-in-the-loop

Three scenarios block the flow and wait for you. Vercel deploys are automatic and not on this list.

| Block | When it triggers | What's blocked | What you do | Timeout | Progress |
|-------|------------------|----------------|-------------|---------|----------|
| **PR approval (main)** | A PR targets `main`: complex tasks after the reviewer returns `decision: merge`, simple tasks right after the PR opens (`decision: skip_review`) | No turn is blocked — the orchestrator finishes and goes idle | Approve the PR (or comment / request changes) on GitHub | None (until PR closes/merges) | Orchestrator ends with a `WATCH <url>` marker; the router calls `pr_watch({action:"watch", url})` via `@vectorfield/pi-prs`; polls every 30s and wakes Pi on external feedback (zero-token). On approval, QA verifies the `APPROVED` review, squashes into main, triggers staging. On changes, feedback is relayed, no merge. |
| **FTP deploy (production)** | QA got `type=deploy` with a production target | The whole QA task | Reply in Telegram after you check the release zip | None, waits for reply | `ping-a-human-pi` in Telegram |
| **Destructive op** | Any operation with irreversible side effects (drop DB, force-push, etc.) | The specific step | Reply in Telegram | None, waits for reply | `ping-a-human-pi` in Telegram |

For contrast, these do not trigger HITL:

- Vercel staging deploy. Runs on merge to main.
- CI failures. Coder fixes in place until green. No ping.
- Bounced PR. QA sent the PR back for fixes. Coder pushes more commits on the same PR. No new HITL.

### Recovery

- PR approval is async: the orchestrator reports the PR URL, then `pr_watch` holds it in the background. When the PR is approved, Pi is woken and QA merges into main. If the watch stops (PR closed/merged or session restarted), the next Telegram message resumes from the current PR state (idempotency check).
- Telegram bot crashed during HITL: `make restart`. The flow resumes from the last `ask_human` block (FTP/deploy). If state is lost, resend the command ("deploy" / "release") in Telegram and the orchestrator picks it up.

## Documentation

- [AGENTS.md](AGENTS.md): full system documentation

## License

MIT
