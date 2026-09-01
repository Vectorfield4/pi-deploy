# pi-deploy

Natural-language dev system on [Pi](https://pi.dev). Detects project type (frontend, backend, fullstack, CLI, infra, content) from the codebase and routes to the right skill. No slash commands, no menus, just text in, merged to main out.

## Features

### 🧠 Memory Stack

Long-term memory for the agents, self-hosted lightweight RAG (`pi-pgvector-api-embeddings`: PostgreSQL + pgvector) with remote API embeddings. Records carry content plus optional tags / predicate / polarity / TTL; recall is cosine-similarity over the embedding plus optional tag filter. Embeddings are hosted (remote OpenAI-compatible endpoint) — no local embedding container.

Used for:
- Task outcomes and review verdicts
- Exploration anti-patterns (TTL, cleaned by memory GC)

Rule and library docs caches are plain on-disk files — deterministic lookups don't warrant an embedding call.

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
| `pgvec-memory` | RAG memory server (`pi-pgvector-api-embeddings`) |

Embeddings are hosted on a remote OpenAI-compatible endpoint (configured via `AI_API_*` in `.env`) — no local embedding container.

## Task flow

```
Telegram → Orchestrator → Subagents (frontend/coder) on a feature branch →
   Reviewer reviews the branch diff vs main first (every coding task, quality loop) → push to main
```

Execution models are flash. The reviewer
(a score decision / quality loop) runs on **every** coding task and returns
deficient work via `bounce` before anything is pushed. There is no PR and no
human approval gate — pushes to `main`
happen via `git merge --ff-only` after the reviewer passes the branch.

## Pi extensions

Versions pinned in `.pi/settings.json`. Makefile reads the list and installs via `pi install`.

| Extension | Version | Role | Used by | Why it's here |
|-----------|---------|------|---------|---------------|
| `pi-subagents` | 0.58.0 | Multi-agent orchestration with strict tool allowlists, async runs, model overrides per role | All agents under `.pi/agents/` | Reads `model` and `tools` from each agent's frontmatter. |
| `pi-pgvector-memory` | local | Native Pi extension that exposes the pgvec memory tools (`pgvec_*`) directly, without the MCP proxy | All agents (orchestrator, coder, frontend-implementer, reviewer, qa) | Thin proxy to the `pgvec-memory` server. Memory is best-effort, never a hard dependency. |
| `@bytesbrains/pi-telegram-bridge` | 1.4.1 | Telegram bot bridge inside the Pi interactive session | Pi container entrypoint | The path from Telegram into Pi. Polls in the background. |
| `ping-a-human-pi` | 0.1.1 | Generic human-in-the-loop notifications | QA agent for FTP deploy blocks | Used where GitHub polling doesn't apply (FTP deploys, destructive ops). |
| `pi-memory` | 0.4.2 | Session memory with qmd semantic search across daily logs and scratchpad | Pi main session | Separate from pgvec evidence. Orchestrator scratchpad lives here. |
| `@upstash/context7-pi` | 0.1.2 | Library docs via Context7 | coder, frontend-implementer, reviewer (via the `docs-lookup` skill) | Workers use `docs-lookup` (Context7 + 7-day file cache) instead of trusting training data; never call `resolve-library-id`/`query-docs` directly. |

### What is not installed

- `pi-context-cap` only caps `contextWindow` for models whose id contains `anthropic` or `claude`. We use deepseek, so it does nothing. Add it back if the model switches.

## Human-in-the-loop

Two scenarios block the flow and wait for you. Vercel staging deploys are
automatic and not on this list; pushes to `main` are not HITL either (every
push is reviewed by the reviewer, then QA fast-forwards into `main`).

| Block | When it triggers | What's blocked | What you do | Timeout | Progress |
|-------|------------------|----------------|-------------|---------|----------|
| **FTP deploy (production)** | QA got `type=deploy` with a production target | The whole QA task | Reply in Telegram after you check the release zip | None, waits for reply | `ping-a-human-pi` in Telegram |
| **Destructive op** | Any operation with irreversible side effects (drop DB, force-push, etc.) | The specific step | Reply in Telegram | None, waits for reply | `ping-a-human-pi` in Telegram |

For contrast, these do not trigger HITL:

- Vercel staging deploy. Runs on push to main.
- CI failures. Coder fixes in place until green. No ping.
- Bounced branch. QA sent the branch back for fixes. Coder pushes more commits on
  the same branch, reviewer re-evaluates. No new HITL.

### Recovery

- Telegram bot crashed during HITL: `make restart`. The flow resumes from the last `ask_human` block (FTP/deploy). If state is lost, resend the command ("deploy" / "release") in Telegram and the orchestrator picks it up.

## Documentation

- [AGENTS.md](AGENTS.md): full system documentation

## License

MIT
