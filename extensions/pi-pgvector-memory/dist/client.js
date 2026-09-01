export class JsonRpcClient {
    endpoint;
    headers;
    timeoutMs;
    constructor(opts) {
        this.endpoint = opts.endpoint.replace(/\/+$/, "");
        this.headers = opts.headers ?? {};
        this.timeoutMs = opts.timeoutMs ?? 30000;
    }
    async call(method, params) {
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
                throw new Error(body.error.message ?? `MCP ${method} error`);
            }
            return body.result;
        }
        finally {
            clearTimeout(timer);
        }
    }
}
function parseSseOrJson(text) {
    const trimmed = text.trim();
    if (trimmed.startsWith("{")) {
        return JSON.parse(trimmed);
    }
    const prefix = 'data: ';
    for (const line of trimmed.split(/\r?\n/)) {
        const s = line.trim();
        if (s.startsWith(prefix)) {
            return JSON.parse(s.slice(prefix.length));
        }
    }
    throw new Error("unparseable MCP response");
}
//# sourceMappingURL=client.js.map