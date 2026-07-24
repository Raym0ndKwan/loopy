import { ExperimentalProposedActionPlan } from './ExperimentalProposedActionPlan';
import { ExperimentalToolRegistry } from './ExperimentalToolRegistry';
import {
  ExperimentalActionPlanValidationResult,
  invalidExperimentalActionPlan,
  validExperimentalActionPlan
} from './ExperimentalActionPlanValidationTypes';

export class ExperimentalToolAuthorizationValidator {
  private readonly registry: ExperimentalToolRegistry;

  constructor(registry: ExperimentalToolRegistry) {
    this.registry = registry;
  }

  validate(
    plan: ExperimentalProposedActionPlan,
    allowedToolIds: string[]
  ): ExperimentalActionPlanValidationResult {
    for (let index = 0; index < plan.nodes.length; index++) {
      const toolId = plan.nodes[index].toolId;
      if (this.registry.find(toolId) === null) {
        return invalidExperimentalActionPlan(
          'tool',
          `$/nodes/${index}/toolId`,
          'ACTION_PLAN_TOOL_NOT_FOUND',
          `Action plan tool is not registered: ${toolId}.`
        );
      }
      if (allowedToolIds.indexOf(toolId) < 0) {
        return invalidExperimentalActionPlan(
          'tool',
          `$/nodes/${index}/toolId`,
          'ACTION_PLAN_TOOL_NOT_AUTHORIZED',
          `Action plan tool is not authorized for this task: ${toolId}.`
        );
      }
    }
    return validExperimentalActionPlan();
  }
}
