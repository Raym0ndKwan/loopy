import {
  AgentMessage,
  LinkedMessageBus
} from '@loop/agent-core';
import { ChatInteractor } from '../interactor/ChatInteractor';

const WELCOME_TRANSCRIPT: string = 'Bus is ready. Messages will appear here.';

@Entry
@Component
struct Index {
  @State transcript: string = WELCOME_TRANSCRIPT;
  @State message: string = '';
  @State errorMessage: string = '';

  private readonly scroller: Scroller = new Scroller();
  private readonly bus: LinkedMessageBus = new LinkedMessageBus();
  private readonly interactor: ChatInteractor = new ChatInteractor(this.bus);

  aboutToAppear(): void {
    this.interactor.startListening(
      (message: AgentMessage): void => this.appendBusMessage(message),
      (error: Error): void => {
        this.errorMessage = error.message;
      }
    );
  }

  aboutToDisappear(): void {
    this.interactor.stopListening();
  }

  build() {
    Column() {
      Text('Bus transcript')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .fontSize(12)
          .fontColor(Color.Red)
          .width('100%')
          .margin({ top: 6 })
      }

      Scroll(this.scroller) {
        Text(this.transcript)
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .lineHeight(20)
          .width('100%')
          .textAlign(TextAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.BottomStart)
      .padding({ top: 10, bottom: 10 })

      Row() {
        TextInput({ text: this.message, placeholder: 'Message Loop' })
          .layoutWeight(1)
          .height(50)
          .borderRadius(18)
          .backgroundColor(Color.White)
          .border({ width: 1, color: $r('app.color.input_stroke') })
          .padding({ left: 14, right: 14 })
          .onChange((value: string): void => {
            this.message = value;
          })
          .onSubmit((): void => {
            this.send();
          })

        Button('Send')
          .width(82)
          .height(50)
          .margin({ left: 8 })
          .backgroundColor($r('app.color.send_button'))
          .fontColor(Color.White)
          .onClick((): void => {
            this.send();
          })
      }
      .width('100%')
      .padding({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .padding(14)
    .backgroundColor($r('app.color.page_background'))
  }

  private send(): void {
    const text: string = this.message.trim();
    if (text.length === 0) {
      return;
    }
    this.message = '';
    this.errorMessage = '';
    try {
      this.interactor.send(text);
    } catch (error) {
      this.errorMessage = error instanceof Error ? error.message : `${error}`;
    }
  }

  private appendBusMessage(message: AgentMessage): void {
    let payload: string;
    try {
      payload = JSON.stringify(message.payload);
    } catch (_error) {
      payload = '<unserializable payload>';
    }
    const prefix: string = this.transcript.trim().length === 0 ? '' : '\n\n';
    this.transcript += `${prefix}[${message.type}]\n` +
      `conversation=${message.conversationId}\n` +
      `turn=${message.turnId}\n` +
      `task=${message.taskId}\n` +
      payload;
    this.scroller.scrollEdge(Edge.Bottom);
  }
}
