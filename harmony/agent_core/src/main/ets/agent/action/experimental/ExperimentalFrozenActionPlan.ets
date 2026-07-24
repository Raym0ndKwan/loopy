import { cloneJsonValue } from '../JsonPointer';
import {
  ExperimentalActionBinding,
  ExperimentalConstantValueSource,
  ExperimentalNodeOutputValueSource,
  ExperimentalProposedActionPlan
} from './ExperimentalProposedActionPlan';
import { ExperimentalToolRegistry } from './ExperimentalToolRegistry';

export const EXPERIMENTAL_FROZEN_ACTION_PLAN_VERSION: string =
  'experimental.action-plan.frozen.v1';

export interface ExperimentalFrozenActionNode {
  nodeId: string;
  toolId: string;
  toolRevision: string;
  inputs: ExperimentalActionBinding[];
}

export interface ExperimentalFrozenActionResult {
  bindings: ExperimentalActionBinding[];
}

/**
 * A validated immutable recipe addressed by actionTaskId.
 *
 * conversationId and turnId remain part of the store key/message envelope.
 * uiTaskId, planId and runId intentionally do not belong to this experiment.
 */
export interface ExperimentalFrozenActionPlan {
  protocolVersion: string;
  actionTaskId: string;
  label: string;
  nodes: ExperimentalFrozenActionNode[];
  topologicalNodeIds: string[];
  result: ExperimentalFrozenActionResult;
}

export interface ExperimentalFreezeActionPlanResult {
  ok: boolean;
  plan: ExperimentalFrozenActionPlan | null;
  errorCode: string;
  message: string;
}

function freezeFailure(
  errorCode: string,
  message: string
): ExperimentalFreezeActionPlanResult {
  return {
    ok: false,
    plan: null,
    errorCode,
    message
  };
}

function cloneBinding(binding: ExperimentalActionBinding): ExperimentalActionBinding | null {
  if (binding.source.kind === 'constant') {
    const cloned = cloneJsonValue(binding.source.value);
    if (!cloned.ok || cloned.value === undefined) {
      return null;
    }
    const source: ExperimentalConstantValueSource = {
      kind: 'constant',
      value: cloned.value
    };
    return {
      targetPath: binding.targetPath,
      source
    };
  }
  const source: ExperimentalNodeOutputValueSource = {
    kind: 'node_output',
    nodeId: binding.source.nodeId,
    path: binding.source.path
  };
  return {
    targetPath: binding.targetPath,
    source
  };
}

function cloneBindings(
  bindings: ExperimentalActionBinding[]
): ExperimentalActionBinding[] | null {
  const cloned: ExperimentalActionBinding[] = [];
  for (let index = 0; index < bindings.length; index++) {
    const binding = cloneBinding(bindings[index]);
    if (binding === null) {
      return null;
    }
    cloned.push(binding);
  }
  return cloned;
}

export function cloneExperimentalFrozenActionPlan(
  plan: ExperimentalFrozenActionPlan
): ExperimentalFrozenActionPlan | null {
  const nodes: ExperimentalFrozenActionNode[] = [];
  for (let index = 0; index < plan.nodes.length; index++) {
    const inputs = cloneBindings(plan.nodes[index].inputs);
    if (inputs === null) {
      return null;
    }
    nodes.push({
      nodeId: plan.nodes[index].nodeId,
      toolId: plan.nodes[index].toolId,
      toolRevision: plan.nodes[index].toolRevision,
      inputs
    });
  }
  const resultBindings = cloneBindings(plan.result.bindings);
  if (resultBindings === null) {
    return null;
  }
  return {
    protocolVersion: plan.protocolVersion,
    actionTaskId: plan.actionTaskId,
    label: plan.label,
    nodes,
    topologicalNodeIds: plan.topologicalNodeIds.slice(),
    result: {
      bindings: resultBindings
    }
  };
}

export class ExperimentalFrozenActionPlanFactory {
  private readonly registry: ExperimentalToolRegistry;

  constructor(registry: ExperimentalToolRegistry) {
    this.registry = registry;
  }

  freeze(
    actionTaskId: string,
    proposal: ExperimentalProposedActionPlan,
    topologicalNodeIds: string[]
  ): ExperimentalFreezeActionPlanResult {
    if (actionTaskId.trim().length === 0 ||
      topologicalNodeIds.length !== proposal.nodes.length) {
      return freezeFailure(
        'ACTION_PLAN_FREEZE_IDENTITY_INVALID',
        'Frozen plan identity or topological order is invalid.'
      );
    }
    const orderIds: Set<string> = new Set<string>();
    for (let index = 0; index < topologicalNodeIds.length; index++) {
      const nodeId = topologicalNodeIds[index];
      if (nodeId.trim().length === 0 || orderIds.has(nodeId)) {
        return freezeFailure(
          'ACTION_PLAN_FREEZE_ORDER_INVALID',
          'Frozen plan topological order is malformed.'
        );
      }
      orderIds.add(nodeId);
    }

    const nodes: ExperimentalFrozenActionNode[] = [];
    for (let index = 0; index < proposal.nodes.length; index++) {
      const node = proposal.nodes[index];
      const spec = this.registry.find(node.toolId);
      if (spec === null || !orderIds.has(node.nodeId)) {
        return freezeFailure(
          'ACTION_PLAN_FREEZE_TOOL_INVALID',
          'Frozen plan references an unavailable tool or node.'
        );
      }
      const inputs = cloneBindings(node.inputs);
      if (inputs === null) {
        return freezeFailure(
          'ACTION_PLAN_FREEZE_BINDING_INVALID',
          'Frozen plan input bindings are not JSON-compatible.'
        );
      }
      nodes.push({
        nodeId: node.nodeId,
        toolId: node.toolId,
        toolRevision: spec.revision,
        inputs
      });
    }
    const resultBindings = cloneBindings(proposal.result.bindings);
    if (resultBindings === null) {
      return freezeFailure(
        'ACTION_PLAN_FREEZE_RESULT_INVALID',
        'Frozen plan result bindings are not JSON-compatible.'
      );
    }
    const plan: ExperimentalFrozenActionPlan = {
      protocolVersion: EXPERIMENTAL_FROZEN_ACTION_PLAN_VERSION,
      actionTaskId,
      label: proposal.label,
      nodes,
      topologicalNodeIds: topologicalNodeIds.slice(),
      result: {
        bindings: resultBindings
      }
    };
    return {
      ok: true,
      plan,
      errorCode: '',
      message: ''
    };
  }
}
