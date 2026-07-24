import { common } from '@kit.AbilityKit';
import { LlmProvider } from '../../../model/LlmProvider';
import { ExperimentalActionPlanRequestHandler } from
  './ExperimentalActionPlanning';
import { LlmExperimentalActionPlanRequestHandler } from
  './LlmExperimentalActionPlanRequestHandler';
import { OpenAiCompatibleExperimentalActionPlanningModel } from
  './OpenAiCompatibleExperimentalActionPlanningModel';

export function createExperimentalActionPlanRequestHandlerFromProvider(
  provider: LlmProvider
): ExperimentalActionPlanRequestHandler {
  return new LlmExperimentalActionPlanRequestHandler(
    new OpenAiCompatibleExperimentalActionPlanningModel(provider)
  );
}

export async function createExperimentalActionPlanRequestHandler(
  context: common.UIAbilityContext
): Promise<ExperimentalActionPlanRequestHandler> {
  const provider = await LlmProvider.fromContext(context);
  return createExperimentalActionPlanRequestHandlerFromProvider(provider);
}
