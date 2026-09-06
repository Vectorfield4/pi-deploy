# Question Flow (Natural Language)

Triggered when intent = `question`. Answers via RAG recall.

## Input
- User's natural language question
- `chat_id` — from Telegram context

## Steps

1. **Recall context (RAG)**
   - `pgvec_recall_memory({ query:"<question>" })`.
   - Project mentioned: also `pgvec_recall_memory({ query:"<question> <project>" })`.
   - `pgvec_*` call fails: answer from general knowledge.

2. **Generate answer**
   - Answer from recalled context + the original question, concise.
   - Reference project rules or past experience if found.
   - No relevant context: answer from general knowledge, note that.

3. **Reply**
   - Keep under 2000 chars for Telegram.
   - Longer: summarize and offer to investigate deeper.