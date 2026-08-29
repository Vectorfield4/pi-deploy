---
name: docs-lookup
description: "Resolves and fetches library documentation via Context7 with a dense-mem cache layer. Returns docs text for the current task and caches the result for 7 days."
---

# Docs Lookup

Single entry point for library documentation. Wraps `resolve-library-id` and `query-docs` from Context7 with a dense-mem cache. Use instead of calling Context7 directly.

## When to use

- Coder, frontend-implementer, reviewer agents need library/API documentation.
- The library is real and current docs matter (React, MUI, TanStack Query, Zustand, three.js, etc.).
- Not for general knowledge — only for library-specific lookup.

## Procedure

1. **Compose the cache key.**
   ```
   key = "<libraryName>:<topic>:<version-or-latest>"
   idempotency_key = "context7:<sha256(key)>"
   ```

2. **Recall the cache.**
   ```
   mcp__dense_mem__recall_memory(query="context7 <libraryName> <topic>")
   ```
   - If the top result's `context` (results are `{ evidence_id, context, space_kind }`) starts with `lib: <libraryName>` and its first line `cache_key:` matches the current `key` → use the cached content. Skip step 3.
   - Parse `valid_until:` from the context. If it is in the past, the cache miss is expected. Proceed to step 3.

3. **Resolve and fetch from Context7 (cache miss or expired).**
   ```
   resolve-library-id(libraryName="<libraryName>")
   query-docs(libraryId="<resolved-id>", query="<topic>")
   ```

4. **Cache the result.** (the `relationship` is required by the v2.6 `remember` contract and makes the cache entry recallable)
   ```
   mcp__dense_mem__remember({
     evidence: [{
       content: "lib: <libraryName>\ncache_key: <key>\nlibrary_id: <resolved-id>\nversion: <version>\ntopic: <topic>\nvalid_until: <YYYY-MM-DD, today + 7 days>\n\n<docs text, summarized to essential parts>",
       source_type: "document"
     }],
     relationships: [{
       ref: "docs:<libraryName>:<topic>:<version>",
       subject: { name: "<libraryName>", entity_kind: "document" },
       predicate: { proposed_key: "library:docs:cache" },
       object: { entity: { name: "<topic>", entity_kind: "concept" } },
       polarity: "+",
       evidence_indices: [0]
     }],
     idempotency_key: "context7:<sha256(key)>"
   })
   ```

5. **Return the docs text** to the caller.

## Rules

- TTL is 7 days. Library docs don't change often, and when they do the cache miss rate rises naturally.
- Cap `content` at ~2000 chars (Context7 returns are often larger). Summarize to what's needed for the task.
- Cache miss rate is your signal: if you keep hitting the cache (key matches and valid), the TTL is fine. If you keep missing, the task is using an unusual library.
- One call per (library, topic) pair. Don't call twice for the same pair in the same task.
- Graceful degradation: if Context7 fails, fall back to training knowledge. Cache the failure as empty content with a short TTL (1 day) to avoid hammering a broken API — same `remember` shape, `source_type: "document"` plus the `relationships` block.

## Verification

- Each call returns either cached or fresh docs.
- If fresh, the cache has a new entry with `idempotency_key: context7:<hash>`.
- If cached, no new `mcp__dense_mem__remember` call was made.
