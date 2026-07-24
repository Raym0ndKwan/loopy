import { ExperimentalSubmitActionPlanTool } from
  './ExperimentalActionPlanToolSchema';

export interface ExperimentalActionPlanningModelRequest {
  systemPrompt: string;
  userPrompt: string;
  submitTool: ExperimentalSubmitActionPlanTool;
}

export interface ExperimentalActionPlanningModelResult {
  ok: boolean;
  argumentsJson: string;
  errorCode: string;
  message: string;
}

export interface ExperimentalActionPlanningModel {
  submit(
    request: ExperimentalActionPlanningModelRequest
  ): Promise<ExperimentalActionPlanningModelResult>;
}
