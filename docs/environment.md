# Environment Variables Reference

This document lists all environment variables required for the Pi-deploy system to function correctly. Variables are categorized by their role in the system.

## 📋 Quick Overview

| Category | Required | Description |
|----------|----------|-------------|
| **AI Providers** | ✅ Yes | Model configuration (DeepSeek/OpenAI-compatible) |
| **Telegram** | ✅ Yes | Bridge connectivity |
| **Dense-mem** | ✅ Yes | Memory stack (PostgreSQL + pgvector + control portal) |
| **Optional Services** | ⚠️ No | Vercel, FTP, Context7, AI verifier |

---

## 1. AI Provider Variables

These configure the LLM integration for the Pi agent.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `OPENAI_API_KEY` | ✅ Yes | - | DeepSeek or OpenAI API key |
| `OPENAI_API_BASE` | ✅ Yes | `https://api.openai.com/v1` | Base URL for API calls (point to DeepSeek) |
| `AI_VERIFIER_API_URL` | ✅ Yes | - | AI verifier service URL — required for claim verification. Must be OpenAI-compatible endpoint. Default for Ollama: `http://host.docker.internal:11434/v1` |
| `AI_VERIFIER_API_KEY` | ✅ Yes | - | AI verifier authentication key — required for claim verification provider. Default for Ollama: `ollama` |
| `AI_VERIFIER_MODEL` | ✅ Yes | - | Model name for verification tasks — required. Default is `gpt-4o-mini`, change to `llama3.1:8b` if using Ollama. A 7B-8B class model verifies comfortably on a laptop; larger models can exceed the default 60-second timeout while they load, leaving claims parked as `candidate_claim` with the error recorded in the placement item. |

---

## 2. Telegram Bridge

Required for the Telegram ↔ Pi interactive session bridge.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `TELEGRAM_BOT_TOKEN` | ✅ Yes | - | Telegram bot token for the bridge |
| `TELEGRAM_CHAT_ID` | ✅ Yes | - | Target chat ID for messages |

---

## 3. GitHub & Deployment

Optional variables for CI/CD and deployment workflows.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `GITHUB_TOKEN` | ❌ No | - | GitHub API token for PR operations |
| `VERCEL_TOKEN` | ❌ No | - | Vercel API token (staging deploy) |
| `VERCEL_ORG_ID` | ❌ No | - | Vercel organization ID |
| `FTP_HOST` | ❌ No | - | Production FTP host |
| `FTP_USER` | ❌ No | - | FTP username |
| `FTP_PASS` | ❌ No | - | FTP password |

---

## 4. Context7 (Library Documentation)

Optional — works without a key at IP-based rate limits.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `CONTEXT7_API_KEY` | ❌ No | - | Context7 API key for library docs lookup |

---

## 5. Dense-mem (Memory Stack) ⭐ Most Critical

These variables configure the dense-mem memory infrastructure (PostgreSQL, pgvector, control portal). **Most are auto-configured by `make setup`.**

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `POSTGRES_PASSWORD` | ✅ Yes | - | Password for PostgreSQL user `densemem` |
| `CONTROL_PORTAL_TOKEN` | ⚠️ Conditional | - | **Control portal token** — auto-resolved by `memory-bootstrap.sh` if not set. Set manually if preferred. |
| `DENSE_MEM_PORT` | ❌ No | `8090` | Host port mapping to dense-mem's container port 8090 |
| `TEAM_NAME` | ❌ No | `pi-coder` | Team name for dense-mem (used by bootstrap script) |
| `CREDS_NAME` | ❌ No | `default` | Credential name for API key (used by bootstrap script) |

### Dense-mem Details

- **`POSTGRES_PASSWORD`** — Required. Set during `make init` (copied from `.env.example`). Used by PostgreSQL container and dense-mem.
- **`CONTROL_PORTAL_TOKEN`** — The script `memory-bootstrap.sh` will **auto-detect** this from the running dense-mem container. If you set it manually in `.env`, that value will be used. If not, the script retrieves it automatically.
- **`DENSE_MEM_PORT`** — Maps `127.0.0.1:${DENSE_MEM_PORT}` → container port `8090`. Change if 8090 is busy on your host.
- **`TEAM_NAME`** & **`CREDS_NAME`** — Used by `memory-bootstrap.sh` to create/lookup the team and credential in dense-mem. Change only if you want non-default names.

---

## 6. Pi Agent Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `PI_THEME` | ❌ No | `default` | UI theme for the Pi agent interface |

---

## Usage Workflow

### Fresh Server / First Deployment (cloud-init.sh use case)

```bash
# cloud-init.sh handles the full initial setup:
# 1. Installs Docker, git, make
# 2. Clones the repository
# 3. make init        # Creates .env from .env.example (all vars empty)
# 4. Fill .env manually with your secrets (OPENAI_API_KEY, etc.)
# 5. make setup       # Bootstrap + start all services

# Or manually:
make init           # Creates .env from .env.example
# Fill in .env with your secrets:
#   OPENAI_API_KEY, OPENAI_API_BASE, TELEGRAM_BOT_TOKEN,
#   TELEGRAM_CHAT_ID, POSTGRES_PASSWORD
make setup          # Full bootstrap — starts dense-mem + auto-resolves token
# Pi is now running
```

### After First Deployment

```bash
# NEVER run make init again — it will merge new keys from .env.example
# but preserve your existing secrets.

# To restart Pi after changing .env:
make restart        # Pi picks up the updated .env values

# To re-run bootstrap (if you changed dense-mem config):
make setup          # Re-runs memory-bootstrap.sh

# Just start services if already bootstrapped:
make up
```

### One-Command Summary (initial setup)

```bash
make init       # Create .env (safe — won't overwrite existing keys)
make setup      # Full bootstrap + install packages
```

### Merging Behavior of make init

- **If .env does NOT exist**: Copies `.env.example` → `.env` (full setup)
- **If .env EXISTS**: Merges only keys from `.env.example` that are **missing** in `.env`
  - Your existing `OPENAI_API_KEY`, `POSTGRES_PASSWORD`, etc. are **preserved**
  - Only new/empty keys from the template are added
  - No secrets are deleted or overwritten

---

## ⚠️ Common Issues

| Problem | Cause | Fix |
|---------|-------|-----|
| `CONTROL_PORTAL_TOKEN not set` | dense-mem not started or bootstrap not run | Run `make setup` (starts dense-mem + auto-resolves token), or set manually in `.env` |
| `POSTGRES_PASSWORD not set` | Missing from `.env` | Add to `.env` or run `make init` again |
| Port 8090 conflict | `DENSE_MEM_PORT` not set, default conflicts | Set `DENSE_MEM_PORT=3890` (or other available port) in `.env` |
| Telegram bridge not connecting | `TELEGRAM_BOT_TOKEN` or `CHAT_ID` incorrect | Verify values in `.env` |

---

## 📁 Related Files

- `.env.example` — Template with all variables (commented)
- `scripts/memory-bootstrap.sh` — Bootstrap script with token auto-resolution
- `docker-compose.yml` — Service configuration and env mappings
- `.pi/settings.json` — Pi package configuration
- `Makefile` — `init`, `setup`, `up` targets

---

## 🔐 Security Notes

- **Never commit real secrets** — `.env` should be in `.gitignore`
- `POSTGRES_PASSWORD` and `OPENAI_API_KEY` are the most sensitive values
- `CONTROL_PORTAL_TOKEN` grants access to dense-mem control portal — treat with care
- Consider using a secrets manager (HashiCorp Vault, AWS Secrets Manager) for production deployments