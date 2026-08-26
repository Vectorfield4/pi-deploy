# Question Flow (Natural Language)

Triggered when intent = `question`. Answers questions using RAG recall.

## Input
- User's natural language question
- `chat_id` — from Telegram context

## Steps

1. **Recall context (RAG)**
   - Call `mcp__dense-mem__recall_memory(query="<question>")`.
   - If a project is mentioned, also recall project-specific context:
     `mcp__dense-mem__recall_memory(query="<question>", filter={tags: ["project:<project>"]})`.
   - Graceful degradation: if MCP fails, answer from general knowledge.

2. **Generate answer**
   - Use recalled context + original question for a concise answer.
   - Reference project rules or past experience if found.
   - If no relevant context → answer from general knowledge, note that.

3. **Reply**
   - Keep concise (under 2000 chars for Telegram).
   - If longer → summarize and offer to investigate deeper.
