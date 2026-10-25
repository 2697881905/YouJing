/**
 * 今日行程卡片 UI（屏13 Widget A 2×2 / Widget B 2×4 同组件自适应）。
 * 实色 surface-elevated + 1px hairline 描边（契约 widget-card：永不模糊、永不半透，
 * 深色 #1E1E1E）；字阶走 TypeTokens（帧的 widget 字阶 11/600、12/600、14/400、11/400
 * 分别落在 overline / time / small / widgetMeta 四档上）；
 * 2×2 内缩 12 / 2×4 内缩 16（LayoutTokens）。
 * serif 在卡片 UIContext 无法注册应用字体，标题暂走 sans 600（精修批次验证卡片字体通道）。
 */

import { TypeTokens } from '../../design/TypeTokens';
import { SpaceTokens } from '../../design/SpaceTokens';
import { LayoutTokens } from '../../design/LayoutTokens';

let cardStorage: LocalStorage = new LocalStorage();

interface CardRow {
  time: string;
  name: string;
  color: string;
}

/** 2×4 编号站点条的一格（帧 .route-node / .current / .gold-ring） */
interface StripNode {
  label: string;
  current: boolean;
  booking: boolean;
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
  @LocalStorageProp('r1c') r1c: string = '';
  @LocalStorageProp('r2t') r2t: string = '';
  @LocalStorageProp('r2n') r2n: string = '';
  @LocalStorageProp('r2c') r2c: string = '';
  @LocalStorageProp('r3t') r3t: string = '';
  @LocalStorageProp('r3n') r3n: string = '';
  @LocalStorageProp('r3c') r3c: string = '';
  @LocalStorageProp('r4t') r4t: string = '';
  @LocalStorageProp('r4n') r4n: string = '';
  @LocalStorageProp('r4c') r4c: string = '';
  // 2×4 的编号站点条（2×2 这三个键恒为空串 → 不渲染）
  @LocalStorageProp('stopTotal') stopTotal: string = '';
  @LocalStorageProp('stopCurrent') stopCurrent: string = '';
  @LocalStorageProp('stopBooking') stopBooking: string = '';
  @LocalStorageProp('tripId') tripId: string = '';

  private num(v: string): number {
    const n: number = Number(v);
    return Number.isNaN(n) ? 0 : n;
  }

  /** 帧 Widget B 的站点条最多四格；当日节点更多时末格记 …（不假装是第四站） */
  private stripNodes(): StripNode[] {
    const total: number = this.num(this.stopTotal);
    const nodes: StripNode[] = [];
    if (total <= 0) {
      return nodes;
    }
    const shown: number = Math.min(total, 4);
    const cur: number = this.num(this.stopCurrent);
    const book: number = this.num(this.stopBooking);
    for (let i = 0; i < shown; i++) {
      const idx: number = i + 1;
      const node: StripNode = {
        label: idx === shown && total > shown ? '…' : `${idx}`,
        current: idx === cur,
        booking: idx === book
      };
      nodes.push(node);
    }
    return nodes;
  }

  /**
   * 色名 → 资源。名字由 CategoryStyle 按活动类别给（与屏8 时间线同一口径），
   * 不再按行序取色——原来第 2 行永远是金色、第 3 行永远是紫色，
   * 而底稿那三行是按「景点 / 餐饮 / 住宿」着色的。
   * 这一步只能留在本地：$r() 只接受字面量，卡片的 Form UIContext 也拿不到 ColorTokens。
   */
  private dotColor(name: string): Resource {
    if (name === 'bookmark') {
      return $r('app.color.bookmark');
    }
    if (name === 'accent_mention') {
      return $r('app.color.accent_mention');
    }
    if (name === 'icon') {
      return $r('app.color.icon');
    }
    if (name === 'faint') {
      return $r('app.color.faint');
    }
    return $r('app.color.primary');
  }

  /** 逐格标量回灌（卡片数组 @LocalStorageProp 不刷新），空槽不占行 */
  private cardRows(): CardRow[] {
    const times: string[] = [this.r1t, this.r2t, this.r3t, this.r4t];
    const names: string[] = [this.r1n, this.r2n, this.r3n, this.r4n];
    const colors: string[] = [this.r1c, this.r2c, this.r3c, this.r4c];
    const rows: CardRow[] = [];
    for (let i = 0; i < times.length; i++) {
      if (names[i].length > 0) {
        const row: CardRow = { time: times[i], name: names[i], color: colors[i] };
        rows.push(row);
      }
    }
    return rows;
  }

  build() {
    Column() {
      Row() {
        Text('有径 · 今日')
          .fontSize(TypeTokens.overline.size)
          .fontWeight(TypeTokens.overline.weight)
          .fontColor($r('app.color.muted'))
          .layoutWeight(1)
      }
      .width('100%')

      Text(this.dayTitle)
        // 帧 7fc1cb85 的卡片日标签是 .serif-title 21/700；字族暂留 sans——
        // Noto Serif SC 是 EntryAbility 里 registerFont 的，FormExtension 卡片进程不共享那次注册，
        // 要真上衬线得在卡片进程里再注册一遍并回桌面实拍验证（见任务 #37）。
        .fontSize(TypeTokens.title.size)
        .fontWeight(TypeTokens.title.weight)
        .fontColor($r('app.color.ink'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      // TodayPlan 算好的「还剩 N 站 · 共 M 站」此前只推到存储、从没上屏（屏13 帧里
      // 这行就是标题下的 meta 行）；空态由 footer 一句承担，所以空数据把 meta 留空
      if (this.meta.length > 0) {
        Text(this.meta)
          .fontSize(TypeTokens.widgetMeta.size)
          .fontWeight(TypeTokens.widgetMeta.weight)
          .fontColor($r('app.color.body'))
          .fontFeature("'tnum' on")
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      Column({ space: SpaceTokens.xs }) {
        ForEach(this.cardRows(), (row: CardRow) => {
          Row({ space: SpaceTokens.xs }) {
            Text(row.time)
              .fontSize(TypeTokens.time.size)
              .fontWeight(TypeTokens.time.weight)
              .fontColor($r('app.color.body'))
              .fontFeature("'tnum' on")
            Circle()
              .width(LayoutTokens.activityDotSize)
              .height(LayoutTokens.activityDotSize)
              .fill(this.dotColor(row.color))
            Text(row.name)
              .fontSize(TypeTokens.small.size)
              .fontWeight(TypeTokens.small.weight)
              .fontColor($r('app.color.ink'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
        }, (row: CardRow): string => `w-${row.time}-${row.name}-${row.color}`)
      }
      .width('100%')
      .margin({ top: SpaceTokens.xs })

      // 帧 Widget B 独有：编号站点条（当前站实心蓝、最近一个待预约节点套金环）
      if (this.stripNodes().length > 0) {
        Stack() {
          Column()
            .width('100%')
            .height(LayoutTokens.routeLineWidth)
            .backgroundColor($r('app.color.primary'))
            .margin({ left: SpaceTokens.md, right: SpaceTokens.md })
          Row() {
            ForEach(this.stripNodes(), (n: StripNode) => {
              Stack() {
                Circle()
                  .width(LayoutTokens.itineraryNodeSize)
                  .height(LayoutTokens.itineraryNodeSize)
                  .fill(n.current ? $r('app.color.primary') : $r('app.color.surface_subtle'))
                  .stroke(n.booking ? $r('app.color.bookmark') : Color.Transparent)
                  .strokeWidth(1)
                Text(n.label)
                  .fontSize(TypeTokens.overline.size)
                  .fontWeight(TypeTokens.overline.weight)
                  .fontColor(n.current ? $r('app.color.on_primary') : $r('app.color.body'))
                  .fontFeature("'tnum' on")
              }
            }, (n: StripNode): string => `s-${n.label}-${n.current}-${n.booking}`)
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
        }
        .width('100%')
        .alignContent(Alignment.Center)
        .margin({ top: SpaceTokens.xs })
      }

      Text(this.footer)
        .fontSize(TypeTokens.widgetMeta.size)
        .fontWeight(TypeTokens.widgetMeta.weight)
        .fontColor($r('app.color.muted'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: SpaceTokens.xs })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
    .padding(this.dimension === '2*4' ? LayoutTokens.widget2x4Padding : LayoutTokens.widget2x2Padding)
    // 契约 widget-card：实色 surface-elevated（深色 #1E1E1E）+ 1px hairline 描边，
    // 永不模糊、永不半透——亮/暗桌面上都读得出这是一块卡（原来用 canvas 无描边）
    .backgroundColor($r('app.color.surface_elevated'))
    .border({ width: 1, color: $r('app.color.hairline') })
    .onClick(() => {
      // 空态不跳转：没有 tripId 时点卡会落到空行程页，让用户以为行程丢了
      if (this.tripId.length === 0) {
        return;
      }
      const routeParams: Record<string, string> = { 'route': 'Itinerary', 'param': this.tripId };
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: routeParams
      });
    })
  }
}
