import { hilog } from '@kit.PerformanceAnalysisKit';
import * as BuildProfile from 'BuildProfile';
import {
  AgentMessage,
  AgentMessageReader,
  AgentMessageType,
  LinkedMessageBus,
  UserInputPayload
} from '@loop/agent-core';

export type ChatMessageListener = (message: AgentMessage) => void;
export type ChatInteractorErrorListener = (error: Error) => void;

const BUS_LOG_DOMAIN: number = 0x0000;
const BUS_LOG_TAG: string = 'LoopBus';
const BUS_LOG_PREFIX: string = 'LOOP_BUS ';
const BUS_LOG_CHUNK_SIZE: number = 2400;
const CONVERSATION_ID_PREFIX: string = 'conversation';
const TURN_ID_PREFIX: string = 'turn';
const ROOT_INPUT_TASK_ID_PREFIX: string = 'input-root';

interface BusLogEnvelope {
  readonly schema: string;
  readonly messageId: string;
  readonly type: string;
  readonly conversationId: string;
  readonly turnId: string;
  readonly taskId: string;
  readonly chunkIndex: number;
  readonly chunkCount: number;
  readonly content: string;
}

export class ChatInteractor {
  private readonly bus: LinkedMessageBus;
  private readonly reader: AgentMessageReader;
  private readonly conversationId: string;
  private listening: boolean = false;
  private stopped: boolean = false;
  private sequence: number = 0;
  private logSequence: number = 0;

  constructor(bus: LinkedMessageBus) {
    this.bus = bus;
    this.reader = bus.openReader();
    this.conversationId = `${CONVERSATION_ID_PREFIX}-${Date.now()}`;
  }

  send(text: string): void {
    const trimmed: string = text.trim();
    if (trimmed.length === 0) {
      return;
    }
    if (this.stopped) {
      throw new Error('A stopped ChatInteractor cannot send messages.');
    }
    this.sequence++;
    const turnId: string = this.createTurnId();
    const payload: UserInputPayload = { text: trimmed };
    this.bus.publish({
      type: AgentMessageType.INPUT_USER,
      conversationId: this.conversationId,
      turnId,
      taskId: this.createRootInputTaskId(),
      payload
    });
  }

  private createTurnId(): string {
    return `${TURN_ID_PREFIX}-${Date.now()}-${this.sequence}`;
  }

  private createRootInputTaskId(): string {
    return `${ROOT_INPUT_TASK_ID_PREFIX}-${this.sequence}`;
  }

  startListening(
    listener: ChatMessageListener,
    errorListener?: ChatInteractorErrorListener
  ): void {
    if (this.listening || this.stopped) {
      return;
    }
    this.listening = true;
    this.listenLoop(listener, errorListener).catch((error: Error): void => {
      this.listening = false;
      this.stopped = true;
      this.reader.close();
      if (errorListener !== undefined) {
        errorListener(error);
      }
    });
  }

  stopListening(): void {
    if (this.stopped) {
      return;
    }
    this.stopped = true;
    this.listening = false;
    this.reader.close();
  }

  private async listenLoop(
    listener: ChatMessageListener,
    errorListener?: ChatInteractorErrorListener
  ): Promise<void> {
    while (this.listening) {
      const message: AgentMessage | null = await this.reader.receive();
      if (message === null) {
        return;
      }
      try {
        this.logBusMessage(message);
        listener(message);
      } catch (error) {
        if (errorListener !== undefined) {
          const normalized: Error = error instanceof Error ? error : new Error(`${error}`);
          errorListener(normalized);
        }
      }
    }
  }

  private logBusMessage(message: AgentMessage): void {
    if (!BuildProfile.DEBUG) {
      return;
    }
    let content: string;
    try {
      content = JSON.stringify(message.payload);
    } catch (_error) {
      content = '<unserializable payload>';
    }
    this.logSequence++;
    const messageId: string = `${Date.now()}-${this.logSequence}`;
    const chunkCount: number = Math.max(1, Math.ceil(content.length / BUS_LOG_CHUNK_SIZE));
    for (let chunkIndex: number = 0; chunkIndex < chunkCount; chunkIndex++) {
      const start: number = chunkIndex * BUS_LOG_CHUNK_SIZE;
      const envelope: BusLogEnvelope = {
        schema: 'loop.bus.v1',
        messageId,
        type: message.type,
        conversationId: message.conversationId,
        turnId: message.turnId,
        taskId: message.taskId,
        chunkIndex,
        chunkCount,
        content: content.substring(start, start + BUS_LOG_CHUNK_SIZE)
      };
      hilog.info(
        BUS_LOG_DOMAIN,
        BUS_LOG_TAG,
        '%{public}s',
        `${BUS_LOG_PREFIX}${JSON.stringify(envelope)}`
      );
    }
  }
}
