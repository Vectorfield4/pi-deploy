# Task Creation Flow (Natural Language)

Triggered when intent = `task`. Creates a task from natural language description.

## Input
- `description` — the user's natural language message
- `chat_id` — from Telegram context

## Steps

1. **Validate description**
   - < 10 characters → "Description is too short. Give me a bit more detail."
   - Contains disallowed tokens (`curl`, `wget`, `eval`, `exec`, `sudo`, `rm -rf`, `<!--`, `<script`) → "Description contains disallowed content."

2. **Detect project**
   - Check `/workspace/` for git repos. If exactly one → use it.
   - If multiple → match by keywords in description.
   - If no match → ask "Which project?"

3. **Classify type and priority**
   - Type: "refactor"/"рефактор"/"restructure" → `refactoring`. "bug"/"fix"/"error" → `bugfix`. "add"/"create"/"implement" → `feature`. Otherwise → `feature`.
   - Priority: "urgent"/"critical"/"срочно" → `urgent`. "bug"/"fix"/"error" → `high`. Otherwise → `normal`.

4. **Compute priority_score** (age=0 at creation)
   - `type_weight`: bugfix=4, release=4, deploy/review=3, feature/ui/integration/refactoring=2, content/init=1.
   - `priority_score = type_weight` + urgent bonus (+2) or high bonus (+1).

5. **Build metadata**
   - Base: `project`, `type`, `priority`, `priority_score`, `review_iterations: 0`, `chat_id`, `source: "telegram"`.
   - If refactoring → add `refactoring_target` (extracted from description).

6. **Delegate to orchestrator**
   - The orchestrator receives the task with full context and begins decomposition.

7. **Reply**
   - "Got it. Working on: **[description]** for project **[project]**."
   - For complex tasks: "I'll break this down and delegate. You'll see updates as work progresses."

## Notes
- No Kanban anymore — tasks live in memory/sessions
- The orchestrator handles decomposition and delegation via pi-subagents
- User sees progress updates as subagents complete work
