import { JsonValue } from '../ActionPlanTypes';
import {
  cloneJsonValue,
  validateJsonPointer
} from '../JsonPointer';
import {
  EXPERIMENTAL_ACTION_PLAN_PROPOSAL_VERSION,
  ExperimentalActionBinding,
  ExperimentalActionValueSource,
  ExperimentalConstantValueSource,
  ExperimentalNodeOutputValueSource,
  ExperimentalProposedActionNode,
  ExperimentalProposedActionPlan,
  ExperimentalProposedActionResult
} from './ExperimentalProposedActionPlan';

type JsonRecord = Record<string, JsonValue | undefined>;

const MAX_LABEL_LENGTH: number = 256;
const MAX_ID_LENGTH: number = 128;
const MAX_POINTER_LENGTH: number = 512;
const MAX_NODE_COUNT: number = 12;
const MAX_NODE_INPUT_COUNT: number = 64;
const MAX_RESULT_BINDING_COUNT: number = 64;

export interface ExperimentalProposedActionPlanParseSuccess {
  ok: true;
  plan: ExperimentalProposedActionPlan;
}

export interface ExperimentalProposedActionPlanParseFailure {
  ok: false;
  path: string;
  errorCode: string;
  message: string;
}

export type ExperimentalProposedActionPlanParseResult =
  ExperimentalProposedActionPlanParseSuccess |
  ExperimentalProposedActionPlanParseFailure;

interface BindingParseResult {
  ok: boolean;
  binding: ExperimentalActionBinding | null;
  path: string;
  errorCode: string;
  message: string;
}

interface NodeParseResult {
  ok: boolean;
  node: ExperimentalProposedActionNode | null;
  path: string;
  errorCode: string;
  message: string;
}

function success(plan: ExperimentalProposedActionPlan):
  ExperimentalProposedActionPlanParseSuccess {
  return {
    ok: true,
    plan
  };
}

function failure(
  path: string,
  errorCode: string,
  message: string
): ExperimentalProposedActionPlanParseFailure {
  return {
    ok: false,
    path,
    errorCode,
    message
  };
}

function bindingFailure(
  path: string,
  errorCode: string,
  message: string
): BindingParseResult {
  return {
    ok: false,
    binding: null,
    path,
    errorCode,
    message
  };
}

function nodeFailure(
  path: string,
  errorCode: string,
  message: string
): NodeParseResult {
  return {
    ok: false,
    node: null,
    path,
    errorCode,
    message
  };
}

function isObject(value: JsonValue | undefined): boolean {
  return value !== null && value !== undefined &&
    typeof value === 'object' && !Array.isArray(value);
}

function exactKeys(value: Object, expected: string): boolean {
  return Object.keys(value).sort().join(',') === expected;
}

function boundedNonempty(value: JsonValue | undefined, maximum: number): boolean {
  return typeof value === 'string' &&
    value.trim().length > 0 &&
    value.length <= maximum;
}

function validPointer(value: JsonValue | undefined, allowRoot: boolean): boolean {
  if (typeof value !== 'string' ||
    value.length > MAX_POINTER_LENGTH ||
    (!allowRoot && value.length === 0)) {
    return false;
  }
  return validateJsonPointer(value).ok;
}

function parseSource(
  value: JsonValue | undefined,
  path: string
): BindingParseResult {
  if (!isObject(value)) {
    return bindingFailure(
      path,
      'ACTION_PLAN_SOURCE_INVALID',
      'Binding source must be an object.'
    );
  }
  const sourceObject = value as Object;
  const source = sourceObject as JsonRecord;
  const kind = source['kind'];
  if (kind === 'constant') {
    if (!exactKeys(sourceObject, 'kind,value')) {
      return bindingFailure(
        path,
        'ACTION_PLAN_CONSTANT_SOURCE_INVALID',
        'Constant source must contain exactly kind and value.'
      );
    }
    const cloned = cloneJsonValue(source['value'] as JsonValue);
    if (!cloned.ok || cloned.value === undefined) {
      return bindingFailure(
        `${path}/value`,
        'ACTION_PLAN_CONSTANT_VALUE_INVALID',
        'Constant source value must be JSON-compatible.'
      );
    }
    const constant: ExperimentalConstantValueSource = {
      kind: 'constant',
      value: cloned.value as JsonValue
    };
    const binding: ExperimentalActionBinding = {
      targetPath: '',
      source: constant
    };
    return {
      ok: true,
      binding,
      path: '',
      errorCode: '',
      message: ''
    };
  }
  if (kind === 'node_output') {
    if (!exactKeys(sourceObject, 'kind,nodeId,path') ||
      !boundedNonempty(source['nodeId'], MAX_ID_LENGTH) ||
      !validPointer(source['path'], true)) {
      return bindingFailure(
        path,
        'ACTION_PLAN_NODE_OUTPUT_SOURCE_INVALID',
        'Node output source must contain a nodeId and a valid JSON Pointer path.'
      );
    }
    const nodeOutput: ExperimentalNodeOutputValueSource = {
      kind: 'node_output',
      nodeId: source['nodeId'] as string,
      path: source['path'] as string
    };
    const binding: ExperimentalActionBinding = {
      targetPath: '',
      source: nodeOutput
    };
    return {
      ok: true,
      binding,
      path: '',
      errorCode: '',
      message: ''
    };
  }
  return bindingFailure(
    `${path}/kind`,
    'ACTION_PLAN_SOURCE_KIND_INVALID',
    'Binding source kind must be constant or node_output.'
  );
}

function parseBinding(
  value: JsonValue | undefined,
  path: string
): BindingParseResult {
  if (!isObject(value)) {
    return bindingFailure(
      path,
      'ACTION_PLAN_BINDING_INVALID',
      'Binding must be an object.'
    );
  }
  const bindingObject = value as Object;
  const bindingRecord = bindingObject as JsonRecord;
  if (!exactKeys(bindingObject, 'source,targetPath') ||
    !validPointer(bindingRecord['targetPath'], false)) {
    return bindingFailure(
      path,
      'ACTION_PLAN_BINDING_INVALID',
      'Binding must contain a non-root targetPath and a source.'
    );
  }
  const sourceResult = parseSource(bindingRecord['source'], `${path}/source`);
  if (!sourceResult.ok || sourceResult.binding === null) {
    return sourceResult;
  }
  return {
    ok: true,
    binding: {
      targetPath: bindingRecord['targetPath'] as string,
      source: sourceResult.binding.source as ExperimentalActionValueSource
    },
    path: '',
    errorCode: '',
    message: ''
  };
}

function parseBindings(
  value: JsonValue | undefined,
  path: string,
  maximum: number,
  requireNonempty: boolean
): ExperimentalActionBinding[] | ExperimentalProposedActionPlanParseFailure {
  if (!Array.isArray(value) ||
    value.length > maximum ||
    (requireNonempty && value.length === 0)) {
    return failure(
      path,
      'ACTION_PLAN_BINDINGS_INVALID',
      requireNonempty ?
        'Bindings must be a nonempty bounded array.' :
        'Bindings must be a bounded array.'
    );
  }
  const bindings: ExperimentalActionBinding[] = [];
  for (let index = 0; index < value.length; index++) {
    const parsed = parseBinding(value[index] as JsonValue, `${path}/${index}`);
    if (!parsed.ok || parsed.binding === null) {
      return failure(parsed.path, parsed.errorCode, parsed.message);
    }
    bindings.push(parsed.binding);
  }
  return bindings;
}

function parseNode(
  value: JsonValue | undefined,
  path: string
): NodeParseResult {
  if (!isObject(value)) {
    return nodeFailure(path, 'ACTION_PLAN_NODE_INVALID', 'Plan node must be an object.');
  }
  const nodeObject = value as Object;
  const nodeRecord = nodeObject as JsonRecord;
  if (!exactKeys(nodeObject, 'inputs,nodeId,toolId') ||
    !boundedNonempty(nodeRecord['nodeId'], MAX_ID_LENGTH) ||
    !boundedNonempty(nodeRecord['toolId'], MAX_ID_LENGTH)) {
    return nodeFailure(
      path,
      'ACTION_PLAN_NODE_INVALID',
      'Plan node must contain nodeId, toolId and inputs.'
    );
  }
  const inputs = parseBindings(
    nodeRecord['inputs'],
    `${path}/inputs`,
    MAX_NODE_INPUT_COUNT,
    false
  );
  if (!Array.isArray(inputs)) {
    return nodeFailure(inputs.path, inputs.errorCode, inputs.message);
  }
  return {
    ok: true,
    node: {
      nodeId: nodeRecord['nodeId'] as string,
      toolId: nodeRecord['toolId'] as string,
      inputs
    },
    path: '',
    errorCode: '',
    message: ''
  };
}

export function parseExperimentalProposedActionPlan(
  value: JsonValue
): ExperimentalProposedActionPlanParseResult {
  try {
    if (!isObject(value)) {
      return failure('$', 'ACTION_PLAN_PROPOSAL_INVALID', 'Proposed plan must be an object.');
    }
    const planObject = value as Object;
    const planRecord = planObject as JsonRecord;
    if (!exactKeys(planObject, 'label,nodes,protocolVersion,result')) {
      return failure(
        '$',
        'ACTION_PLAN_PROPOSAL_FIELDS_INVALID',
        'Proposed plan contains missing or unknown fields.'
      );
    }
    if (planRecord['protocolVersion'] !== EXPERIMENTAL_ACTION_PLAN_PROPOSAL_VERSION) {
      return failure(
        '$/protocolVersion',
        'ACTION_PLAN_PROPOSAL_VERSION_INVALID',
        'Proposed plan protocol version is unsupported.'
      );
    }
    if (!boundedNonempty(planRecord['label'], MAX_LABEL_LENGTH)) {
      return failure(
        '$/label',
        'ACTION_PLAN_LABEL_INVALID',
        'Proposed plan label must be a bounded nonempty string.'
      );
    }
    const rawNodes = planRecord['nodes'];
    if (!Array.isArray(rawNodes) || rawNodes.length > MAX_NODE_COUNT) {
      return failure(
        '$/nodes',
        'ACTION_PLAN_NODES_INVALID',
        'Proposed plan nodes must be a bounded array.'
      );
    }
    const nodes: ExperimentalProposedActionNode[] = [];
    for (let index = 0; index < rawNodes.length; index++) {
      const parsed = parseNode(rawNodes[index] as JsonValue, `$/nodes/${index}`);
      if (!parsed.ok || parsed.node === null) {
        return failure(parsed.path, parsed.errorCode, parsed.message);
      }
      nodes.push(parsed.node);
    }
    const rawResult = planRecord['result'];
    if (!isObject(rawResult) ||
      !exactKeys(rawResult as Object, 'bindings')) {
      return failure(
        '$/result',
        'ACTION_PLAN_RESULT_INVALID',
        'Proposed plan result must contain exactly bindings.'
      );
    }
    const resultRecord = rawResult as JsonRecord;
    const bindings = parseBindings(
      resultRecord['bindings'],
      '$/result/bindings',
      MAX_RESULT_BINDING_COUNT,
      true
    );
    if (!Array.isArray(bindings)) {
      return bindings;
    }
    const result: ExperimentalProposedActionResult = {
      bindings
    };
    return success({
      protocolVersion: EXPERIMENTAL_ACTION_PLAN_PROPOSAL_VERSION,
      label: planRecord['label'] as string,
      nodes,
      result
    });
  } catch (_error) {
    return failure(
      '$',
      'ACTION_PLAN_PROPOSAL_PARSE_FAILED',
      'Proposed plan parsing failed.'
    );
  }
}
