import { JsonValue } from '../ActionPlanTypes';
import { ExperimentalJsonSchema } from './ExperimentalJsonSchema';
import { EXPERIMENTAL_ACTION_PLAN_PROPOSAL_VERSION } from
  './ExperimentalProposedActionPlan';
import { ExperimentalToolSpec } from './ExperimentalToolTypes';

export interface ExperimentalPlanningJsonSchema {
  type?: string;
  description?: string;
  properties?: Record<string, ExperimentalPlanningJsonSchema>;
  required?: string[];
  additionalProperties?: boolean;
  items?: ExperimentalPlanningJsonSchema;
  enum?: JsonValue[];
  const?: JsonValue;
  anyOf?: ExperimentalPlanningJsonSchema[];
  minimum?: number;
  maximum?: number;
  minLength?: number;
  minItems?: number;
  maxItems?: number;
  pattern?: string;
}

export interface ExperimentalSubmitActionPlanFunction {
  name: string;
  description: string;
  strict: boolean;
  parameters: ExperimentalPlanningJsonSchema;
}

export interface ExperimentalSubmitActionPlanTool {
  type: 'function';
  function: ExperimentalSubmitActionPlanFunction;
}

function stringSchema(
  description: string = '',
  pattern: string = ''
): ExperimentalPlanningJsonSchema {
  const schema: ExperimentalPlanningJsonSchema = {
    type: 'string',
    minLength: 1
  };
  if (description.length > 0) {
    schema.description = description;
  }
  if (pattern.length > 0) {
    schema.pattern = pattern;
  }
  return schema;
}

function strictConstantSchema(
  source: ExperimentalJsonSchema
): ExperimentalPlanningJsonSchema {
  const schema: ExperimentalPlanningJsonSchema = {
    type: source.type
  };
  if (source.description !== undefined) {
    schema.description = source.description;
  }
  if (source.enum !== undefined) {
    schema.enum = source.enum.slice();
  }
  if (source.minimum !== undefined) {
    schema.minimum = source.minimum;
  }
  if (source.maximum !== undefined) {
    schema.maximum = source.maximum;
  }
  if (source.minLength !== undefined) {
    schema.minLength = source.minLength;
  }
  if (source.type === 'object') {
    const sourceProperties = source.properties === undefined ?
      {} as Record<string, ExperimentalJsonSchema> : source.properties;
    const properties: Record<string, ExperimentalPlanningJsonSchema> = {};
    const keys = Object.keys(sourceProperties);
    for (let index = 0; index < keys.length; index++) {
      properties[keys[index]] = strictConstantSchema(sourceProperties[keys[index]]);
    }
    schema.properties = properties;
    // Strict Tool Call schemas require every declared property to be required.
    // Supplying an originally optional property remains valid for the source
    // tool schema because only declared properties are emitted.
    schema.required = keys;
    schema.additionalProperties = false;
  } else if (source.type === 'array' && source.items !== undefined) {
    schema.items = strictConstantSchema(source.items);
  }
  return schema;
}

function collectConstantSchemas(
  schema: ExperimentalJsonSchema,
  candidates: ExperimentalPlanningJsonSchema[],
  seen: Set<string>
): void {
  const strict = strictConstantSchema(schema);
  const key = JSON.stringify(strict);
  if (!seen.has(key)) {
    seen.add(key);
    candidates.push(strict);
  }
  if (schema.type === 'object' && schema.properties !== undefined) {
    const keys = Object.keys(schema.properties);
    for (let index = 0; index < keys.length; index++) {
      collectConstantSchemas(schema.properties[keys[index]], candidates, seen);
    }
  } else if (schema.type === 'array' && schema.items !== undefined) {
    collectConstantSchemas(schema.items, candidates, seen);
  }
}

function constantValueSchema(
  tools: ExperimentalToolSpec[]
): ExperimentalPlanningJsonSchema {
  const candidates: ExperimentalPlanningJsonSchema[] = [];
  const seen: Set<string> = new Set<string>();
  for (let index = 0; index < tools.length; index++) {
    collectConstantSchemas(tools[index].inputSchema, candidates, seen);
  }
  return {
    anyOf: candidates
  };
}

function sourceSchema(
  tools: ExperimentalToolSpec[]
): ExperimentalPlanningJsonSchema {
  const constantKindSchema: ExperimentalPlanningJsonSchema = {
    type: 'string',
    const: 'constant'
  };
  const constantProperties: Record<string, ExperimentalPlanningJsonSchema> = {};
  constantProperties['kind'] = constantKindSchema;
  constantProperties['value'] = constantValueSchema(tools);
  const nodeOutputKindSchema: ExperimentalPlanningJsonSchema = {
    type: 'string',
    const: 'node_output'
  };
  const nodeOutputPathSchema: ExperimentalPlanningJsonSchema = {
    type: 'string',
    pattern: '^(|/.*)$'
  };
  const nodeOutputProperties: Record<string, ExperimentalPlanningJsonSchema> = {};
  nodeOutputProperties['kind'] = nodeOutputKindSchema;
  nodeOutputProperties['nodeId'] =
    stringSchema('The local id of the source node.');
  nodeOutputProperties['path'] = nodeOutputPathSchema;
  return {
    anyOf: [{
      type: 'object',
      properties: constantProperties,
      required: ['kind', 'value'],
      additionalProperties: false
    }, {
      type: 'object',
      properties: nodeOutputProperties,
      required: ['kind', 'nodeId', 'path'],
      additionalProperties: false
    }]
  };
}

function bindingSchema(
  tools: ExperimentalToolSpec[]
): ExperimentalPlanningJsonSchema {
  const properties: Record<string, ExperimentalPlanningJsonSchema> = {};
  properties['targetPath'] = stringSchema(
    'A non-root JSON Pointer into the target input or result object.',
    '^/.*'
  );
  properties['source'] = sourceSchema(tools);
  return {
    type: 'object',
    properties,
    required: ['targetPath', 'source'],
    additionalProperties: false
  };
}

function nodeSchema(
  tools: ExperimentalToolSpec[]
): ExperimentalPlanningJsonSchema {
  const toolIds: JsonValue[] = [];
  for (let index = 0; index < tools.length; index++) {
    toolIds.push(tools[index].toolId);
  }
  const toolIdSchema: ExperimentalPlanningJsonSchema = {
    type: 'string',
    enum: toolIds
  };
  const inputsSchema: ExperimentalPlanningJsonSchema = {
    type: 'array',
    items: bindingSchema(tools),
    minItems: 0,
    maxItems: 64
  };
  const properties: Record<string, ExperimentalPlanningJsonSchema> = {};
  properties['nodeId'] =
    stringSchema('A unique local id for this tool invocation.');
  properties['toolId'] = toolIdSchema;
  properties['inputs'] = inputsSchema;
  return {
    type: 'object',
    properties,
    required: ['nodeId', 'toolId', 'inputs'],
    additionalProperties: false
  };
}

export function buildExperimentalSubmitActionPlanTool(
  tools: ExperimentalToolSpec[]
): ExperimentalSubmitActionPlanTool {
  const bindingsSchema: ExperimentalPlanningJsonSchema = {
    type: 'array',
    items: bindingSchema(tools),
    minItems: 1,
    maxItems: 64
  };
  const resultProperties: Record<string, ExperimentalPlanningJsonSchema> = {};
  resultProperties['bindings'] = bindingsSchema;
  const protocolVersionSchema: ExperimentalPlanningJsonSchema = {
    type: 'string',
    const: EXPERIMENTAL_ACTION_PLAN_PROPOSAL_VERSION
  };
  const nodesSchema: ExperimentalPlanningJsonSchema = {
    type: 'array',
    items: nodeSchema(tools),
    minItems: 0,
    maxItems: 12
  };
  const resultSchema: ExperimentalPlanningJsonSchema = {
    type: 'object',
    properties: resultProperties,
    required: ['bindings'],
    additionalProperties: false
  };
  const planProperties: Record<string, ExperimentalPlanningJsonSchema> = {};
  planProperties['protocolVersion'] = protocolVersionSchema;
  planProperties['label'] =
    stringSchema('A short user-facing label for this plan.');
  planProperties['nodes'] = nodesSchema;
  planProperties['result'] = resultSchema;
  return {
    type: 'function',
    function: {
      name: 'submit_action_plan',
      description: 'Submit exactly one proposed Action Plan without executing business tools.',
      strict: true,
      parameters: {
        type: 'object',
        properties: planProperties,
        required: ['protocolVersion', 'label', 'nodes', 'result'],
        additionalProperties: false
      }
    }
  };
}
