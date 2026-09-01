import { MemoryDb, MemoryRecordRow } from "./db.js";
import { EmbeddingStore } from "./embeddings.js";

export interface Tool {
  name: string;
  description: string;
  inputSchema: Record<string, unknown>;
  run(args: Record<string, unknown>, ctx: ToolContext): Promise<unknown>;
}

export interface ToolContext {
  db: MemoryDb;
  embed: EmbeddingStore;
  owner: string;
  maxResults: number;
}

const SOURCE_TYPES = new Set([
  "conversation",
  "document",
  "observation",
  "manual",
]);

function asString(v: unknown, name: string): string {
  if (typeof v !== "string" || v.length === 0) {
    throw new Error(`${name} must be a non-empty string`);
  }
  return v;
}

function rowToResult(r: MemoryRecordRow) {
  return {
    evidence_id: r.id,
    content: r.content,
    space_kind: r.source_type,
    tags: r.tags,
    valid_until: r.valid_until ? r.valid_until.toISOString().slice(0, 10) : null,
    confidence: r.confidence,
    owner: r.owner,
    created_at: r.created_at.toISOString(),
  };
}

const tools: Tool[] = [
  {
    name: "remember",
    description:
      "Store a durable memory record. content is the stored text (structure with a project:/type:/tags:... prefix for filtering). tags are the classifier labels (e.g. anti-pattern, review-bounce, project:<name>). source_type enum: conversation|document|observation|manual. valid_until is an ISO date for TTL decay (memory-gc retires past it). idempotency_key dedups repeated writes. Returns { evidence_id }.",
    inputSchema: {
      type: "object",
      properties: {
        content: { type: "string" },
        tags: { type: "array", items: { type: "string" } },
        source_type: {
          type: "string",
          enum: ["conversation", "document", "observation", "manual"],
        },
        valid_until: { type: "string" },
        confidence: { type: "string" },
        supersedes_evidence_ids: {
          type: "array",
          items: { type: "string" },
        },
        idempotency_key: { type: "string" },
      },
      required: ["content", "source_type", "idempotency_key"],
      additionalProperties: false,
    },
    async run(args, ctx) {
      const content = asString(args.content, "content");
      const sourceType = asString(args.source_type, "source_type");
      if (!SOURCE_TYPES.has(sourceType)) {
        throw new Error(`source_type must be one of ${[...SOURCE_TYPES].join(", ")}`);
      }
      const idempotencyKey = asString(args.idempotency_key, "idempotency_key");
      const tags = Array.isArray(args.tags)
        ? args.tags.filter((t): t is string => typeof t === "string")
        : [];
      const validUntil =
        typeof args.valid_until === "string" && args.valid_until.length > 0
          ? args.valid_until
          : null;
      const confidence =
        typeof args.confidence === "string" && args.confidence.length > 0
          ? args.confidence
          : null;
      const supersedes = Array.isArray(args.supersedes_evidence_ids)
        ? args.supersedes_evidence_ids.filter((t): t is string => typeof t === "string")
        : null;

      const [embedding] = await ctx.embed.embed([content]);
      const existing = await ctx.db.recall({
        embedding,
        limit: 1,
      });

      // Idempotency: exact content + owner already present and non-expired => reuse.
      const dup = existing.find(
        (r) => r.content === content && r.owner === ctx.owner
      );
      if (dup) {
        return { evidence_id: dup.id, deduped: true, idempotency_key: idempotencyKey };
      }

      const id = await ctx.db.insert({
        content,
        tags,
        source_type: sourceType,
        valid_until: validUntil,
        confidence,
        supersedes,
        owner: ctx.owner,
        embedding,
      });
      return { evidence_id: id, deduped: false, idempotency_key: idempotencyKey };
    },
  },
  {
    name: "recall_memory",
    description:
      "Search memory by semantic similarity to query. Optionally filter by a single tag (tag matches a tag in the record's tags list). Returns { results: [{evidence_id, content, tags, space_kind, valid_until, confidence}] }. Read content, never raw. limit caps results (default from server, max 50).",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string" },
        limit: { type: "number" },
        tag: { type: "string" },
      },
      required: ["query"],
      additionalProperties: false,
    },
    async run(args, ctx) {
      const query = asString(args.query, "query");
      const limit =
        typeof args.limit === "number"
          ? Math.min(Math.max(1, Math.floor(args.limit)), 50)
          : ctx.maxResults;
      const tag =
        typeof args.tag === "string" && args.tag.length > 0 ? args.tag : null;
      const [embedding] = await ctx.embed.embed([query]);
      const rows = await ctx.db.recall({ embedding, limit, tag });
      return { results: rows.map(rowToResult) };
    },
  },
  {
    name: "retract_evidence",
    description:
      "Retire caller-owned evidence records by id. reason is required for provenance. Returns { retracted: N }.",
    inputSchema: {
      type: "object",
      properties: {
        evidence_ids: { type: "array", items: { type: "string" } },
        reason: { type: "string" },
        idempotency_key: { type: "string" },
      },
      required: ["evidence_ids", "reason"],
      additionalProperties: false,
    },
    async run(args, ctx) {
      const ids = Array.isArray(args.evidence_ids)
        ? args.evidence_ids.filter((t): t is string => typeof t === "string")
        : [];
      if (ids.length === 0) throw new Error("evidence_ids must be a non-empty array");
      asString(args.reason, "reason");
      const retracted = await ctx.db.retract({
        evidenceIds: ids,
        reason: String(args.reason),
        owner: ctx.owner,
      });
      return { retracted };
    },
  },
  {
    name: "gc",
    description:
      "Retire records whose valid_until has passed (memory GC). Scans, retires up to limit. Returns { scanned, retracted }.",
    inputSchema: {
      type: "object",
      properties: {
        limit: { type: "number" },
      },
      additionalProperties: false,
    },
    async run(args, ctx) {
      const limit =
        typeof args.limit === "number"
          ? Math.min(Math.max(1, Math.floor(args.limit)), 100)
          : 20;
      return ctx.db.gc(limit);
    },
  },
];

export function listTools(): { name: string; description: string; inputSchema: unknown }[] {
  return tools.map((t) => ({
    name: t.name,
    description: t.description,
    inputSchema: t.inputSchema,
  }));
}

export async function callTool(
  name: string,
  args: Record<string, unknown>,
  ctx: ToolContext
): Promise<unknown> {
  const tool = tools.find((t) => t.name === name);
  if (!tool) throw new Error(`unknown tool: ${name}`);
  return tool.run(args ?? {}, ctx);
}
