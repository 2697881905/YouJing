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
  // 默认值与 TodayTripFormAbility 的 emptyData() 对齐：数据到达前不闪底稿里的京都行程
  @LocalStorageProp('dayTitle') dayTitle: string = '今天没有行程安排';
  @LocalStorageProp('meta') meta: string = '';
  @LocalStorageProp('footer') footer: string = '生成行程后自动出现在这里';
  @LocalStorageProp('dimension') dimension: string = '2*2';
  @LocalStorageProp('r1t') r1t: string = '';
  @LocalStorageProp('r1n') r1n: string = '';
  @LocalStorageProp('r2t') r2t: string = '';
  @LocalStorageProp('r2n') r2n: string = '';
  @LocalStorageProp('r3t') r3t: string = '';
  @LocalStorageProp('r3n') r3n: string = '';
  @LocalStorageProp('tripId') tripId: string = '';
  private dots: Resource[] = [
    $r('app.color.primary'), $r('app.color.bookmark'), $r('app.color.accent_mention')
  ];

  /** 逐格标量回灌（卡片数组 @LocalStorageProp 不刷新），空槽不占行 */
  private cardRows(): CardRow[] {
    const times: string[] = [this.r1t, this.r2t, this.r3t];
    const names: string[] = [this.r1n, this.r2n, this.r3n];
    const rows: CardRow[] = [];
    for (let i = 0; i < times.length; i++) {
      if (names[i].length > 0) {
        const row: CardRow = { time: times[i], name: names[i], dot: this.dots[i] };
        rows.push(row);
      }
    }
    return rows;
  }

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

      // TodayPlan 算好的「还剩 N 站 · 共 M 站」此前只推到存储、从没上屏（屏13 帧里
      // 这行就是标题下的 meta 行）；空态由 footer 一句承担，所以空数据把 meta 留空
      if (this.meta.length > 0) {
        Text(this.meta)
          .fontSize(11)
          .fontWeight(450)
          .fontColor($r('app.color.body'))
          .fontFeature("'tnum' on")
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
      }

      Column({ space: 4 }) {
        ForEach(this.cardRows(), (row: CardRow) => {
          Row({ space: 6 }) {
            Text(row.time)
              .fontSize(11)
              .fontWeight(450)
              .fontColor($r('app.color.body'))
            Circle()
              .width(8)
              .height(8)
              .fill(row.dot)
            Text(row.name)
              .fontSize(12)
              .fontWeight(450)
              .fontColor($r('app.color.ink'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
        }, (row: CardRow): string => `w-${row.time}-${row.name}`)
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
      const routeParams: Record<string, string> = { 'route': 'Itinerary', 'param': this.tripId };
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: routeParams
      });
    })
  }
}
