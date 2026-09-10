import { Type } from "@sinclair/typebox";
import { InferenceClient } from "@huggingface/inference";
import { readFileSync } from "node:fs";
const DEFAULT_MODEL = "black-forest-labs/FLUX.2-klein-9B:preferred";
const DEFAULT_PROVIDER = "auto";
const DEFAULT_SAVE_DIR = "/root/.pi/agent/generated-images";
const ASPECT_SIZES = {
    "1:1": { width: 1024, height: 1024 },
    "2:3": { width: 768, height: 1152 },
    "3:2": { width: 1152, height: 768 },
    "3:4": { width: 768, height: 1024 },
    "4:3": { width: 1024, height: 768 },
    "4:5": { width: 1024, height: 1280 },
    "5:4": { width: 1280, height: 1024 },
    "9:16": { width: 720, height: 1280 },
    "16:9": { width: 1280, height: 720 },
    "21:9": { width: 1344, height: 576 },
};
function aspectToSize(aspect) {
    return ASPECT_SIZES[aspect] ?? ASPECT_SIZES["1:1"];
}
function shortHash(s) {
    let h = 0;
    for (let i = 0; i < s.length; i++)
        h = (h * 31 + s.charCodeAt(i)) | 0;
    return (h >>> 0).toString(16).padStart(8, "0").slice(0, 8);
}
function isInsufficientBalance(message) {
    return /(insufficient balance|payment required|exceeded.*monthly.*quota|monthly.*quota.*exceeded|billing|no (enough |available )?(credits|funds)|credit.*insufficient)/i.test(message);
}
function isRateLimited(message) {
    return /(rate\s?limit|too many requests|429)/i.test(message);
}
function loadConfig() {
    const envProvider = process.env.HF_IMAGE_PROVIDER;
    const envModel = process.env.HF_IMAGE_MODEL;
    const envSaveDir = process.env.HF_IMAGE_SAVE_DIR;
    let file;
    const candidates = [
        process.env.HF_IMAGE_CONFIG,
        "/root/.pi/agent/settings/pi-huggingface-image-gen.json",
        ".pi/settings/pi-huggingface-image-gen.json",
    ].filter((p) => Boolean(p));
    for (const p of candidates) {
        try {
            file = JSON.parse(readFileSync(p, "utf8"));
            break;
        }
        catch {
            // try next candidate
        }
    }
    return {
        provider: envProvider ?? file?.provider ?? DEFAULT_PROVIDER,
        model: envModel ?? file?.model ?? DEFAULT_MODEL,
        saveDir: envSaveDir ?? file?.saveDir ?? DEFAULT_SAVE_DIR,
    };
}
export default async function (pi) {
    pi.registerTool({
        name: "hf_generate_image",
        label: "Generate image (HuggingFace)",
        description: "Generate an image from a text prompt via the HuggingFace Inference API router. Provider/model come from the tool params, else HF_IMAGE_PROVIDER/HF_IMAGE_MODEL env, else the settings file, else defaults. Returns details.savedPath when save=custom. Fallback tool: generate_image. On failure throws with error.code: 'insufficient_balance' (HF billing/credits exhausted) or 'rate_limited'; route to fallback tool in those cases.",
        parameters: Type.Object({
            prompt: Type.String({ minLength: 1 }),
            provider: Type.Optional(Type.String()),
            model: Type.Optional(Type.String()),
            aspectRatio: Type.Optional(Type.String({ default: "1:1" })),
            save: Type.Optional(Type.Union([Type.Literal("none"), Type.Literal("custom")], { default: "none" })),
            saveDir: Type.Optional(Type.String()),
        }),
        async execute(_toolCallId, params, _signal) {
            const prompt = String(params.prompt ?? "");
            const aspect = String(params.aspectRatio ?? "1:1");
            const save = String(params.save ?? "none");
            const token = process.env.HF_TOKEN;
            if (!token) {
                throw new Error("HF_TOKEN is not set in the environment");
            }
            const cfg = loadConfig();
            const provider = String(params.provider ?? cfg.provider);
            const model = String(params.model ?? cfg.model);
            const saveDir = String(params.saveDir ?? cfg.saveDir);
            try {
                const client = new InferenceClient(token);
                const { width, height } = aspectToSize(aspect);
                const blob = await client.textToImage({
                    provider: provider,
                    model,
                    inputs: prompt,
                    parameters: { width, height },
                }, { outputType: "blob" });
                const arrayBuffer = await blob.arrayBuffer();
                const buf = Buffer.from(arrayBuffer);
                const mimeType = blob.type || "image/png";
                let savedPath;
                let saveError;
                if (save === "custom") {
                    try {
                        const fs = await import("node:fs/promises");
                        const path = await import("node:path");
                        const ext = mimeType.includes("jpeg") || mimeType.includes("jpg") ? "jpg" : mimeType.includes("webp") ? "webp" : "png";
                        const ts = new Date().toISOString().replace(/[:.]/g, "-");
                        const base = path.join(saveDir, `image-${ts}-${shortHash(prompt + Date.now())}.${ext}`);
                        await fs.mkdir(saveDir, { recursive: true });
                        await fs.writeFile(base, buf);
                        savedPath = base;
                    }
                    catch (e) {
                        saveError = e instanceof Error ? e.message : String(e);
                    }
                }
                return {
                    content: [
                        {
                            type: "text",
                            text: `Generated image via HuggingFace (${model}, ${provider}, ${aspect}).${savedPath ? ` Saved to: ${savedPath}` : ""}`,
                        },
                        { type: "image", data: buf.toString("base64"), mimeType },
                    ],
                    details: {
                        provider,
                        model,
                        aspectRatio: aspect,
                        savedPath,
                        saveError,
                        saveMode: save,
                    },
                };
            }
            catch (e) {
                const message = e instanceof Error ? e.message : String(e);
                const code = isInsufficientBalance(message) ? "insufficient_balance" : isRateLimited(message) ? "rate_limited" : undefined;
                const err = new Error(`hf_generate_image failed: ${message}`);
                if (code)
                    err.code = code;
                throw err;
            }
        },
    });
}
//# sourceMappingURL=index.js.map