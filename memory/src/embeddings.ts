export interface EmbeddingStore {
  embed(texts: string[]): Promise<number[][]>;
}

export class ApiEmbeddingStore implements EmbeddingStore {
  private readonly url: string;
  private readonly apiKey: string;
  private readonly model: string;

  constructor(opts: { url: string; apiKey: string; model: string }) {
    this.url = opts.url.replace(/\/+$/, "") + "/embeddings";
    this.apiKey = opts.apiKey;
    this.model = opts.model;
  }

  async embed(texts: string[]): Promise<number[][]> {
    if (texts.length === 0) return [];
    const res = await fetch(this.url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${this.apiKey}`,
      },
      body: JSON.stringify({ model: this.model, input: texts }),
    });
    if (!res.ok) {
      const body = await res.text().catch(() => "");
      throw new Error(`embedding request failed: ${res.status} ${body}`.trim());
    }
    const data = (await res.json()) as {
      data: { index: number; embedding: number[] }[];
    };
    const out = new Array<number[]>(texts.length);
    for (const item of data.data) {
      out[item.index] = item.embedding;
    }
    return out;
  }
}
