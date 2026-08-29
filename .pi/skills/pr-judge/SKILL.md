---
name: pr-judge
description: "Evaluates a feature branch diff against main using a quality rubric (code quality, tests, security, docs) and returns a score 1-10."
---

# Branch Judge

Automated quality evaluation of a feature branch's diff against `main` using a
fixed rubric. Operates on local git state — there is no PR.

Run from `/workspace/<project>` after `git fetch origin main <branch>`.

## Rubric (score 1–10)

| Dimension | Weight | What to check |
|-----------|--------|---------------|
| Code quality | 25% | Readability, naming, DRY, separation of concerns |
| Tests | 25% | Coverage of new logic, edge cases, meaningful assertions |
| Security | 25% | No hardcoded secrets, input validation, auth checks |
| Docs | 25% | AGENTS.md adherence, JSDoc where needed |

## Instructions

### 1. List changed files
```bash
git diff --name-only origin/main...origin/<branch>
```
Use the file list to decide which files to read in full. If the diff is over
3000 lines, read only the changed files, not the raw diff.

### 2. Get the diff for review
```bash
git diff origin/main...origin/<branch>
```

### 3. Evaluate each dimension (1–10)
- 1–3: Significant issues, would block deployment
- 4–5: Needs improvement
- 6–7: Acceptable
- 8–10: Excellent

### 4. Compute overall score
```
overall = round(code_quality * 0.25 + tests * 0.25 + security * 0.25 + docs * 0.25)
```

### 5. Return structured result
```
[JUDGE_SCORE=N] summary | quality=N tests=N security=N docs=N
```

## Score Thresholds
| Score | Action |
|-------|--------|
| ≥ 7 | Verified — save as high-confidence template |
| 5–6 | Neutral — no memory action |
| ≤ 4 | Anti-pattern — save as anti-pattern |

## Content Quality Overlay (for any markdown write)
If any file changed by the branch is markdown (`*.md`), scan for banned
words/phrases from `prose-quality.md`. ≥3 flags → docs dimension ≤ 4.