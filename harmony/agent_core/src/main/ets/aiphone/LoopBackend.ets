import { AgentEvent, AgentEventKind } from '../agent/AgentEvent';
import { ConversationContext } from '../agent/ConversationContext';
import { ReActAgentRunner } from '../agent/ReActAgentRunner';
import { ToolRegistry } from '../agent/ToolRegistry';
import { LlmProvider } from '../model/LlmProvider';
import { LocalModel } from '../model/LocalModel';
import { OpenAiCompatibleModel } from '../model/OpenAiCompatibleModel';
import { ScriptedLocalModel } from '../model/ScriptedLocalModel';
import { LoopBackendCallbacks, LoopBackendRequest, LoopRunResult, LoopToolTrace } from './LoopBackendTypes';

export class LoopBackend {
  async run(request: LoopBackendRequest, callbacks: LoopBackendCallbacks): Promise<LoopRunResult> {
    const conversation = this.buildConversation(request);
    const model = this.buildModel(request);
    const runner = new ReActAgentRunner(model, new ToolRegistry(), request.maxSteps > 0 ? request.maxSteps : 6);
    const toolCalls: LoopToolTrace[] = [];
    let finalAnswer = '';
    let error = '';
    let raw = '';
    let lastAction = '';

    await runner.run(request.prompt, (event: AgentEvent): void => {
      raw += `${event.kind}: ${event.text}\n`;
      if (callbacks.onEvent !== undefined) {
        callbacks.onEvent(event);
      }

      if (event.kind === AgentEventKind.FINAL) {
        finalAnswer = event.text;
      } else if (event.kind === AgentEventKind.ERROR) {
        error = event.text;
      } else if (event.kind === AgentEventKind.ACTION) {
        lastAction = event.text;
      } else if (event.kind === AgentEventKind.OBSERVATION) {
        toolCalls.push({
          toolId: lastAction,
          input: '',
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
}
