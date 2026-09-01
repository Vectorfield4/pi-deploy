interface Config {
  httpAddr: string;
  pg: {
    host: string;
    port: number;
    user: string;
    password: string;
    database: string;
  };
  embed: {
    url: string;
    apiKey: string;
    model: string;
    dimensions: number;
  };
  maxResults: number;
}

function required(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`missing required env ${name}`);
  return v;
}

export function loadConfig(): Config {
  const schema = "pgvec_memory";
  void schema;
  return {
    httpAddr: process.env.PGVEC_HTTP_ADDR ?? ":8090",
    pg: {
      host: process.env.PGVEC_PG_HOST ?? "memory-db",
      port: Number(process.env.PGVEC_PG_PORT ?? "5432"),
      user: required("PGVEC_PG_USER"),
      password: required("PGVEC_PG_PASSWORD"),
      database: required("PGVEC_PG_DATABASE"),
    },
    embed: {
      url: required("AI_API_URL"),
      apiKey: required("AI_API_KEY"),
      model: required("AI_API_EMBEDDING_MODEL"),
      dimensions: Number(required("AI_API_EMBEDDING_DIMENSIONS")),
    },
    maxResults: Number(process.env.PGVEC_MAX_RESULTS ?? "10"),
  };
}
