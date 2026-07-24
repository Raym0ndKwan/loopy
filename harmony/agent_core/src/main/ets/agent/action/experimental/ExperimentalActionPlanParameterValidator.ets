import {
  ExperimentalJsonSchema,
  validateExperimentalValue
} from './ExperimentalJsonSchema';
import {
  ExperimentalActionBinding,
  ExperimentalProposedActionPlan
} from './ExperimentalProposedActionPlan';
import {
  ExperimentalActionPlanValidationResult,
  invalidExperimentalActionPlan,
  validExperimentalActionPlan
} from './ExperimentalActionPlanValidationTypes';
import {
  experimentalSchemasAssignable,
  pointersOverlap,
  resolveExperimentalSchemaPath
} from './ExperimentalSchemaCompatibility';
import { ExperimentalToolRegistry } from './ExperimentalToolRegistry';
import { ExperimentalToolSpec } from './ExperimentalToolTypes';

interface RequiredValidationResult {
  ok: boolean;
  path: string;
}

function escapePointerToken(token: string): string {
  return token.replace(/~/g, '~0').replace(/\//g, '~1');
}

function covered(path: string, targets: string[]): boolean {
  for (let index = 0; index < targets.length; index++) {
    if (pointersOverlap(path, targets[index])) {
      return true;
    }
  }
  return false;
}

function requiredInputsCovered(
  schema: ExperimentalJsonSchema,
  basePath: string,
  targets: string[]
): RequiredValidationResult {
  if (schema.type !== 'object') {
    return {
      ok: true,
      path: ''
    };
  }
  const properties = schema.properties === undefined ?
    {} as Record<string, ExperimentalJsonSchema> : schema.properties;
  const required = schema.required === undefined ? [] : schema.required;
  const keys = Object.keys(properties);
  for (let index = 0; index < keys.length; index++) {
    const key = keys[index];
    const propertyPath = `${basePath}/${escapePointerToken(key)}`;
    const isRequired = required.indexOf(key) >= 0;
    const isActive = isRequired || covered(propertyPath, targets);
    if (isRequired && !covered(propertyPath, targets)) {
      return {
        ok: false,
        path: propertyPath
      };
    }
    if (isActive && properties[key].type === 'object') {
      const nested = requiredInputsCovered(properties[key], propertyPath, targets);
      if (!nested.ok) {
        return nested;
      }
    }
  }
  return {
    ok: true,
    path: ''
  };
}

function overlappingBinding(
  bindings: ExperimentalActionBinding[],
  currentIndex: number
): number {
  const current = bindings[currentIndex].targetPath;
  for (let index = 0; index < currentIndex; index++) {
    if (pointersOverlap(current, bindings[index].targetPath)) {
      return index;
    }
  }
  return -1;
}

export class ExperimentalActionPlanParameterValidator {
  private readonly registry: ExperimentalToolRegistry;

  constructor(registry: ExperimentalToolRegistry) {
    this.registry = registry;
  }

  validate(plan: ExperimentalProposedActionPlan): ExperimentalActionPlanValidationResult {
    const nodeSpecs: Map<string, ExperimentalToolSpec> =
      new Map<string, ExperimentalToolSpec>();
    for (let index = 0; index < plan.nodes.length; index++) {
      const spec = this.registry.find(plan.nodes[index].toolId);
      if (spec !== null) {
        nodeSpecs.set(plan.nodes[index].nodeId, spec);
      }
    }
    for (let nodeIndex = 0; nodeIndex < plan.nodes.length; nodeIndex++) {
      const node = plan.nodes[nodeIndex];
      const targetSpec = nodeSpecs.get(node.nodeId);
      if (targetSpec === undefined) {
        return invalidExperimentalActionPlan(
          'parameter',
          `$/nodes/${nodeIndex}/toolId`,
          'ACTION_PLAN_PARAMETER_TOOL_MISSING',
          'Parameter validation requires a registered target tool.'
        );
      }
      const targetPaths: string[] = [];
      for (let bindingIndex = 0; bindingIndex < node.inputs.length; bindingIndex++) {
        const binding = node.inputs[bindingIndex];
        const overlap = overlappingBinding(node.inputs, bindingIndex);
        if (overlap >= 0) {
          return invalidExperimentalActionPlan(
            'parameter',
            `$/nodes/${nodeIndex}/inputs/${bindingIndex}/targetPath`,
            'ACTION_PLAN_INPUT_BINDING_OVERLAP',
            `Input binding overlaps binding ${overlap}.`
          );
        }
        const target = resolveExperimentalSchemaPath(
          targetSpec.inputSchema,
          binding.targetPath
        );
        if (!target.ok || target.schema === null) {
          return invalidExperimentalActionPlan(
            'parameter',
            `$/nodes/${nodeIndex}/inputs/${bindingIndex}/targetPath`,
            'ACTION_PLAN_INPUT_PATH_NOT_FOUND',
            target.message
          );
        }
        targetPaths.push(binding.targetPath);
        if (binding.source.kind === 'constant') {
          const constant = validateExperimentalValue(
            target.schema,
            binding.source.value
          );
          if (!constant.ok) {
            return invalidExperimentalActionPlan(
              'parameter',
              `$/nodes/${nodeIndex}/inputs/${bindingIndex}/source/value`,
              'ACTION_PLAN_CONSTANT_SCHEMA_MISMATCH',
              constant.message
            );
          }
          continue;
        }
        const sourceSpec = nodeSpecs.get(binding.source.nodeId);
        if (sourceSpec === undefined) {
          return invalidExperimentalActionPlan(
            'parameter',
            `$/nodes/${nodeIndex}/inputs/${bindingIndex}/source/nodeId`,
            'ACTION_PLAN_SOURCE_TOOL_MISSING',
            'Source node tool schema is unavailable.'
          );
        }
        const source = resolveExperimentalSchemaPath(
          sourceSpec.outputSchema,
          binding.source.path
        );
        if (!source.ok || source.schema === null) {
          return invalidExperimentalActionPlan(
            'parameter',
            `$/nodes/${nodeIndex}/inputs/${bindingIndex}/source/path`,
            'ACTION_PLAN_OUTPUT_PATH_NOT_FOUND',
            source.message
          );
        }
        if (!experimentalSchemasAssignable(source.schema, target.schema)) {
          return invalidExperimentalActionPlan(
            'parameter',
            `$/nodes/${nodeIndex}/inputs/${bindingIndex}`,
            'ACTION_PLAN_SCHEMA_INCOMPATIBLE',
            'Source output schema is not assignable to target input schema.'
          );
        }
      }
      const required = requiredInputsCovered(
        targetSpec.inputSchema,
        '',
        targetPaths
      );
      if (!required.ok) {
        return invalidExperimentalActionPlan(
          'parameter',
          `$/nodes/${nodeIndex}/inputs`,
          'ACTION_PLAN_REQUIRED_INPUT_MISSING',
          `Required tool input is not bound: ${required.path}.`
        );
      }
    }
    return validExperimentalActionPlan();
  }
}
