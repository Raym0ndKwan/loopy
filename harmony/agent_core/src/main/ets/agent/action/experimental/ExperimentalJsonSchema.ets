import { JsonValue } from '../ActionPlanTypes';

export type ExperimentalJsonSchemaType =
  'object' | 'array' | 'string' | 'number' | 'integer' | 'boolean' | 'null';

export interface ExperimentalJsonSchema {
  type: ExperimentalJsonSchemaType;
  description?: string;
  properties?: Record<string, ExperimentalJsonSchema>;
  required?: string[];
  additionalProperties?: boolean;
  items?: ExperimentalJsonSchema;
  enum?: JsonValue[];
  minimum?: number;
  maximum?: number;
  minLength?: number;
}

export interface ExperimentalSchemaValidationResult {
  ok: boolean;
  path: string;
  code: string;
  message: string;
}

const MAX_SCHEMA_DEPTH: number = 12;

function valid(path: string = '$'): ExperimentalSchemaValidationResult {
  return {
    ok: true,
    path,
    code: '',
    message: ''
  };
}

function invalid(
  path: string,
  code: string,
  message: string
): ExperimentalSchemaValidationResult {
  return {
    ok: false,
    path,
    code,
    message
  };
}

function isSupportedType(type: string): boolean {
  return type === 'object' || type === 'array' || type === 'string' ||
    type === 'number' || type === 'integer' || type === 'boolean' ||
    type === 'null';
}

function valueRecord(
  value: JsonValue
): Record<string, Object | string | number | boolean | null | undefined> {
  return value as Record<string, Object | string | number | boolean | null | undefined>;
}

function owns(record: Record<string, Object | string | number | boolean | null | undefined>, key: string): boolean {
  return Object.keys(record).indexOf(key) >= 0;
}

function enumMatches(expected: JsonValue, actual: JsonValue): boolean {
  if (expected === null || actual === null ||
    typeof expected !== 'object' || typeof actual !== 'object') {
    return expected === actual;
  }
  try {
    return JSON.stringify(expected) === JSON.stringify(actual);
  } catch (_error) {
    return false;
  }
}

function validateEnum(
  schema: ExperimentalJsonSchema,
  value: JsonValue,
  path: string
): ExperimentalSchemaValidationResult {
  if (schema.enum === undefined) {
    return valid(path);
  }
  if (!Array.isArray(schema.enum) || schema.enum.length === 0) {
    return invalid(path, 'SCHEMA_ENUM_INVALID', 'Schema enum must not be empty.');
  }
  for (let index = 0; index < schema.enum.length; index++) {
    if (enumMatches(schema.enum[index], value)) {
      return valid(path);
    }
  }
  return invalid(path, 'VALUE_NOT_IN_ENUM', 'Value is not one of the allowed enum values.');
}

function validateObject(
  schema: ExperimentalJsonSchema,
  value: JsonValue,
  path: string,
  depth: number
): ExperimentalSchemaValidationResult {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    return invalid(path, 'VALUE_TYPE_MISMATCH', 'Expected an object.');
  }
  const record = valueRecord(value);
  const properties = schema.properties === undefined ?
    {} as Record<string, ExperimentalJsonSchema> : schema.properties;
  const required = schema.required === undefined ? [] : schema.required;
  for (let index = 0; index < required.length; index++) {
    if (!owns(record, required[index])) {
      return invalid(
        `${path}/${required[index]}`,
        'VALUE_REQUIRED_PROPERTY_MISSING',
        `Required property is missing: ${required[index]}.`
      );
    }
  }
  const keys = Object.keys(record);
  for (let index = 0; index < keys.length; index++) {
    const key = keys[index];
    const propertySchema = properties[key];
    if (propertySchema === undefined) {
      if (schema.additionalProperties === false) {
        return invalid(
          `${path}/${key}`,
          'VALUE_ADDITIONAL_PROPERTY',
          `Additional property is not allowed: ${key}.`
        );
      }
      continue;
    }
    const propertyValue = record[key] as JsonValue;
    const result = validateExperimentalValue(propertySchema, propertyValue, `${path}/${key}`, depth + 1);
    if (!result.ok) {
      return result;
    }
  }
  return valid(path);
}

function validateArray(
  schema: ExperimentalJsonSchema,
  value: JsonValue,
  path: string,
  depth: number
): ExperimentalSchemaValidationResult {
  if (!Array.isArray(value)) {
    return invalid(path, 'VALUE_TYPE_MISMATCH', 'Expected an array.');
  }
  if (schema.items === undefined) {
    return valid(path);
  }
  for (let index = 0; index < value.length; index++) {
    const result = validateExperimentalValue(
      schema.items,
      value[index] as JsonValue,
      `${path}/${index}`,
      depth + 1
    );
    if (!result.ok) {
      return result;
    }
  }
  return valid(path);
}

function validateString(
  schema: ExperimentalJsonSchema,
  value: JsonValue,
  path: string
): ExperimentalSchemaValidationResult {
  if (typeof value !== 'string') {
    return invalid(path, 'VALUE_TYPE_MISMATCH', 'Expected a string.');
  }
  if (schema.minLength !== undefined && value.length < schema.minLength) {
    return invalid(path, 'VALUE_STRING_TOO_SHORT', 'String is shorter than minLength.');
  }
  return valid(path);
}

function validateNumber(
  schema: ExperimentalJsonSchema,
  value: JsonValue,
  path: string,
  integer: boolean
): ExperimentalSchemaValidationResult {
  if (typeof value !== 'number' || !Number.isFinite(value) ||
    (integer && Math.floor(value) !== value)) {
    return invalid(
      path,
      'VALUE_TYPE_MISMATCH',
      integer ? 'Expected an integer.' : 'Expected a finite number.'
    );
  }
  if (schema.minimum !== undefined && value < schema.minimum) {
    return invalid(path, 'VALUE_NUMBER_TOO_SMALL', 'Number is smaller than minimum.');
  }
  if (schema.maximum !== undefined && value > schema.maximum) {
    return invalid(path, 'VALUE_NUMBER_TOO_LARGE', 'Number is larger than maximum.');
  }
  return valid(path);
}

export function validateExperimentalValue(
  schema: ExperimentalJsonSchema,
  value: JsonValue,
  path: string = '$',
  depth: number = 0
): ExperimentalSchemaValidationResult {
  if (depth > MAX_SCHEMA_DEPTH) {
    return invalid(path, 'SCHEMA_DEPTH_EXCEEDED', 'Schema nesting exceeds the experimental limit.');
  }
  const enumResult = validateEnum(schema, value, path);
  if (!enumResult.ok) {
    return enumResult;
  }
  if (schema.type === 'object') {
    return validateObject(schema, value, path, depth);
  }
  if (schema.type === 'array') {
    return validateArray(schema, value, path, depth);
  }
  if (schema.type === 'string') {
    return validateString(schema, value, path);
  }
  if (schema.type === 'number') {
    return validateNumber(schema, value, path, false);
  }
  if (schema.type === 'integer') {
    return validateNumber(schema, value, path, true);
  }
  if (schema.type === 'boolean') {
    return typeof value === 'boolean' ?
      valid(path) : invalid(path, 'VALUE_TYPE_MISMATCH', 'Expected a boolean.');
  }
  return value === null ?
    valid(path) : invalid(path, 'VALUE_TYPE_MISMATCH', 'Expected null.');
}

function validateSchemaNode(
  schema: ExperimentalJsonSchema,
  path: string,
  depth: number
): ExperimentalSchemaValidationResult {
  if (schema === null || typeof schema !== 'object' || Array.isArray(schema)) {
    return invalid(path, 'SCHEMA_INVALID', 'Schema must be an object.');
  }
  if (depth > MAX_SCHEMA_DEPTH) {
    return invalid(path, 'SCHEMA_DEPTH_EXCEEDED', 'Schema nesting exceeds the experimental limit.');
  }
  if (typeof schema.type !== 'string' || !isSupportedType(schema.type)) {
    return invalid(`${path}/type`, 'SCHEMA_TYPE_INVALID', 'Schema type is unsupported.');
  }
  if (schema.description !== undefined && typeof schema.description !== 'string') {
    return invalid(`${path}/description`, 'SCHEMA_DESCRIPTION_INVALID', 'Schema description must be a string.');
  }
  if (schema.minimum !== undefined && typeof schema.minimum !== 'number') {
    return invalid(`${path}/minimum`, 'SCHEMA_MINIMUM_INVALID', 'Schema minimum must be a number.');
  }
  if (schema.maximum !== undefined && typeof schema.maximum !== 'number') {
    return invalid(`${path}/maximum`, 'SCHEMA_MAXIMUM_INVALID', 'Schema maximum must be a number.');
  }
  if (schema.minimum !== undefined && schema.maximum !== undefined &&
    schema.minimum > schema.maximum) {
    return invalid(path, 'SCHEMA_NUMBER_RANGE_INVALID', 'Schema minimum exceeds maximum.');
  }
  if (schema.minLength !== undefined &&
    (typeof schema.minLength !== 'number' || schema.minLength < 0 ||
      Math.floor(schema.minLength) !== schema.minLength)) {
    return invalid(`${path}/minLength`, 'SCHEMA_MIN_LENGTH_INVALID', 'Schema minLength must be a non-negative integer.');
  }
  if (schema.enum !== undefined && (!Array.isArray(schema.enum) || schema.enum.length === 0)) {
    return invalid(`${path}/enum`, 'SCHEMA_ENUM_INVALID', 'Schema enum must not be empty.');
  }
  if (schema.type === 'object') {
    const properties = schema.properties === undefined ?
      {} as Record<string, ExperimentalJsonSchema> : schema.properties;
    const propertyKeys = Object.keys(properties);
    for (let index = 0; index < propertyKeys.length; index++) {
      const key = propertyKeys[index];
      const result = validateSchemaNode(properties[key], `${path}/properties/${key}`, depth + 1);
      if (!result.ok) {
        return result;
      }
    }
    const required = schema.required === undefined ? [] : schema.required;
    const seen: Set<string> = new Set<string>();
    for (let index = 0; index < required.length; index++) {
      const key = required[index];
      if (typeof key !== 'string' || key.length === 0 || seen.has(key) ||
        properties[key] === undefined) {
        return invalid(`${path}/required`, 'SCHEMA_REQUIRED_INVALID', 'Schema required keys must be unique declared properties.');
      }
      seen.add(key);
    }
  }
  if (schema.type === 'array') {
    if (schema.items === undefined) {
      return invalid(`${path}/items`, 'SCHEMA_ITEMS_MISSING', 'Array schema requires an items schema.');
    }
    return validateSchemaNode(schema.items, `${path}/items`, depth + 1);
  }
  return valid(path);
}

export function validateExperimentalSchema(
  schema: ExperimentalJsonSchema
): ExperimentalSchemaValidationResult {
  return validateSchemaNode(schema, '$', 0);
}

export function cloneExperimentalSchema(
  schema: ExperimentalJsonSchema
): ExperimentalJsonSchema {
  return JSON.parse(JSON.stringify(schema)) as ExperimentalJsonSchema;
}
