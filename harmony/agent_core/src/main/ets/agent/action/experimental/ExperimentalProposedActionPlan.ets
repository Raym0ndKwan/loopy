import { JsonValue } from '../ActionPlanTypes';

export const EXPERIMENTAL_ACTION_PLAN_PROPOSAL_VERSION: string =
  'experimental.action-plan.proposal.v1';

export interface ExperimentalConstantValueSource {
  kind: 'constant';
  value: JsonValue;
}

export interface ExperimentalNodeOutputValueSource {
  kind: 'node_output';
  nodeId: string;
  path: string;
}

export type ExperimentalActionValueSource =
  ExperimentalConstantValueSource | ExperimentalNodeOutputValueSource;

export interface ExperimentalActionBinding {
  targetPath: string;
  source: ExperimentalActionValueSource;
}

export interface ExperimentalProposedActionNode {
  nodeId: string;
  toolId: string;
  inputs: ExperimentalActionBinding[];
}

export interface ExperimentalProposedActionResult {
  bindings: ExperimentalActionBinding[];
}

/**
 * Model-authored candidate only. Runtime identity, tool revisions and schema
 * fingerprints are attached later when a semantically valid plan is frozen.
 */
export interface ExperimentalProposedActionPlan {
  protocolVersion: string;
  label: string;
  nodes: ExperimentalProposedActionNode[];
  result: ExperimentalProposedActionResult;
}
