# Skills catalog

Pi loads all project skills into the session; agent `frontmatter.skills` gates
which ones are usable. Each skill lives in `.pi/skills/<name>/SKILL.md` and is
self-contained.

## Universal

- intent-router, orchestrate-task, execute-task, setup-ci, project-init, content-strategist, narrative-designer, project-discover
- pgvector-memory — call `pgvec_*` tools directly (pi-pgvector-api-embeddings extension)
- docs-lookup — Context7 with 7-day file cache; use instead of `resolve-library-id`/`query-docs` directly
- drawer-image — owned by the `drawer` agent. Two local extensions, both loaded via drawer's `subagentOnlyExtensions` (`/extensions/.../dist/index.js`), never via npm: `hf_generate_image` (HuggingFace, primary) and `generate_image` (OpenAI-compatible, fallback). Config: `.pi/settings/pi-huggingface-image-gen.json` / `.pi/settings/pi-openai-image-generation.json`. Whitelist before generation: `hero | cover | og | illustration | concept | background | avatar | thumbnail | diagram`.

## Frontend

- ui-architect, ui-implementer, mui-svg-composition, integration-specialist, threejs-scene-builder

## QA

- execute-qa-task — dispatcher; delegates review to `reviewer` on every coding task (quality loop), pushes branches into `main` and bounces deficient work back (no PR), runs `memory-gc` after each push/release
- create-github-release — single-phase: build from main + publish artifact to GitHub Releases (no PR, no watch)
- deploy-vercel, deploy-ftp — staging (auto on push to main) / production (manual HITL)
- memory-gc — retire evidence with expired `valid_until`
- sessions-gc — cron-only, **not** a skill. `scripts/sessions-gc.sh` runs at 03:00 via `setup-cron-jobs.sh` and prunes `*.broken` / `*.bak` / `__RETIRED_*_scratch/` plus `*.jsonl` older than 24h + sibling dirs. Do not invoke from agents.

## Reviewer

- execute-review — validate, score the branch diff against `main`, decide (merge decision is a push-approval only — QA executes the push, never here)
- pr-judge, resolve-merge-conflict, cleanup-branch