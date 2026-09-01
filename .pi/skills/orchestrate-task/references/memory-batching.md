# Batched Memory Context (orchestrator, step 4.5)

After decomposition but before delegation, do **one** batched recall that covers
the whole task. Each sub-task will get the result via
`metadata.memory_context` instead of doing its own recall.

```
combined_query = "<main goal> <project>"
memory_results = pgvec_recall_memory({ query:combined_query, limit:10 })
```

Also recall anti-patterns:

```
anti_patterns = pgvec_recall_memory({ query:"<main goal> <project>", tag:"anti-pattern", limit:5 })
```

Then for each sub-task in step 7, include in the delegated task JSON (the
`metadata` object inside the `task` string):

- `metadata.memory_context`: top-5 memory results as a single string,
  summarized from each result's `context` field (recall results are
  `{ evidence_id, context, space_kind }`; newest first, note the relevance).
- `metadata.anti_patterns`: top-3 anti-patterns (use as warnings, do not act
  on directly).

Graceful degradation: if recall returns nothing, pass
`metadata.memory_context: ""` and let the sub-task proceed. The sub-task's
`component.md` step 3 will skip recall when `metadata.memory_context` is
present (even if empty).

This saves N-1 embedding calls per N-sub-task task. For a 3-component
backend feature, we drop from 3 recalls to 1.
