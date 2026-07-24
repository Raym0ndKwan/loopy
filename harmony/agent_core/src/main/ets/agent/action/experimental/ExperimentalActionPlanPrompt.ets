import { ExperimentalActionPlanningRequest } from './ExperimentalActionPlanning';

export interface ExperimentalActionPlanPrompt {
  systemPrompt: string;
  userPrompt: string;
}

export function buildExperimentalActionPlanPrompt(
  request: ExperimentalActionPlanningRequest
): ExperimentalActionPlanPrompt {
  const systemPrompt =
    'You are an Action Plan compiler. You never execute business tools.\n' +
    'Compile the natural-language task into exactly one proposed Action Plan.\n' +
    'Rules:\n' +
    '1. Call submit_action_plan exactly once and output no alternative plan.\n' +
    '2. Use only toolId values present in the provided tool specifications.\n' +
    '3. Give every tool invocation a unique nodeId.\n' +
    '4. Bind every input explicitly from constant or node_output.\n' +
    '5. node_output must name a source nodeId and an output JSON Pointer.\n' +
    '6. Dependencies must form an acyclic graph.\n' +
    '7. Keep result separate from nodes and expose at least one result binding.\n' +
    '8. Every node must contribute to result; do not hide side effects.\n' +
    '9. Do not invent planId, runId, uiTaskId, actionTaskId, tool revisions, ' +
      'or schema fingerprints.';
  const userPrompt =
    `Natural-language task:\n${request.query}\n\n` +
    'Available tool specifications (descriptive only; do not call them):\n' +
    JSON.stringify(request.tools);
  return {
    systemPrompt,
    userPrompt
  };
}
