---
name: project-init
description: "Initializes a new project on the standardized stack (Astro SSG + React + StyleX + FSD) and links it to Vercel."
---

# Project Init

Clones repo, scaffolds the stack, installs deps, links Vercel, sets up CI.

## Steps

### 1. Clone
- If `/workspace/<project>` missing → `git clone <repo_url> /workspace/<project>`
- If exists → `git -C /workspace/<project> pull`

### 2. Write project AGENTS.md
Create `/workspace/<project>/AGENTS.md` listing:
- Stack: Astro 7 (SSG) + React 19 + TypeScript 5 strict + StyleX 0.19 + lucide-react + Radix + GSAP 3 + Three.js/R3F (3D islands) + Vitest + Testing Library + Biome 2 + Storybook 9
- Commands: `npm run dev`, `npm run build`, `npm run test`, `npm run lint`, `npm run format`, `npm run storybook`
- Tooling: Biome is the sole linter/formatter; style is StyleX via `@stylexjs/unplugin`; i18n is build-time `createT`; data is synchronous fixture reads
- Point structure to the FSD + Atomic Design standards (see the project's `docs/frontend/` if present)

### 3. Scaffold
Run `python3 /etc/pi-skel/skills/project-init/scripts/scaffold.py /workspace/<project> <project>`.
It creates the FSD dirs (.gitkeep on empty layers) and `package.json` (name substituted).
Then create the skeleton files the agent writes:
- `astro.config.ts` — `site`, `trailingSlash: "never"`, integrations `react()` + `sitemap()`; `vite.plugins` Stylex-unplugin (`useCSSLayers: true`, aliases `@/*`), `vite.resolve.alias` `@` → `src/`; `i18n` with `defaultLocale` and `prefixDefaultLocale: false`
- `tsconfig.json` (references) + `tsconfig.app.json` + `tsconfig.node.json`
- `src/app/layouts/BaseLayout.astro` — head (title/description/canonical/hreflang), theme bootstrap, slot
- `src/app/styles/global.css` — base styles
- `src/shared/design/tokens.stylex.ts` — StyleX design tokens (vars), `theme.ts`
- `src/shared/config/breakpoints.ts` + `constants.ts`
- `src/shared/i18n/t.ts` (`createT`), `dict.ts` (`astroDictRu`/`astroDictEn`), `ru/<ns>.ts` + `en/<ns>.ts`
- `src/shared/hooks/useT.ts` + `useMatchMedia.ts`
- `src/shared/data/entities.ts` — fixture getters
- `src/pages/index.astro` — root page
- `vitest.config.ts` — Stylex plugin + jsdom via `test/environment.ts`; `test/setup.ts`
- `biome.json` (space indent = 2, CRLF, double quotes)
- `.storybook/main.ts` (stories glob `../stories/**/*.stories.@(ts|tsx)`), `.storybook/preview.ts`
- `.gitignore`, `AGENTS.md`

### 4. Install dependencies
Run `npm install`. Retry on network errors.

### 5. Link to Vercel
- Requires `VERCEL_TOKEN` in env.
- `npx --yes vercel@latest link --yes --token "$VERCEL_TOKEN"`
- If `VERCEL_ORG_ID` set → append `--scope "$VERCEL_ORG_ID"`
- On failure → return error

### 6. Deploy to Vercel
- `npx --yes vercel@latest build --yes --token "$VERCEL_TOKEN"` — runs the Astro build via the Vercel preset
- `npx --yes vercel@latest deploy --prebuilt --yes --token "$VERCEL_TOKEN"`
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