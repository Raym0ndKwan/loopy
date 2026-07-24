export type ExperimentalActionPlanValidationStage =
  '' | 'tool' | 'dag' | 'parameter' | 'result';

export interface ExperimentalActionPlanValidationResult {
  ok: boolean;
  stage: ExperimentalActionPlanValidationStage;
  path: string;
  errorCode: string;
  message: string;
  topologicalNodeIds: string[];
}

export function validExperimentalActionPlan(
  topologicalNodeIds: string[] = []
): ExperimentalActionPlanValidationResult {
  return {
    ok: true,
    stage: '',
    path: '',
    errorCode: '',
    message: '',
    topologicalNodeIds: topologicalNodeIds.slice()
  };
}

export function invalidExperimentalActionPlan(
  stage: ExperimentalActionPlanValidationStage,
  path: string,
  errorCode: string,
  message: string
): ExperimentalActionPlanValidationResult {
  return {
    ok: false,
    stage,
    path,
    errorCode,
    message,
    topologicalNodeIds: []
  };
}
