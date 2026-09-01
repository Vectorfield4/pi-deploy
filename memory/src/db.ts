import pg from "pg";

export interface MemoryRecordRow {
  id: string;
  content: string;
  tags: string[];
  source_type: string;
  valid_until: Date | null;
  confidence: string | null;
  supersedes: string[] | null;
  owner: string;
  created_at: Date;
}

export interface DbOpts {
  host: string;
  port: number;
  user: string;
  password: string;
  database: string;
  dimensions: number;
}

export class MemoryDb {
  private pool: pg.Pool;
  private readonly dimensions: number;

  constructor(opts: DbOpts) {
    this.pool = new pg.Pool({
      host: opts.host,
      port: opts.port,
      user: opts.user,
      password: opts.password,
      database: opts.database,
      max: 10,
    });
    this.dimensions = opts.dimensions;
  }

  async init(): Promise<void> {
    await this.pool.query(
      `CREATE SCHEMA IF NOT EXISTS pgvec_memory`
    );
    await this.pool.query(`
      CREATE TABLE IF NOT EXISTS pgvec_memory.records (
        id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        content       text NOT NULL,
        tags          text[] NOT NULL DEFAULT '{}',
        source_type   text NOT NULL,
        valid_until   date NULL,
        confidence    text NULL,
        supersedes    uuid[] NULL,
        owner         text NOT NULL DEFAULT 'system',
        created_at    timestamptz NOT NULL DEFAULT now(),
        expired_at    timestamptz NULL,
        embedding     vector(${this.dimensions})
      )
    `);
    await this.pool.query(
      `CREATE INDEX IF NOT EXISTS records_embedding_hnsw
        ON pgvec_memory.records USING hnsw (embedding vector_cosine_ops)`
    );
    await this.pool.query(
      `CREATE UNIQUE INDEX IF NOT EXISTS records_tag_idx
        ON pgvec_memory.records (owner, content, created_at)`
    );
  }

  async insert(
    values: {
      content: string;
      tags: string[];
      source_type: string;
      valid_until: string | null;
      confidence: string | null;
      supersedes: string[] | null;
      owner: string;
      embedding: number[];
    }
  ): Promise<string> {
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      if (values.supersedes && values.supersedes.length > 0) {
        await client.query(
          `UPDATE pgvec_memory.records
             SET expired_at = now()
           WHERE id = ANY($1::uuid[]) AND owner = $2`,
          [values.supersedes, values.owner]
        );
      }
      const res = await client.query(
        `INSERT INTO pgvec_memory.records
           (content, tags, source_type, valid_until, confidence, supersedes, owner, embedding)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
         RETURNING id`,
        [
          values.content,
          values.tags,
          values.source_type,
          values.valid_until,
          values.confidence,
          values.supersedes,
          values.owner,
          `[${values.embedding.join(",")}]`,
        ]
      );
      await client.query("COMMIT");
      return res.rows[0].id as string;
    } catch (err) {
      await client.query("ROLLBACK");
      throw err;
    } finally {
      client.release();
    }
  }

  async recall(
    query: {
      embedding: number[];
      limit: number;
      tag?: string | null;
      includeExpired?: boolean;
    }
  ): Promise<MemoryRecordRow[]> {
    const conditions = ["expired_at IS NULL"];
    const params: unknown[] = [`[${query.embedding.join(",")}]`];
    if (!query.includeExpired) {
      conditions.push("(valid_until IS NULL OR valid_until >= CURRENT_DATE)");
    }
    if (query.tag) {
      params.push(query.tag);
      conditions.push(`$2::text = ANY(tags)`);
    }
    params.push(query.limit);
    const where = conditions.join(" AND ");
    const res = await this.pool.query(
      `SELECT id, content, tags, source_type, valid_until, confidence, supersedes, owner, created_at
         FROM pgvec_memory.records
        WHERE ${where}
        ORDER BY embedding <=> $1::vector
        LIMIT $${params.length}`,
      params
    );
    return res.rows as MemoryRecordRow[];
  }

  async retract(
    opts: { evidenceIds: string[]; reason: string; owner: string }
  ): Promise<number> {
    void opts.reason;
    const res = await this.pool.query(
      `UPDATE pgvec_memory.records
          SET expired_at = now()
        WHERE id = ANY($1::uuid[]) AND owner = $2 AND expired_at IS NULL`,
      [opts.evidenceIds, opts.owner]
    );
    return res.rowCount ?? 0;
  }

  async gc(limit: number): Promise<{ retracted: number; scanned: number }> {
    const scanned = await this.pool.query(
      `SELECT count(*)::int AS n
         FROM pgvec_memory.records
        WHERE expired_at IS NULL AND valid_until IS NOT NULL AND valid_until < CURRENT_DATE`
    );
    const res = await this.pool.query(
      `UPDATE pgvec_memory.records
          SET expired_at = now()
        WHERE id IN (
          SELECT id FROM pgvec_memory.records
           WHERE expired_at IS NULL AND valid_until IS NOT NULL AND valid_until < CURRENT_DATE
           LIMIT $1
        )`,
      [limit]
    );
    return { retracted: res.rowCount ?? 0, scanned: scanned.rows[0].n as number };
  }

  async close(): Promise<void> {
    await this.pool.end();
  }
}
