---
name: execute-review
description: "Runs the full branch-review pipeline inside the reviewer agent: load context, validate, score the diff against main, decide, write memory, return a structured result."
---

# Execute Review

The full review pipeline for a single feature branch. Loaded by the `reviewer`
agent when a review task arrives — which happens only for tasks where the
orchestrator invoked the Pro model (`task.metadata.pro_invoked: true`). Simple
Flash tasks skip this skill (`execute-qa-task` returns `decision: skip_review`
instead). The agent's job is to make the merge/bounce/explore decision and write
the result. The review reads the **branch diff against `main`** — there is no
PR.

The task arrives as a **JSON string** — parse it as `task` and read fields via
`task.project`, `task.branch`, `task.metadata.*`, etc.

## Input

- `task.project`: project name (workspace dir under `/workspace/<project>`)
- `task.branch`: feature branch name
- `task.metadata.acceptance_criteria`: list of strings, may be empty
- `task.metadata.review_iterations`: int, starts at 0, incremented on each bounce
- `task.metadata.exploration_triggered`: bool, default false

## Tunables

- `CI_POLL_INTERVAL_S` (default 30): seconds between CI status checks.
- `CI_TIMEOUT_S` (default 600): max seconds to wait for CI.
- `SCORE_PASS` (default 7): threshold to approve the push.
- `SCORE_NEEDS_FIXES` (default 5): below this, bounce with anti-pattern.

## Steps

### 1. Load context
Recall project rules from dense-mem. The query format embeds the project and key:
`mcp__dense-mem__recall_memory(query="project-rules project:<project> key:<rules_key>")`. If the top result's first line `rules_hash:` (read from the result's `context` — results are `{ evidence_id, context, space_kind }`) doesn't match `task.metadata.rules_hash` or recall returns nothing, read `/workspace/<project>/AGENTS.md` and `/workspace/<project>/SOUL.md` directly. Graceful degradation: never block on memory.

Recall past anti-patterns:
`mcp__dense-mem__recall_memory(query="<feature summary> project:<project> anti-pattern")`. If recalled, these are known failures — use a different approach.

If `exploration_triggered == true` in `task.metadata`, also recall exploration anti-patterns:
`mcp__dense-mem__recall_memory(query="<feature summary> project:<project> anti-pattern exploration")` and avoid repeating the same approach.

### 2. Wait for CI
- `gh run list --branch <branch> --limit 3 --json status` (the branch is pushed; CI may run on it).
- If a run is in progress → wait and retry every `${CI_POLL_INTERVAL_S}s` (max `${CI_TIMEOUT_S}s`).
- If a run failed → `decision: bounce`, findings = CI error log tail.
- If no runs exist (no CI on the repo) → skip to step 3; local validation is the gate.

### 3. Pre-push validation
If `task.metadata.acceptance_criteria` contains any of: `lint`, `test`, `build`, `typecheck`:
- Read validation commands from `/workspace/<project>/AGENTS.md` (look for `## Commands` or similar)
- Run each in a worktree checked out on the branch
- If any fails → `decision: bounce`, findings = the failing command and its output

Skip this step if no validation commands are mentioned. The skill must not invent commands that aren't in `AGENTS.md`.

### 4. Score the diff
Use the `pr-judge` skill to score:
- Get the file list first: `git diff --name-only origin/main...origin/<branch>`
- Read each changed file. Skip unchanged parts.
- Compute score per `pr-judge` rubric.

If total added/removed lines exceed 3000, do not run the full diff inline; score from per-file reads.

### 5. Decide
- `score >= SCORE_PASS` → `decision: merge`
- `SCORE_NEEDS_FIXES <= score < SCORE_PASS` → `decision: bounce`, no memory write
- `score < SCORE_NEEDS_FIXES` → `decision: bounce`, store anti-pattern
- `task.metadata.review_iterations >= 3` and the same kind of issue keeps appearing → `decision: explore` (see step 7)

### 6. Merge decision (do NOT push)
The reviewer does not push and does not deploy. `decision: merge` means
"ready to push": QA fast-forwards the branch into `main`. No `git push origin
main`, no `gh pr merge`, no `deploy-vercel` here.

### 7. Exploration escalation (only on `decision: explore`)
Write an anti-pattern (best-effort):
```
mcp__dense-mem__remember({
  evidence: [{
    content: "project: <project>\ntype: exploration\ntags: anti-pattern,exploration,project:<project>\nconfidence: high\nvalid_until: <YYYY-MM-DD, today + 30 days>\n\nTask '<title>' failed <N> iterations. Recurring: <pattern>. Orchestrator must re-decompose.",
    source_type: "observation"
  }],
  relationships: [{
    ref: "exploration:<project>:<task_id>",
    subject: { name: "<project>", entity_kind: "project" },
    predicate: { proposed_key: "project:exploration:anti-pattern" },
    object: { entity: { name: "task:<task_id>", entity_kind: "concept" } },
    polarity: "-",
    evidence_indices: [0]
  }],
  idempotency_key: "exploration:<project>:<task_id>"
})
```
Set `exploration_flag: true` in the result. Do not bounce to coder, do not approve.

### 8. Memory write (best-effort, at most once per task)
- `score >= SCORE_PASS` and quality is genuine → write verified pattern:
  ```
  mcp__dense-mem__remember({
    evidence: [{
      content: "project: <project>\ntype: verified\ntags: verified,project:<project>\nconfidence: high\nvalid_until: <YYYY-MM-DD, today + 90 days>\n\n<short verdict, under 200 chars>",
      source_type: "observation"
    }],
    relationships: [{
      ref: "review-verified:<project>:<task_id>",
      subject: { name: "<project>", entity_kind: "project" },
      predicate: { proposed_key: "project:review:verified" },
      object: { entity: { name: "task:<task_id>", entity_kind: "concept" } },
      polarity: "+",
      evidence_indices: [0]
    }],
    idempotency_key: "review-verified:<project>:<task_id>"
  })
  ```
- `score < SCORE_NEEDS_FIXES` → already written in step 5; do not write again
- Otherwise → no memory write

Cap `content` at one sentence (~200 chars). Never store full source dumps.

### 9. Return structured result

```
[REVIEW_RESULT]
decision: merge | bounce | explore
score: <1-10>
breakdown: quality=<n> tests=<n> security=<n> docs=<n>
findings: <one-line per issue, or "none">
memory_written: <true|false>
exploration_flag: <true|false>
summary: <one sentence>
```

For `decision: merge`, no URL is needed — QA pushes the branch to `main`. The
orchestrator reads this output and routes accordingly. Do not call the
orchestrator from inside this skill.

## Verification

- Result has exactly one `decision` value.
- `score` is 1-10 integer.
- `findings` is non-empty for `bounce` and `explore`, empty/`none` for `merge`.
- Memory write attempted at most once.
- If `explore`: `exploration_flag: true`, no bounce, no approve.
- If `merge`: NO `git push origin main` / `gh pr merge` ran — the push is
  delegated to QA.