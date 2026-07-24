import { ExperimentalActionPlanDagValidator } from
  './ExperimentalActionPlanDagValidator';
import { ExperimentalActionPlanParameterValidator } from
  './ExperimentalActionPlanParameterValidator';
import { ExperimentalActionPlanResultValidator } from
  './ExperimentalActionPlanResultValidator';
import { ExperimentalProposedActionPlan } from './ExperimentalProposedActionPlan';
import {
  ExperimentalActionPlanValidationResult,
  validExperimentalActionPlan
} from './ExperimentalActionPlanValidationTypes';
import { ExperimentalToolAuthorizationValidator } from
  './ExperimentalToolAuthorizationValidator';
import { ExperimentalToolRegistry } from './ExperimentalToolRegistry';

export class ExperimentalActionPlanValidator {
  private readonly toolValidator: ExperimentalToolAuthorizationValidator;
  private readonly dagValidator: ExperimentalActionPlanDagValidator;
  private readonly parameterValidator: ExperimentalActionPlanParameterValidator;
  private readonly resultValidator: ExperimentalActionPlanResultValidator;

  constructor(registry: ExperimentalToolRegistry) {
    this.toolValidator = new ExperimentalToolAuthorizationValidator(registry);
    this.dagValidator = new ExperimentalActionPlanDagValidator();
    this.parameterValidator = new ExperimentalActionPlanParameterValidator(registry);
    this.resultValidator = new ExperimentalActionPlanResultValidator(registry);
  }

  validate(
    plan: ExperimentalProposedActionPlan,
    allowedToolIds: string[]
  ): ExperimentalActionPlanValidationResult {
    const tool = this.toolValidator.validate(plan, allowedToolIds);
    if (!tool.ok) {
      return tool;
    }
    const dag = this.dagValidator.validate(plan);
    if (!dag.ok) {
      return dag;
    }
    const parameters = this.parameterValidator.validate(plan);
    if (!parameters.ok) {
      return parameters;
    }
    const result = this.resultValidator.validate(plan);
    if (!result.ok) {
      return result;
    }
    return validExperimentalActionPlan(dag.topologicalNodeIds);
  }
}
