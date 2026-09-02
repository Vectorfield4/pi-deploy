# Persist Design Decisions (orchestrator, step 7.1)

After `frontend-architect` produces `artifacts/design-spec.md`, record the
decision once so the design-reuse step (step 5.2) skips the architect on the
next similar task:

```
pgvec_remember({
  content: "project: <project>\ndesign: <feature-title>\ntags: design-decision,project:<project>,<relevant-concepts>\nvalid_until: <YYYY-MM-DD, today + 90 days>\n\n<decision summary: architecture chosen, alternatives rejected, spec path — under 300 chars>",
  tags: ["design-decision", "project:<project>", "<relevant-concepts>"],
  source_type: "observation",
  valid_until: "<YYYY-MM-DD, today + 90 days>",
  idempotency_key: "design:<project>:<feature>:<hash>"
})
```

If step 5.2 recalls an older design record for the same feature area, list
it in `supersedes_evidence_ids` *if the remember call provides that flag* —
otherwise let the idempotency key overwrite. On any MCP failure → log and
continue; the spec on disk is the source of truth.
