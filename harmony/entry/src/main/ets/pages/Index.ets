import { A2uiComponentDef } from '@loop/agent-core';
import { common } from '@kit.AbilityKit';
import {
  AgentEvent,
  AgentEventKind,
  A2uiAgentRunner,
  clearStoredConversation,
  ConversationContext,
  ConversationRole,
  createA2uiModelInfo,
  createConfiguredLoopToolRegistry,
  createLoopModelInfo,
  loadConversation,
  parseJsonl,
  ReActAgentRunner,
  saveConversation,
  ScriptedA2uiModel,
  ToolRegistry,
  UiRenderHandler
} from '@loop/agent-core';
import { A2uiFallbackView } from '../agenui/A2uiFallbackView';
import { hasRenderableRoot, parseComponentsFromJsonl } from '../agenui/A2uiFallbackParser';
import { componentsFromUiEvent } from '../agenui/LoopUiApplier';

const MAX_STEPS = 6;
const WELCOME_TRANSCRIPT = 'Loop is ready. Ask anything — I will show a UI card when helpful.\n';

@Entry
@Component
struct Index {
  @State transcript: string = WELCOME_TRANSCRIPT;
  @State message: string = '';
  @State sending: boolean = false;
  @State modelStatus: string = 'Checking model…';
  @State uiComponents: A2uiComponentDef[] = [];
  @State hasUiPanel: boolean = false;

  private scroller: Scroller = new Scroller();
  private conversation: ConversationContext = new ConversationContext();
  private lastUiTask: string = '';
  private toolRegistryPromise: Promise<ToolRegistry> | null = null;

  private getAbilityContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    this.restoreConversation();
    this.toolRegistryPromise = createConfiguredLoopToolRegistry(this.getAbilityContext());
    createLoopModelInfo(this.getAbilityContext()).then((info) => {
      this.updateModelStatus(info.mode, info.modelName);
    });
  }

  aboutToDisappear(): void {
    const tools = this.toolRegistryPromise;
    this.toolRegistryPromise = null;
    tools?.then(async (registry: ToolRegistry): Promise<void> => registry.close()).catch((_error: Error): void => {});
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

      if (this.hasUiPanel) {
        Column() {
          Text('On-screen UI')
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
      this.updateModelStatus(modelInfo.mode, modelInfo.modelName);

      const uiHandler = await this.buildUiHandler();
      if (this.toolRegistryPromise === null) {
        this.toolRegistryPromise = createConfiguredLoopToolRegistry(this.getAbilityContext());
      }
      const tools = await this.toolRegistryPromise;
      const runner = new ReActAgentRunner(
        modelInfo.model,
        tools,
        MAX_STEPS,
        uiHandler
      );

      await runner.run(task, (event: AgentEvent) => {
        if (event.kind === AgentEventKind.FINAL) {
          finalAnswer = event.text;
        }
        if (event.kind === AgentEventKind.ACTION && event.text.startsWith('ui(')) {
          this.lastUiTask = this.extractToolInput(event.text);
        }
        if (event.kind === AgentEventKind.UI) {
          const uiTask = this.lastUiTask.length > 0 ? this.lastUiTask : task;
          this.applyUiPayload(event.text, uiTask);
        }
        this.addEvent(event);
      }, this.conversation);
    } finally {
      if (finalAnswer !== null) {
        this.conversation.addUser(task);
        this.conversation.addAssistant(finalAnswer);
        saveConversation(this.getAbilityContext(), this.conversation);
      }
      this.sending = false;
    }
  }

  private async buildUiHandler(): Promise<UiRenderHandler> {
    const a2uiInfo = await createA2uiModelInfo(this.getAbilityContext());
    const a2uiRunner = new A2uiAgentRunner(a2uiInfo.model);
    const scripted = new ScriptedA2uiModel();

    return async (description: string): Promise<string[]> => {
      const lines: string[] = [];
      const surfaceId = await a2uiRunner.run(
        description,
        (line: string) => {
          lines.push(line);
        },
        (_message: string) => {
          // errors surface as observation via empty lines + fallback below
        }
      );

      if (surfaceId !== null && hasRenderableRoot(parseComponentsFromJsonl(lines))) {
        return lines;
      }

      const fallbackRaw = await scripted.generate(description, surfaceId ?? 'loop_ui', undefined);
      return parseJsonl(fallbackRaw);
    };
  }

  private extractToolInput(actionText: string): string {
    const open = actionText.indexOf('(');
    const close = actionText.lastIndexOf(')');
    if (open >= 0 && close > open) {
      return actionText.substring(open + 1, close);
    }
    return actionText;
  }

  private applyUiPayload(jsonlPayload: string, fallbackTask: string): void {
    this.uiComponents = componentsFromUiEvent(jsonlPayload, fallbackTask);
    this.hasUiPanel = this.uiComponents.length > 0;
  }

  private updateModelStatus(mode: 'llm' | 'scripted', modelName: string): void {
    if (mode === 'llm') {
      this.modelStatus = `LLM: ${modelName}`;
    } else {
      this.modelStatus = 'Offline demo (no API key — add entry/.../rawfile/llm_config.json)';
    }
  }

  private restoreConversation(): void {
    this.conversation = loadConversation(this.getAbilityContext());
    this.transcript = this.buildTranscriptFromConversation(this.conversation);
  }

  private buildTranscriptFromConversation(conversation: ConversationContext): string {
    const turns = conversation.toChatMessages();
    if (turns.length === 0) {
      return WELCOME_TRANSCRIPT;
    }

    let transcript = WELCOME_TRANSCRIPT.trim();
    for (const turn of turns) {
      const speaker = turn.role === ConversationRole.USER ? 'You' : 'Loop';
      transcript += `\n\n${speaker}\n${turn.content}`;
    }
    return `${transcript}\n`;
  }

  private clearConversation(): void {
    this.conversation.clear();
    clearStoredConversation(this.getAbilityContext());
    this.transcript = WELCOME_TRANSCRIPT;
    this.uiComponents = [];
    this.hasUiPanel = false;
    this.lastUiTask = '';
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
      case AgentEventKind.UI:
        this.appendLine('UI', 'Updated on-screen panel above.');
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
