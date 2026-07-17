import { AgentEvent, AgentEventKind } from './AgentEvent';
import {
  MESSAGE_TYPE_CONTROL_CLEAR,
  MESSAGE_TYPE_INPUT,
  MESSAGE_TYPE_OTHERS,
  MESSAGE_TYPE_OUTPUT
} from './AgentMessageTypes';
import { AgentMessage } from './MessageBus';
import { MessageDrivenAgent } from './MessageDrivenAgent';

export class LeaderAgent extends MessageDrivenAgent {
  protected handle(message: AgentMessage): void {
    if (message.type === MESSAGE_TYPE_CONTROL_CLEAR) {
      this.clearContext();
      return;
    }
    if (message.type !== MESSAGE_TYPE_INPUT) {
      return;
    }
    this.enqueueMessage(message);
  }

  protected onAgentEvent(event: AgentEvent): void {
    if (event.kind === AgentEventKind.FINAL) {
      this.bus.write({
        type: MESSAGE_TYPE_OUTPUT,
        content: event.text
      });
      return;
    }

    this.bus.write({
      type: `${MESSAGE_TYPE_OTHERS}.${event.kind}`,
      content: event.text
    });
  }

  protected onRunError(error: Error): void {
    this.bus.write({
      type: `${MESSAGE_TYPE_OTHERS}.${AgentEventKind.ERROR}`,
      content: error.message
    });
  }
}
