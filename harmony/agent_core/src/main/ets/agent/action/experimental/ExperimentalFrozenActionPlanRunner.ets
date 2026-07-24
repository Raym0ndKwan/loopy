import { JsonValue } from '../ActionPlanTypes';
import {
  ExperimentalFrozenActionNode,
  ExperimentalFrozenActionPlan
} from './ExperimentalFrozenActionPlan';
import {
  ExperimentalActionPlanValueResolver
} from './ExperimentalActionPlanValueResolver';
import { ExperimentalToolRegistry } from './ExperimentalToolRegistry';
import { ExperimentalToolExecutionContext } from './ExperimentalToolTypes';

export interface ExperimentalActionPlanRunContext {
  conversationId: string;
  turnId: string;
  actionTaskId: string;
  nowIso: string;
}

export type ExperimentalActionPlanProgressStatus =
  'plan_started' | 'node_started' | 'node_succeeded' | 'node_failed';

export interface ExperimentalActionPlanProgress {
  actionTaskId: string;
  status: ExperimentalActionPlanProgressStatus;
  completedNodeIds: string[];
  nodeId?: string;
  toolId?: string;
  errorCode?: string;
  message?: string;
}

export interface ExperimentalActionPlanNodeOutput {
  nodeId: string;
  toolId: string;
  output: JsonValue;
}

export interface ExperimentalActionPlanRunSuccess {
  status: 'success';
  actionTaskId: string;
  completedNodeIds: string[];
  nodeOutputs: ExperimentalActionPlanNodeOutput[];
  result: JsonValue;
}

export interface ExperimentalActionPlanRunFailure {
  status: 'error';
  actionTaskId: string;
  completedNodeIds: string[];
  nodeOutputs: ExperimentalActionPlanNodeOutput[];
  failedNodeId: string;
  errorCode: string;
  message: string;
}

export type ExperimentalActionPlanRunResult =
  ExperimentalActionPlanRunSuccess | ExperimentalActionPlanRunFailure;

export interface ExperimentalActionPlanProgressObserver {
  onProgress(progress: ExperimentalActionPlanProgress): void;
}

function failure(
  plan: ExperimentalFrozenActionPlan,
  completedNodeIds: string[],
  nodeOutputs: ExperimentalActionPlanNodeOutput[],
  failedNodeId: string,
  errorCode: string,
  message: string
): ExperimentalActionPlanRunFailure {
  return {
    status: 'error',
    actionTaskId: plan.actionTaskId,
    completedNodeIds: completedNodeIds.slice(),
    nodeOutputs: nodeOutputs.slice(),
    failedNodeId,
    errorCode,
    message
  };
}

export class ExperimentalFrozenActionPlanRunner {
  private readonly registry: ExperimentalToolRegistry;
  private readonly resolver: ExperimentalActionPlanValueResolver =
    new ExperimentalActionPlanValueResolver();

  constructor(registry: ExperimentalToolRegistry) {
    this.registry = registry;
  }

  async run(
    plan: ExperimentalFrozenActionPlan,
    context: ExperimentalActionPlanRunContext,
    observer?: ExperimentalActionPlanProgressObserver
  ): Promise<ExperimentalActionPlanRunResult> {
    const completedNodeIds: string[] = [];
    const outputs: ExperimentalActionPlanNodeOutput[] = [];
    const outputValues: Map<string, JsonValue> = new Map<string, JsonValue>();
    const nodes: Map<string, ExperimentalFrozenActionNode> =
      new Map<string, ExperimentalFrozenActionNode>();

    if (plan.actionTaskId !== context.actionTaskId ||
      plan.nodes.length !== plan.topologicalNodeIds.length) {
      return failure(
        plan,
        completedNodeIds,
        outputs,
        '',
        'ACTION_PLAN_RUN_IDENTITY_INVALID',
        'Frozen Action plan identity or topological order is invalid.'
      );
    }
    for (let index = 0; index < plan.nodes.length; index++) {
      const node = plan.nodes[index];
      if (nodes.has(node.nodeId)) {
        return failure(
          plan,
          completedNodeIds,
          outputs,
          node.nodeId,
          'ACTION_PLAN_RUN_ORDER_INVALID',
          'Frozen Action plan contains a duplicate node.'
        );
      }
      nodes.set(node.nodeId, node);
    }

    this.progress(observer, {
      actionTaskId: plan.actionTaskId,
      status: 'plan_started',
      completedNodeIds: []
    });
    const ordered: Set<string> = new Set<string>();
    for (let index = 0; index < plan.topologicalNodeIds.length; index++) {
      const nodeId = plan.topologicalNodeIds[index];
      const node = nodes.get(nodeId);
      if (node === undefined || ordered.has(nodeId)) {
        return failure(
          plan,
          completedNodeIds,
          outputs,
          nodeId,
          'ACTION_PLAN_RUN_ORDER_INVALID',
          'Frozen Action plan topological order references an invalid node.'
        );
      }
      ordered.add(nodeId);
      this.progress(observer, {
        actionTaskId: plan.actionTaskId,
        status: 'node_started',
        nodeId,
        toolId: node.toolId,
        completedNodeIds: completedNodeIds.slice()
      });

      const resolved = this.resolver.resolve(node.inputs, outputValues);
      if (!resolved.ok || resolved.value === undefined ||
        resolved.value === null ||
        typeof resolved.value !== 'object' ||
        Array.isArray(resolved.value)) {
        const errorCode = resolved.ok ?
          'ACTION_PLAN_NODE_INPUT_NOT_OBJECT' : resolved.errorCode;
        const message = resolved.ok ?
          'Resolved tool input must be an object.' : resolved.message;
        this.nodeFailed(observer, plan.actionTaskId, node, completedNodeIds, errorCode, message);
        return failure(plan, completedNodeIds, outputs, nodeId, errorCode, message);
      }

      const toolContext: ExperimentalToolExecutionContext = {
        conversationId: context.conversationId,
        turnId: context.turnId,
        actionTaskId: context.actionTaskId,
        nodeId,
        nowIso: context.nowIso
      };
      const execution = await this.registry.execute(
        node.toolId,
        node.toolRevision,
        resolved.value as Object,
        toolContext
      );
      if (execution.status === 'error') {
        this.nodeFailed(
          observer,
          plan.actionTaskId,
          node,
          completedNodeIds,
          execution.errorCode,
          execution.message
        );
        return failure(
          plan,
          completedNodeIds,
          outputs,
          nodeId,
          execution.errorCode,
          execution.message
        );
      }
      outputValues.set(nodeId, execution.output);
      outputs.push({
        nodeId,
        toolId: node.toolId,
        output: execution.output
      });
      completedNodeIds.push(nodeId);
      this.progress(observer, {
        actionTaskId: plan.actionTaskId,
        status: 'node_succeeded',
        nodeId,
        toolId: node.toolId,
        completedNodeIds: completedNodeIds.slice()
      });
    }

    const resolvedResult = this.resolver.resolve(plan.result.bindings, outputValues);
    if (!resolvedResult.ok || resolvedResult.value === undefined) {
      return failure(
        plan,
        completedNodeIds,
        outputs,
        '',
        resolvedResult.errorCode,
        resolvedResult.message
      );
    }
    return {
      status: 'success',
      actionTaskId: plan.actionTaskId,
      completedNodeIds,
      nodeOutputs: outputs,
      result: resolvedResult.value
    };
  }

  private nodeFailed(
    observer: ExperimentalActionPlanProgressObserver | undefined,
    actionTaskId: string,
    node: ExperimentalFrozenActionNode,
    completedNodeIds: string[],
    errorCode: string,
    message: string
  ): void {
    this.progress(observer, {
      actionTaskId,
      status: 'node_failed',
      nodeId: node.nodeId,
      toolId: node.toolId,
      completedNodeIds: completedNodeIds.slice(),
      errorCode,
      message
    });
  }

  private progress(
    observer: ExperimentalActionPlanProgressObserver | undefined,
    progress: ExperimentalActionPlanProgress
  ): void {
    if (observer === undefined) {
      return;
    }
    try {
      observer.onProgress(progress);
    } catch (_error) {
      // Observability must not alter execution semantics.
    }
  }
}
