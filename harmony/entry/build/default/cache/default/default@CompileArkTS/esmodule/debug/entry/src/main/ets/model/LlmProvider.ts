import util from "@ohos:util";
import type common from "@ohos:app.ability.common";
interface LlmConfigJson {
    providerName?: string;
    apiKey?: string;
    baseUrl?: string;
    model?: string;
}
export class LlmProvider {
    readonly name: string;
    readonly apiKey: string;
    readonly baseUrl: string;
    readonly model: string;
    constructor(name: string, apiKey: string, baseUrl: string, model: string) {
        this.name = name;
        this.apiKey = apiKey;
        this.baseUrl = LlmProvider.trimTrailingSlash(baseUrl);
        this.model = model;
    }
    isConfigured(): boolean {
        return this.apiKey.trim().length > 0
            && this.baseUrl.trim().length > 0
            && this.model.trim().length > 0;
    }
    chatCompletionsUrl(): string {
        return `${this.baseUrl}/chat/completions`;
    }
    static async fromContext(context: common.UIAbilityContext): Promise<LlmProvider> {
        try {
            const raw = await context.resourceManager.getRawFileContent('llm_config.json');
            const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
            const bytes = raw instanceof ArrayBuffer ? new Uint8Array(raw) : new Uint8Array(raw.buffer);
            const text = decoder.decodeWithStream(bytes, { stream: false });
            const json = JSON.parse(text) as LlmConfigJson;
            return new LlmProvider(json.providerName ?? '', json.apiKey ?? '', json.baseUrl ?? '', json.model ?? '');
        }
        catch (_error) {
            return new LlmProvider('', '', '', '');
        }
    }
    private static trimTrailingSlash(value: string): string {
        let trimmed = value.trim();
        while (trimmed.endsWith('/')) {
            trimmed = trimmed.substring(0, trimmed.length - 1);
        }
        return trimmed;
    }
}
