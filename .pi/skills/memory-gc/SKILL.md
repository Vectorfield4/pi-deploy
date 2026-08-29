---
name: memory-gc
description: "Retires dense-mem evidence whose valid_until has passed. Called by the QA agent after each successful review/release/deploy iteration."
---

# Memory GC

Decay mechanism for dense-mem. Every `remember` call writes `valid_until: YYYY-MM-DD` in the content. This skill walks active evidence, parses the date, and retires anything expired via `retract_evidence`.

## TTL policy (defined by caller)

| Idempotency key prefix | TTL | Notes |
|------------------------|-----|-------|
| `rules:*`, `rules-index:*`, `project-meta:*` | never | config and metadata |
| `task:*` | 90 days | task outcomes, decisions, patterns |
| `design:*` | 90 days | frontend architecture decisions (predicate `project:design:decision`) |
| `review-verified:*` | 90 days | verified review verdicts |
| `feedback:*` | 60 days | user feedback |
| `exploration:*` | 30 days | anti-patterns; decay fast as practices evolve |

Callers write the `valid_until` line as part of `evidence.content`. This skill never invents TTLs; it only enforces what callers wrote.

## Algorithm

1. **Recall candidate evidence.**
   ```
   mcp__dense-mem__recall_memory(query="memory evidence with valid_until date")
   ```
   The query is broad so it returns a mix of recent and old records. We do not aim for completeness on a single pass; the skill runs on every QA iteration, so over time most expired evidence is found.

2. **Parse `valid_until` from each result's `context`.**
   - Each recall result is `{ evidence_id, context, space_kind }`. Find a line starting with `valid_until:` anywhere in `context` → ISO date.
   - Missing or unparseable → skip the record. (It was written before TTL was enforced, or it is config which never expires.)
   - Compare to today's date (UTC). If `valid_until < today` → expired, queue for retraction.

3. **Retract in batch.**
   For each expired evidence item, take `evidence_id` directly from the recall result, then:
   ```
   mcp__dense-mem__retract_evidence({
     evidence_ids: ["<evidence_id>"],
     reason: "TTL expired (<original valid_until>)",
     idempotency_key: "memory-gc:retract:<evidence_id>:<YYYY-MM-DD>"
   })
   ```
   If `recall_memory` cannot supply the id (degraded result), fall back to `trace_memory` to look it up.

4. **Cap per-call work.** Process at most 20 records per call. More than that → return early and run again next iteration. This keeps the call cheap.

5. **Graceful degradation.** If `recall_memory` fails or returns empty, do nothing. Memory grows slightly but the system stays up. If `retract_evidence` fails for one id, skip it and continue with the rest. Never block the calling QA flow.

6. **Return summary.**
   ```
   [MEMORY_GC]
   scanned: <int>
   expired: <int>
   retracted: <int>
   errors: <int>
   ```

## Caller contract

This skill is called by the QA agent after every successful review/release/deploy. The caller does not check the return value. If GC fails, the next call retries.

Cost: 1 recall (~one embedding call) + 0-20 retract writes per call. On a healthy system, expired records are rare, so most calls do 0 work. On a system that has been running for months, GC may do meaningful work for a few iterations then settle.

## Verification

- `scanned >= expired >= retracted`.
- `retracted + errors == expired`.
- No idempotency_key collision with other skills.
- Skill does not run for `release` or `deploy` tasks that have no memory writes; QA decides when to invoke.
