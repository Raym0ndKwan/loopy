import { AgentEvent } from './AgentEvent';
import { AgentTool } from './AgentTool';

export type AgentListener = (event: AgentEvent) => void;

export interface Agent {
  readonly name: string;

  registerTool(tool: AgentTool): void;

  run(task: string, listener: AgentListener): Promise<void>;

  clearContext(): void;

  close(): Promise<void>;
}
