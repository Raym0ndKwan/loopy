import { AgentEvent, AgentEventKind } from "@bundle:com.example.loop/entry/ets/agent/AgentEvent";
import type { ToolRegistry } from './ToolRegistry';
import type { LocalModel } from '../model/LocalModel';
export type AgentListener = (event: AgentEvent) => void;
class ToolCall {
    name: string;
    input: string;
    constructor(name: string, input: string) {
        this.name = name;
        this.input = input;
    }
}
export class ReActAgentRunner {
    private model: LocalModel;
    private tools: ToolRegistry;
    private maxSteps: number;
    constructor(model: LocalModel, tools: ToolRegistry, maxSteps: number) {
        this.model = model;
        this.tools = tools;
        this.maxSteps = maxSteps;
    }
    async run(task: string, listener: AgentListener): Promise<void> {
        const scratchpad: string[] = [];
        for (let step = 0; step < this.maxSteps; step++) {
            let response: string;
            try {
                response = await this.model.complete(this.buildPrompt(task, scratchpad));
            }
            catch (error) {
                const message = error instanceof Error ? error.message : `${error}`;
                listener(new AgentEvent(AgentEventKind.ERROR, message));
                return;
            }
            this.emitResponse(response, listener);
            const finalAnswer = this.readLineValue(response, 'Final:');
            if (finalAnswer !== null) {
                listener(new AgentEvent(AgentEventKind.FINAL, finalAnswer));
                return;
            }
            const call = this.parseAction(response);
            if (call === null) {
                listener(new AgentEvent(AgentEventKind.ERROR, 'Model did not return an Action or Final answer.'));
                return;
            }
            listener(new AgentEvent(AgentEventKind.ACTION, `${call.name}(${call.input})`));
            const observation = this.tools.run(call.name, call.input);
            scratchpad.push(response);
            scratchpad.push(`Observation: ${observation}`);
            listener(new AgentEvent(AgentEventKind.OBSERVATION, observation));
        }
        listener(new AgentEvent(AgentEventKind.ERROR, `Stopped after ${this.maxSteps} steps without a final answer.`));
    }
    private buildPrompt(task: string, scratchpad: string[]): string {
        let prompt = 'You are a local HarmonyOS ReAct agent.\n';
        prompt += 'Use Thought, Action, Observation, and Final.\n\n';
        prompt += 'Tools:\n';
        prompt += this.tools.describeTools();
        prompt += '\nUser task:\n';
        prompt += task;
        prompt += '\n\n';
        for (const item of scratchpad) {
            prompt += `${item}\n`;
        }
        return prompt;
    }
    private emitResponse(response: string, listener: AgentListener): void {
        const thought = this.readLineValue(response, 'Thought:');
        if (thought !== null) {
            listener(new AgentEvent(AgentEventKind.THOUGHT, thought));
        }
    }
    private readLineValue(text: string, prefix: string): string | null {
        const lines = text.split(/\r?\n/);
        for (const line of lines) {
            if (line.startsWith(prefix)) {
                return line.substring(prefix.length).trim();
            }
        }
        return null;
    }
    private parseAction(response: string): ToolCall | null {
        const action = this.readLineValue(response, 'Action:');
        if (action === null) {
            return null;
        }
        const open = action.indexOf('[');
        const close = action.lastIndexOf(']');
        if (open <= 0 || close < open) {
            return null;
        }
        const name = action.substring(0, open).trim();
        const input = action.substring(open + 1, close).trim();
        return new ToolCall(name, input);
    }
}
