# pi-deploy

AI-powered development system built on [Pi](https://pi.dev). Project-agnostic — detects frontend, backend, fullstack, CLI, infra, or content projects and routes to appropriate skills. Natural language interface — no slash commands, just talk to the bot.

## Quick Start

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

## Task Flow

```
Telegram → Orchestrator → Subagents (coder) → PR → QA → Pass/Fail → Deploy
```

## Documentation

- [AGENTS.md](AGENTS.md) — full system documentation

## License

MIT
