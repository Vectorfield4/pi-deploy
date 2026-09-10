# Fan-out

How `orchestrate-task` dispatches workers (step 7) and the wait discipline
(step 8.5). One LLM pass authors all sibling launches; Pi fans the children
out in finish order, each completion arriving as its own notification turn.

## Frontend complex

Sequential: `frontend-architect` once (creates `artifacts/design-spec.md`),
then persistence (step 7.1), then `frontend-implementer`. Same worktree.
Never re-invoke the architect.

## Image generation

Parallel fan-out when `task.metadata.assets` has `source: generate` rows:
`drawer` (images) + the implementing worker in one `runs.all` pass. Each in
its **own worktree and branch** — the drawer on `images/<task_id>-<title>` in
`/workspace/<project>-<task_id>-images`, the implementer on
`feature/<task_id>-<title>`. The drawer commits+pushes images; the implementer
wires the `repo_path`s and never calls `hf_generate_image`/`generate_image`.
Split branches make the parallel commits race-free. After both notifications
arrive, the orchestrator merges `images/<task_id>-<title>` into the feature
branch (`orchestrate-task` 7.2), then QA fast-forwards it into `main`.

## Multiple UI changes in one feedback

Each point is its own simple task (own scope, file area, test). Fan out via
`runs.all([{key, agent, task}, ...])`. One sibling failing does not block the
others; bounce findings route back per-worker.

## Backend / infra / content

Split into per-component `coder` sub-tasks, each in its own worktree.
`metadata.complex: true` routes extra scrutiny; simple tasks run without it.

## Simple / design-reuse

No fan-out: `frontend-implementer` directly (no architect, no spec).

## Wait discipline

`subagent` returns a `runId`; end the turn, the result-watcher injects a
`<subagent_notification>` with the outcome. `subagent_wait`/`status` are
diagnostic only; polling burned 13+ calls per task. All sibling launches in
one generation; never across separate turns.