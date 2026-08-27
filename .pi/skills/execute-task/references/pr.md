# PR Creation (`pr_creation == true`)

Loaded by `execute-task` after the project rules have been loaded (see `references/memory.md`).

## Steps

1. **Ensure all components are done**
   - Verify that the branch contains changes.

2. **Validate the code**
   - Run project-specific validation (linting, tests).
   - Use validation commands from cached rules (see `references/memory.md`) or from `AGENTS.md`.

3. **Self-review the diff (against judge rubric)**
   - Run `git diff --name-only` to see what was changed.
   - For each changed file, verify against the judge rubric dimensions:
     - **Code quality**: DRY? Naming clear? No commented-out code? Consistent style with project?
     - **Tests**: Does the diff include tests for new/changed logic? Edge cases covered?
     - **Security**: No hardcoded secrets? Input sanitized? Auth checks in place?
     - **Docs & conventions**: AGENTS.md conventions followed? JSDoc where needed? No TODO-blockers?
   - If any dimension is clearly deficient → fix it now (do not push a known violation to QA).
   - If all clean → proceed to PR creation.

4. **Create the pull request**
   - Load and follow the `create-pr` skill.
   - This skill commits all changes, pushes the branch, and opens a PR.

5. **Hand off to QA review**
   - On success: return to the orchestrator with the PR URL and a summary.
   - The orchestrator delegates the QA review task to the QA agent.
   - On failure: return error details to the orchestrator.
   - Code review is NOT done here — QA handles it via `execute-qa-task` → `review-and-merge`. If QA finds issues it sends the task back to the coder (see `references/review-fix.md`).
