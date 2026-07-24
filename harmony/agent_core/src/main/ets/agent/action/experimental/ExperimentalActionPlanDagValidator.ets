import {
  ExperimentalActionBinding,
  ExperimentalProposedActionPlan
} from './ExperimentalProposedActionPlan';
import {
  ExperimentalActionPlanValidationResult,
  invalidExperimentalActionPlan,
  validExperimentalActionPlan
} from './ExperimentalActionPlanValidationTypes';

export class ExperimentalActionPlanDagValidator {
  validate(plan: ExperimentalProposedActionPlan): ExperimentalActionPlanValidationResult {
    const indexes: Map<string, number> = new Map<string, number>();
    for (let index = 0; index < plan.nodes.length; index++) {
      const nodeId = plan.nodes[index].nodeId;
      if (indexes.has(nodeId)) {
        return invalidExperimentalActionPlan(
          'dag',
          `$/nodes/${index}/nodeId`,
          'ACTION_PLAN_NODE_ID_DUPLICATE',
          `Action plan node id is duplicated: ${nodeId}.`
        );
      }
      indexes.set(nodeId, index);
    }

    const dependencies: Map<string, Set<string>> = new Map<string, Set<string>>();
    const dependents: Map<string, string[]> = new Map<string, string[]>();
    for (let index = 0; index < plan.nodes.length; index++) {
      const node = plan.nodes[index];
      const nodeDependencies: Set<string> = new Set<string>();
      for (let bindingIndex = 0; bindingIndex < node.inputs.length; bindingIndex++) {
        const binding: ExperimentalActionBinding = node.inputs[bindingIndex];
        if (binding.source.kind !== 'node_output') {
          continue;
        }
        const sourceId = binding.source.nodeId;
        if (!indexes.has(sourceId)) {
          return invalidExperimentalActionPlan(
            'dag',
            `$/nodes/${index}/inputs/${bindingIndex}/source/nodeId`,
            'ACTION_PLAN_DEPENDENCY_NOT_FOUND',
            `Action plan dependency does not exist: ${sourceId}.`
          );
        }
        if (sourceId === node.nodeId) {
          return invalidExperimentalActionPlan(
            'dag',
            `$/nodes/${index}/inputs/${bindingIndex}/source/nodeId`,
            'ACTION_PLAN_SELF_DEPENDENCY',
            'Action plan node cannot depend on itself.'
          );
        }
        nodeDependencies.add(sourceId);
      }
      dependencies.set(node.nodeId, nodeDependencies);
      dependents.set(node.nodeId, []);
    }

    dependencies.forEach((sources: Set<string>, targetId: string) => {
      sources.forEach((sourceId: string) => {
        const targets = dependents.get(sourceId);
        if (targets !== undefined) {
          targets.push(targetId);
        }
      });
    });

    const ready: string[] = [];
    for (let index = 0; index < plan.nodes.length; index++) {
      const nodeId = plan.nodes[index].nodeId;
      const sources = dependencies.get(nodeId);
      if (sources !== undefined && sources.size === 0) {
        ready.push(nodeId);
      }
    }
    const order: string[] = [];
    while (ready.length > 0) {
      const current = ready.shift() as string;
      order.push(current);
      const targets = dependents.get(current);
      if (targets === undefined) {
        continue;
      }
      for (let index = 0; index < targets.length; index++) {
        const remaining = dependencies.get(targets[index]);
        if (remaining === undefined) {
          continue;
        }
        remaining.delete(current);
        if (remaining.size === 0) {
          ready.push(targets[index]);
        }
      }
    }
    if (order.length !== plan.nodes.length) {
      return invalidExperimentalActionPlan(
        'dag',
        '$/nodes',
        'ACTION_PLAN_DAG_CYCLE',
        'Action plan dependency graph contains a cycle.'
      );
    }
    return validExperimentalActionPlan(order);
  }
}
