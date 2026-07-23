import { AgentMessage, UserInputPayload } from '../message/AgentMessage';
import { ToolRiskLevel } from '../../aiphone/runtime/ToolDefinitionTypes';

export type InputUserPayload = UserInputPayload;

export interface LeaderUiTask {
  taskId: string;
  intent: string;
  expectedOutputSchema: string;
}

export interface LeaderDataTask {
  taskId: string;
  toolId: string;
  outputSchema: string;
  args: Object;
}

/**
 * Describes what ActionAgent should achieve and which registered tools it may
 * consider. Leader intentionally does not choose steps or data bindings.
 */
export interface LeaderActionTask {
  taskId: string;
  query: string;
  allowedToolIds: string[];
}

export interface LeaderPlan {
  skillId: string;
  ui: LeaderUiTask;
  data: LeaderDataTask;
  action?: LeaderActionTask;
}

export interface LeaderToolMetadata {
  toolId: string;
  intent: string;
  riskLevel: ToolRiskLevel;
  inputSchema: string;
  outputSchema: string;
  actions: string[];
}

export interface LeaderSkillMetadata {
  skillId: string;
  description: string;
  instructions: string;
}

export interface LeaderPlanningContext {
  tools: LeaderToolMetadata[];
  skills: LeaderSkillMetadata[];
}

export interface LeaderPlanner {
  plan(
    message: AgentMessage,
    input: InputUserPayload,
    context: LeaderPlanningContext
  ): Promise<LeaderPlan>;
}
