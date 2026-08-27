---
name: docs-lookup
description: "Resolves and fetches library documentation via Context7 with a dense-mem cache layer. Returns docs text for the current task and caches the result for 7 days."
---

# Docs Lookup

Single entry point for library documentation. Wraps `resolve-library-id` and `query-docs` from Context7 with a dense-mem cache. Use instead of calling Context7 directly.

## When to use

- Coder, frontender, reviewer agents need library/API documentation.
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
   mcp__dense-mem__recall_memory(query="context7 <libraryName> <topic>")
   ```
   - If the top result's content starts with `lib: <libraryName>` and its first line `cache_key:` matches the current `key` → use the cached content. Skip step 3.
   - Parse `valid_until:` from the first line. If it is in the past, the cache miss is expected. Proceed to step 3.

3. **Resolve and fetch from Context7 (cache miss or expired).**
   ```
   resolve-library-id(libraryName="<libraryName>")
   query-docs(libraryId="<resolved-id>", query="<topic>")
   ```

4. **Cache the result.**
   ```
   mcp__dense-mem__remember({
     evidence: [{
       content: "lib: <libraryName>\ncache_key: <key>\nlibrary_id: <resolved-id>\nversion: <version>\ntopic: <topic>\nvalid_until: <YYYY-MM-DD, today + 7 days>\n\n<docs text, summarized to essential parts>",
       source_type: "tool_output"
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
- Graceful degradation: if Context7 fails, fall back to training knowledge. Cache the failure as empty content with a short TTL (1 day) to avoid hammering a broken API.

## Verification

- Each call returns either cached or fresh docs.
- If fresh, the cache has a new entry with `idempotency_key: context7:<hash>`.
- If cached, no new `mcp__dense-mem__remember` call was made.
