@Entry
@Component
struct Index {
  build() {
    Column({ space: 16 }) {
      Text('Loopy Agent Core')
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))

      Text('Single structured runtime')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.send_button'))

      Text('Leader · Data · UI · Action')
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))

      Divider()
        .color($r('app.color.input_stroke'))

      Text('Loopy now ships the same agent_core used by Appless. This entry is a library status shell; product interaction and provider credentials remain in the host app.')
        .fontSize(15)
        .lineHeight(23)
        .fontColor($r('app.color.text_primary'))
        .opacity(0.72)
    }
    .width('100%')
    .height('100%')
    .padding(28)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.page_background'))
  }
}
