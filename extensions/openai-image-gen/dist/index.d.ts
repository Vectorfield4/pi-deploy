export default function (pi: {
    registerTool: (tool: {
        name: string;
        label: string;
        description: string;
        parameters: unknown;
        execute: (toolCallId: string, params: Record<string, unknown>, signal: AbortSignal) => Promise<unknown>;
    }) => void;
}): Promise<void>;
