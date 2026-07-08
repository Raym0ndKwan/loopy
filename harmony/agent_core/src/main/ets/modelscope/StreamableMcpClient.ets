import http from '@ohos.net.http';

const MCP_PROTOCOL_VERSION: string = '2025-06-18';
const CONNECT_TIMEOUT_MS: number = 15000;
const READ_TIMEOUT_MS: number = 90000;

class EmptyMcpCapabilities {}
class EmptyMcpParams {}

interface McpInitializeClientInfo {
  name: string;
  version: string;
}

interface McpInitializeParams {
  protocolVersion: string;
  capabilities: EmptyMcpCapabilities;
  clientInfo: McpInitializeClientInfo;
}

interface McpToolsCallParams {
  name: string;
  arguments: Object;
}

interface McpJsonRpcRequest {
  jsonrpc: string;
  id?: number;
  method: string;
  params?: Object;
}

interface McpJsonRpcError {
  code?: number;
  message?: string;
  data?: Object | string | number | boolean;
}

interface McpJsonRpcPayload {
  id?: number;
  result?: Object;
  error?: McpJsonRpcError;
}

interface McpToolListResult {
  tools?: Object[];
}

interface McpToolRecord {
  name?: string;
  description?: string;
  inputSchema?: Object;
}

export interface ModelScopeMcpTool {
  name: string;
  description: string;
  inputSchema: Object;
}

interface HttpMcpResponse {
  status: number;
  text: string;
  sessionId: string;
}

function textOf(value: Object | string | number | boolean | null | undefined): string {
  if (value === undefined || value === null) {
    return '';
  }
  if (typeof value === 'string') {
    return value;
  }
  if (typeof value === 'number' || typeof value === 'boolean') {
    return value.toString();
  }
  return JSON.stringify(value);
}

function headerValue(headers: Object, key: string): string {
  const record = headers as Record<string, Object | string | number | boolean | null | undefined>;
  const lower = key.toLowerCase();
  const keys = Object.keys(record);
  for (let index = 0; index < keys.length; index++) {
    if (keys[index].toLowerCase() === lower) {
      return textOf(record[keys[index]]);
    }
  }
  return '';
}

function parseEventStreamPayload(raw: string, expectedId: number): string {
  const lines = raw.split('\n');
  const payloads: string[] = [];
  for (let index = 0; index < lines.length; index++) {
    const line = lines[index].trim();
    if (!line.startsWith('data:')) {
      continue;
    }
    const data = line.substring(5).trim();
    if (data.length > 0 && data !== '[DONE]') {
      payloads.push(data);
    }
  }
  for (let index = 0; index < payloads.length; index++) {
    try {
      const parsed = JSON.parse(payloads[index]) as McpJsonRpcPayload;
      if ((parsed.id ?? -1) === expectedId) {
        return payloads[index];
      }
    } catch (_error) {
    }
  }
  return payloads.length > 0 ? payloads[payloads.length - 1] : raw.trim();
}

function jsonRpcPayloadText(raw: string, expectedId: number): string {
  const trimmed = raw.trim();
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    return trimmed;
  }
  return parseEventStreamPayload(raw, expectedId);
}

function toolsFromResult(result: Object | undefined): ModelScopeMcpTool[] {
  if (result === undefined || result === null) {
    return [];
  }
  const record = result as McpToolListResult;
  if (!Array.isArray(record.tools)) {
    return [];
  }
  return record.tools.map((item: Object): ModelScopeMcpTool => {
    const tool = item as McpToolRecord;
    return {
      name: textOf(tool.name),
      description: textOf(tool.description),
      inputSchema: tool.inputSchema === undefined || tool.inputSchema === null ? new Object() : tool.inputSchema
    };
  }).filter((tool: ModelScopeMcpTool): boolean => tool.name.length > 0);
}

function buildInitializeRequest(id: number): McpJsonRpcRequest {
  const params: McpInitializeParams = {
    protocolVersion: MCP_PROTOCOL_VERSION,
    capabilities: new EmptyMcpCapabilities(),
    clientInfo: {
      name: 'loop-harmony-modelscope-direct',
      version: '0.1.0'
    }
  };
  return {
    jsonrpc: '2.0',
    id: id,
    method: 'initialize',
    params: params
  };
}

function buildInitializedNotification(): McpJsonRpcRequest {
  return {
    jsonrpc: '2.0',
    method: 'notifications/initialized',
    params: new EmptyMcpParams()
  };
}

function buildToolsListRequest(id: number): McpJsonRpcRequest {
  return {
    jsonrpc: '2.0',
    id: id,
    method: 'tools/list',
    params: new EmptyMcpParams()
  };
}

function buildToolsCallRequest(id: number, name: string, args: Object): McpJsonRpcRequest {
  const params: McpToolsCallParams = {
    name: name,
    arguments: args
  };
  return {
    jsonrpc: '2.0',
    id: id,
    method: 'tools/call',
    params: params
  };
}

export class StreamableMcpClient {
  async listTools(endpoint: string): Promise<ModelScopeMcpTool[]> {
    const session = await this.open(endpoint);
    const listed = await this.post(endpoint, buildToolsListRequest(2), session, 2);
    const payload = this.parsePayload(listed, 2);
    return toolsFromResult(payload.result);
  }

  async callTool(endpoint: string, toolName: string, args: Object): Promise<Object> {
    const session = await this.open(endpoint);
    const response = await this.post(endpoint, buildToolsCallRequest(3, toolName, args), session, 3);
    const payload = this.parsePayload(response, 3);
    return payload.result ?? new Object();
  }

  private async open(endpoint: string): Promise<string> {
    const initialized = await this.post(endpoint, buildInitializeRequest(1), '', 1);
    const payload = this.parsePayload(initialized, 1);
    if (payload.result === undefined && payload.error !== undefined) {
      throw new Error(textOf(payload.error.message));
    }
    const session = initialized.sessionId;
    await this.post(endpoint, buildInitializedNotification(), session, -1);
    return session;
  }

  private parsePayload(response: HttpMcpResponse, expectedId: number): McpJsonRpcPayload {
    if (response.status < 200 || response.status >= 300) {
      throw new Error(`MCP HTTP ${response.status}: ${response.text.substring(0, 500)}`);
    }
    if (expectedId < 0 || response.text.trim().length === 0) {
      return {};
    }
    const payload = JSON.parse(jsonRpcPayloadText(response.text, expectedId)) as McpJsonRpcPayload;
    if (payload.error !== undefined && payload.error !== null) {
      const message = textOf(payload.error.message);
      throw new Error(message.length > 0 ? message : JSON.stringify(payload.error));
    }
    return payload;
  }

  private async post(endpoint: string, body: McpJsonRpcRequest, sessionId: string, _expectedId: number): Promise<HttpMcpResponse> {
    const request = http.createHttp();
    try {
      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
        'MCP-Protocol-Version': MCP_PROTOCOL_VERSION
      };
      if (sessionId.length > 0) {
        headers['Mcp-Session-Id'] = sessionId;
      }
      const response = await request.request(endpoint, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING,
        usingProxy: false,
        connectTimeout: CONNECT_TIMEOUT_MS,
        readTimeout: READ_TIMEOUT_MS
      });
      return {
        status: response.responseCode,
        text: textOf(response.result),
        sessionId: headerValue(response.header, 'Mcp-Session-Id')
      };
    } finally {
      request.destroy();
    }
  }
}
