# Persist Design Decisions (orchestrator, step 7.1)

After `frontend-architect` produces `artifacts/design-spec.md`, record the
decision once so the complex gate (step 5.2) reuses it instead of re-running
the architect:

```
dense_mem_remember({
  evidence: [{
    content: "project: <project>\ndesign: <feature-title>\ntags: design-decision,project:<project>,<relevant-concepts>\nvalid_until: <YYYY-MM-DD, today + 90 days>\n\n<decision summary: architecture chosen, alternatives rejected, spec path — under 300 chars>",
    source_type: "observation",
    supersedes_evidence_ids: ["<old-design-record-for-this-feature-area-if-any>"]
  }],
  relationships: [{
    ref: "design:<project>:<feature>:<hash>",
    subject: { name: "<project>", entity_kind: "project" },
    predicate: { proposed_key: "project:design:decision" },
    object: { entity: { name: "<feature>", entity_kind: "concept" } },
    polarity: "+",
    evidence_indices: [0]
  }],
  idempotency_key: "design:<project>:<feature>:<hash>"
})
```

If step 5.2 recalled an older design record for the same feature area, list
it in `supersedes_evidence_ids`. On any MCP failure → log and continue; the
spec on disk is the source of truth.
