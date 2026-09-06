# Memory GC

Decay for pi-pgvector-api-embeddings. Every `remember` call writes `valid_until`; `pgvec_gc` retires expired records server-side against the `valid_until` column — no content parsing, no per-record candidate recall.

## TTL policy (written by caller)

| Record type | TTL | Notes |
|-------------|-----|-------|
| project meta | never | config and metadata |
| task outcomes | 90 days | decisions, patterns |
| design decisions | 90 days | frontend architecture decisions |
| review verified | 90 days | verified review verdicts |
| review bounce | 7 days | superseded by the fix or exploration |
| user feedback | 60 days | user feedback |
| exploration anti-pattern | 30 days | decay fast as practices evolve |

Callers write `valid_until` per the policy. This skill never invents TTLs; it enforces what callers wrote.

## Algorithm

1. **Delegate to the backend.**
   ```
   pgvec_gc({})
   ```
   Backend compares each `valid_until` to today (UTC), retracts expired records, capped at 20 per call.

2. **Graceful degradation.** On `pgvec_gc` failure or error, do nothing. Memory grows slightly; system stays up. Never block the calling QA flow.

3. **Return summary.**
   ```
   [MEMORY_GC]
   scanned: <int>
   expired: <int>
   retracted: <int>
   errors: <int>
   ```

## Caller contract

Called by QA after every successful review/release/deploy. Caller does not check the return value; the next call retries.

Cost: 1 `pgvec_gc` call per iteration — no per-record embedding or recall work. On a healthy system, expired records are rare; most calls do 0 work.

## Verification

- `retracted + errors == expired`.
- `release` / `deploy` tasks with no memory writes skip GC. QA decides when to invoke.