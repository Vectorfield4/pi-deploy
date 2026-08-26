---
name: execute-qa-task
description: "Executes a single QA task — dispatches to review-and-merge, release-to-main, or deploy-ftp based on task type."
---

# Execute QA Task

## Steps

### 1. Fetch the task
- Extract `title`, `description`, `metadata`.

### 2. Dispatch by task type
- **`type == "release"`** → delegate to `release-to-main` subagent
- **`type == "deploy"`** → delegate to `deploy-ftp` subagent
- **Otherwise** → continue with review

### 3. Load project rules
- Recall rules from dense-mem by key, verify `rules_hash` matches.
- Fallback: read from `/workspace/<project>/AGENTS.md`.

### 4. Pre-merge acceptance criteria check
- If `acceptance_criteria` mentions lint/test/build → run validation
- If fails → bounce to coder without merging

### 5. Run the review pipeline
- Delegate to `review-and-merge` subagent.
- On success → delegate to `pr-judge` subagent for scoring.

### 6. Handle result

**SUCCESS:**
- Complete with score summary
- Memory decision (best-effort):
  - Score ≥ 7 → store as verified pattern
  - Score ≤ 4 → retract positive evidence, store anti-pattern

**NEEDS_FIXES:**
- Increment `review_iterations`
- If `review_iterations >= 3` → trigger exploration (re-decompose)
- Otherwise → bounce to coder with findings

**FAILURE:**
- Block with error details

## Verification
- Task status is done, blocked, or ready (bounced)
- No task remains in intermediate state
- Memory store fired at most once per task
