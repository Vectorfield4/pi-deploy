#!/bin/bash
# Diagnose pgvec 503 — run on the server
set -euo pipefail

echo "=== containers ==="
docker ps --format '{{.Names}}\t{{.Status}}'

echo -e "\n=== pgvec-memory env ==="
docker exec pi-pgvec-memory sh -c 'echo "PGVEC_PG_HOST=$PGVEC_PG_HOST AI_API_URL=$AI_API_URL EMBEDDING_MODEL=$AI_API_EMBEDDING_MODEL"'

echo -e "\n=== test embedding API from pgvec-memory ==="
docker exec pi-pgvec-memory node -e '
fetch(process.env.AI_API_URL + "/embeddings", {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "Authorization": "Bearer " + process.env.AI_API_KEY
  },
  body: JSON.stringify({
    model: process.env.AI_API_EMBEDDING_MODEL,
    input: "hello"
  })
}).then(r => { console.log("HTTP " + r.status); return r.text(); })
  .then(t => console.log(t.slice(0,300)))
  .catch(e => console.error("ERROR: " + e.message))
'

echo -e "\n=== test pgvec MCP tools/list from pi-agent ==="
docker exec pi-agent sh -c 'curl -s -X POST http://pi-pgvec-memory:8090/mcp -H "Content-Type: application/json" -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\",\"params\":{}}" | head -c 500'

echo -e "\n\n=== test pgvec MCP tools/call (pgvec_recall_memory) from pi-agent ==="
docker exec pi-agent sh -c 'curl -s -X POST http://pi-pgvec-memory:8090/mcp -H "Content-Type: application/json" -d "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"pgvec_recall_memory\",\"arguments\":{\"query\":\"test\"}}}" | head -c 500'

echo -e "\n\n=== pgvec-memory recent logs ==="
docker logs pi-pgvec-memory --tail 20 2>&1

echo -e "\n=== pi-agent recent pgvec errors ==="
docker logs pi-agent --tail 200 2>&1 | grep -i "pgvec\|503\|recall" | tail -20
