export interface RpcOptions {
    endpoint: string;
    headers?: Record<string, string>;
    timeoutMs?: number;
}
export declare class JsonRpcClient {
    private readonly endpoint;
    private readonly headers;
    private readonly timeoutMs;
    constructor(opts: RpcOptions);
    call(method: string, params: Record<string, unknown>): Promise<unknown>;
}
