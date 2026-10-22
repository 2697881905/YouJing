/**
 * 今日行程卡片 UI（屏13 Widget A 2×2 / Widget B 2×4 同组件自适应）。
 * 实色 canvas；最小可读字号 11；2×2 内缩 12 / 2×4 内缩 16（LayoutTokens）。
 * serif 在卡片 UIContext 无法注册应用字体，标题暂走 sans 600（精修批次验证卡片字体通道）。
 */

let cardStorage: LocalStorage = new LocalStorage();

interface CardRow {
  time: string;
  name: string;
  dot: Resource;
}

@Entry(cardStorage)
@Component
struct TodayTripCard {
  @LocalStorageProp('dayTitle') dayTitle: string = 'Day 2 · 6月11日';
  @LocalStorageProp('meta') meta: string = '步行 5.2km · 还剩 2 站';
  @LocalStorageProp('footer') footer: string = '还有 1 个需预约节点 · 14:20 前';
  @LocalStorageProp('dimension') dimension: string = '2*2';
  private rows: CardRow[] = [
    { time: '09:00', name: '岚山竹林', dot: $r('app.color.primary') },
    { time: '11:30', name: '天龙寺', dot: $r('app.color.bookmark') },
    { time: '13:00', name: '午餐 · 岚面', dot: $r('app.color.accent_mention') }
  ];

  build() {
    Column() {
      Row() {
        Text('有径 · 今日')
          .fontSize(11)
          .fontWeight(600)
          .fontColor($r('app.color.muted'))
          .layoutWeight(1)
      }
      .width('100%')

      Text(this.dayTitle)
        .fontSize(18)
        .fontWeight(600)
        .fontColor($r('app.color.ink'))
        .margin({ top: 2 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Column({ space: 4 }) {
        ForEach(this.rows, (row: CardRow) => {
          Row({ space: 6 }) {
            Text(row.time)
              .fontSize(11)
              .fontWeight(450)
              .fontColor($r('app.color.body'))
            Column()
              .width(8)
              .height(8)
              .borderRadius(999)
              .backgroundColor(row.dot)
            Text(row.name)
              .fontSize(12)
              .fontWeight(450)
              .fontColor($r('app.color.ink'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
        }, (row: CardRow): string => `w-${row.time}`)
      }
      .width('100%')
      .margin({ top: 6 })

      Text(this.footer)
        .fontSize(11)
        .fontWeight(450)
        .fontColor($r('app.color.muted'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 6 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
    .padding(this.dimension === '2*4' ? 16 : 12)
    .backgroundColor($r('app.color.canvas'))
    .onClick(() => {
      const routeParams: Record<string, string> = { 'route': 'Itinerary' };
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: routeParams
      });
    })
  }
}
