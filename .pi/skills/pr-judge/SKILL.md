---
name: pr-judge
description: "Evaluates a PR against a quality rubric (code quality, tests, security, docs) and returns a score 1-10."
---

# PR Judge

Automated quality evaluation of a PR diff against a fixed rubric.

## Rubric (score 1–10)

| Dimension | Weight | What to check |
|-----------|--------|---------------|
| Code quality | 25% | Readability, naming, DRY, separation of concerns |
| Tests | 25% | Coverage of new logic, edge cases, meaningful assertions |
| Security | 25% | No hardcoded secrets, input validation, auth checks |
| Docs | 25% | AGENTS.md adherence, JSDoc where needed |

## Instructions

### 1. Get the diff
```bash
gh pr diff <pr_number> --repo <repo>
```
If >3000 lines, focus on changed files only.

### 2. Evaluate each dimension (1–10)
- 1–3: Significant issues, would block deployment
- 4–5: Needs improvement
- 6–7: Acceptable
- 8–10: Excellent

### 3. Compute overall score
```
overall = round(code_quality * 0.25 + tests * 0.25 + security * 0.25 + docs * 0.25)
```

### 4. Return structured result
```
[JUDGE_SCORE=N] summary | quality=N tests=N security=N docs=N
```

## Score Thresholds
| Score | Action |
|-------|--------|
| ≥ 7 | Verified — save as high-confidence template |
| 5–6 | Neutral — no memory action |
| ≤ 4 | Anti-pattern — save as anti-pattern |

## Content Quality Overlay (for `artifacts/*.md`)
If PR touches markdown in `artifacts/`, scan for banned words/phrases from `prose-quality.md`. ≥3 flags → docs dimension ≤ 4.
