export interface RpcOptions {
  endpoint: string;
  headers?: Record<string, string>;
  timeoutMs?: number;
}

export class JsonRpcClient {
  private readonly endpoint: string;
  private readonly headers: Record<string, string>;
  private readonly timeoutMs: number;

  constructor(opts: RpcOptions) {
    this.endpoint = opts.endpoint.replace(/\/+$/, "");
    this.headers = opts.headers ?? {};
    this.timeoutMs = opts.timeoutMs ?? 30000;
  }

  async call(method: string, params: Record<string, unknown>): Promise<unknown> {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), this.timeoutMs);
    try {
      const res = await fetch(this.endpoint, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json, text/event-stream",
          ...this.headers,
        },
        body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
        signal: ctrl.signal,
      });
      if (!res.ok) {
        throw new Error(`MCP ${method} failed: HTTP ${res.status}`);
      }
      const text = await res.text();
      const body = parseSseOrJson(text);
      if (body.error) {
        throw new Error(
          (body.error as { message?: string }).message ?? `MCP ${method} error`
        );
      }
      return body.result as { content?: unknown; structuredContent?: unknown };
    } finally {
      clearTimeout(timer);
    }
  }
}

function parseSseOrJson(text: string): {
  error?: { message?: string };
  result?: unknown;
} {
  const trimmed = text.trim();
  if (trimmed.startsWith("{")) {
    return JSON.parse(trimmed) as { error?: { message?: string }; result?: unknown };
  }
  const prefix = 'data: ';
  for (const line of trimmed.split(/\r?\n/)) {
    const s = line.trim();
    if (s.startsWith(prefix)) {
      return JSON.parse(s.slice(prefix.length)) as {
        error?: { message?: string };
        result?: unknown;
      };
    }
  }
  throw new Error("unparseable MCP response");
}
