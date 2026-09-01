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
Create files: `index.html`, `vite.config.ts`, `tsconfig.json`, `biome.json`, `src/main.tsx`, `src/App.tsx`, `src/stores/useAppStore.ts`, MSW **test** setup (`src/test/server.ts`, `src/test/setup.ts`), Storybook config, `.gitignore`. Do NOT create a browser MSW worker (`src/mocks/browser.ts`) or `/api/health` handler — those only belong if the project gains a real backend to mock. Keep `src/mocks/handlers.ts` empty/removable for tests.

### 4. Create package.json
Load template from `references/package.json`. Replace `<project_name>`.

### 5. Install dependencies
Run `npm install`. Retry on network errors.

### 6. Link to Vercel
- Requires `VERCEL_TOKEN` in env.
- `npx --yes vercel@latest link --yes --token "$VERCEL_TOKEN"`
- If `VERCEL_ORG_ID` set → append `--scope "$VERCEL_ORG_ID"`
- On failure → return error

### 7. Deploy to Vercel
- `npx --yes vercel@latest deploy --prebuilt --token "$VERCEL_TOKEN"`
- Retry on transient errors (timeout, 5xx)

### 8. Verify Vercel project config
- Read `/workspace/<project>/.vercel/project.json`
- If missing → error: "Vercel not linked for project <project>"
- Verify `.vercel/project.json` is committed to repo (no secrets stored)

### 9. Commit and push
Commit scaffold to main branch and push.

### 10. Set up CI
Load and follow the `setup-ci` skill in-place (create `.github/workflows/ci.yml`, commit, push). No subagent — it is a deterministic file write.

### 11. Return
Report: cloned repo, scaffolded files, deps installed, Vercel link status, deploy URL, CI status.
