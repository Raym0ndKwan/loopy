import { JsonValue } from '../ActionPlanTypes';
import {
  cloneExperimentalSchema,
  ExperimentalSchemaValidationResult,
  validateExperimentalSchema,
  validateExperimentalValue
} from './ExperimentalJsonSchema';
import {
  ExperimentalToolDefinition,
  ExperimentalToolErrorResult,
  ExperimentalToolExample,
  ExperimentalToolExecutionContext,
  ExperimentalToolExecutionResult,
  ExperimentalToolExecutor,
  ExperimentalToolRisk,
  ExperimentalToolSpec
} from './ExperimentalToolTypes';

interface StoredExperimentalTool {
  spec: ExperimentalToolSpec;
  executor: ExperimentalToolExecutor;
}

function nonempty(value: string): boolean {
  return typeof value === 'string' && value.trim().length > 0;
}

function validRisk(risk: ExperimentalToolRisk): boolean {
  return risk === 'read' || risk === 'draft' || risk === 'confirm_required';
}

function cloneValue(value: JsonValue): JsonValue {
  if (value === null || typeof value !== 'object') {
    return value;
  }
  return JSON.parse(JSON.stringify(value)) as JsonValue;
}

function cloneExamples(
  examples: ExperimentalToolExample[] | undefined
): ExperimentalToolExample[] | undefined {
  if (examples === undefined) {
    return undefined;
  }
  const cloned: ExperimentalToolExample[] = [];
  for (let index = 0; index < examples.length; index++) {
    const source = examples[index];
    const example: ExperimentalToolExample = {
      input: cloneValue(source.input),
      output: cloneValue(source.output)
    };
    if (source.explanation !== undefined) {
      example.explanation = source.explanation;
    }
    cloned.push(example);
  }
  return cloned;
}

function cloneSpec(spec: ExperimentalToolSpec): ExperimentalToolSpec {
  const cloned: ExperimentalToolSpec = {
    toolId: spec.toolId,
    revision: spec.revision,
    name: spec.name,
    description: spec.description,
    riskLevel: spec.riskLevel,
    inputSchema: cloneExperimentalSchema(spec.inputSchema),
    outputSchema: cloneExperimentalSchema(spec.outputSchema)
  };
  const examples = cloneExamples(spec.examples);
  if (examples !== undefined) {
    cloned.examples = examples;
  }
  return cloned;
}

function executionError(
  errorCode: string,
  message: string
): ExperimentalToolErrorResult {
  return {
    status: 'error',
    errorCode,
    message
  };
}

function schemaErrorMessage(prefix: string, result: ExperimentalSchemaValidationResult): string {
  return `${prefix} at ${result.path}: ${result.message}`;
}

function validateExamples(definition: ExperimentalToolDefinition): void {
  if (definition.examples === undefined) {
    return;
  }
  if (!Array.isArray(definition.examples)) {
    throw new Error(`Experimental tool examples must be an array: ${definition.toolId}.`);
  }
  for (let index = 0; index < definition.examples.length; index++) {
    const example = definition.examples[index];
    const input = validateExperimentalValue(definition.inputSchema, example.input);
    if (!input.ok) {
      throw new Error(schemaErrorMessage(
        `Experimental tool example input is invalid for ${definition.toolId}`,
        input
      ));
    }
    const output = validateExperimentalValue(definition.outputSchema, example.output);
    if (!output.ok) {
      throw new Error(schemaErrorMessage(
        `Experimental tool example output is invalid for ${definition.toolId}`,
        output
      ));
    }
  }
}

export class ExperimentalToolRegistry {
  private readonly tools: Map<string, StoredExperimentalTool> =
    new Map<string, StoredExperimentalTool>();

  register(definition: ExperimentalToolDefinition): void {
    if (definition === null || definition === undefined ||
      !nonempty(definition.toolId) || !nonempty(definition.revision) ||
      !nonempty(definition.name) || !nonempty(definition.description) ||
      !validRisk(definition.riskLevel) ||
      definition.executor === null || definition.executor === undefined ||
      typeof definition.executor.execute !== 'function') {
      throw new Error('Experimental tool definition is malformed.');
    }
    if (this.tools.has(definition.toolId)) {
      throw new Error(`Duplicate experimental tool id: ${definition.toolId}.`);
    }
    const inputSchema = validateExperimentalSchema(definition.inputSchema);
    if (!inputSchema.ok) {
      throw new Error(schemaErrorMessage(
        `Experimental input schema is invalid for ${definition.toolId}`,
        inputSchema
      ));
    }
    const outputSchema = validateExperimentalSchema(definition.outputSchema);
    if (!outputSchema.ok) {
      throw new Error(schemaErrorMessage(
        `Experimental output schema is invalid for ${definition.toolId}`,
        outputSchema
      ));
    }
    validateExamples(definition);
    const spec: ExperimentalToolSpec = {
      toolId: definition.toolId,
      revision: definition.revision,
      name: definition.name,
      description: definition.description,
      riskLevel: definition.riskLevel,
      inputSchema: cloneExperimentalSchema(definition.inputSchema),
      outputSchema: cloneExperimentalSchema(definition.outputSchema)
    };
    const examples = cloneExamples(definition.examples);
    if (examples !== undefined) {
      spec.examples = examples;
    }
    this.tools.set(definition.toolId, {
      spec,
      executor: definition.executor
    });
  }

  size(): number {
    return this.tools.size;
  }

  find(toolId: string): ExperimentalToolSpec | null {
    const stored = this.tools.get(toolId);
    return stored === undefined ? null : cloneSpec(stored.spec);
  }

  describe(toolIds: string[], includeExamples: boolean = false): ExperimentalToolSpec[] {
    const specs: ExperimentalToolSpec[] = [];
    const seen: Set<string> = new Set<string>();
    for (let index = 0; index < toolIds.length; index++) {
      const toolId = toolIds[index];
      if (seen.has(toolId)) {
        throw new Error(`Duplicate authorized experimental tool id: ${toolId}.`);
      }
      const stored = this.tools.get(toolId);
      if (stored === undefined) {
        throw new Error(`Unknown experimental tool id: ${toolId}.`);
      }
      const spec = cloneSpec(stored.spec);
      if (!includeExamples) {
        spec.examples = undefined;
      }
      specs.push(spec);
      seen.add(toolId);
    }
    return specs;
  }

  async execute(
    toolId: string,
    revision: string,
    args: Object,
    context: ExperimentalToolExecutionContext
  ): Promise<ExperimentalToolExecutionResult> {
    const stored = this.tools.get(toolId);
    if (stored === undefined) {
      return executionError('EXPERIMENTAL_TOOL_NOT_FOUND', `Unknown experimental tool: ${toolId}.`);
    }
    if (stored.spec.revision !== revision) {
      return executionError(
        'EXPERIMENTAL_TOOL_REVISION_MISMATCH',
        `Expected ${toolId} revision ${stored.spec.revision}, received ${revision}.`
      );
    }
    if (args === null || typeof args !== 'object' || Array.isArray(args)) {
      return executionError('EXPERIMENTAL_TOOL_INPUT_INVALID', 'Experimental tool arguments must be an object.');
    }
    const inputResult = validateExperimentalValue(stored.spec.inputSchema, args as JsonValue);
    if (!inputResult.ok) {
      return executionError(
        'EXPERIMENTAL_TOOL_INPUT_INVALID',
        schemaErrorMessage(`Input validation failed for ${toolId}`, inputResult)
      );
    }
    let result: ExperimentalToolExecutionResult;
    try {
      result = await stored.executor.execute(args, context);
    } catch (error) {
      return executionError(
        'EXPERIMENTAL_TOOL_EXECUTION_FAILED',
        error instanceof Error ? error.message : `${error}`
      );
    }
    if (result === null || result === undefined ||
      (result.status !== 'success' && result.status !== 'error')) {
      return executionError(
        'EXPERIMENTAL_TOOL_RESULT_INVALID',
        `Executor returned an invalid result for ${toolId}.`
      );
    }
    if (result.status === 'error') {
      if (!nonempty(result.errorCode) || !nonempty(result.message)) {
        return executionError(
          'EXPERIMENTAL_TOOL_RESULT_INVALID',
          `Executor returned a malformed error for ${toolId}.`
        );
      }
      return {
        status: 'error',
        errorCode: result.errorCode,
        message: result.message
      };
    }
    const outputResult = validateExperimentalValue(stored.spec.outputSchema, result.output);
    if (!outputResult.ok) {
      return executionError(
        'EXPERIMENTAL_TOOL_OUTPUT_INVALID',
        schemaErrorMessage(`Output validation failed for ${toolId}`, outputResult)
      );
    }
    return {
      status: 'success',
      output: cloneValue(result.output)
    };
  }
}
