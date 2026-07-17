import { Agent, AgentListener } from './Agent';
import { AgentEvent, AgentEventKind } from './AgentEvent';
import { AgentTool } from './AgentTool';
import { ChatMessage, ConversationContext } from './ConversationContext';
import { ToolRegistry } from './ToolRegistry';
import { LocalModel } from '../model/LocalModel';

export type UiRenderHandler = (description: string) => Promise<string[]>;

const UI_TOOL_NAME: string = 'ui';
const MAX_CONTEXT_MESSAGES: number = 50;
const REACT_TAGS: string[] = ['Thought:', 'Action:', 'Observation:', 'Final:'];

class ToolCall {
  name: string;
  input: string;

  constructor(name: string, input: string) {
    this.name = name;
    this.input = input;
  }
}

export class ReActAgent implements Agent {
  readonly name: string;

  private identityPrompt: string;
  private model: LocalModel;
  private tools: ToolRegistry;
  private maxSteps: number;
  private uiHandler: UiRenderHandler | null;
  private conversation: ConversationContext;

  constructor(
    name: string,
    identityPrompt: string,
    model: LocalModel,
    maxSteps: number,
    tools?: ToolRegistry,
    uiHandler?: UiRenderHandler,
    initialContext?: ConversationContext
  ) {
    this.name = name;
    this.identityPrompt = identityPrompt.trim();
    this.model = model;
    this.maxSteps = maxSteps;
    this.tools = tools ?? new ToolRegistry();
    this.uiHandler = uiHandler ?? null;
    this.conversation = initialContext === undefined
      ? new ConversationContext()
      : ConversationContext.fromMessages(initialContext.toChatMessages());
  }

  registerTool(tool: AgentTool): void {
    this.tools.register(tool);
  }

  clearContext(): void {
    this.conversation.clear();
  }

  async close(): Promise<void> {
    await this.tools.close();
  }

  async run(task: string, listener: AgentListener): Promise<void> {
    const normalizedTask = task.trim();
    if (normalizedTask.length === 0) {
      listener(new AgentEvent(AgentEventKind.ERROR, 'Agent task is empty.'));
      return;
    }

    const scratchpad: string[] = [];
    for (let step = 0; step < this.maxSteps; step++) {
      let response: string;
      try {
        response = await this.model.complete(
          this.buildPrompt(normalizedTask, scratchpad),
          this.conversation,
          this.buildSystemPrompt()
        );
      } catch (error) {
        const message = error instanceof Error ? error.message : `${error}`;
        listener(new AgentEvent(AgentEventKind.ERROR, message));
        return;
      }

      this.emitResponse(response, listener);

      const finalAnswer = this.readLineValue(response, 'Final:');
      if (finalAnswer !== null) {
        this.finish(normalizedTask, finalAnswer, listener);
        return;
      }

      const call = this.parseAction(response);
      if (call === null) {
        const responseText = response.length > 0 ? response : '(empty response)';
        listener(new AgentEvent(
          AgentEventKind.ERROR,
          `Model did not return an Action or Final answer.\n\nLLM response:\n${responseText}`
        ));
        return;
      }

      listener(new AgentEvent(AgentEventKind.ACTION, `${call.name}(${call.input})`));

      let observation: string;
      try {
        if (call.name === UI_TOOL_NAME) {
          if (this.uiHandler === null) {
            this.finish(normalizedTask, call.input, listener);
            return;
          }
          observation = await this.runUiTool(call.input, listener);
        } else {
          observation = await this.tools.run(call.name, call.input);
        }
      } catch (error) {
        const message = error instanceof Error ? error.message : `${error}`;
        listener(new AgentEvent(AgentEventKind.ERROR, `Tool ${call.name} failed: ${message}`));
        return;
      }

      scratchpad.push(response);
      scratchpad.push(`Observation: ${observation}`);
      listener(new AgentEvent(AgentEventKind.OBSERVATION, observation));
    }

    listener(new AgentEvent(AgentEventKind.ERROR, `Stopped after ${this.maxSteps} steps without a final answer.`));
  }

  private finish(task: string, finalAnswer: string, listener: AgentListener): void {
    this.appendContext(task, finalAnswer);
    listener(new AgentEvent(AgentEventKind.FINAL, finalAnswer));
  }

  private appendContext(task: string, finalAnswer: string): void {
    const messages = this.conversation.toChatMessages();
    messages.push({ role: 'user', content: task });
    messages.push({ role: 'assistant', content: finalAnswer.trim() });
    const retained: ChatMessage[] = messages.length > MAX_CONTEXT_MESSAGES
      ? messages.slice(messages.length - MAX_CONTEXT_MESSAGES)
      : messages;
    this.conversation = ConversationContext.fromMessages(retained);
  }

  private async runUiTool(description: string, listener: AgentListener): Promise<string> {
    if (this.uiHandler === null) {
      return 'UI rendering is not available for this agent.';
    }

    const prompt = description.trim().length > 0 ? description : 'Simple information card';
    try {
      const lines = await this.uiHandler(prompt);
      if (lines.length === 0) {
        return 'UI tool returned no protocol data.';
      }
      listener(new AgentEvent(AgentEventKind.UI, lines.join('\n')));
      return `Rendered on-screen UI (${lines.length} protocol lines) for: ${prompt}`;
    } catch (error) {
      const message = error instanceof Error ? error.message : `${error}`;
      return `UI render failed: ${message}`;
    }
  }

  private buildSystemPrompt(): string {
    let prompt = this.identityPrompt;
    if (prompt.length > 0) {
      prompt += '\n\n';
    }
    prompt += 'Use Thought, Action, Observation, and Final.\n';
    prompt += 'Every tool call must use exactly this syntax on one line: Action: tool_name[input].\n';
    prompt += 'Use only the tools listed in the current task prompt.\n';
    if (this.uiHandler !== null) {
      prompt += 'Use the ui tool when the user asks for an on-screen card, form, dashboard, or visual summary.\n';
    }
    return prompt.trim();
  }

  private buildPrompt(task: string, scratchpad: string[]): string {
    let prompt = 'Tools:\n';
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
    const start = this.findTagStart(text, prefix);
    if (start < 0) {
      return null;
    }
    const valueStart = start + prefix.length;
    const tail = text.substring(valueStart);
    const next = this.findNextTagStart(tail, prefix);
    const value = next < 0 ? tail : tail.substring(0, next);
    return value.trim();
  }

  private findTagStart(text: string, prefix: string): number {
    let searchFrom = 0;
    while (searchFrom < text.length) {
      const index = text.indexOf(prefix, searchFrom);
      if (index < 0) {
        return -1;
      }
      if (this.isTagBoundary(text, index)) {
        return index;
      }
      searchFrom = index + prefix.length;
    }
    return -1;
  }

  private findNextTagStart(text: string, currentPrefix: string): number {
    let result = -1;
    for (let index = 0; index < REACT_TAGS.length; index++) {
      const prefix = REACT_TAGS[index];
      if (prefix === currentPrefix) {
        continue;
      }
      const start = this.findTagStart(text, prefix);
      if (start >= 0 && (result < 0 || start < result)) {
        result = start;
      }
    }
    return result;
  }

  private isTagBoundary(text: string, index: number): boolean {
    if (index === 0) {
      return true;
    }
    const previous = text.charAt(index - 1);
    return previous === '\n' || previous === '\r' || previous === ' ' || previous === '\t';
  }

  private parseAction(response: string): ToolCall | null {
    const action = this.readLineValue(response, 'Action:');
    if (action === null) {
      return null;
    }

    const bracketCall = this.parseDelimitedAction(action, '[', ']');
    if (bracketCall !== null) {
      return bracketCall;
    }
    const parenCall = this.parseDelimitedAction(action, '(', ')');
    if (parenCall !== null) {
      return parenCall;
    }
    return this.parseJsonAction(action);
  }

  private parseJsonAction(action: string): ToolCall | null {
    const trimmed = action.trim();
    if (!trimmed.startsWith('{')) {
      return null;
    }
    try {
      const parsed = JSON.parse(trimmed) as Record<string, Object | string | number | boolean | null | undefined>;
      const operation = `${parsed.operation ?? ''}`;
      if (operation === 'search' || operation === 'execute') {
        return new ToolCall('modelscope', trimmed);
      }
    } catch (_error) {
    }
    return null;
  }

  private parseDelimitedAction(action: string, openToken: string, closeToken: string): ToolCall | null {
    const open = action.indexOf(openToken);
    const close = action.lastIndexOf(closeToken);
    if (open <= 0 || close < open) {
      return null;
    }

    const name = action.substring(0, open).trim();
    const input = action.substring(open + 1, close).trim();
    return new ToolCall(name, input);
  }
}
