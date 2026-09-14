---
name: project-init
description: "Initializes a new project on the standardized stack (React + Vite + TypeScript + MUI) and links it to Vercel."
---

# Project Init

Clones repo, scaffolds the stack, installs deps, links Vercel, sets up CI.

## Steps

### 1. Clone
- If `/workspace/<project>` missing → `git clone <repo_url> /workspace/<project>`
- If exists → `git -C /workspace/<project> pull`

### 2. Write project AGENTS.md
Create `/workspace/<project>/AGENTS.md` listing:
- Stack: React 19 + Vite 7 + TypeScript 5 + MUI 7 + Zustand 5 + TanStack Query 5 + GSAP 3 + Three.js/R3F 9 + Vitest + MSW + Biome 2 + Storybook 9
- Commands: `npm run dev`, `npm run build`, `npm run test`, `npm run lint`, `npm run format`, `npm run storybook`
- No Tailwind, no ESLint/Prettier — Biome instead

### 3. Scaffold
Run `python3 /etc/pi-skel/skills/project-init/scripts/scaffold.py /workspace/<project> <project>`.
It creates the FSD dirs (.gitkeep on empty layers) and `package.json` (name substituted).
Then create the skeleton files the agent writes:
- `src/main.tsx` — Vite entry: mounts App
- `src/app/App.tsx` — root: providers + routed pages
- `src/app/providers/*` — Theme → Query → I18n → Router
- `src/app/layouts/*` — route shells
- `src/app/routes/index.tsx` — route registry (single source of truth)
- `src/shared/config/theme.ts` — MUI theme tokens
- `src/shared/config/useAppStore.ts` — theme/lang state (Zustand)
- `src/shared/mocks/handlers.ts` — empty; handlers land when a backend exists
- `test/server.ts` — MSW node server (test-only)
- `test/setup.ts` — Vitest setup: jest-dom, renderWithProviders
- `test/renderWithProviders.tsx` — RTL helper: providers + router
- Root config: `index.html`, `vite.config.ts`, `tsconfig.json`, `biome.json`, `.storybook/main.ts` (stories glob `../stories/**/*.stories.@(ts|tsx)`), `.storybook/preview.ts`, `.gitignore`, `AGENTS.md`

### 4. Install dependencies
Run `npm install`. Retry on network errors.

### 5. Link to Vercel
- Requires `VERCEL_TOKEN` in env.
- `npx --yes vercel@latest link --yes --token "$VERCEL_TOKEN"`
- If `VERCEL_ORG_ID` set → append `--scope "$VERCEL_ORG_ID"`
- On failure → return error

### 6. Deploy to Vercel
- `npx --yes vercel@latest deploy --prebuilt --token "$VERCEL_TOKEN"`
- Retry on transient errors (timeout, 5xx)

### 7. Verify Vercel project config
- Read `/workspace/<project>/.vercel/project.json`
- If missing → error: "Vercel not linked for project <project>"
- Verify `.vercel/project.json` is committed to repo (no secrets stored)

### 8. Commit and push
Commit scaffold to main branch and push.

### 9. Set up CI
Load and follow the `setup-ci` skill in-place (create `.github/workflows/ci.yml`, commit, push). No subagent — it is a deterministic file write.

### 10. Return
Report: cloned repo, scaffolded files, deps installed, Vercel link status, deploy URL, CI status.
