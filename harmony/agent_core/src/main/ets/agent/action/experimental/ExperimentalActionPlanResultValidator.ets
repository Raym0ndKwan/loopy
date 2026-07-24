import {
  ExperimentalActionBinding,
  ExperimentalProposedActionNode,
  ExperimentalProposedActionPlan
} from './ExperimentalProposedActionPlan';
import {
  ExperimentalActionPlanValidationResult,
  invalidExperimentalActionPlan,
  validExperimentalActionPlan
} from './ExperimentalActionPlanValidationTypes';
import {
  pointersOverlap,
  resolveExperimentalSchemaPath
} from './ExperimentalSchemaCompatibility';
import { ExperimentalToolRegistry } from './ExperimentalToolRegistry';
import { ExperimentalToolSpec } from './ExperimentalToolTypes';

function overlappingResultBinding(
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

export class ExperimentalActionPlanResultValidator {
  private readonly registry: ExperimentalToolRegistry;

  constructor(registry: ExperimentalToolRegistry) {
    this.registry = registry;
  }

  validate(plan: ExperimentalProposedActionPlan): ExperimentalActionPlanValidationResult {
    const nodes: Map<string, ExperimentalProposedActionNode> =
      new Map<string, ExperimentalProposedActionNode>();
    const specs: Map<string, ExperimentalToolSpec> =
      new Map<string, ExperimentalToolSpec>();
    for (let index = 0; index < plan.nodes.length; index++) {
      const node = plan.nodes[index];
      nodes.set(node.nodeId, node);
      const spec = this.registry.find(node.toolId);
      if (spec !== null) {
        specs.set(node.nodeId, spec);
      }
    }

    const roots: string[] = [];
    for (let index = 0; index < plan.result.bindings.length; index++) {
      const binding = plan.result.bindings[index];
      const overlap = overlappingResultBinding(plan.result.bindings, index);
      if (overlap >= 0) {
        return invalidExperimentalActionPlan(
          'result',
          `$/result/bindings/${index}/targetPath`,
          'ACTION_PLAN_RESULT_BINDING_OVERLAP',
          `Result binding overlaps binding ${overlap}.`
        );
      }
      if (binding.source.kind === 'constant') {
        continue;
      }
      const sourceNode = nodes.get(binding.source.nodeId);
      const sourceSpec = specs.get(binding.source.nodeId);
      if (sourceNode === undefined || sourceSpec === undefined) {
        return invalidExperimentalActionPlan(
          'result',
          `$/result/bindings/${index}/source/nodeId`,
          'ACTION_PLAN_RESULT_NODE_NOT_FOUND',
          `Result source node does not exist: ${binding.source.nodeId}.`
        );
      }
      const source = resolveExperimentalSchemaPath(
        sourceSpec.outputSchema,
        binding.source.path
      );
      if (!source.ok) {
        return invalidExperimentalActionPlan(
          'result',
          `$/result/bindings/${index}/source/path`,
          'ACTION_PLAN_RESULT_PATH_NOT_FOUND',
          source.message
        );
      }
      if (roots.indexOf(sourceNode.nodeId) < 0) {
        roots.push(sourceNode.nodeId);
      }
    }

    const observable: Set<string> = new Set<string>();
    const pending: string[] = roots.slice();
    while (pending.length > 0) {
      const nodeId = pending.pop() as string;
      if (observable.has(nodeId)) {
        continue;
      }
      observable.add(nodeId);
      const node = nodes.get(nodeId);
      if (node === undefined) {
        continue;
      }
      for (let index = 0; index < node.inputs.length; index++) {
        const source = node.inputs[index].source;
        if (source.kind === 'node_output' && !observable.has(source.nodeId)) {
          pending.push(source.nodeId);
        }
      }
    }

    for (let index = 0; index < plan.nodes.length; index++) {
      if (!observable.has(plan.nodes[index].nodeId)) {
        return invalidExperimentalActionPlan(
          'result',
          `$/nodes/${index}`,
          'ACTION_PLAN_NODE_NOT_OBSERVABLE',
          `Action plan node does not contribute to the final result: ` +
            `${plan.nodes[index].nodeId}.`
        );
      }
    }
    return validExperimentalActionPlan();
  }
}
