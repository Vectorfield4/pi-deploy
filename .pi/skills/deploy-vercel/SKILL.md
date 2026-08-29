---
name: deploy-vercel
description: "Builds the main branch and deploys to Vercel staging (preview)."
---

# Deploy to Vercel (Staging)

Builds the project at `main` and uploads to Vercel as staging/preview deployment.

## Prerequisites
- Project linked to Vercel (`.vercel/project.json` committed)
- `VERCEL_TOKEN` in environment

## Instructions

### 1. Sync main
- `git checkout main && git pull origin main`

### 2. Resolve Vercel link
- Read `/workspace/<project>/.vercel/project.json`
- If missing → error: "Vercel not linked for project <project>"

### 3. Pull Vercel project settings
- `npx --yes vercel@latest pull --yes --environment=preview --token "$VERCEL_TOKEN"`

### 4. Build locally
- `npx --yes vercel@latest build --token "$VERCEL_TOKEN"`
- On failure → return error

### 5. Deploy (staging)
- `npx --yes vercel@latest deploy --prebuilt --token "$VERCEL_TOKEN"`
- Retry on transient errors (timeout, 5xx)

### 6. Return staging URL

## Verification
- Main is up to date
- Vercel link resolved
- Local build succeeds
- Deployment URL returned and reachable
