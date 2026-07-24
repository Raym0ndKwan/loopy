import { JsonValue } from '../ActionPlanTypes';
import { cloneJsonValue, resolveJsonPointer } from '../JsonPointer';
import { ExperimentalActionBinding } from './ExperimentalProposedActionPlan';

type JsonRecord = Record<string, JsonValue | undefined>;

export interface ExperimentalResolvedBindings {
  ok: boolean;
  value: JsonValue | undefined;
  errorCode: string;
  message: string;
}

function failure(
  errorCode: string,
  message: string
): ExperimentalResolvedBindings {
  return {
    ok: false,
    value: undefined,
    errorCode,
    message
  };
}

function decodeToken(token: string): string | null {
  let decoded = '';
  for (let index = 0; index < token.length; index++) {
    const current = token.charAt(index);
    if (current !== '~') {
      decoded += current;
      continue;
    }
    if (index + 1 >= token.length) {
      return null;
    }
    const escaped = token.charAt(index + 1);
    if (escaped === '0') {
      decoded += '~';
    } else if (escaped === '1') {
      decoded += '/';
    } else {
      return null;
    }
    index++;
  }
  if (decoded === '__proto__' ||
    decoded === 'prototype' ||
    decoded === 'constructor') {
    return null;
  }
  return decoded;
}

function pointerTokens(pointer: string): string[] | null {
  if (pointer === '') {
    return [];
  }
  if (!pointer.startsWith('/')) {
    return null;
  }
  const encoded = pointer.substring(1).split('/');
  const tokens: string[] = [];
  for (let index = 0; index < encoded.length; index++) {
    const decoded = decodeToken(encoded[index]);
    if (decoded === null) {
      return null;
    }
    tokens.push(decoded);
  }
  return tokens;
}

function arrayIndex(token: string): number {
  if (token.length === 0 || (token.length > 1 && token.charAt(0) === '0')) {
    return -1;
  }
  for (let index = 0; index < token.length; index++) {
    const code = token.charCodeAt(index);
    if (code < 48 || code > 57) {
      return -1;
    }
  }
  const parsed = Number(token);
  return Number.isSafeInteger(parsed) && parsed >= 0 ? parsed : -1;
}

function containerFor(nextToken: string): JsonValue {
  if (arrayIndex(nextToken) >= 0) {
    const array: JsonValue[] = [];
    return array;
  }
  const record: JsonRecord = {};
  return record as Object;
}

function assign(
  document: JsonValue,
  pointer: string,
  replacement: JsonValue
): ExperimentalResolvedBindings {
  const tokens = pointerTokens(pointer);
  if (tokens === null) {
    return failure(
      'ACTION_PLAN_BINDING_TARGET_INVALID',
      `Binding target is not a valid JSON Pointer: ${pointer}.`
    );
  }
  const cloned = cloneJsonValue(replacement);
  if (!cloned.ok || cloned.value === undefined) {
    return failure('ACTION_PLAN_BINDING_VALUE_INVALID', cloned.message);
  }
  if (tokens.length === 0) {
    return {
      ok: true,
      value: cloned.value,
      errorCode: '',
      message: ''
    };
  }

  let current: JsonValue = document;
  for (let index = 0; index < tokens.length; index++) {
    const token = tokens[index];
    const final = index === tokens.length - 1;
    if (Array.isArray(current)) {
      const currentArray: JsonValue[] = current as JsonValue[];
      const selected = arrayIndex(token);
      if (selected < 0) {
        return failure(
          'ACTION_PLAN_BINDING_TARGET_INVALID',
          `Array binding target must use a canonical index: ${pointer}.`
        );
      }
      while (currentArray.length <= selected) {
        currentArray.push(null);
      }
      if (final) {
        currentArray[selected] = cloned.value as JsonValue;
        continue;
      }
      const child: JsonValue = currentArray[selected];
      if (child === null) {
        currentArray[selected] = containerFor(tokens[index + 1]);
      } else if (typeof child !== 'object') {
        return failure(
          'ACTION_PLAN_BINDING_TARGET_CONFLICT',
          `Binding target traverses a primitive value: ${pointer}.`
        );
      }
      current = currentArray[selected];
      continue;
    }
    if (current === null || typeof current !== 'object') {
      return failure(
        'ACTION_PLAN_BINDING_TARGET_CONFLICT',
        `Binding target traverses a primitive value: ${pointer}.`
      );
    }
    const record = current as JsonRecord;
    if (final) {
      record[token] = cloned.value;
      continue;
    }
    const child = record[token];
    if (child === undefined) {
      record[token] = containerFor(tokens[index + 1]);
    } else if (child === null || typeof child !== 'object') {
      return failure(
        'ACTION_PLAN_BINDING_TARGET_CONFLICT',
        `Binding target traverses a primitive value: ${pointer}.`
      );
    }
    current = record[token] as JsonValue;
  }
  return {
    ok: true,
    value: document,
    errorCode: '',
    message: ''
  };
}

function sourceValue(
  binding: ExperimentalActionBinding,
  nodeOutputs: Map<string, JsonValue>
): ExperimentalResolvedBindings {
  if (binding.source.kind === 'constant') {
    const cloned = cloneJsonValue(binding.source.value);
    if (!cloned.ok || cloned.value === undefined) {
      return failure('ACTION_PLAN_CONSTANT_INVALID', cloned.message);
    }
    return {
      ok: true,
      value: cloned.value,
      errorCode: '',
      message: ''
    };
  }
  const output = nodeOutputs.get(binding.source.nodeId);
  if (output === undefined) {
    return failure(
      'ACTION_PLAN_DEPENDENCY_NOT_COMPLETED',
      `Node output is unavailable: ${binding.source.nodeId}.`
    );
  }
  const resolved = resolveJsonPointer(output, binding.source.path);
  if (!resolved.ok || resolved.value === undefined) {
    return failure(
      'ACTION_PLAN_OUTPUT_VALUE_NOT_FOUND',
      `Cannot resolve ${binding.source.nodeId}${binding.source.path}: ${resolved.message}`
    );
  }
  return {
    ok: true,
    value: resolved.value,
    errorCode: '',
    message: ''
  };
}

export class ExperimentalActionPlanValueResolver {
  resolve(
    bindings: ExperimentalActionBinding[],
    nodeOutputs: Map<string, JsonValue>
  ): ExperimentalResolvedBindings {
    const initial: JsonRecord = {};
    let document: JsonValue = initial as Object;
    for (let index = 0; index < bindings.length; index++) {
      const binding = bindings[index];
      const source = sourceValue(binding, nodeOutputs);
      if (!source.ok || source.value === undefined) {
        return source;
      }
      const assigned = assign(
        document,
        binding.targetPath,
        source.value
      );
      if (!assigned.ok || assigned.value === undefined) {
        return assigned;
      }
      document = assigned.value;
    }
    return {
      ok: true,
      value: document,
      errorCode: '',
      message: ''
    };
  }
}
