import { Type } from "@sinclair/typebox";
import { readFileSync, existsSync } from "node:fs";

type ImageApi = "openai-images" | "openai-chat-image" | "google-generative-ai-image";

interface Config {
  provider: string;
  model: string;
  baseUrl: string;
  apiKey: string;
  api: ImageApi;
  saveDir: string;
}

const DEFAULTS: Config = {
  provider: "openrouter",
  model: "black_forest_labs/flux-2-pro",
  baseUrl: "https://openrouter.ai/api/v1",
  apiKey: "",
  api: "openai-chat-image",
  saveDir: "/root/.pi/agent/generated-images",
};

const OPENAI_SIZES: Record<string, string> = {
  "1:1": "1024x1024",
  "16:9": "1536x1024",
  "9:16": "1024x1536",
  "4:3": "1536x1024",
  "3:4": "1024x1536",
  "3:2": "1536x1024",
  "2:3": "1024x1536",
};

function inferApi(provider: string, apiField?: string): ImageApi {
  if (apiField === "openai-images" || apiField === "openai-chat-image" || apiField === "google-generative-ai-image") return apiField;
  if (provider === "openai") return "openai-images";
  if (provider === "google") return "google-generative-ai-image";
  return "openai-chat-image";
}

function loadConfig(): Config {
  const env = {
    provider: process.env.OPENAI_IMAGE_PROVIDER,
    model: process.env.OPENAI_IMAGE_MODEL,
    baseUrl: process.env.OPENAI_IMAGE_BASE_URL ?? process.env.IMAGE_API_URL,
    apiKey: process.env.OPENAI_IMAGE_API_KEY ?? process.env.IMAGE_API_KEY,
  };

  let file: Partial<Config> | undefined;
  const candidates = [
    process.env.OPENAI_IMAGE_CONFIG,
    "/root/.pi/agent/settings/pi-openai-image-generation.json",
    ".pi/settings/pi-openai-image-generation.json",
  ].filter((p): p is string => Boolean(p));
  for (const p of candidates) {
    try {
      file = JSON.parse(readFileSync(p, "utf8"));
      break;
    } catch {}
  }

  const api = inferApi(env.provider ?? file?.provider ?? DEFAULTS.provider, file?.api);

  return {
    provider: env.provider ?? file?.provider ?? DEFAULTS.provider,
    model: env.model ?? file?.model ?? DEFAULTS.model,
    baseUrl: env.baseUrl ?? file?.baseUrl ?? DEFAULTS.baseUrl,
    apiKey: env.apiKey ?? file?.apiKey ?? DEFAULTS.apiKey,
    api,
    saveDir: file?.saveDir ?? DEFAULTS.saveDir,
  };
}

function shortHash(s: string): string {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
  return (h >>> 0).toString(16).padStart(8, "0").slice(0, 8);
}

function isRecoverableError(message: string): { code: string } | null {
  if (/(insufficient balance|payment required|exceeded.*monthly.*quota|billing|no (enough |available )?credits|credit.*insufficient)/i.test(message))
    return { code: "insufficient_balance" };
  if (/(rate\s?limit|too many requests|429)/i.test(message))
    return { code: "rate_limited" };
  return null;
}

// ── API implementations ────────────────────────────────────────────

interface GeneratedImage {
  data: string; // base64
  mimeType: string;
}

async function generateViaOpenAIImages(
  cfg: Config,
  prompt: string,
  aspectRatio: string,
  signal?: AbortSignal,
): Promise<GeneratedImage> {
  const size = OPENAI_SIZES[aspectRatio] || "1024x1024";
  const res = await fetch(`${cfg.baseUrl}/images/generations`, {
    method: "POST",
    headers: { Authorization: `Bearer ${cfg.apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({ model: cfg.model, prompt, n: 1, size, response_format: "b64_json" }),
    signal,
  });
  if (!res.ok) throw new Error(`OpenAI images failed (${res.status}): ${await res.text()}`);
  const json = (await res.json()) as { data: Array<{ b64_json?: string }> };
  if (!json.data?.[0]?.b64_json) throw new Error("OpenAI returned no image data");
  return { data: json.data[0].b64_json, mimeType: "image/png" };
}

async function generateViaChatImage(
  cfg: Config,
  prompt: string,
  aspectRatio: string,
  signal?: AbortSignal,
): Promise<GeneratedImage> {
  const body: Record<string, unknown> = {
    model: cfg.model,
    messages: [{ role: "user", content: prompt }],
    modalities: ["image"],
  };
  if (aspectRatio && aspectRatio !== "1:1") {
    body.image_config = { aspect_ratio: aspectRatio };
  }

  const res = await fetch(`${cfg.baseUrl}/chat/completions`, {
    method: "POST",
    headers: { Authorization: `Bearer ${cfg.apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal,
  });
  if (!res.ok) throw new Error(`Chat image failed (${res.status}): ${await res.text()}`);

  const json = (await res.json()) as {
    choices: Array<{ message: { images?: Array<{ image_url: { url: string } }> } }>;
  };
  const images = json.choices?.[0]?.message?.images;
  if (!images?.[0]?.image_url?.url) throw new Error("No images in response (model may not support image generation)");

  const url = images[0].image_url.url;
  if (url.startsWith("data:")) {
    const commaIdx = url.indexOf(",");
    const mimeType = url.slice(0, commaIdx).match(/data:(.*);/)?.[1] || "image/png";
    return { data: url.slice(commaIdx + 1), mimeType };
  }
  const imgRes = await fetch(url, { signal });
  const buf = await imgRes.arrayBuffer();
  return { data: Buffer.from(buf).toString("base64"), mimeType: imgRes.headers.get("content-type") || "image/png" };
}

async function generateViaGoogleImage(
  cfg: Config,
  prompt: string,
  signal?: AbortSignal,
): Promise<GeneratedImage> {
  const res = await fetch(`${cfg.baseUrl}/models/${cfg.model}:generateContent?key=${cfg.apiKey}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ role: "user", parts: [{ text: prompt }] }],
      generationConfig: { responseModalities: ["TEXT", "IMAGE"] },
    }),
    signal,
  });
  if (!res.ok) throw new Error(`Google image failed (${res.status}): ${await res.text()}`);

  const json = (await res.json()) as {
    candidates?: Array<{ content?: { parts?: Array<{ inlineData?: { mimeType?: string; data?: string } }> } }>;
  };
  const parts = json.candidates?.[0]?.content?.parts;
  if (!parts) throw new Error("Google returned no content");
  for (const p of parts) {
    if (p.inlineData?.data) return { data: p.inlineData.data, mimeType: p.inlineData.mimeType || "image/png" };
  }
  throw new Error("Google returned no image data");
}

async function generate(
  cfg: Config,
  prompt: string,
  aspectRatio: string,
  signal?: AbortSignal,
): Promise<GeneratedImage> {
  switch (cfg.api) {
    case "openai-images":       return generateViaOpenAIImages(cfg, prompt, aspectRatio, signal);
    case "openai-chat-image":   return generateViaChatImage(cfg, prompt, aspectRatio, signal);
    case "google-generative-ai-image": return generateViaGoogleImage(cfg, prompt, signal);
  }
}

// ── Extension entry ────────────────────────────────────────────────

export default async function (pi: {
  registerTool: (tool: {
    name: string;
    label: string;
    description: string;
    parameters: unknown;
    execute: (toolCallId: string, params: Record<string, unknown>, signal: AbortSignal) => Promise<unknown>;
  }) => void;
}): Promise<void> {
  pi.registerTool({
    name: "generate_image",
    label: "Generate image (OpenAI-compatible)",
    description:
      "Generate an image from a text prompt via OpenAI-compatible endpoints (OpenRouter, OpenAI direct, Google). Provider/model/baseUrl come from env OPENAI_IMAGE_*, then .pi/settings/pi-openai-image-generation.json, then env IMAGE_API_URL/IMAGE_API_KEY. Primary tool: hf_generate_image.",
    parameters: Type.Object({
      prompt: Type.String({ minLength: 1 }),
      aspectRatio: Type.Optional(Type.String({ default: "1:1" })),
      save: Type.Optional(Type.Union([Type.Literal("none"), Type.Literal("custom")], { default: "none" })),
      saveDir: Type.Optional(Type.String()),
    }),
    async execute(_toolCallId, params, signal) {
      const prompt = String(params.prompt ?? "");
      const aspect = String(params.aspectRatio ?? "1:1");
      const save = String(params.save ?? "none");

      const cfg = loadConfig();
      if (!cfg.apiKey) throw new Error("No API key: set OPENAI_IMAGE_API_KEY or IMAGE_API_KEY env");
      if (!cfg.baseUrl) throw new Error("No base URL: set OPENAI_IMAGE_BASE_URL or IMAGE_API_URL env");

      const saveDir = String(params.saveDir ?? cfg.saveDir);

      try {
        const img = await generate(cfg, prompt, aspect, signal);

        let savedPath: string | undefined;
        let saveError: string | undefined;

        if (save === "custom") {
          try {
            const fs = await import("node:fs/promises");
            const path = await import("node:path");
            const ext = img.mimeType.includes("jpeg") || img.mimeType.includes("jpg") ? "jpg"
              : img.mimeType.includes("webp") ? "webp" : "png";
            const ts = new Date().toISOString().replace(/[:.]/g, "-");
            const base = path.join(saveDir, `image-${ts}-${shortHash(prompt + Date.now())}.${ext}`);
            await fs.mkdir(saveDir, { recursive: true });
            await fs.writeFile(base, Buffer.from(img.data, "base64"));
            savedPath = base;
          } catch (e) {
            saveError = e instanceof Error ? e.message : String(e);
          }
        }

        return {
          content: [
            { type: "text" as const, text: `Generated image (${cfg.provider}/${cfg.model}, ${cfg.api}, ${aspect}).${savedPath ? ` Saved: ${savedPath}` : ""}` },
            { type: "image" as const, data: img.data, mimeType: img.mimeType },
          ],
          details: { provider: cfg.provider, model: cfg.model, api: cfg.api, aspectRatio: aspect, savedPath, saveError, saveMode: save },
        };
      } catch (e) {
        const message = e instanceof Error ? e.message : String(e);
        const rec = isRecoverableError(message);
        const err = new Error(`generate_image failed: ${message}`);
        if (rec) (err as Error & { code?: string }).code = rec.code;
        throw err;
      }
    },
  });
}