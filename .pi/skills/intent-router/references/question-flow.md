# Question Flow (Natural Language)

Triggered when intent = `question`. Answers questions using RAG recall.

## Input
- User's natural language question
- `chat_id` — from Telegram context

## Steps

1. **Recall context (RAG)**
   - Call `mcp({ tool: "dense_mem_recall_memory", args: { query="<question>" } })`.
   - If a project is mentioned, also recall project-specific context:
     `mcp({ tool: "dense_mem_recall_memory", args: { query="<question> project:<project>" } })`.
   - Graceful degradation: if MCP fails, answer from general knowledge.

2. **Generate answer**
   - Use recalled context + original question for a concise answer.
   - Reference project rules or past experience if found.
   - If no relevant context → answer from general knowledge, note that.

3. **Reply**
   - Keep concise (under 2000 chars for Telegram).
   - If longer → summarize and offer to investigate deeper.
