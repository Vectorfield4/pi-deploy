import http from "node:http";
import { loadConfig } from "./config.js";
import { MemoryDb } from "./db.js";
import { ApiEmbeddingStore } from "./embeddings.js";
import { callTool, listTools, ToolContext } from "./tools.js";

function ownerFromRequest(req: http.IncomingMessage): string {
  const h = req.headers["x-pi-owner"];
  if (typeof h === "string" && h.length > 0) return h;
  return "system";
}

function sendJson(
  res: http.ServerResponse,
  status: number,
  body: unknown,
  sse: boolean
): void {
  if (sse) {
    res.writeHead(status, {
      "Content-Type": "text/event-stream",
      Connection: "keep-alive",
      "Cache-Control": "no-cache",
    });
    res.write(`event: message\ndata: ${JSON.stringify(body)}\n\n`);
    res.end();
  } else {
    res.writeHead(status, { "Content-Type": "application/json" });
    res.end(JSON.stringify(body));
  }
}

async function handle(
  bodyText: string,
  res: http.ServerResponse,
  ctx: ToolContext
): Promise<void> {
  let req: unknown;
  try {
    req = JSON.parse(bodyText);
  } catch {
    sendJson(res, 400, { jsonrpc: "2.0", id: null, error: { code: -32700, message: "parse error" } }, false);
    return;
  }
  const r = req as { jsonrpc?: string; id?: unknown; method?: string; params?: Record<string, unknown> };
  const id = r.id ?? null;

  if (r.method === "tools/list") {
    sendJson(res, 200, { jsonrpc: "2.0", id, result: { tools: listTools() } }, false);
    return;
  }
  if (r.method === "tools/call") {
    const params = (r.params ?? {}) as { name?: string; arguments?: Record<string, unknown> };
    const name = params.name ?? "";
    try {
      const result = await callTool(name, params.arguments ?? {}, ctx);
      const text = typeof result === "string" ? result : JSON.stringify(result, null, 2);
      sendJson(res, 200, {
        jsonrpc: "2.0",
        id,
        result: { content: [{ type: "text", text }], structuredContent: result },
      }, true);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      sendJson(res, 200, {
        jsonrpc: "2.0",
        id,
        result: {
          isError: true,
          content: [{ type: "text", text: msg }],
        },
      }, true);
    }
    return;
  }
  sendJson(res, 200, { jsonrpc: "2.0", id, error: { code: -32601, message: `method not found: ${r.method}` } }, false);
}

async function main(): Promise<void> {
  const config = loadConfig();
  const db = new MemoryDb({ ...config.pg, dimensions: config.embed.dimensions });
  await db.init();
  const embed = new ApiEmbeddingStore(config.embed);
  const ctx: ToolContext = {
    db,
    embed,
    owner: "system",
    maxResults: config.maxResults,
  };

  const server = http.createServer((req, res) => {
    if (req.method === "GET" && req.url === "/health") {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ status: "ok" }));
      return;
    }
    if (req.method !== "POST" || req.url !== "/mcp") {
      res.writeHead(404, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "not found" }));
      return;
    }
    const accept = req.headers.accept ?? "";
    const sse = accept.includes("text/event-stream");
    ctx.owner = ownerFromRequest(req);
    const chunks: Buffer[] = [];
    req.on("data", (c) => chunks.push(c as Buffer));
    req.on("end", () => {
      const body = Buffer.concat(chunks).toString("utf8");
      handle(body, res, ctx).catch((err) => {
        sendJson(res, 500, { jsonrpc: "2.0", id: null, error: { code: -32603, message: err instanceof Error ? err.message : String(err) } }, sse);
      });
    });
  });

  const m = /^:(\d+)$/.exec(config.httpAddr);
  const port = m ? Number(m[1]) : 8090;
  server.listen(port, () => {
    console.log(`pi-pgvector-api-embeddings listening on :${port}/mcp`);
  });

  const shutdown = async () => {
    await db.close();
    server.close(() => process.exit(0));
  };
  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);
}

main().catch((err) => {
  console.error("fatal:", err);
  process.exit(1);
});
