import http from '@ohos.net.http';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ModelScopeClient } from './ModelScopeClient';
import { ModelScopeConfig } from './ModelScopeConfig';
import { ModelScopeMcpTool, StreamableMcpClient } from './StreamableMcpClient';

const LOG_DOMAIN: number = 0x1200;
const LOG_TAG: string = 'LoopModelScope';
const CONNECT_TIMEOUT_MS: number = 15000;
const READ_TIMEOUT_MS: number = 90000;
const MAX_OBSERVATION_CHARS: number = 16000;
const MAX_SEARCH_TOOLS: number = 24;
const MAX_DESCRIPTION_TOOLS: number = 36;
const MAX_TOOL_DESCRIPTION_CHARS: number = 220;

const WRITE_PATTERNS: string[] = [
  'send', 'create', 'update', 'delete', 'remove', 'post', 'publish',
  'book', 'order', 'pay', 'purchase', 'cancel', 'refund', '上传', '发送',
  '删除', '创建', '修改', '支付', '下单', '预订'
];

interface HttpResult {
  code: number;
  text: string;
}

interface OperationalEnvelope {
  success?: boolean;
  message?: string;
  error?: string;
  data?: Object;
}

interface OperationalPayload {
  mcp_server_list?: Object[];
  servers?: Object[];
}

interface RawOperationalServer {
  id?: string;
  name?: string;
  description?: string;
  mcp_servers?: Object[];
  operational_urls?: Object[];
}

interface RawOperationalUrl {
  url?: string;
  type?: string;
}

interface DirectServer {
  serverId: string;
  name: string;
  description: string;
  endpoint: string;
}

interface DirectTool {
  qualifiedName: string;
  serverId: string;
  serverName: string;
  endpoint: string;
  name: string;
  description: string;
  risk: string;
  inputSchema: Object;
}

interface SearchCandidate {
  qualifiedName: string;
  serverId: string;
  serverName: string;
  name: string;
  description: string;
  risk: string;
  inputSchema: Object;
  useHint: string;
}

interface SearchObservation {
  source: string;
  mode: string;
  useCase: string;
  tools: SearchCandidate[];
  instruction: string;
}

interface ScoredTool {
  tool: DirectTool;
  score: number;
}

interface TruncatedObservation {
  source: string;
  truncated: boolean;
  preview: string;
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

function safeSegment(value: string): string {
  let result = '';
  const chars = Array.from(value);
  for (let index = 0; index < chars.length; index++) {
    const char = chars[index];
    result += /[A-Za-z0-9_-]/.test(char) ? char : '_';
  }
  return result.length > 0 ? result : 'tool';
}

function toolRisk(name: string, description: string): string {
  const text = `${name} ${description}`.toLowerCase();
  for (let index = 0; index < WRITE_PATTERNS.length; index++) {
    if (text.indexOf(WRITE_PATTERNS[index]) >= 0) {
      return 'write';
    }
  }
  return 'read';
}

export class ModelScopeDirectClient implements ModelScopeClient {
  private config: ModelScopeConfig;
  private mcp: StreamableMcpClient = new StreamableMcpClient();
  private initialized: boolean = false;
  private syncError: string = '';
  private serverCount: number = 0;
  private toolCount: number = 0;
  private tools: DirectTool[] = [];
  private discoveredTools: Set<string> = new Set();

  constructor(config: ModelScopeConfig) {
    this.config = config;
  }

  async initialize(): Promise<void> {
    if (this.initialized) {
      return;
    }
    this.initialized = true;
    if (!this.config.isConfigured()) {
      this.syncError = `ModelScope Direct 未配置：${this.config.missingConfiguration()}`;
      return;
    }
    try {
      const servers = await this.fetchOperationalServers();
      this.serverCount = servers.length;
      const loadedTools: DirectTool[] = [];
      const errors: string[] = [];
      for (let serverIndex = 0; serverIndex < servers.length; serverIndex++) {
        const server = servers[serverIndex];
        try {
          const remoteTools = await this.mcp.listTools(server.endpoint);
          for (let toolIndex = 0; toolIndex < remoteTools.length; toolIndex++) {
            const tool = remoteTools[toolIndex];
            const qualifiedName = this.qualifiedToolName(serverIndex, server.serverId, tool.name);
            loadedTools.push({
              qualifiedName: qualifiedName,
              serverId: server.serverId,
              serverName: server.name,
              endpoint: server.endpoint,
              name: tool.name,
              description: tool.description,
              risk: toolRisk(tool.name, tool.description),
              inputSchema: tool.inputSchema
            });
          }
        } catch (error) {
          errors.push(`${server.name.length > 0 ? server.name : server.serverId}: ${this.errorMessage(error)}`);
        }
      }
      this.tools = loadedTools;
      this.toolCount = loadedTools.length;
      if (errors.length > 0) {
        this.syncError = `部分 MCP 同步失败：${errors.join('；')}`;
      }
      hilog.info(LOG_DOMAIN, LOG_TAG, 'direct synced servers=%{public}d tools=%{public}d', this.serverCount, this.toolCount);
    } catch (error) {
      this.syncError = this.safeFailure('同步 MCP', error);
    }
  }

  toolDescription(): string {
    if (!this.config.isConfigured()) {
      return `ModelScope Direct unavailable (${this.syncError}). Do not call this tool.`;
    }
    const availability = this.syncError.length === 0
      ? `${this.serverCount} activated MCP servers and ${this.toolCount} tools are available via direct ModelScope.`
      : `${this.serverCount} servers are available via direct ModelScope with warning: ${this.syncError}.`;
    return 'Use when the user request can be fulfilled by a ModelScope MCP tool. ' +
      `${availability} Available tools loaded at app startup: ${this.catalogSummary()} ` +
      'For Chinese flight/air ticket requests such as 航班/机票/飞机/飞常准, search ModelScope first and prefer 飞常准-Aviation flight tools. ' +
      'For train/12306 requests, search ModelScope first and prefer 12306 tools. Two phases are mandatory. First output Action: modelscope[' +
      '{"operation":"search","useCase":"the full user task"}]. Then choose a returned tool and output Action: modelscope[' +
      '{"operation":"execute","qualifiedName":"returned qualifiedName","arguments":{...}}]. ' +
      'Never invent qualifiedName. Arguments must match inputSchema. Tools execute immediately in this internal direct demo.';
  }

  async search(useCase: string): Promise<string> {
    const query = useCase.trim();
    if (query.length === 0) {
      return 'ModelScope 搜索参数错误：useCase 不能为空。';
    }
    await this.initialize();
    if (!this.config.isConfigured()) {
      return this.syncError;
    }
    if (this.tools.length === 0) {
      return this.syncError.length > 0
        ? `ModelScope Direct 没有可用工具：${this.syncError}`
        : 'ModelScope Direct 没有在已激活 MCP 中找到可用工具。';
    }
    const selected = this.rankTools(this.tools, query);
    const candidates: SearchCandidate[] = [];
    for (let index = 0; index < selected.length; index++) {
      const tool = selected[index].tool;
      this.discoveredTools.add(tool.qualifiedName);
      candidates.push({
        qualifiedName: tool.qualifiedName,
        serverId: tool.serverId,
        serverName: tool.serverName,
        name: tool.name,
        description: tool.description,
        risk: tool.risk,
        inputSchema: tool.inputSchema,
        useHint: this.useHint(tool)
      });
    }
    const observation: SearchObservation = {
      source: 'ModelScope',
      mode: 'direct',
      useCase: query,
      tools: candidates,
      instruction: 'Choose exactly one returned qualifiedName. For flight route queries prefer searchFlightsByDepArr or searchFlightItineraries; use city IATA codes when schema asks for city codes, for example Shenzhen SZX and Xi’an/Xian XIY. Output Action: modelscope[{"operation":"execute","qualifiedName":"returned qualifiedName","arguments":{...}}]. Arguments must match inputSchema.'
    };
    return this.limitObservation(JSON.stringify(observation));
  }

  async execute(qualifiedName: string, args: Object): Promise<string> {
    const normalized = qualifiedName.trim();
    if (normalized.length === 0) {
      return 'ModelScope 执行参数错误：qualifiedName 不能为空。';
    }
    if (!this.discoveredTools.has(normalized)) {
      return `ModelScope 拒绝执行：${normalized} 尚未通过当前会话的 search 发现。`;
    }
    const tool = this.findTool(normalized);
    if (tool === null) {
      return `ModelScope 执行失败：${normalized} 不在当前同步工具列表中。`;
    }
    try {
      const content = await this.mcp.callTool(tool.endpoint, tool.name, args);
      const isError = (content as Record<string, Object | string | number | boolean | null | undefined>)['isError'] === true;
      return this.limitObservation(JSON.stringify({
        source: 'ModelScope',
        mode: 'direct',
        status: isError ? 'tool_error' : 'success',
        qualifiedName: normalized,
        risk: tool.risk,
        content: content
      }));
    } catch (error) {
      return this.safeFailure('执行工具', error);
    }
  }

  private async fetchOperationalServers(): Promise<DirectServer[]> {
    const response = await this.request(`${this.config.modelscopeApiBaseUrl}/openapi/v1/mcp/servers/operational`);
    if (response.code < 200 || response.code >= 300) {
      throw new Error(`ModelScope HTTP ${response.code}: ${response.text.substring(0, 500)}`);
    }
    const envelope = JSON.parse(response.text) as OperationalEnvelope;
    if (envelope.success === false) {
      const message = textOf(envelope.message).length > 0 ? textOf(envelope.message) : textOf(envelope.error);
      throw new Error(message.length > 0 ? message : 'ModelScope rejected the request');
    }
    const payload = envelope.data as OperationalPayload;
    if (payload === undefined || payload === null) {
      throw new Error('ModelScope response is missing data');
    }
    const rawServers = Array.isArray(payload.mcp_server_list) ? payload.mcp_server_list : (payload.servers ?? []);
    const servers: DirectServer[] = [];
    for (let index = 0; index < rawServers.length; index++) {
      const raw = rawServers[index] as RawOperationalServer;
      const endpoint = this.endpointFromServer(raw);
      const serverId = textOf(raw.id);
      if (serverId.length === 0 || endpoint.length === 0) {
        continue;
      }
      servers.push({
        serverId: serverId,
        name: textOf(raw.name).length > 0 ? textOf(raw.name) : serverId,
        description: textOf(raw.description),
        endpoint: endpoint
      });
    }
    return servers;
  }

  private endpointFromServer(raw: RawOperationalServer): string {
    const urls = Array.isArray(raw.mcp_servers) && raw.mcp_servers.length > 0
      ? raw.mcp_servers
      : (raw.operational_urls ?? []);
    for (let index = 0; index < urls.length; index++) {
      const item = urls[index] as RawOperationalUrl;
      const url = textOf(item.url);
      const type = textOf(item.type).toLowerCase();
      if (url.length > 0 && (type.length === 0 || type === 'streamable_http' ||
        url.endsWith('/mcp') || url.endsWith('/streamable_http'))) {
        return url;
      }
    }
    return '';
  }

  private async request(url: string): Promise<HttpResult> {
    const request = http.createHttp();
    hilog.info(LOG_DOMAIN, LOG_TAG, 'direct request url=%{public}s', url);
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'Accept': 'application/json',
          'Authorization': `Bearer ${this.config.modelscopeToken}`
        },
        expectDataType: http.HttpDataType.STRING,
        usingProxy: false,
        connectTimeout: CONNECT_TIMEOUT_MS,
        readTimeout: READ_TIMEOUT_MS
      });
      return {
        code: response.responseCode,
        text: textOf(response.result)
      };
    } finally {
      request.destroy();
    }
  }

  private qualifiedToolName(serverIndex: number, serverId: string, toolName: string): string {
    const serverPart = safeSegment(serverId).substring(0, 20);
    const toolPart = safeSegment(toolName);
    return `mcp__${serverIndex.toString()}_${serverPart}__${toolPart}`.substring(0, 96);
  }

  private findTool(qualifiedName: string): DirectTool | null {
    for (let index = 0; index < this.tools.length; index++) {
      if (this.tools[index].qualifiedName === qualifiedName) {
        return this.tools[index];
      }
    }
    return null;
  }

  private rankTools(tools: DirectTool[], useCase: string): ScoredTool[] {
    const normalizedQuery = useCase.toLowerCase();
    const scored: ScoredTool[] = [];
    for (let index = 0; index < tools.length; index++) {
      const tool = tools[index];
      const text = `${tool.name} ${tool.description} ${tool.serverId} ${tool.serverName}`.toLowerCase();
      let score = this.domainBoost(tool, normalizedQuery, text);
      const words = normalizedQuery.split(/[\s,，。；;：:、]+/);
      for (let wordIndex = 0; wordIndex < words.length; wordIndex++) {
        const word = words[wordIndex];
        if (word.length > 0 && text.indexOf(word) >= 0) {
          score += word.length + 2;
        }
      }
      const chars = Array.from(normalizedQuery);
      for (let charIndex = 0; charIndex < chars.length; charIndex++) {
        const char = chars[charIndex];
        if (char.trim().length > 0 && text.indexOf(char) >= 0) {
          score += 1;
        }
      }
      scored.push({ tool: tool, score: score });
    }
    scored.sort((left: ScoredTool, right: ScoredTool): number => right.score - left.score);
    return scored.slice(0, MAX_SEARCH_TOOLS);
  }

  private domainBoost(tool: DirectTool, query: string, text: string): number {
    let score = 0;
    if (this.containsAny(query, ['航班', '机票', '飞机', '飞常准', '机场', '起飞', '落地', '直飞', '中转']) &&
      this.containsAny(text, ['flight', 'variflight', 'aviation', '飞常准', 'airport'])) {
      score += 100;
      if (this.containsAny(tool.name.toLowerCase(), ['searchflightsbydeparr', 'searchflightitineraries', 'getflightpricebycities'])) {
        score += 40;
      }
      if (this.containsAny(tool.name.toLowerCase(), ['number', 'happiness', 'weather', 'realtimelocation'])) {
        score -= 25;
      }
    }
    if (this.containsAny(query, ['火车', '高铁', '动车', '车票', '12306', '列车']) &&
      this.containsAny(text, ['12306', 'train', 'ticket', '铁路', '火车', '车票'])) {
      score += 100;
    }
    if (this.containsAny(query, ['天气', '气象']) && this.containsAny(text, ['weather', '天气'])) {
      score += 60;
    }
    return score;
  }

  private containsAny(text: string, values: string[]): boolean {
    for (let index = 0; index < values.length; index++) {
      if (text.indexOf(values[index].toLowerCase()) >= 0) {
        return true;
      }
    }
    return false;
  }

  private catalogSummary(): string {
    if (!this.config.isConfigured()) {
      return 'not configured.';
    }
    if (!this.initialized) {
      return 'initializing.';
    }
    if (this.tools.length === 0) {
      return this.syncError.length > 0 ? `none (${this.syncError})` : 'none.';
    }
    const parts: string[] = [];
    const count = Math.min(this.tools.length, MAX_DESCRIPTION_TOOLS);
    for (let index = 0; index < count; index++) {
      const tool = this.tools[index];
      const description = tool.description.length > MAX_TOOL_DESCRIPTION_CHARS
        ? `${tool.description.substring(0, MAX_TOOL_DESCRIPTION_CHARS)}…`
        : tool.description;
      parts.push(`${tool.serverName}/${tool.name}: ${description}`);
    }
    if (this.tools.length > count) {
      parts.push(`...and ${this.tools.length - count} more`);
    }
    return parts.join(' | ');
  }

  private useHint(tool: DirectTool): string {
    const name = tool.name.toLowerCase();
    const serverText = `${tool.serverName} ${tool.serverId}`.toLowerCase();
    if (serverText.indexOf('variflight') >= 0 || serverText.indexOf('飞常准') >= 0 || name.indexOf('flight') >= 0) {
      if (name === 'searchflightsbydeparr') {
        return '用于按出发地、到达地、日期查询直飞航班；深圳通常用 SZX，西安通常用 XIY。';
      }
      if (name === 'searchflightitineraries') {
        return '用于给出自然语言航班行程推荐摘要。';
      }
      if (name === 'getflightpricebycities') {
        return '用于查询城市间结构化航班价格列表。';
      }
      return '飞常准航班/机场相关工具。';
    }
    if (serverText.indexOf('12306') >= 0 || name.indexOf('train') >= 0) {
      return '12306 火车票/列车查询相关工具。';
    }
    return '';
  }

  private errorMessage(error: Error | Object | string): string {
    return error instanceof Error ? error.message : `${error}`;
  }

  private safeFailure(action: string, error: Error | Object | string): string {
    return `ModelScope Direct ${action}失败：${this.errorMessage(error)}`;
  }

  private limitObservation(text: string): string {
    if (text.length <= MAX_OBSERVATION_CHARS) {
      return text;
    }
    const observation: TruncatedObservation = {
      source: 'ModelScope',
      truncated: true,
      preview: text.substring(0, MAX_OBSERVATION_CHARS)
    };
    return JSON.stringify(observation);
  }
}
