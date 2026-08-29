# File Inventory (orchestrator, step 4.7)

Heavy file reads belong to workers. The orchestrator builds an inventory (a
list of paths) per sub-task and ships it inside the task JSON's `metadata`
object. The worker reads what it needs from the inventory; the orchestrator
never does.

For each planned sub-task, produce a `file_inventory` array. Keep it short
(≤ 30 paths) and **scoped to the sub-task**, not the whole project:

```
file_inventory = [
  "AGENTS.md",                      # rules — worker reads its own section
  "artifacts/design-spec.md",       # if architect already produced one
  "src/api/handlers/<thing>.ts",    # the file(s) the sub-task will touch
  "src/api/handlers/<thing>.test.ts",
  "src/api/services/<svc>.ts",      # adjacent service(s) the sub-task reads
  "package.json",                   # only if a script or dep is relevant
]
```

How to build the inventory (orchestrator does, no reads):

- `ls /workspace/<project>/src` (or relevant top dir) for the layout.
- `find /workspace/<project>/src -maxdepth 3 -name "*.ts" -path "*<feature>*"`
  for feature-scoped files.
- `git diff --name-only origin/main...HEAD` for the in-flight change.
- `grep -rln "<symbol>" /workspace/<project>/src` for callers/imports.
- Trust the worker to do `cat`/`read`/`grep` on what you list; you do not
  paste contents.

The inventory goes into `metadata.file_inventory` on each delegation. The
worker is told (in the task JSON): "Read what you need from
`metadata.file_inventory`. Do not read files outside that list unless
required."
