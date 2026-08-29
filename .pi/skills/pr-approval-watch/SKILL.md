---
name: pr-approval-watch
description: "Orchestrator-side zero-token HITL for any PR targeting main: after reviewers pass a PR, hand the URL to the router (WATCH marker), classify the wake feedback, and delegate the merge or relay the feedback."
---

# PR Approval Watch

Zero-token human-in-the-loop for every PR that targets `main`. The watch itself
runs on the **main routing session** via the `pr_watch` tool of
`@vectorfield/pi-prs` (0.1.1+) — a subagent cannot run slash commands or hold
the poller. The orchestrator owns the handshake: pass the PR to the router,
then classify the wake and re-delegate.

## When to use

- **Every PR targeting `main`** gets the human approval gate via the zero-token
  watch — simple and complex alike. What differs is whether a reviewer ran first:
  - **Complex tasks** (`metadata.pro_invoked: true`): the reviewer returned
    `[REVIEW_RESULT] decision: merge` → gate the merge on human approval.
  - **Simple tasks** (`pro_invoked` false): no reviewer — QA returned
    `decision: skip_review`; the worker PR goes straight to this gate.
- Unless flagged `skip_human` in the task (documented shortcut), always watch.

## Flow

### 1. The PR is ready for human judgment
- Complex: reviewers returned `decision: merge` (they did NOT merge — merging
  waits for human approval here).
- Simple: the worker opened the PR (`base: main`); there is no reviewer result.

### 2. Hand the PR to the router (watch handoff)
End your turn by emitting the exact marker alone on a line:
```
WATCH <pr-url>
```
Example: `WATCH https://github.com/acme/web/pull/123`.

The main routing session is instructed (AGENTS.md, "PR watch markers") to
translate every `WATCH <url>` line in your final message into
`pr_watch({ action: "watch", url })`. Report the PR link to the user in the
same reply.

### 3. Finish the turn and go idle
`pr_watch` polls GitHub every 30s in the background. Parallel Telegram
messages keep working. Model tokens are spent only when the watch wakes the
session with new feedback.

### 4. Respond to the wake
New external feedback (approval, comment, requested changes) steers this
session. The steering text is compact: `owner/repo#n · <count> findings · @author`
plus the feedback bodies. Classify:

- **Approved** — a review with `APPROVED`, or the reviewer writes `approved` /
  `LGTM` / `merge` / `✔` → delegate the merge:
  ```
  subagent({ agent: "qa", task: { type: "merge", project, pr_number, branch }, skill: "execute-qa-task" })
  ```
  QA verifies an `APPROVED` review exists, squashes into `main`, cleans up the
  branch, triggers Vercel staging, and runs `memory-gc`. Do NOT re-watch after
  the merge.
- **Requested changes / rejection / substantive comment** → do NOT merge.
  Relay the feedback to the user. If the user asks for a fix, return to the
  worker on the same branch/PR. Surface it — do not keep waiting silently.
- **PR merged/closed by someone else** → close out, no further action.
- **Unclearly classified by the model** → ask the user rather than guessing.

### 5. Cleanup
- The watch auto-stops when the PR merges or closes (pi-pr lifecycle check).
- If the PR is abandoned while still open: end your turn with `UNWATCH` and the
  router calls `pr_watch({ action: "unwatch" })`.

## Notes

- Only the main session can hold a watch. If `pr_watch` fails to start (wrong
  URL, auth), the router reports it; tell the user the PR is open but
  unmonitored and share the link.
- What counts as "external": pi-pr filters out feedback authored by the session's
  own GitHub login, so the agent's own actions never self-trigger a wake.

## Verification

- PR existed and was in a watchable state before the handoff: complex → reviewers
  passed it (`decision: merge`); simple → worker PR open (`decision: skip_review`).
- Final orchestrator message contained the `WATCH <url>` marker.
- On approval wake: QA merge was delegated; on changes: feedback relayed, no merge.
- Watch stopped (auto on merge/close, or explicit `UNWATCH` when abandoned).