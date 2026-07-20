import {
  MESSAGE_TYPE_CONTROL_CLEAR,
  MESSAGE_TYPE_INPUT,
  ReactAgentMessage,
  ReactBusReader,
  ReactMessageBus
} from '@loop/agent-core';

export type ChatMessageListener = (message: ReactAgentMessage) => void;
export type ChatInteractorErrorListener = (error: Error) => void;

export class ChatInteractor {
  private readonly bus: ReactMessageBus;
  private readonly reader: ReactBusReader;
  private listening: boolean = false;
  private stopped: boolean = false;
  private listenPromise: Promise<void> | null = null;

  constructor(bus: ReactMessageBus) {
    this.bus = bus;
    this.reader = bus.getReader();
  }

  send(content: string): void {
    if (content.trim().length === 0) {
      return;
    }
    if (this.stopped) {
      throw new Error('A stopped ChatInteractor cannot send messages.');
    }

    this.bus.write({
      type: MESSAGE_TYPE_INPUT,
      content: content
    });
  }

  clear(): void {
    if (this.stopped) {
      throw new Error('A stopped ChatInteractor cannot clear the conversation.');
    }

    this.bus.write({
      type: MESSAGE_TYPE_CONTROL_CLEAR,
      content: ''
    });
  }

  startListening(
    listener: ChatMessageListener,
    errorListener?: ChatInteractorErrorListener
  ): void {
    if (this.listening) {
      return;
    }
    if (this.stopped) {
      throw new Error('A stopped ChatInteractor cannot restart listening.');
    }

    this.listening = true;
    const listening = this.listenLoop(listener, errorListener);
    this.listenPromise = listening;
    listening.catch((error: Error): void => {
      this.listening = false;
      this.stopped = true;
      this.listenPromise = null;
      this.reader.close();
      if (errorListener !== undefined) {
        errorListener(error);
      }
    });
  }

  async stopListening(): Promise<void> {
    if (this.stopped) {
      return;
    }

    this.stopped = true;
    this.listening = false;
    this.reader.close();
    const listening = this.listenPromise;
    this.listenPromise = null;
    if (listening !== null) {
      try {
        await listening;
      } catch (_error) {
      }
    }
  }

  private async listenLoop(
    listener: ChatMessageListener,
    errorListener?: ChatInteractorErrorListener
  ): Promise<void> {
    while (this.listening) {
      const message: ReactAgentMessage | null = await this.reader.receive();
      if (message === null) {
        return;
      }

      try {
        listener(message);
      } catch (error) {
        if (errorListener !== undefined) {
          const normalized = error instanceof Error ? error : new Error(`${error}`);
          errorListener(normalized);
        }
      }
    }
  }
}
