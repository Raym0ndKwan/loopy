import {
  MESSAGE_TAG_UI_MAKER,
  MESSAGE_TYPE_CONTROL_CLEAR,
  MESSAGE_TYPE_OTHERS,
  MESSAGE_TYPE_TASK_CREATE_UI,
  MESSAGE_TYPE_TASK_RESULT_UI
} from './AgentMessageTypes';
import { AgentEvent, AgentEventKind } from './AgentEvent';
import { AgentMessage } from './MessageBus';
import { AgentRunOutcome, AgentRunOutcomeKind, MessageDrivenAgent } from './MessageDrivenAgent';

export class UIMakerAgent extends MessageDrivenAgent {
  protected handle(message: AgentMessage): void {
    if (message.type === MESSAGE_TYPE_CONTROL_CLEAR) {
      this.clearContext();
      return;
    }
    if (message.type !== MESSAGE_TYPE_TASK_CREATE_UI) {
      return;
    }
    this.enqueueMessage(message);
  }

  protected onAgentEvent(event: AgentEvent): void {
    this.bus.write({
      type: `${MESSAGE_TYPE_OTHERS}.${MESSAGE_TAG_UI_MAKER}.${event.kind}`,
      content: event.text
    });
  }

  protected onRunError(error: Error): void {
    this.bus.write({
      type: `${MESSAGE_TYPE_OTHERS}.${MESSAGE_TAG_UI_MAKER}.${AgentEventKind.ERROR}`,
      content: error.message
    });
  }

  protected onRunFinished(messages: AgentMessage[], outcome: AgentRunOutcome): void {
    const original = messages.length > 0 ? messages[0].content : '';
    const terminalKind = outcome.kind === AgentRunOutcomeKind.FINAL ? 'FINAL' : 'ERROR';
    this.bus.write({
      type: MESSAGE_TYPE_TASK_RESULT_UI,
      content:
        `Original UI task:\n${original}\n\n` +
        `Loop outcome:\n${terminalKind}\n\n` +
        `UImaker ${outcome.kind === AgentRunOutcomeKind.FINAL ? 'Final' : 'Error'}:\n${outcome.text}`
    });
  }
}
