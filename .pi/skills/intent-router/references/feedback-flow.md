# Feedback Flow (Natural Language)

Triggered when intent = `feedback`. Processes user feedback about existing work.

## Input
- User's natural language feedback (may reference a task implicitly or explicitly)
- `chat_id` — from Telegram context

## Steps

1. **Parse input**
   - If message references a specific task/PR/commit → extract reference
   - Otherwise → `task_id = null`, `feedback_text = entire message`

2. **Gather context**
   - If task reference found → fetch related context from memory
   - Get recent tasks/sessions for broader context
   - Check if feedback relates to a specific file/component

3. **Analyze and act**
   The LLM decides what to do based on feedback content:
   - **Create a refactoring task** — if feedback describes something that needs changing
   - **Store in memory** — if feedback contains a pattern, preference, or rule
   - **Both** — if feedback requires code change AND memory storage
   - **Neither** — if feedback is informational or a compliment

   For memory writes (best-effort):
   ```
   mcp_dense_mem_remember(
     evidence="<feedback summary>",
     tags=["project:<project>", "user-feedback", "<intent-tag>"],
     claims=["feedback-type:<type>"],
     confidence=medium
   )
   ```

4. **Reply**
   - Confirm action: "Got it. I'll fix that." / "Noted. Stored in memory." / "Thanks for the feedback!"
   - If creating a task: "I'll create a task to address this."
