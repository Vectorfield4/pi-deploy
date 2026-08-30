---
name: orchestrate-task
description: "Breaks down complex development tasks into parallel sub-tasks for worker agents, coordinating a single feature branch and final push to main."
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
- **backend**: package.json + Express/Fastify/Nest, or go.mod, requirements.txt, Cargo.toml → complexity gate (step 5.1a): complex → `coder` on Pro, simple → `coder`
- **fullstack**: Monorepo or both frontend + backend markers → frontend: complexity gate (step 5.1) architect (complex) / implementer; backend: complexity gate (step 5.1a) → `coder`
- **CLI/lib**: package.json with bin/main, or Makefile + src/ → complexity gate (step 5.1a) → `coder`
- **infra**: docker-compose.yml, Dockerfile, .github/workflows → complexity gate (step 5.1a) → `coder`
- **content**: Markdown-heavy, no code → complexity gate (step 5.1a) → `coder`

### 3. Load Project Rules (lightweight)

The orchestrator's cache dominates the bill. Loading the full `AGENTS.md` into
the orchestrator's context is expensive (replayed as cacheRead on every
turn). Stay light; let workers do the heavy reads.

- Navigate to `/workspace/<project>`.
- Pull latest: `git pull origin dev` (or `main` if `dev` doesn't exist).
- Get git hash: `git rev-parse HEAD` → `rules_hash`.
- Run `wc -l AGENTS.md SOUL.md 2>/dev/null` first. If the total is **≤ 200
  lines** → `read` both fully. Otherwise:
  - `grep -nE '^## ' AGENTS.md SOUL.md` to get a section inventory.
  - For project-type-relevant sections, `read` only that section
    (`head -n <end> AGENTS.md | tail -n +<start>` or similar).
- Extract key rule sections relevant to the project type.
- Ensure `artifacts/` directory exists in the project root: `mkdir -p /workspace/<project>/artifacts`. This is where cross-skill design specs, content plans, and implementation plans are stored.
- Workers will read the full `AGENTS.md`/section they need; the orchestrator passes only `metadata.rules_hash` and `metadata.file_inventory` (see step 4.7).

### 3.5. Store Rules in dense-mem Memory (orchestrator-only)

Full procedure (rule keys, recall/remember shapes, index record, graceful
degradation) lives in `references/rules-caching.md`. Read it when you reach
this step. Summary: per project type, recall the existing `project-rules`
records (keyed by `rules_hash`); write a new record on hash mismatch with
the v2.6 `remember` contract (evidence + relationships + idempotency_key);
write the `rules-index` record once; on MCP failure, log and continue —
disk is the source of truth.

### 4. Recall Past Experience
- Use `dense_mem_recall_memory` to find similar past plans, decisions, or patterns.
- Recall anti-patterns: `dense_mem_recall_memory({ query:"<goal> project:<project> anti-pattern" })`.
- Include as advisory hints — project rules always take precedence.
- Graceful degradation: if MCP fails, continue without it.

### 4.5. Batched memory context for sub-tasks

One batched recall for the whole task; pass the result to each sub-task via
`metadata.memory_context`. Drops N-1 embedding calls per N-sub-task task.
Full procedure (queries, fields, graceful degradation) lives in
`references/memory-batching.md`. Read it when you reach this step.

### 4.7. Build a file inventory (orchestrator does NOT read)

Heavy file reads belong to workers. Build a `file_inventory` array per
sub-task (≤ 30 paths, scoped to the sub-task) and ship it as
`metadata.file_inventory`. The worker reads what it needs; the orchestrator
never does. Full procedure (template, build commands, what to include) lives
in `references/file-inventory.md`. Read it when you reach this step.

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

### 5.1a. Assess Complexity for Non-Frontend

The same cold-path rule applies to backend/infra/CLI/content: the Pro model is
invoked only for genuinely complex work, and review follows Pro.

**Simple** (delegate `coder` on Flash, default model):
- Well-scoped, 1-3 files, existing patterns cover the change
- No schema/API contract changes, no cross-cutting concerns, no new services

**Complex** (delegate `coder` with `model: "deepseek/deepseek-v4-pro"`):
- Vague requirements or open architecture tradeoffs
- Schema/migration changes, new public APIs or contracts
- Multi-module or cross-cutting changes (auth flow, shared state across services)
- Anything where a wrong architectural choice is expensive to undo

### 5.1b. Pro gate (`metadata.pro_invoked`)

`metadata.pro_invoked` is `true` for a task iff **any delegation in its path
used the Pro model**: `frontend-architect` invoked (complex frontend) OR a
`coder` complex-path override. Design-reuse and simple tasks are `false`. This
flag drives the review gate (`execute-qa-task`): the reviewer subagent runs
only when it is `true`.

### 5.2. Reuse Past Design Decisions (before any cost)

All frontend routing checks memory before the architect — memory is cheaper than asking the architect. On a `complex` task:

1. One recall: `dense_mem_recall_memory({ query:"<goal> project:<project> design decision" })`.
2. If a matching recent `design:*` record exists (predicate `project:design:decision`) → **skip the architect**. Route as "design-reuse": delegate to `frontend-implementer` with the recorded decision and spec path parsed from the record's `context`.
3. Otherwise → call `frontend-architect` (step 7). When unsure whether a recalled decision matches the task scope, prefer calling the architect — reuse only genuinely same-scope decisions.

Never run more than one recall here. If it returns nothing, proceed to the architect.

#### For backend projects (Layered Architecture):
1. route/endpoint → handler → service → repository → model
2. Data flow, validation, error handling
3. Database schema changes, migrations

#### For fullstack projects:
- Frontend features → `frontend-implementer` subagent
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

`subagent` accepts `task` as a **string only** (an object fails with
`task: must be string`). Serialize the context bundle into JSON:

```
subagent({
  agent: "<agent>",
  task: `{"type":"...","task_id":"...","description":"...","acceptance_criteria":["..."],"project":"...","branch":"...","rules_hash":"...","metadata":{"memory_context":"...","anti_patterns":["..."],"pro_invoked":<bool>,"file_inventory":["<path1>","<path2>"]}}`,
  skill: "<skill>"
})
```

Payload fields: top-level `type`/`task_id`/`description`/`acceptance_criteria`/
`project`/`branch`/`rules_hash`; `metadata` carries `memory_context` (from
step 4.5), `anti_patterns`, `pro_invoked` (step 5.1b), `file_inventory` (from
step 4.7), and task-specific fields. Pass `""` / `[]` / `false` for empty
values — never omit the structure. Workers read fields as `task.metadata.*`.

| Work | `agent` | `skill` |
|------|---------|---------|
| backend/infra/content/CLI component | `coder` | `execute-task` |
| complex component (any non-frontend) | `coder` + `model: "deepseek/deepseek-v4-pro"` | `execute-task` |
| frontend architecture (complex only) | `frontend-architect` | `ui-architect` |
| frontend implementation | `frontend-architect` or `frontend-implementer` | `ui-architect` / `ui-implementer` |
| finalize: review gate + push to main | `qa` | `execute-qa-task` |
| release / deploy | `qa` | `execute-qa-task` |
| branch review (via QA, complex only) | `reviewer` | `execute-review` |

- Frontend complex (architect + implementer): delegate `frontend-architect`
  **once** with full context; it creates `artifacts/design-spec.md`. After
  it completes, persist the design (step 7.1) and delegate implementation
  to `frontend-implementer`. Both share the same worktree. Never re-invoke
  the architect — an underspecified spec is fixed inside implementation.
- Frontend simple / design-reuse: delegate to `frontend-implementer`
  directly (no architect).
- Backend/infra/content: split into per-component sub-tasks; each `coder`
  in its own worktree. Complex → `model: "deepseek/deepseek-v4-pro"`,
  `metadata.pro_invoked: true`. Simple → Flash, `pro_invoked: false`.

### 7.1. Persist Design Decisions (orchestrator, after architecture completes)

Record the decision once so the complex gate (step 5.2) reuses it instead
of re-running the architect. Full `remember` shape (v2.6 contract, TTL 90d,
`supersedes_evidence_ids` for older records, graceful degradation) lives
in `references/persist-design.md`. Read it when you reach this step.

### 8. Finalize Task (push to main)

```
subagent({ agent: "qa", task: '{"type":"push","project":"<project>","branch":"<branch>","metadata":{"pro_invoked":<bool>}}', skill: "execute-qa-task" })
```

QA runs the reviewer subagent only when `pro_invoked == true`; simple tasks
skip the reviewer and push straight to `main`. No PR, no human gate.

### 8.5. Wait Discipline (notification-based; don't poll)

The intended flow: `subagent({ agent, task, skill })` returns a `runId`; end
the turn; the result-watcher injects a `<subagent_notification>` into your
next turn with the worker's outcome. `subagent_wait` and `subagent status`
are diagnostic only — polling them burned 13+ calls per task and produced
duplicated acceptance reports. `subagent_wait` is the exception path for
`pi -p` non-interactive runs where there is no next turn to receive the
notification.

- Launch all sibling workers in a single turn (fan-out budget 64); end
  the turn. Each completion arrives as its own notification turn, in
  finish order. Track outstanding workers by which notifications you
  have already received.
- `subagent({ action: "status", id, view: "transcript", lines: 30 })` —
  one-shot diagnostic only (events.jsonl under
  `/tmp/pi-subagents-uid-0/async-subagent-runs/<id>/` for crashes).
- Blocked-fallback: if a downstream step truly cannot proceed and the
  notification has not arrived, use **one** `bash sleep 120` then read
  the events log directly.

### 9. Quality Check
- Every criterion traces to the original task description
- At least one criterion is verifiable via lint/test/build
- Behavioral requirements are specific (not "looks good")

## Verification
- All sub-tasks delegated to workers
- Finalize task (push to main) created and delegated
- No task remains in intermediate state
- `frontend-architect` invoked at most once per task (complex path only, never for simple or design-reuse)
- `metadata.pro_invoked` set to `true` iff Pro was actually invoked (architect invoked, or `coder` complex override)
- Reviewer was NOT invoked for tasks with `pro_invoked: false`
- Wait discipline (step 8.5): workers' results are received via the result-watcher `<subagent_notification>` injection, not via `subagent_wait` or `status` polling loops. `subagent status` only as a one-shot diagnostic, never as a wait primitive.
