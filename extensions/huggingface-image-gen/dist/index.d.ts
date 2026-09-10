export default function (pi: {
    registerTool: (tool: {
        name: string;
        label: string;
        description: string;
        parameters: unknown;
        execute: (toolCallId: string, params: Record<string, unknown>, signal: AbortSignal, onUpdate: (ev: unknown) => void, ctx: unknown) => Promise<unknown>;
    }) => void;
}): Promise<void>;
