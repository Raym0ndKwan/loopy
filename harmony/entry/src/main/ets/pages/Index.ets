import { common } from '@kit.AbilityKit';
import {
  A2uiAgentRunner,
  A2uiComponentDef,
  AgentEventKind,
  AgentMessage,
  createLeaderToolRegistry,
  createA2uiModelInfo,
  createLoopModelInfo,
  createUIMakerToolRegistry,
  LeaderAgent,
  LEADER_AGENT_IDENTITY_PROMPT,
  LinkedMessageBus,
  MESSAGE_TAG_UI_MAKER,
  MESSAGE_TYPE_CONTROL_CLEAR,
  MESSAGE_TYPE_OTHERS,
  MessageBus,
  MessageProcessingMode,
  parseJsonl,
  ScriptedA2uiModel,
  UIMakerAgent,
  UI_MAKER_AGENT_IDENTITY_PROMPT,
  UiRenderHandler
} from '@loop/agent-core';
import { A2uiFallbackView } from '../agenui/A2uiFallbackView';
import { hasRenderableRoot, parseComponentsFromJsonl } from '../agenui/A2uiFallbackParser';
import { componentsFromUiEvent } from '../agenui/LoopUiApplier';
import { ChatInteractor } from '../interactor/ChatInteractor';

const MAX_STEPS = 6;
const WELCOME_TRANSCRIPT = 'Muti-Loop is ready. Ask anything — I will show a UI card when helpful.\n';

class AgentRuntime {
  readonly leader: LeaderAgent;
  readonly uiMaker: UIMakerAgent;

  constructor(leader: LeaderAgent, uiMaker: UIMakerAgent) {
    this.leader = leader;
    this.uiMaker = uiMaker;
  }

  async close(): Promise<void> {
    await this.leader.close();
    await this.uiMaker.close();
  }
}

@Entry
@Component
struct Index {
  @State transcript: string = WELCOME_TRANSCRIPT;
  @State message: string = '';
  @State modelStatus: string = 'Checking model…';
  @State uiComponents: A2uiComponentDef[] = [];
  @State hasUiPanel: boolean = false;

  private scroller: Scroller = new Scroller();
  private bus: MessageBus = new LinkedMessageBus();
  private interactor: ChatInteractor = new ChatInteractor(this.bus);
  private agentsPromise: Promise<AgentRuntime> | null = null;
  private lastUiTask: string = '';

  private getAbilityContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    this.interactor.startListening(
      (message: AgentMessage): void => this.handleBusMessage(message),
      (error: Error): void => {
        this.modelStatus = `Bus error: ${error.message}`;
      }
    );
    this.agentsPromise = this.createAgents();
    this.agentsPromise.catch((error: Error): void => {
      this.modelStatus = `Agent initialization failed: ${error.message}`;
      this.agentsPromise = null;
    });
  }

  aboutToDisappear(): void {
    const agents = this.agentsPromise;
    this.agentsPromise = null;
    this.interactor.stopListening().catch((_error: Error): void => {});
    agents?.then(async (value: AgentRuntime): Promise<void> => value.close()).catch((_error: Error): void => {});
  }

  build() {
    Column() {
      Row() {
        Text(this.modelStatus)
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
          .opacity(0.7)
          .layoutWeight(1)

        Button('Clear')
          .fontSize(12)
          .height(28)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.send_button'))
          .onClick(() => {
            this.interactor.clear();
          })
      }
      .width('100%')
      .margin({ bottom: 8 })

      if (this.hasUiPanel) {
        Column() {
          Text('UImaker output')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .margin({ bottom: 6 })

          Scroll() {
            A2uiFallbackView({ components: this.uiComponents })
              .width('100%')
          }
          .width('100%')
          .height(220)
        }
        .width('100%')
        .padding(12)
        .margin({ bottom: 8 })
        .borderRadius(12)
        .backgroundColor(Color.White)
        .border({ width: 1, color: $r('app.color.input_stroke') })
      }

      Scroll(this.scroller) {
        Text(this.transcript)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .lineHeight(24)
          .width('100%')
          .textAlign(TextAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.BottomStart)
      .padding({ left: 4, right: 4, top: 4, bottom: 12 })

      Row() {
        TextInput({ text: this.message, placeholder: 'Message Loop' })
          .layoutWeight(1)
          .height(52)
          .borderRadius(20)
          .backgroundColor(Color.White)
          .border({ width: 1, color: $r('app.color.input_stroke') })
          .padding({ left: 14, right: 14 })
          .onChange((value: string) => {
            this.message = value;
          })
          .onSubmit(() => {
            this.runAgent();
          })

        Button('Send')
          .width(86)
          .height(52)
          .margin({ left: 8 })
          .backgroundColor($r('app.color.send_button'))
          .fontColor(Color.White)
          .onClick(() => {
            this.runAgent();
          })
      }
      .width('100%')
      .padding({ top: 10 })
    }
    .width('100%')
    .height('100%')
    .padding(14)
    .backgroundColor($r('app.color.page_background'))
  }

  private async runAgent(): Promise<void> {
    const task = this.message.trim();
    if (task.length === 0) {
      return;
    }

    this.message = '';

    try {
      if (this.agentsPromise === null) {
        this.agentsPromise = this.createAgents();
      }
      await this.agentsPromise;
      this.interactor.send(task);
    } catch (error) {
      const message = error instanceof Error ? error.message : `${error}`;
      this.modelStatus = `Agent error: ${message}`;
    }
  }

  private async createAgents(): Promise<AgentRuntime> {
    const modelInfo = await createLoopModelInfo(this.getAbilityContext());
    this.updateModelStatus(modelInfo.mode, modelInfo.modelName);
    const uiHandler = await this.buildUiHandler();
    const leader = new LeaderAgent(
      'Leader',
      LEADER_AGENT_IDENTITY_PROMPT,
      modelInfo.model,
      MAX_STEPS,
      this.bus,
      MessageProcessingMode.BATCH_PENDING,
      createLeaderToolRegistry(this.bus)
    );
    const uiMaker = new UIMakerAgent(
      'UImaker',
      UI_MAKER_AGENT_IDENTITY_PROMPT,
      modelInfo.model,
      MAX_STEPS,
      this.bus,
      MessageProcessingMode.ONE_BY_ONE,
      createUIMakerToolRegistry(),
      uiHandler
    );
    uiMaker.startListening();
    leader.startListening();
    return new AgentRuntime(leader, uiMaker);
  }

  private async buildUiHandler(): Promise<UiRenderHandler> {
    const a2uiInfo = await createA2uiModelInfo(this.getAbilityContext());
    const runner = new A2uiAgentRunner(a2uiInfo.model);
    const scripted = new ScriptedA2uiModel();

    return async (description: string): Promise<string[]> => {
      const lines: string[] = [];
      const surfaceId = await runner.run(
        description,
        (line: string): void => {
          lines.push(line);
        },
        (_message: string): void => {
        }
      );
      if (surfaceId !== null && hasRenderableRoot(parseComponentsFromJsonl(lines))) {
        return lines;
      }

      const fallbackRaw = await scripted.generate(description, surfaceId ?? 'uimaker_ui', undefined);
      return parseJsonl(fallbackRaw);
    };
  }

  private updateModelStatus(mode: 'llm' | 'scripted', modelName: string): void {
    if (mode === 'llm') {
      this.modelStatus = `LLM: ${modelName}`;
    } else {
      this.modelStatus = 'Offline demo (no API key — add entry/.../rawfile/llm_config.json)';
    }
  }

  private clearView(): void {
    this.transcript = WELCOME_TRANSCRIPT;
    this.uiComponents = [];
    this.hasUiPanel = false;
    this.lastUiTask = '';
  }

  private handleBusMessage(message: AgentMessage): void {
    if (message.type === MESSAGE_TYPE_CONTROL_CLEAR) {
      this.clearView();
    }
    if (message.type === this.uiMakerEventType(AgentEventKind.ACTION)) {
      this.lastUiTask = this.extractUiTask(message.content);
    }
    if (message.type === this.uiMakerEventType(AgentEventKind.UI)) {
      this.applyUiPayload(message.content);
    }
    this.appendBusMessage(message);
  }

  private uiMakerEventType(kind: AgentEventKind): string {
    return `${MESSAGE_TYPE_OTHERS}.${MESSAGE_TAG_UI_MAKER}.${kind}`;
  }

  private extractUiTask(action: string): string {
    const open = action.indexOf('(');
    const close = action.lastIndexOf(')');
    if (open >= 0 && close > open) {
      return action.substring(open + 1, close).trim();
    }
    return action.trim();
  }

  private applyUiPayload(jsonlPayload: string): void {
    const fallbackTask = this.lastUiTask.length > 0
      ? this.lastUiTask
      : 'UImaker generated UI';
    this.uiComponents = componentsFromUiEvent(jsonlPayload, fallbackTask);
    this.hasUiPanel = this.uiComponents.length > 0;
  }

  private appendBusMessage(message: AgentMessage): void {
    const prefix = this.transcript.trim().length === 0 ? '' : '\n\n';
    const content = message.content.length > 0 ? `\n${message.content}` : '';
    this.transcript += `${prefix}[${message.type}]${content}`;
    this.scroller.scrollEdge(Edge.Bottom);
  }
}
