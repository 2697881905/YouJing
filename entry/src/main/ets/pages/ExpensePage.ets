/**
 * 屏11 费用 · 预算对账（帧 1ab099b1）+ 屏11b 超支数据态（帧 70642048）。
 * 同路由双数据态：segment 预算/实际 切换即两帧（稿件分帧只是分别取证）。
 * §7 必改已落：dock padding 10→8、hero-figure margin 6→4、record-btn gap 6→4、segmented padding 2→0。
 * 金额 hero：32/700 走 sans（数字永不 serif，禁令 8）。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { ImmersiveSegmentBar, SegmentedItem } from '../components/ImmersiveSegmentBar';

interface CategorySpend {
  name: string;
  amount: number;
  pct: number;
  color: Resource;
}

interface Receipt {
  time: string;
  name: string;
  amount: string;
}

@Component
export struct ExpensePage {
  private pathStack: NavPathStack = APP_NAV;
  @State private seg: number = 0;
  private segments: SegmentedItem[] = [{ label: '预算' }, { label: '实际' }];
  private budgetCats: CategorySpend[] = [
    { name: '住宿', amount: 6400, pct: 100, color: ColorTokens.accentMention },
    { name: '交通', amount: 2800, pct: 44, color: ColorTokens.icon },
    { name: '餐饮', amount: 2640, pct: 41, color: ColorTokens.bookmark },
    { name: '门票', amount: 1000, pct: 16, color: ColorTokens.primary }
  ];
  private actualCats: CategorySpend[] = [
    { name: '住宿', amount: 7200, pct: 100, color: ColorTokens.accentMention },
    { name: '交通', amount: 3400, pct: 47, color: ColorTokens.icon },
    { name: '餐饮', amount: 3300, pct: 46, color: ColorTokens.bookmark },
    { name: '门票', amount: 2940, pct: 41, color: ColorTokens.primary }
  ];
  private receipts: Receipt[] = [
    { time: '07:40', name: '早餐 · 一番街', amount: '¥900' },
    { time: '09:12', name: '竹林门票', amount: '¥500' },
    { time: '10:05', name: '打车 · 岚山→京都站', amount: '¥1,900' }
  ];

  @Builder
  categoryRow(cat: CategorySpend) {
    Row({ space: SpaceTokens.sm }) {
      Column()
        .width(8)
        .height(8)
        .borderRadius(RadiusTokens.pill)
        .backgroundColor(cat.color)
      Text(cat.name)
        .fontSize(TypeTokens.small.size)
        .fontColor(ColorTokens.ink)
        .width(40)
      Row() {
        Row()
          .height(6)
          .layoutWeight(Math.max(1, cat.pct))
          .borderRadius(RadiusTokens.pill)
          .backgroundColor(cat.color)
        Row()
          .height(6)
          .layoutWeight(Math.max(1, 100 - cat.pct))
          .borderRadius(RadiusTokens.pill)
          .backgroundColor(ColorTokens.surfaceSunken)
      }
      .layoutWeight(1)

      Text(`¥${cat.amount.toLocaleString('en-US')}`)
        .fontSize(TypeTokens.caption.size)
        .fontWeight(450)
        .fontColor(ColorTokens.body)
        .fontFeature("'tnum' on")
        .width(72)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          Text('费用')
            .fontSize(TypeTokens.body.size)
            .fontWeight(600)
            .fontColor(ColorTokens.ink)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          SymbolGlyph($r('sys.symbol.ellipsis_circle'))
            .fontSize(22)
            .fontColor([ColorTokens.ink])
        }
        .height(LayoutTokens.titleBarHeight)
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })

        Scroll() {
          Column() {
            ImmersiveSegmentBar({
              items: this.segments,
              selectedIndex: $seg,
              itemWidth: 164,
              buttonVerticalPadding: 2.15
            })
              .margin({ bottom: SpaceTokens.lg })

            // hero 面板：永不带影（决议 4）
            Column() {
              Text(this.seg === 0 ? '预算 ¥16,000 · 2 人 · 5 天' : '实际 ¥16,840 · 2 人 · 5 天')
                .fontSize(TypeTokens.overline.size)
                .fontWeight(600)
                .fontColor(ColorTokens.muted)
                .fontFeature("'tnum' on")
              Row({ space: SpaceTokens.sm }) {
                Text(this.seg === 0 ? '¥12,840' : '¥16,840')
                  .fontSize(TypeTokens.display.size)
                  .fontWeight(700)
                  .fontColor(this.seg === 0 ? ColorTokens.ink : ColorTokens.danger)
                  .fontFeature("'tnum' on")
                Text('已花')
                  .fontSize(TypeTokens.caption.size)
                  .fontWeight(450)
                  .fontColor(ColorTokens.muted)
                  .margin({ bottom: SpaceTokens.xs })
              }
              .alignItems(VerticalAlign.Bottom)
              .margin({ top: SpaceTokens.xs })

              Row() {
                Row()
                  .height(4)
                  .layoutWeight(this.seg === 0 ? 80 : 100)
                  .borderRadius(RadiusTokens.pill)
                  .backgroundColor(this.seg === 0 ? ColorTokens.primary : ColorTokens.danger)
                if (this.seg === 0) {
                  Row()
                    .height(4)
                    .layoutWeight(20)
                    .borderRadius(RadiusTokens.pill)
                    .backgroundColor(ColorTokens.surfaceSunken)
                }
              }
              .width('100%')
              .margin({ top: SpaceTokens.md })

              Text(this.seg === 0 ? '剩 ¥3,160 · 还剩 2 天' : '超支 ¥840 · 主要来自门票')
                .fontSize(TypeTokens.caption.size)
                .fontWeight(450)
                .fontColor(this.seg === 0 ? ColorTokens.body : ColorTokens.danger)
                .fontFeature("'tnum' on")
                .margin({ top: SpaceTokens.sm })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding(SpaceTokens.lg)
            .borderRadius(RadiusTokens.hero)
            .backgroundColor(ColorTokens.surfaceElevated)

            Text('分类支出')
              .fontSize(TypeTokens.overline.size)
              .fontWeight(600)
              .fontColor(ColorTokens.muted)
              .alignSelf(ItemAlign.Start)
              .margin({ top: SpaceTokens.xl, bottom: SpaceTokens.sm })

            Column() {
              ForEach(this.seg === 0 ? this.budgetCats : this.actualCats,
                (cat: CategorySpend) => {
                  this.categoryRow(cat)
                }, (cat: CategorySpend): string => `cat-${this.seg}-${cat.name}`)
            }
            .width('100%')
            .padding({ left: SpaceTokens.md, right: SpaceTokens.md })
            .borderRadius(RadiusTokens.card)
            .backgroundColor(ColorTokens.canvas)

            Text('最近记账')
              .fontSize(TypeTokens.overline.size)
              .fontWeight(600)
              .fontColor(ColorTokens.muted)
              .alignSelf(ItemAlign.Start)
              .margin({ top: SpaceTokens.xl, bottom: SpaceTokens.sm })

            Column() {
              ForEach(this.receipts, (r: Receipt, idx: number) => {
                Row() {
                  Text(r.time)
                    .fontSize(TypeTokens.caption.size)
                    .fontWeight(450)
                    .fontColor(ColorTokens.muted)
                    .fontFeature("'tnum' on")
                    .width(52)
                  Text(r.name)
                    .fontSize(TypeTokens.small.size)
                    .fontColor(ColorTokens.ink)
                    .layoutWeight(1)
                  Text(r.amount)
                    .fontSize(TypeTokens.small.size)
                    .fontWeight(600)
                    .fontColor(ColorTokens.ink)
                    .fontFeature("'tnum' on")
                }
                .width('100%')
                .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
                if (idx < this.receipts.length - 1) {
                  Divider().strokeWidth(LayoutTokens.hairlineWidth).color(ColorTokens.separator)
                }
              }, (r: Receipt): string => `rc-${r.time}`)
            }
            .width('100%')
            .padding({ left: SpaceTokens.md, right: SpaceTokens.md })
            .borderRadius(RadiusTokens.card)
            .backgroundColor(ColorTokens.canvas)
          }
          .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, bottom: LayoutTokens.bottomScrollReserve })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ColorTokens.canvas)
    }
    .hideTitleBar(true)
  }
}
