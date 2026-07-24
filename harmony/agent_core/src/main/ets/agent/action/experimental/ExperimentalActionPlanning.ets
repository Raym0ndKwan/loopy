import { ExperimentalToolSpec } from './ExperimentalToolTypes';

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
  handle(request: ExperimentalActionPlanningRequest): Promise<void>;
}

/**
 * Default placeholder used by experiments that want to observe the complete
 * inbound chain before an LLM-backed compiler is installed.
 */
export class EmptyExperimentalActionPlanRequestHandler
implements ExperimentalActionPlanRequestHandler {
  handle(_request: ExperimentalActionPlanningRequest): Promise<void> {
    return Promise.resolve();
  }
}
