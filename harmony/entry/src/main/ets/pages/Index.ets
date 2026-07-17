import { common } from '@kit.AbilityKit';
import {
  AgentMessage,
  createConfiguredLoopToolRegistry,
  createLoopModelInfo,
  LeaderAgent,
  LinkedMessageBus,
  LOOP_AGENT_IDENTITY_PROMPT,
  MESSAGE_TYPE_CONTROL_CLEAR,
  MessageBus
} from '@loop/agent-core';
import { ChatInteractor } from '../interactor/ChatInteractor';

const MAX_STEPS = 6;
const WELCOME_TRANSCRIPT = 'Muti-Loop is ready. Ask anything — I will show a UI card when helpful.\n';

@Entry
@Component
struct Index {
  @State transcript: string = WELCOME_TRANSCRIPT;
  @State message: string = '';
  @State modelStatus: string = 'Checking model…';

  private scroller: Scroller = new Scroller();
  private bus: MessageBus = new LinkedMessageBus();
  private interactor: ChatInteractor = new ChatInteractor(this.bus);
  private agentPromise: Promise<LeaderAgent> | null = null;

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
    this.agentPromise = this.createAgent();
    this.agentPromise.catch((error: Error): void => {
      this.modelStatus = `Agent initialization failed: ${error.message}`;
      this.agentPromise = null;
    });
  }

  aboutToDisappear(): void {
    const agent = this.agentPromise;
    this.agentPromise = null;
    this.interactor.stopListening().catch((_error: Error): void => {});
    agent?.then(async (value: LeaderAgent): Promise<void> => value.close()).catch((_error: Error): void => {});
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
      if (this.agentPromise === null) {
        this.agentPromise = this.createAgent();
      }
      await this.agentPromise;
      this.interactor.send(task);
    } catch (error) {
      const message = error instanceof Error ? error.message : `${error}`;
      this.modelStatus = `Agent error: ${message}`;
    }
  }

  private async createAgent(): Promise<LeaderAgent> {
    const modelInfo = await createLoopModelInfo(this.getAbilityContext());
    this.updateModelStatus(modelInfo.mode, modelInfo.modelName);
    const tools = await createConfiguredLoopToolRegistry(this.getAbilityContext());
    const agent = new LeaderAgent(
      'Loop',
      LOOP_AGENT_IDENTITY_PROMPT,
      modelInfo.model,
      MAX_STEPS,
      this.bus,
      tools
    );
    agent.startListening();
    return agent;
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
  }

  private handleBusMessage(message: AgentMessage): void {
    if (message.type === MESSAGE_TYPE_CONTROL_CLEAR) {
      this.clearView();
    }
    this.appendBusMessage(message);
  }

  private appendBusMessage(message: AgentMessage): void {
    const prefix = this.transcript.trim().length === 0 ? '' : '\n\n';
    const content = message.content.length > 0 ? `\n${message.content}` : '';
    this.transcript += `${prefix}[${message.type}]${content}`;
    this.scroller.scrollEdge(Edge.Bottom);
  }
}
