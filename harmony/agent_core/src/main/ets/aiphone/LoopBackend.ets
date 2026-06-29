import { AgentEvent, AgentEventKind } from '../agent/AgentEvent';
import { AgentTool } from '../agent/AgentTool';
import { ConversationContext } from '../agent/ConversationContext';
import { ReActAgentRunner } from '../agent/ReActAgentRunner';
import { ToolRegistry } from '../agent/ToolRegistry';
import { LlmProvider } from '../model/LlmProvider';
import { LocalModel } from '../model/LocalModel';
import { OpenAiCompatibleModel } from '../model/OpenAiCompatibleModel';
import { ScriptedLocalModel } from '../model/ScriptedLocalModel';
import { splitJsonl } from './AiphoneA2ui';
import { allToolDefinitions, ToolDefinition } from './AiphoneToolDefinitions';
import { runAiphoneTool } from './AiphoneToolExecutor';
import { LoopBackendCallbacks, LoopBackendRequest, LoopRunResult, LoopToolTrace } from './LoopBackendTypes';

class AiphoneTool implements AgentTool {
  private toolId: string;
  private descriptionText: string;
  private request: LoopBackendRequest;
  private callbacks: LoopBackendCallbacks;

  constructor(toolId: string, descriptionText: string, request: LoopBackendRequest, callbacks: LoopBackendCallbacks) {
    this.toolId = toolId;
    this.descriptionText = descriptionText;
    this.request = request;
    this.callbacks = callbacks;
  }

  name(): string {
    return this.toolId;
  }

  description(): string {
    return this.descriptionText;
  }

  async run(input: string): Promise<string> {
    const jsonl = await runAiphoneTool(
      this.toolId,
      input,
      this.request.surfaceId,
      this.request.actionId,
      this.request.args ?? null
    );
    for (const line of splitJsonl(jsonl)) {
      this.callbacks.onA2uiJsonl?.(line);
    }
    return jsonl;
  }
}

export class LoopBackend {
  async run(request: LoopBackendRequest, callbacks: LoopBackendCallbacks): Promise<LoopRunResult> {
    const conversation = this.buildConversation(request);
    const model = this.buildModel(request);
    const runner = new ReActAgentRunner(model, this.buildToolRegistry(request, callbacks), request.maxSteps > 0 ? request.maxSteps : 6);
    const toolCalls: LoopToolTrace[] = [];
    let finalAnswer = '';
    let error = '';
    let raw = '';
    let lastAction: LoopToolTrace = { toolId: '', input: '', observation: '' };

    await runner.run(request.prompt, (event: AgentEvent): void => {
      raw += `${event.kind}: ${event.text}\n`;
      try {
        callbacks.onEvent?.(event);
      } catch (callbackError) {
        const message = callbackError instanceof Error ? callbackError.message : `${callbackError}`;
        error = `Callback failed: ${message}`;
        raw += `ERROR: ${error}\n`;
        return;
      }

      if (event.kind === AgentEventKind.FINAL) {
        finalAnswer = event.text;
      } else if (event.kind === AgentEventKind.ERROR) {
        error = event.text;
      } else if (event.kind === AgentEventKind.ACTION) {
        lastAction = this.parseActionTrace(event.text);
      } else if (event.kind === AgentEventKind.OBSERVATION) {
        toolCalls.push({
          toolId: lastAction.toolId,
          input: lastAction.input,
          observation: event.text
        });
      }
    }, conversation);

    return {
      ok: error.length === 0,
      finalAnswer,
      error,
      toolCalls,
      raw: raw.trim()
    };
  }

  private buildConversation(request: LoopBackendRequest): ConversationContext {
    const conversation = new ConversationContext();
    for (const message of request.history) {
      if (message.role === 'user') {
        conversation.addUser(message.content);
      } else if (message.role === 'assistant') {
        conversation.addAssistant(message.content);
      }
    }
    return conversation;
  }

  private buildModel(request: LoopBackendRequest): LocalModel {
    const settings = request.modelSettings;
    const provider = new LlmProvider(settings.provider, settings.apiKey, settings.baseUrl, settings.model);
    return provider.isConfigured() ? new OpenAiCompatibleModel(provider) : new ScriptedLocalModel();
  }

  private buildToolRegistry(request: LoopBackendRequest, callbacks: LoopBackendCallbacks): ToolRegistry {
    const registry = new ToolRegistry();
    for (const definition of allToolDefinitions()) {
      registry.register(new AiphoneTool(
        definition.toolId,
        this.describeAiphoneTool(definition),
        request,
        callbacks
      ));
    }
    registry.register(new AiphoneTool(
      'dynamic.search',
      'dynamic.search inputSchema=dynamicToolSearchQuery outputSchema=dynamicToolConnect',
      request,
      callbacks
    ));
    return registry;
  }

  private describeAiphoneTool(definition: ToolDefinition): string {
    return definition.intent + ' inputSchema=' + definition.inputSchema + ' outputSchema=' + definition.outputSchema;
  }

  private parseActionTrace(action: string): LoopToolTrace {
    const open = action.indexOf('(');
    const close = action.lastIndexOf(')');
    if (open <= 0 || close < open) {
      return { toolId: action, input: '', observation: '' };
    }
    return {
      toolId: action.substring(0, open).trim(),
      input: action.substring(open + 1, close).trim(),
      observation: ''
    };
  }
}
