import { JsonValue } from '../ActionPlanTypes';
import { ExperimentalJsonSchema } from './ExperimentalJsonSchema';

export type ExperimentalToolRisk = 'read' | 'draft' | 'confirm_required';

export interface ExperimentalToolExecutionContext {
  conversationId: string;
  turnId: string;
  actionTaskId: string;
  nodeId: string;
  nowIso: string;
}

export interface ExperimentalToolSuccessResult {
  status: 'success';
  output: JsonValue;
}

export interface ExperimentalToolErrorResult {
  status: 'error';
  errorCode: string;
  message: string;
}

export type ExperimentalToolExecutionResult =
  ExperimentalToolSuccessResult | ExperimentalToolErrorResult;

export interface ExperimentalToolExecutor {
  execute(
    args: Object,
    context: ExperimentalToolExecutionContext
  ): Promise<ExperimentalToolExecutionResult>;
}

export interface ExperimentalToolExample {
  input: JsonValue;
  output: JsonValue;
  explanation?: string;
}

export interface ExperimentalToolDefinition {
  toolId: string;
  revision: string;
  name: string;
  description: string;
  riskLevel: ExperimentalToolRisk;
  inputSchema: ExperimentalJsonSchema;
  outputSchema: ExperimentalJsonSchema;
  examples?: ExperimentalToolExample[];
  executor: ExperimentalToolExecutor;
}

export interface ExperimentalToolSpec {
  toolId: string;
  revision: string;
  name: string;
  description: string;
  riskLevel: ExperimentalToolRisk;
  inputSchema: ExperimentalJsonSchema;
  outputSchema: ExperimentalJsonSchema;
  examples?: ExperimentalToolExample[];
}
