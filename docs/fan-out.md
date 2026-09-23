# Fan-out

How `orchestrate-task` dispatches workers (step 7) and the wait discipline
(step 8.5). One LLM pass authors all sibling launches; Pi fans the children
out in finish order, each completion arriving as its own notification turn.

## Depth-1 routing

Every frontend task → `frontend-architect`; every non-frontend task →
`backend-architect`. The architect recalls domain memory, binds i18n keys,
and delegates to its worker in the same turn. Planning output never lands on
disk — the task string is the spec.

## Single worktree invariant

Depth 0 is the sole creator of working directories (orchestrate-task step
6.5): one `git worktree add` per `task_id`, one `feature/<task_id>`
branch, before any delegation. All depth-1/2 subagents inherit
`task.cwd` = that worktree and run **no** git network operations
(`worktree add`, `fetch`, `pull`, `rebase`, `push`) — they only
`git add <their paths>` + `git commit` locally. QA sends the branch upstream
and fast-forwards it into `main` centrally (execute-qa-task section 3).

## Parallel copy (Git-Commit partition)

When a task needs layout changes and deep copywork, the architect launches
`frontend-implementer` and `content` together (`runs.all`), both on the
**identical `task.branch` and `task.cwd`** (the single worktree), partitioned
by path so their concurrent commits stay race-free:

- `content` — copy assets only: locale dictionaries at
  `metadata.locale_dirs`, keys from the pre-bound `metadata.locale_keys`.
  Never `.astro`/`.tsx`/`.vue`.
- `frontend-implementer` — UI structures + mapping those exact keys. Never
  edits dictionary files.
- No intermediate tracking files (`artifacts/i18n-keys.json` is dead); each
  commits its own files locally to the shared branch. Concurrent commits in
  one worktree are protected by disjoint file paths and atomic `git commit
  -- <paths>`; an index-lock hiccup resolves by a brief wait and retry.

## Image generation

Parallel fan-out when `task.metadata.assets` has `source: generate` rows:
`drawer` (images) + the architect pass in one `runs.all`, **same `task.cwd`
and `task.branch`** (the single worktree). `drawer` partitions to
`shared/assets/images/` and commits locally; the worker wires the
`repo_path`s and never calls `hf_generate_image`/`generate_image`. Nothing is
merged afterwards — one branch holds everything when QA reviews.

## Multiple UI changes in one feedback

Each point is its own task (own scope, file area, test), each routed through
its scope's architect in its own worktree/branch. Fan out via
`runs.all([{key, agent, task}, ...])` (one worktree per sibling, step 6.5).
One sibling failing does not block the others; bounce findings route back
per-worker.

## Backend / infra / content

`backend-architect` is the single authority for non-frontend scopes: it
recalls domain memory, routes to `backend`/`devops`/`content`, and splits
composite tasks. `metadata.complex: true` routes extra reviewer
scrutiny; it is never a routing gate.

## Wait discipline

`subagent` returns a `runId`; end the turn, the result-watcher injects a
`<subagent_notification>` with the outcome. `subagent_wait`/`status` are
diagnostic only; polling burned 13+ calls per task. All sibling launches in
one generation; never across separate turns.