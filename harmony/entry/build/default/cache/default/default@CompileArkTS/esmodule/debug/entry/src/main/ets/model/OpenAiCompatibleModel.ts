import http from "@ohos:net.http";
import type { LocalModel } from './LocalModel';
import type { LlmProvider } from './LlmProvider';
interface ChatMessage {
    role: string;
    content: string;
}
interface ChatRequest {
    model: string;
    messages: ChatMessage[];
    temperature: number;
}
interface ChatChoice {
    message?: ChatMessage;
}
interface ChatResponse {
    choices?: ChatChoice[];
}
export class OpenAiCompatibleModel implements LocalModel {
    private provider: LlmProvider;
    constructor(provider: LlmProvider) {
        this.provider = provider;
    }
    async complete(prompt: string): Promise<string> {
        if (!this.provider.isConfigured()) {
            throw new Error('LLM provider is not configured.');
        }
        const httpRequest = http.createHttp();
        try {
            const response = await httpRequest.request(this.provider.chatCompletionsUrl(), {
                method: http.RequestMethod.POST,
                header: {
                    'Authorization': `Bearer ${this.provider.apiKey}`,
                    'Content-Type': 'application/json; charset=utf-8',
                    'Accept': 'application/json'
                },
                extraData: JSON.stringify(this.buildRequest(prompt)),
                expectDataType: http.HttpDataType.STRING,
                connectTimeout: 20000,
                readTimeout: 60000
            });
            const statusCode = response.responseCode;
            const body = `${response.result ?? ''}`;
            if (statusCode < 200 || statusCode >= 300) {
                throw new Error(`LLM request failed with HTTP ${statusCode}: ${body}`);
            }
            return this.parseContent(body);
        }
        catch (error) {
            const message = error instanceof Error ? error.message : `${error}`;
            throw new Error(`LLM request failed: ${message}`);
        }
        finally {
            httpRequest.destroy();
        }
    }
    private buildRequest(prompt: string): ChatRequest {
        return {
            model: this.provider.model,
            messages: [
                {
                    role: 'system',
                    content: 'You are Loop, a concise ReAct agent. Reply with Thought and either Action: tool[input] or Final: answer. Use only listed tools.'
                },
                {
                    role: 'user',
                    content: prompt
                }
            ],
            temperature: 0.2
        };
    }
    private parseContent(body: string): string {
        const json = JSON.parse(body) as ChatResponse;
        const choices = json.choices;
        if (choices === undefined || choices.length === 0) {
            throw new Error('No choices returned.');
        }
        const message = choices[0].message;
        if (message === undefined || message.content === undefined) {
            throw new Error('No message content returned.');
        }
        return message.content.trim();
    }
}
