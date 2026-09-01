---
name: memory-gc
description: "Retires memory evidence whose valid_until has passed. Called by the QA agent after each successful review/release/deploy iteration."
---

# Memory GC

Decay mechanism for pi-pgvector-api-embeddings. Every `remember` call writes a
`valid_until` date. `pgvec_gc` retires expired records server-side against the
`valid_until` column — no content parsing, no per-record candidate recall.

## TTL policy (written by caller)

| Record type | TTL | Notes |
|-------------|-----|-------|
| project meta | never | config and metadata |
| task outcomes | 90 days | task outcomes, decisions, patterns |
| design decisions | 90 days | frontend architecture decisions |
| review verified | 90 days | verified review verdicts |
| review bounce | 7 days | bounce findings; superseded by the fix or exploration |
| user feedback | 60 days | user feedback |
| exploration anti-pattern | 30 days | anti-patterns; decay fast as practices evolve |

Callers write the `valid_until` per the policy. This skill never invents TTLs;
it only enforces what callers wrote.

## Algorithm

1. **Delegate to the backend.**
   ```
   pgvec_gc({})
   ```
   The backend scans active records, compares each `valid_until` to today
   (UTC), and retracts anything expired, capped at 20 per call.

2. **Graceful degradation.** If `pgvec_gc` fails or errors, do nothing. Memory
   grows slightly but the system stays up. Never block the calling QA flow.

3. **Return summary.**
   ```
   [MEMORY_GC]
   scanned: <int>
   expired: <int>
   retracted: <int>
   errors: <int>
   ```

## Caller contract

This skill is called by the QA agent after every successful review/release/deploy. The caller does not check the return value. If GC fails, the next call retries.

Cost: 1 `pgvec_gc` call per iteration — no per-record embedding or recall work. On a healthy system, expired records are rare, so most calls do 0 work.

## Verification

- `retracted + errors == expired`.
- Skill does not run for `release` or `deploy` tasks that have no memory writes; QA decides when to invoke.
