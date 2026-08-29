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
   The LLM picks one of these actions:
   - **Create a refactoring task** — if feedback describes something that needs changing
   - **Store in memory** — if feedback contains a pattern, preference, or rule
   - **Both** — if feedback requires code change AND memory storage
   - **Neither** — if feedback is informational or a compliment

   The LLM also states a confidence level (high/medium/low) for its pick.

   **Confidence gate**:
   - If `confidence == "high"` and the action is clear (e.g. "the button color is wrong" → refactoring task), proceed.
   - If `confidence == "low"` OR multiple actions seem equally valid, ask a clarifying question via Telegram instead of acting. Example questions:
     - "Do you want me to (a) create a task to fix this, (b) just remember this preference, or (c) both?"
     - "Could you clarify what part of the result you want changed?"
   - Never guess on destructive or system-wide actions.

   For memory writes (best-effort):
   ```
   mcp__dense-mem__remember({
     evidence: [{
       content: "project: <project>\ntype: <feedback-type>\ntags: project:<project>,user-feedback,<intent-tag>\nconfidence: medium\nvalid_until: <YYYY-MM-DD, today + 60 days>\n\n<feedback summary, under 200 chars>",
       source_type: "observation"
     }],
     relationships: [{
       ref: "feedback:<project>:<intent-tag>:<short-hash>",
       subject: { name: "<project>", entity_kind: "project" },
       predicate: { proposed_key: "project:user:feedback" },
       object: { entity: { name: "<intent-tag>", entity_kind: "concept" } },
       polarity: "+",
       evidence_indices: [0]
     }],
     idempotency_key: "feedback:<project>:<intent-tag>:<short-hash>"
   })
   ```

4. **Reply**
   - If acting: "Got it. I'll fix that." / "Noted. Stored in memory." / "Thanks for the feedback!"
   - If asking: send the clarifying question and stop. Do not create a task or write to memory until the user replies.
   - If creating a task: "I'll create a task to address this."
