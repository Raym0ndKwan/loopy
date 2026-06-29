import { common } from '@kit.AbilityKit';
import {
  AgentEvent,
  AgentEventKind,
  ConversationContext,
  createLoopModelInfo,
  ReActAgentRunner,
  ToolRegistry
} from '@loop/agent-core';

const MAX_STEPS = 4;

@Entry
@Component
struct Index {
  @State transcript: string = 'Loop is ready.\n';
  @State message: string = '';
  @State sending: boolean = false;
  @State modelStatus: string = 'Checking model…';

  private scroller: Scroller = new Scroller();
  private conversation: ConversationContext = new ConversationContext();

  private getAbilityContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    createLoopModelInfo(this.getAbilityContext()).then((info) => {
      if (info.mode === 'llm') {
        this.modelStatus = `LLM: ${info.modelName}`;
      } else {
        this.modelStatus = 'Offline demo (no API key — add entry/.../rawfile/llm_config.json)';
      }
    });
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
          .enabled(!this.sending)
          .onClick(() => {
            this.clearConversation();
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
          .enabled(!this.sending)
          .onChange((value: string) => {
            this.message = value;
          })
          .onSubmit(() => {
            this.runAgent();
          })

        Button(this.sending ? '...' : 'Send')
          .width(86)
          .height(52)
          .margin({ left: 8 })
          .backgroundColor($r('app.color.send_button'))
          .fontColor(Color.White)
          .enabled(!this.sending)
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
    if (task.length === 0 || this.sending) {
      return;
    }

    this.appendUserMessage(task);
    this.message = '';
    this.sending = true;

    let finalAnswer: string | null = null;

    try {
      const modelInfo = await createLoopModelInfo(this.getAbilityContext());
      if (modelInfo.mode === 'llm') {
        this.modelStatus = `LLM: ${modelInfo.modelName}`;
      } else {
        this.modelStatus = 'Offline demo (no API key — add entry/.../rawfile/llm_config.json)';
      }

      const runner = new ReActAgentRunner(
        modelInfo.model,
        new ToolRegistry(),
        MAX_STEPS
      );
      await runner.run(task, (event: AgentEvent) => {
        if (event.kind === AgentEventKind.FINAL) {
          finalAnswer = event.text;
        }
        this.addEvent(event);
      }, this.conversation);
    } finally {
      if (finalAnswer !== null) {
        this.conversation.addUser(task);
        this.conversation.addAssistant(finalAnswer);
      }
      this.sending = false;
    }
  }

  private clearConversation(): void {
    this.conversation.clear();
    this.transcript = 'Loop is ready.\n';
  }

  private addEvent(event: AgentEvent): void {
    switch (event.kind) {
      case AgentEventKind.THOUGHT:
        this.appendLine('Loop', event.text);
        break;
      case AgentEventKind.ACTION:
        this.appendLine('Tool', event.text);
        break;
      case AgentEventKind.OBSERVATION:
        this.appendLine('Observation', event.text);
        break;
      case AgentEventKind.FINAL:
        this.appendLine('Loop', event.text);
        break;
      case AgentEventKind.ERROR:
      default:
        this.appendLine('Error', event.text);
        break;
    }
  }

  private appendUserMessage(message: string): void {
    this.appendLine('You', message);
  }

  private appendLine(speaker: string, text: string): void {
    const prefix = this.transcript.trim().length === 0 ? '' : '\n\n';
    this.transcript += `${prefix}${speaker}\n${text}`;
    this.scroller.scrollEdge(Edge.Bottom);
  }
}
