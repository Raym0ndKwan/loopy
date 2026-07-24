import { ExperimentalToolSpec } from './ExperimentalToolTypes';
import { ExperimentalProposedActionPlan } from './ExperimentalProposedActionPlan';

/**
 * Fully resolved input for the experimental Action planning boundary.
 *
 * The bus only carries authorized tool ids. ActionAgent resolves those ids
 * through its local registry before invoking the handler, so a handler never
 * needs direct access to the registry or to executable tool implementations.
 */
export interface ExperimentalActionPlanningRequest {
  conversationId: string;
  turnId: string;
  actionTaskId: string;
  uiTaskId: string;
  query: string;
  tools: ExperimentalToolSpec[];
}

/**
 * Experimental seam for the future LLM-backed plan compiler.
 *
 * Plan output is deliberately absent until the frozen Action Plan protocol is
 * defined. The first experiment only establishes and tests the inbound call
 * chain.
 */
export interface ExperimentalActionPlanRequestHandler {
  handle(
    request: ExperimentalActionPlanningRequest
  ): Promise<ExperimentalActionPlanningResult>;
}

export interface ExperimentalActionPlanProposalResult {
  status: 'proposal';
  proposal: ExperimentalProposedActionPlan;
}

export type ExperimentalActionPlanningFailureKind =
  'not_implemented' | 'model' | 'protocol';

export interface ExperimentalActionPlanningFailure {
  status: 'failure';
  failureKind: ExperimentalActionPlanningFailureKind;
  errorCode: string;
  message: string;
}

export type ExperimentalActionPlanningResult =
  ExperimentalActionPlanProposalResult | ExperimentalActionPlanningFailure;

/**
 * Default placeholder used by experiments that want to observe the complete
 * inbound chain before an LLM-backed compiler is installed.
 */
export class EmptyExperimentalActionPlanRequestHandler
implements ExperimentalActionPlanRequestHandler {
  handle(
    _request: ExperimentalActionPlanningRequest
  ): Promise<ExperimentalActionPlanningResult> {
    const failure: ExperimentalActionPlanningFailure = {
      status: 'failure',
      failureKind: 'not_implemented',
      errorCode: 'ACTION_PLAN_HANDLER_NOT_IMPLEMENTED',
      message: 'Experimental Action Plan handler is not implemented.'
    };
    return Promise.resolve(failure);
  }
}
