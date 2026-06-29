export interface AgentTool {
  name(): string;

  description(): string;

  run(input: string): string;
}
