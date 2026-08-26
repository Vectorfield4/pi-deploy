---
name: prioritize-tasks
description: "Scores ready tasks by composite weight (type value + aging + iterations + dependency unblocking). Deterministic — no LLM needed."
---

# Prioritize Tasks

Score every task so the highest-value work surfaces first. Deterministic arithmetic — no LLM call.

## Formula

```
score = type_weight + aging + iteration_boost + unblock_bonus
```

| Signal | Calculation | Range |
|--------|-------------|-------|
| **type_weight** | lookup table | 1–4 |
| **aging** | `min(age_minutes / 30, 5)` | 0–5 |
| **iteration_boost** | `review_iterations × 2` | 0–∞ |
| **unblock_bonus** | `3` if blocked tasks depend on this, else `0` | 0 or 3 |

### Type weights

| Type | Weight |
|------|--------|
| bugfix, release | 4 |
| deploy, review | 3 |
| feature, ui, integration, refactoring | 2 |
| content, init | 1 |

## How to apply

1. List all tasks in the queue.
2. For each task compute `score` using the formula.
3. Pick the task with the highest score.
4. When QA bounces a task, increment `review_iterations` by 1 and add `+1` to `priority_score`.

## Notes

- Per-signal weights are capped (max ~5) to prevent any single signal from dominating.
- Aging provides anti-starvation: old tasks rise naturally.
