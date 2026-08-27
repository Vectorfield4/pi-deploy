---
name: release-to-main
description: "Two-phase release: Phase A opens a PR from dev to main and returns its URL (no blocking); Phase B merges after approval, builds, and creates a GitHub Release."
---

# Release to Main

Two-phase release to `main`. **Phase A** opens the `dev → main` PR and returns its URL — it does NOT block. Human approval is a zero-token wake handled by the **main orchestrator session** via `@vectorfield/pi-prs` (`/pr watch <url>`). After the watch wakes the orchestrator on approval, QA is re-invoked to run **Phase B**: merge, build, and create the GitHub Release.

**Important: Idempotent** — check for existing PR before creating a new one.

## Phase A — Open the release PR (no blocking)

### A1. Check for existing PR (idempotency guard)
- `gh pr list --head dev --base main --json number,state,url,mergeable`
- If an OPEN PR already exists → do not create a new one. Return its URL and stop.
- If no PR exists → fresh run → continue.

### A2. Create PR
- `gh pr create --base main --head dev --title "Release: <project>" --body "Release PR. Merge after human approval."`

### A3. Return the PR URL and stop
- Output/report the PR URL (e.g. `https://github.com/OWNER/REPO/pull/123`) clearly.
- **Stop here.** Do NOT poll, do NOT wait, do NOT merge. The orchestrator will run `/pr watch <url>` on the main session and re-invoke this skill for Phase B once the human approves.

## Phase B — Merge + Build + Release (after approval)

Run only when re-invoked after the human approved the PR (the orchestrator delegated Phase B after its `/pr watch` woke it).

### B1. Verify the PR was approved
- `gh pr view <number> --json reviews,state --jq '{state, approved: [.reviews[] | select(.state=="APPROVED")]}'`
- If there is no `APPROVED` review → do not merge. Report that approval is still pending and stop.
- If the PR was changed/requested → do NOT merge; report the requested changes for the user. **(Approval/feedback classification is done by the orchestrator watch; QA only acts on an approved PR.)**

### B2. Merge
- Verify the PR is mergeable.
- If mergeable → `gh pr merge <number> --squash`.
- If conflict → delegate to `resolve-merge-conflict` subagent, then re-attempt merge.

### B3. Build and create GitHub Release
- Checkout main, pull.
- Run build commands.
- Create zip archive.
- Determine version tag.
- `gh release create <tag> /tmp/<project>-<version>.zip`.

### B4. Complete
- Report release summary.
- Best-effort: store verified experience in dense-mem.

## Verification

- Phase A: PR exists (created or resumed), URL returned, QA did not block.
- Phase A is invoked for the watch handshake and re-invoked for Phase B.
- Phase B: approval confirmed, PR merged, build succeeds, GitHub Release created with zip artifact.