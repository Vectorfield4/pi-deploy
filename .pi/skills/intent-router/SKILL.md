---
name: intent-router
description: "Routes natural language messages to the correct action: task creation, questions, feedback, project management, status, deploys. No slash commands needed."
---

# Intent Router

Every incoming message from Telegram goes through intent classification before any action is taken.

## Intent Classification

Analyze the user message and classify it into ONE of these intents:

| Intent | Signal words (non-exhaustive) | Action |
|--------|-------------------------------|--------|
| `task` | add, create, build, implement, fix, refactor, make, do, write, add page, add component, update, change, improve | Create task → orchestrate-task |
| `question` | what, how, why, where, when, does, can, is there, explain, tell me, show me | RAG recall → answer |
| `feedback` | color is wrong, should be, I don't like, change this, looks bad, prefer, instead of, the issue is | Analyze → task/memory/both/neither |
| `project_add` | add project, register project, new project, connect repo | Register project → memory |
| `status` | status, progress, what's happening, how's it going, task status | Read status → reply |
| `cancel` | cancel, stop, abort, drop task | Cancel task |
| `deploy` | deploy, push to production, ship it, go live, FTP | **Confirm** → QA deploy |
| `release` | release, cut release, version bump, publish | **Confirm** → QA release |
| `unclear` | (low confidence) | Ask clarifying question |

## Classification Rules

1. **One intent per message.** If ambiguous, pick the most likely and confirm.
2. **Project detection** — always try to detect which project the message refers to:
   - Explicit: "in my-app, add..." → project = "my-app"
   - Implicit: check `/workspace/` for repos, match by keywords
   - If no project found → ask "Which project?"
3. **Type detection** for task intent:
   - "refactor"/"рефактор"/"restructure" → `refactoring`
   - "bug"/"fix"/"error"/"сломалось" → `bugfix`
   - "add"/"create"/"implement"/"создай" → `feature`
   - "content"/"copy"/"text"/"текст" → `content`
4. **Priority detection:**
   - "urgent"/"critical"/"срочно"/"ASAP" → urgent (+2)
   - "bug"/"fix"/"error" → high (+1)
   - Default → normal
5. **Stay lightweight.** Project detection uses `ls /workspace` and
   `find /workspace -maxdepth 2 -name package.json -o -name go.mod -o
   -name requirements.txt`, never `read` of source files. Reading project
   files in full belongs to the worker; the orchestrator only inventories.

## Rejection Filter

Reject messages that are:
- Empty or whitespace-only
- Single emoji with no text
- Spam patterns (repeated characters, URLs only)
- Commands meant for other bots

Reply: "I didn't understand that. Try describing what you need, or ask me a question."

## Dangerous Actions

Deploy and release require explicit confirmation:
1. Classify intent as `deploy` or `release`
2. Reply: "⚠️ You want to **[deploy/release]** project **[name]** to **[target]**. Confirm?"
3. Wait for confirmation ("yes", "да", "confirm", "подтверждаю")
4. Only then delegate to QA subagent

## Flow

```
Message → Classify Intent → Detect Project → Route
                                          ├─ task → orchestrate-task
                                          ├─ question → RAG recall → answer
                                          ├─ feedback → analyze → task/memory/both
                                          ├─ project_add → memory write
                                          ├─ status → memory read → reply
                                          ├─ cancel → cancel task
                                          ├─ deploy/release → confirm → QA
                                          └─ unclear → clarifying question
```

## Verification
- Every message produces exactly one response
- Ambiguous messages get a clarifying question, not a wrong action
- Dangerous actions always require confirmation
