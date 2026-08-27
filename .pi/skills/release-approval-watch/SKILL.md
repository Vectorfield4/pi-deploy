---
name: release-approval-watch
description: "Orchestrator-side zero-token HITL handshake for releases: runs /pr watch on the main session for the dev→main release PR, then delegates Phase B (merge + release) to QA on approval."
---

# Release Approval Watch

Zero-token human-in-the-loop for releases. This runs on the **main orchestrator session only** — a detached subagent cannot execute extension commands like `/pr watch`, so the orchestrator owns the watch and re-delegates after approval.

## Flow

### 1. Confirm the release request
On `release` intent, confirm with the user before doing anything, then delegate Phase A to QA:
```
subagent({ agent: "qa", task: <release task>, skill: "execute-qa-task" })
```
QA runs `release-to-main` Phase A and returns the release PR URL.

### 2. Start the watch (zero-token HITL)
After QA returns the release PR URL, start `@vectorfield/pi-prs` watching it from the main session:
```
/pr watch <release-pr-url>
```
- `/pr watch` polls GitHub every 30 seconds in the background and does **not** block the session, so parallel Telegram messages keep working.
- Report to the user: "Release PR is open and awaiting your approval: <url>".
- If a fresh `/pr watch` is not available, use the explicit-number form `/pr watch #<number>` (resolves against the repo at the session cwd) or the full URL (works from any directory).

### 3. Finish your turn and go idle
Watch is a background activity. End the orchestrator turn. The session stays responsive to Telegram while `/pr watch` runs.

### 4. Respond to the wake
When pi-prs detects new external feedback (approval, comment, or requested changes), it wakes the main session with a steer message. Classify the feedback:
- **Approved** (`state == APPROVED`) or a comment explicitly saying `approved` / `LGTM` / `merge` → delegate **Phase B** to QA:
  ```
  subagent({ agent: "qa", task: <release merge + build + release>, skill: "execute-qa-task" })
  ```
  QA merges, builds, and creates the GitHub Release, then runs `memory-gc`.
- **Requested changes / rejection** or a substantive comment → do NOT merge. Report the feedback to the user. Do not re-run the watch; tell the user what the reviewer asked for.
- If the PR was merged/closed by someone else → stop watching and close out.

### 5. Cleanup
- `/pr unwatch` once the PR is merged/closed or the release is abandoned.

## Notes

- The watch target is repo-qualified via the URL, so it works even though the main session's cwd is the `/workspace` project root (a stock pi-prs `/pr watch` only follows the current branch's PR — `@vectorfield/pi-prs` adds explicit URL/number targeting).
- Do not delegate the watch to a subagent. Only the main session can run `/pr watch`.
- QA must be re-invoked for Phase B; QA never polls for approval itself.

## Verification

- Release request was confirmed before any action.
- QA Phase A returned the PR URL.
- Orchestrator ran `/pr watch <url>` on the main session and reported to the user.
- On approval wake, QA Phase B was delegated; on changes, feedback was reported without merging.
- Watch was stopped after merge/close.
