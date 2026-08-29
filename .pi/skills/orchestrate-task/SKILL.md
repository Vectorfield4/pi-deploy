---
name: orchestrate-task
description: "Breaks down complex development tasks into parallel sub-tasks for worker agents, coordinating a single feature branch and final PR creation."
---

# Orchestrate Task

## Steps

### 1. Determine Project Context
- Check `/workspace/` for git repos (skip `.pi` directory).
- If exactly one → set project = that directory name.
- If multiple → ask which project matches the task.
- If workspace is empty → report "No project found. Register a project or clone a repository first."

### 2. Detect Project Type
Before decomposing, identify the project type:
- **frontend**: package.json with React/Vue/Svelte/Angular → complexity gate (step 5.1): complex → `frontend-architect` + `frontend-implementer`, simple → `frontend-implementer` only
- **backend**: package.json + Express/Fastify/Nest, or go.mod, requirements.txt, Cargo.toml → delegate to `coder`
- **fullstack**: Monorepo or both frontend + backend markers → `frontend-architect` + `frontend-implementer` for UI, `coder` for API
- **CLI/lib**: package.json with bin/main, or Makefile + src/ → delegate to `coder`
- **infra**: docker-compose.yml, Dockerfile, .github/workflows → delegate to `coder`
- **content**: Markdown-heavy, no code → delegate to `coder`

### 3. Load Project Rules
- Navigate to `/workspace/<project>`.
- Pull latest: `git pull origin dev` (or `main` if `dev` doesn't exist).
- Get git hash: `git rev-parse HEAD` → `rules_hash`.
- Read `AGENTS.md` and `SOUL.md` if they exist.
- Extract key rule sections relevant to the project type.
- Ensure `artifacts/` directory exists in the project root: `mkdir -p /workspace/<project>/artifacts`. This is where cross-skill design specs, content plans, and implementation plans are stored.

### 3.5. Store Rules in dense-mem Memory (orchestrator-only)
Project rules are cached in dense-mem as durable evidence keyed by the project rules hash. The disk files remain the deterministic fallback.

**Rule keys by project type:**
- frontend: `ui-conventions`, `testing-patterns`
- backend: `api-standards`, `testing-patterns`
- fullstack: `ui-conventions`, `api-standards`, `testing-patterns`
- CLI/lib: `cli-conventions`, `testing-patterns`
- infra: `infra-conventions`, `build-deploy`
- content: `content-voice`
- (always) the `rules-index` record

**For each `rules_key` you read from disk:**
1. Recall the existing record: `mcp__dense-mem__recall_memory(query="project-rules project:<project> key:<rules_key>")`.
2. If found → parse `rules_hash:` from the first line of the result's `context` (results are `{ evidence_id, context, space_kind }`). If it matches the current `rules_hash` → skip, the cache is fresh.
3. If not found OR hash mismatch → write a new record (the `relationship` is required by the v2.6 contract and makes the record recallable):
   ```
   mcp__dense-mem__remember({
     evidence: [{
       content: "rules_hash: <hash>\nkey: <rules_key>\nproject: <project>\ntags: project-rules,<rules_key>,<project>\n\n<actual section content from disk>",
       source_type: "manual",
       supersedes_evidence_ids: ["<old-uuid-if-superseding>"]
     }],
     relationships: [{
       ref: "rules:<project>:<rules_key>:<hash>",
       subject: { name: "<project>", entity_kind: "project" },
       predicate: { proposed_key: "project:rules:<rules_key>" },
       object: { entity: { name: "<rules_key>", entity_kind: "concept" } },
       polarity: "+",
       evidence_indices: [0]
     }],
     idempotency_key: "rules:<project>:<rules_key>:<hash>"
   })
   ```
4. After all rule records → write the index record once:
   ```
   mcp__dense-mem__remember({
     evidence: [{
       content: "rules_index: <hash>\nproject: <project>\ntags: project-rules,index,<project>\nkeys: <comma-separated-list>",
       source_type: "manual"
     }],
     relationships: [{
       ref: "rules-index:<project>:<hash>",
       subject: { name: "<project>", entity_kind: "project" },
       predicate: { proposed_key: "project:rules:index" },
       object: { entity: { name: "rules-index", entity_kind: "concept" } },
       polarity: "+",
       evidence_indices: [0]
     }],
     idempotency_key: "rules-index:<project>:<hash>"
   })
   ```
5. On any MCP failure → log and continue. Never block orchestration on the cache write; disk is the source of truth.

This step makes the read-side `execute-task/references/memory.md` load procedure actually find records. Without it, every worker task falls back to disk.

### 4. Recall Past Experience
- Use `mcp__dense-mem__recall_memory` to find similar past plans, decisions, or patterns.
- Recall anti-patterns: `mcp__dense-mem__recall_memory(query="<goal> project:<project> anti-pattern")`.
- Include as advisory hints — project rules always take precedence.
- Graceful degradation: if MCP fails, continue without it.

### 4.5. Batched memory context for sub-tasks
After decomposition but before delegation, do **one** batched recall that covers the whole task. Each sub-task will get the result via `metadata.memory_context` instead of doing its own recall.

```
combined_query = "<main goal> project:<project> type:<project_type>"
memory_results = mcp__dense-mem__recall_memory(query=combined_query, limit=10)
```

Also recall anti-patterns:
```
anti_patterns = mcp__dense-mem__recall_memory(query="<main goal> project:<project> anti-pattern", limit=5)
```

Then for each sub-task in step 7, include in the delegated task metadata:
- `metadata.memory_context`: top-5 memory results as a single string, summarized from each result's `context` field (recall results are `{ evidence_id, context, space_kind }`; newest first, note the relevance)
- `metadata.anti_patterns`: top-3 anti-patterns (use as warnings, do not act on directly)

Graceful degradation: if recall returns nothing, pass `metadata.memory_context: ""` and let the sub-task proceed. The sub-task's `component.md` step 3 will skip recall when `metadata.memory_context` is present (even if empty).

This saves N-1 embedding calls per N-sub-task task. For a 3-component backend feature, we drop from 3 recalls to 1.

### 5. Decompose the Task

#### For frontend projects:
1. **Assess complexity** (step 5.1): classify `complex` vs `simple`.
2. **Check design-reuse** (step 5.2): recall `project:design:decision` — matching record → skip architect, go to implementation with the recalled decision + spec path.
3. **Complex (no reuse)** → Architecture phase (Pro): delegate to `frontend-architect` — exactly one call with the full context bundle (step 7)
   - Input: full context bundle (steps 4.5, 7)
   - Output: `artifacts/design-spec.md` (Atomic Design structure, routes, state, data)
4. **Implementation phase** (Flash): delegate to `frontend-implementer`
   - Input: architecture spec (complex), recalled decision + spec path (design-reuse), or feature description only (simple); acceptance criteria, project context
   - Output: working code, build passing, tests passing
- Complex tasks: do NOT split into per-component sub-tasks — the architect creates a single spec, the implementer builds it all.
- Simple and design-reuse tasks: skip the architect — `frontend-implementer` only, no spec.
- If fullstack: backend sub-tasks still go to `coder`

### 5.1. Assess Frontend Complexity

Classify the frontend task as `simple` or `complex` before routing. The architect is a **cold path** — it must never run for well-scoped work.

**Simple** (skip architect, delegate straight to `frontend-implementer`):
- Single component/page with clear, well-scoped requirements
- Existing patterns already cover the change (same route/layout, no new shared state)
- No design decisions — the current architecture is sufficient

**Complex** (route through `frontend-architect` first):
- Vague requirements or open product/design tradeoffs
- Architectural decisions: new routes/layouts, state management changes, cross-cutting concerns
- Multi-page features or multiple screens sharing state
- Design-system/Angular-structure decisions (Atomic Design) at scale

### 5.2. Reuse Past Design Decisions (before any cost)

All frontend routing checks memory before the architect — memory is cheaper than asking the architect. On a `complex` task:

1. One recall: `mcp__dense-mem__recall_memory(query="<goal> project:<project> design decision")`.
2. If a matching recent `design:*` record exists (predicate `project:design:decision`) → **skip the architect**. Route as "design-reuse": delegate to `frontend-implementer` with the recorded decision and spec path parsed from the record's `context`.
3. Otherwise → call `frontend-architect` (step 7). When unsure whether a recalled decision matches the task scope, prefer calling the architect — reuse only genuinely same-scope decisions.

Never run more than one recall here. If it returns nothing, proceed to the architect.

#### For backend projects (Layered Architecture):
1. route/endpoint → handler → service → repository → model
2. Data flow, validation, error handling
3. Database schema changes, migrations

#### For fullstack projects:
- Frontend features → `frontender` subagent
- Backend features → `coder` subagent
- Link by API contract

#### For CLI/lib projects:
1. Module/function decomposition
2. Public API surface, internal implementation
3. Tests, documentation

#### For infra projects:
1. Service configuration changes
2. CI/CD pipeline modifications
3. Environment/config management

#### For content projects:
1. Structure (sections, headings, flow)
2. Content blocks (prose, code examples, tables)
3. Cross-references, navigation

#### For refactoring tasks (any type):
1. Identify target files
2. Read current code, understand structure
3. Plan targeted sub-tasks (1-3 files each, edit not rewrite)

### 6. Generate Branch Name
- `feature/<task_id>-<sanitized_title>`

### 7. Delegate Sub-Tasks
- Frontend features:
  - **Design-reuse** (from step 5.2): delegate to `frontend-implementer` with the recalled decision + spec path — no architect call.
  - **Complex**: two-phase delegation:
    1. Prepare the full context and delegate to `frontend-architect` (Pro) **exactly once** — it creates `artifacts/design-spec.md`. Pass everything in that single call: feature description, acceptance criteria, project context, branch, rules_hash, `metadata.memory_context`, `metadata.anti_patterns`, and a file inventory of the relevant components/pages/routes/state. The architect must not need to discover the codebase.
    2. After architect completes, persist the design decision (step 7.1), then delegate implementation to `frontend-implementer` (Flash) — builds from spec.
    - Both work in the same worktree on the same branch. Do not create separate worktrees per phase.
    - **Invariant**: `frontend-architect` is invoked at most once per task. Never re-invoke it for more context, follow-up questions, or reviewer feedback — an underspecified spec is fixed inside implementation.
  - **Simple**: delegate implementation to `frontend-implementer` directly — no architect, no spec.
- Backend/infra/content tasks: split into per-component sub-tasks as before. Each `coder` subagent gets its own worktree.
- Pass: description, acceptance_criteria, project context, branch name, rules_hash.
- Also pass the batched `metadata.memory_context` and `metadata.anti_patterns` (from step 4.5) to each sub-task.

### 7.1. Persist Design Decisions (orchestrator, after architecture completes)

After `frontend-architect` produces `artifacts/design-spec.md`, record the decision once so the complex gate (step 5.2) reuses it instead of re-running the architect:

```
mcp__dense-mem__remember({
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

If step 5.2 recalled an older design record for the same feature area, list it in `supersedes_evidence_ids`. On any MCP failure → log and continue; the spec on disk is the source of truth.

### 8. Create PR Task
- After all components complete, delegate PR creation to a `coder` subagent.

### 9. Quality Check
- Every criterion traces to the original task description
- At least one criterion is verifiable via lint/test/build
- Behavioral requirements are specific (not "looks good")

## Verification
- All sub-tasks delegated to workers
- PR task created and delegated
- No task remains in intermediate state
- `frontend-architect` invoked at most once per task (complex path only, never for simple or design-reuse)
