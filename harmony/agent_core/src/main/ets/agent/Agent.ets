import { AgentEvent } from './AgentEvent';

export type AgentListener = (event: AgentEvent) => void;

export interface Agent {
  readonly name: string;

  run(task: string, listener: AgentListener): Promise<void>;

  clearContext(): void;

  close(): Promise<void>;
}
