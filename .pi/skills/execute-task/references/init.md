# Project Initialization (`type == "init"`)

Loaded by `execute-task` for tasks with `metadata.type == "init"`. Project rules are not loaded — the project may not exist yet.

## Steps

1. **Initialize the project and set up CI**
   - Call `skill_run(project-init, project, repo_url)`:
     - Clones the repo (if `/workspace/<project>` is missing) and pulls the latest if present.
     - Creates the base structure (e.g. `package.json`), installs dependencies, sets up linting.
   - Call `skill_run(setup-ci, project)`:
     - Creates `.github/workflows/ci.yml`, commits and pushes it.
   - Call `kanban_heartbeat` before each `skill_run`.

2. **Complete the init task**
   - On success: `kanban_complete --task {{ env.HERMES_KANBAN_TASK }} --comment "Project initialized and CI configured."`
   - On failure: `kanban_block --task {{ env.HERMES_KANBAN_TASK }} --reason "<error>"`
