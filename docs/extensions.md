# Extensions

Pi extensions are npm packages (or local paths) that register tools, hooks,
and resources via `pi.registerTool()`. Two installation mechanisms exist.

## 1. Settings-driven packages (primary)

The `packages` array in `.pi/settings.json` is the source of truth.

```json
{
  "packages": [
    "npm:pi-subagents@0.58.0",
    "npm:@bytesbrains/pi-telegram-bridge@1.4.1",
    "/extensions/pi-pgvector-memory"
  ]
}
```

Format: `npm:<package>[@<version>]` or `/<absolute-path>`.

### Install flow

```
settings.json  →  install-packages.sh  →  docker exec pi pi install <pkg>
```

- `make install-packages` (or `bash scripts/install-packages.sh`) reads
  `/root/.pi/agent/settings.json` inside the container, parses the `packages`
  array, runs `pi install` for each entry.
- Local path entries (`/extensions/...`) also get `npm install --omit=dev` in
  their directory.
- Idempotent: safe to re-run. Missing packages get installed; already-installed
  ones are no-ops.

### Update flow

`update-on-push.sh` detects settings.json changes and runs:

```
git pull → make install-packages → docker compose restart pi
```

Full rebuilds (`make update`) also run `install-packages` after recreate.
Adding or bumping a version in `packages` + pushing is enough to trigger
install on the next cron tick.

## 2. Local extensions directory

The `./extensions/` directory on the host is bind-mounted at `/extensions`
in the container. Each subdirectory is a standalone npm package with its own
`package.json`.

Current local extensions:

| Path | Purpose |
|------|---------|
| `extensions/pi-pgvector-memory` | pgvector memory tools (`pgvec_*`) |
| `extensions/huggingface-image-gen` | HuggingFace image generation |
| `extensions/openai-image-gen` | OpenAI-compatible image generation |

Local extensions are registered via their path in `settings.json` packages
(e.g. `"/extensions/pi-pgvector-memory"`). The path must be absolute from
the container's perspective (`/extensions/...`).

### Adding a local extension

1. Create directory under `extensions/<name>/` with `package.json` + entry.
2. Add `"/extensions/<name>"` to `packages` in `.pi/settings.json`.
3. Run `make install-packages`.

## 3. Pi-managed extensions

Some extensions live under `.pi/extensions/` and are loaded by Pi's internal
discovery (not the `packages` list). Currently:

- `.pi/extensions/subagent/` — subagent configuration

Do not confuse these with the `extensions/` root directory.

## Rules

- **One source of truth**: every npm extension must appear in
  `.pi/settings.json` `packages`. No silent installs.
- **Pin versions**: use `npm:<pkg>@<version>` for npm packages. Unpinned
  packages drift on rebuild.
- **Dockerfile.pi is frozen**: never add extension installs there. The
  Dockerfile handles system packages and the pi binary only.
- **Local extensions need deps**: `install-packages.sh` runs `npm install`
  for local path entries, but only with `--omit=dev`. Peer deps or optional
  native modules may need manual attention.
- **Container restart required**: extensions load at session start. After
  `pi install`, the agent must restart (or `/reload`) to pick them up.
