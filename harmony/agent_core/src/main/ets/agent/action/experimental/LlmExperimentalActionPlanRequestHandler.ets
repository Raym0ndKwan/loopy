import { JsonValue } from '../ActionPlanTypes';
import {
  ExperimentalActionPlanningFailure,
  ExperimentalActionPlanningRequest,
  ExperimentalActionPlanningResult,
  ExperimentalActionPlanProposalResult,
  ExperimentalActionPlanRequestHandler
} from './ExperimentalActionPlanning';
import {
  ExperimentalActionPlanningModel,
  ExperimentalActionPlanningModelRequest,
  ExperimentalActionPlanningModelResult
} from './ExperimentalActionPlanningModel';
import { buildExperimentalActionPlanPrompt } from
  './ExperimentalActionPlanPrompt';
import { buildExperimentalSubmitActionPlanTool } from
  './ExperimentalActionPlanToolSchema';
import {
  ExperimentalProposedActionPlanParseFailure,
  parseExperimentalProposedActionPlan
} from
  './ExperimentalProposedActionPlanParser';

function planningFailure(
  failureKind: 'model' | 'protocol',
  errorCode: string,
  message: string
): ExperimentalActionPlanningFailure {
  return {
    status: 'failure',
    failureKind,
    errorCode,
    message
  };
}

export class LlmExperimentalActionPlanRequestHandler
implements ExperimentalActionPlanRequestHandler {
  private readonly model: ExperimentalActionPlanningModel;

  constructor(model: ExperimentalActionPlanningModel) {
    this.model = model;
  }

  async handle(
    request: ExperimentalActionPlanningRequest
  ): Promise<ExperimentalActionPlanningResult> {
    if (request.tools.length === 0) {
      return planningFailure(
        'protocol',
        'ACTION_PLAN_TOOLS_EMPTY',
        'Action planning requires at least one authorized tool.'
      );
    }
    const prompt = buildExperimentalActionPlanPrompt(request);
    const modelRequest: ExperimentalActionPlanningModelRequest = {
      systemPrompt: prompt.systemPrompt,
      userPrompt: prompt.userPrompt,
      submitTool: buildExperimentalSubmitActionPlanTool(request.tools)
    };
    let modelResult: ExperimentalActionPlanningModelResult;
    try {
      modelResult = await this.model.submit(modelRequest);
    } catch (error) {
      const message = error instanceof Error ? error.message : `${error}`;
      return planningFailure(
        'model',
        'ACTION_PLAN_MODEL_THROWN',
        `Action planning model threw an exception: ${message}`
      );
    }
    if (!modelResult.ok) {
      return planningFailure(
        'model',
        modelResult.errorCode,
        modelResult.message
      );
    }
    let raw: JsonValue;
    try {
      raw = JSON.parse(modelResult.argumentsJson) as JsonValue;
    } catch (_error) {
      return planningFailure(
        'protocol',
        'ACTION_PLAN_ARGUMENTS_JSON_INVALID',
        'submit_action_plan arguments are not valid JSON.'
      );
    }
    const parsed = parseExperimentalProposedActionPlan(raw);
    if (!parsed.ok) {
      const failure = parsed as ExperimentalProposedActionPlanParseFailure;
      return planningFailure(
        'protocol',
        failure.errorCode,
        `${failure.path}: ${failure.message}`
      );
    }
    const proposal: ExperimentalActionPlanProposalResult = {
      status: 'proposal',
      proposal: parsed.plan
    };
    return proposal;
  }
}
