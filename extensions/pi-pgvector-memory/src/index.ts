import { Type } from "@sinclair/typebox";
import { JsonRpcClient } from "./client.js";

const SourceType = Type.Union([
  Type.Literal("conversation"),
  Type.Literal("document"),
  Type.Literal("observation"),
  Type.Literal("manual"),
]);

interface ToolDef {
  name: string;
  label: string;
  description: string;
  parameters: ReturnType<typeof Type.Object>;
  serverName: string;
}

const tools: ToolDef[] = [
  {
    name: "pgvec_remember",
    label: "Remember (write)",
    description:
      "Store a durable memory record in pgvector. content is the stored text (use a project:/type:/tags:... structured prefix). tags are classifier labels (anti-pattern, review-bounce, project:<name>, ...). source_type enum: conversation|document|observation|manual. valid_until is ISO date for TTL. idempotency_key dedups. Returns { evidence_id }.",
    parameters: Type.Object({
      content: Type.String({ minLength: 1 }),
      tags: Type.Optional(Type.Array(Type.String())),
      source_type: SourceType,
      valid_until: Type.Optional(Type.String()),
      confidence: Type.Optional(Type.String()),
      supersedes_evidence_ids: Type.Optional(Type.Array(Type.String())),
      idempotency_key: Type.String({ minLength: 1 }),
    }),
    serverName: "remember",
  },
  {
    name: "pgvec_recall_memory",
    label: "Recall memory",
    description:
      "Search memory by semantic similarity to query. Optionally tag-filter (must equal a stored tag). Returns { results: [{evidence_id, content, tags, space_kind, valid_until, confidence}] }. Read content.",
    parameters: Type.Object({
      query: Type.String({ minLength: 1 }),
      limit: Type.Optional(Type.Number({ minimum: 1, maximum: 50 })),
      tag: Type.Optional(Type.String()),
    }),
    serverName: "recall_memory",
  },
  {
    name: "pgvec_retract_evidence",
    label: "Retract evidence",
    description:
      "Retire memory records by evidence_id (from recall). reason required. Returns { retracted: N }.",
    parameters: Type.Object({
      evidence_ids: Type.Array(Type.String(), { minItems: 1 }),
      reason: Type.String({ minLength: 1 }),
      idempotency_key: Type.Optional(Type.String()),
    }),
    serverName: "retract_evidence",
  },
  {
    name: "pgvec_gc",
    label: "Memory GC",
    description:
      "Retire records whose valid_until has passed. Returns { scanned, retracted }. Called by QA after iterations.",
    parameters: Type.Object({
      limit: Type.Optional(Type.Number({ minimum: 1, maximum: 100 })),
    }),
    serverName: "gc",
  },
];

export default async function (pi: {
  registerTool: (tool: {
    name: string;
    label: string;
    description: string;
    parameters: unknown;
    execute: (
      toolCallId: string,
      params: Record<string, unknown>,
      signal: AbortSignal,
      onUpdate: (ev: unknown) => void,
      ctx: unknown
    ) => Promise<unknown>;
  }) => void;
}): Promise<void> {
  const endpoint = process.env.PGVEC_URL ?? "http://pgvec-memory:8090/mcp";
  const owner = process.env.PGVEC_OWNER ?? "system";
  const client = new JsonRpcClient({
    endpoint,
    headers: { "X-Pi-Owner": owner },
  });

  for (const t of tools) {
    pi.registerTool({
      name: t.name,
      label: t.label,
      description: t.description,
      parameters: t.parameters,
      async execute(_toolCallId, params) {
        const raw = await client.call("tools/call", {
          name: t.serverName,
          arguments: params ?? {},
        });
        return extractText(raw);
      },
    });
  }
}

function extractText(raw: unknown): string {
  const result = raw as { content?: { text?: string }[]; isError?: boolean };
  if (result?.isError) {
    throw new Error(result.content?.[0]?.text ?? "MCP tool error");
  }
  return result.content?.[0]?.text ?? "ok";
}
