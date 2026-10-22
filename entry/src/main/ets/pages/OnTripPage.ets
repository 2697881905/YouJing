/**
 * 屏15 旅行中模式（帧 fc4e40cd）。
 * §7 必改已落：badge padding 3→4、check-right gap 6→4、stop-row padding 10→8、scroll 72→94。
 * hero 站名走 sans 21/700（禁令 8：serif 不上站名）。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';

interface CheckedRow {
  time: string;
  name: string;
  amount: string;
  ongoing: boolean;
}

@Component
export struct OnTripPage {
  private pathStack: NavPathStack = APP_NAV;
  @State private checkedIn: boolean = false;
  private checked: CheckedRow[] = [
    { time: '07:40', name: '早餐', amount: '¥900', ongoing: false },
    { time: '08:30', name: '渡月桥', amount: '', ongoing: false },
    { time: '09:00', name: '竹林', amount: '', ongoing: true }
  ];

  @Builder
  checkRow(row: CheckedRow) {
    Row() {
      Text(row.time)
        .fontSize(TypeTokens.time.size)
        .fontWeight(600)
        .fontColor(row.ongoing ? ColorTokens.primary : ColorTokens.muted)
        .fontFeature("'tnum' on")
        .width(52)
      Text(row.name)
        .fontSize(TypeTokens.small.size)
        .fontWeight(row.ongoing ? 600 : 400)
        .fontColor(ColorTokens.ink)
        .layoutWeight(1)
      if (row.amount.length > 0) {
        Text(row.amount)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.body)
          .fontFeature("'tnum' on")
          .margin({ right: SpaceTokens.sm })
      }
      Text(row.ongoing ? '进行中' : '已打卡')
        .fontSize(TypeTokens.overline.size)
        .fontWeight(600)
        .fontColor(row.ongoing ? ColorTokens.primary : ColorTokens.success)
      if (!row.ongoing) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(14)
          .fontColor([ColorTokens.success])
          .margin({ left: SpaceTokens.xs })
      }
    }
    .width('100%')
    .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          Text('进行中 · Day 2')
            .fontSize(TypeTokens.body.size)
            .fontWeight(600)
            .fontColor(ColorTokens.ink)
            .fontFeature("'tnum' on")
            .layoutWeight(1)
          Text('09:12')
            .fontSize(TypeTokens.body.size)
            .fontWeight(600)
            .fontColor(ColorTokens.ink)
            .fontFeature("'tnum' on")
        }
        .height(LayoutTokens.titleBarHeight)
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })

        Scroll() {
          Column() {
            Column() {
              Text('当前节点')
                .fontSize(TypeTokens.overline.size)
                .fontWeight(600)
                .fontColor(ColorTokens.muted)
              Text('岚山竹林')
                .fontSize(TypeTokens.title.size)
                .fontWeight(700)
                .fontColor(ColorTokens.ink)
                .margin({ top: SpaceTokens.xs })
              Text('09:00 开始 · 建议 1.5小时 · 已过 12分钟')
                .fontSize(TypeTokens.caption.size)
                .fontWeight(450)
                .fontColor(ColorTokens.body)
                .fontFeature("'tnum' on")
                .margin({ top: 2 })
              Row() {
                Row()
                  .height(4)
                  .layoutWeight(15)
                  .borderRadius(RadiusTokens.pill)
                  .backgroundColor(ColorTokens.primary)
                Row()
                  .height(4)
                  .layoutWeight(85)
                  .borderRadius(RadiusTokens.pill)
                  .backgroundColor(ColorTokens.surfaceSunken)
              }
              .width('100%')
              .margin({ top: SpaceTokens.md })
              Text('周一人少，10:00 后团队到达')
                .fontSize(TypeTokens.caption.size)
                .fontWeight(450)
                .fontColor(ColorTokens.warning)
                .margin({ top: SpaceTokens.sm })
              Row({ space: SpaceTokens.md }) {
                YoujingButton({
                  variant: this.checkedIn ? YoujingButtonVariant.SECONDARY : YoujingButtonVariant.SECONDARY,
                  label: this.checkedIn ? '已打卡' : '完成打卡',
                  buttonWidth: 140,
                  onAction: (): void => {
                    this.checkedIn = true;
                  }
                })
                YoujingButton({
                  variant: YoujingButtonVariant.PRIMARY,
                  label: '记一笔费用',
                  buttonWidth: 150,
                  onAction: (): void => {
                    this.pathStack.pushPath({ name: 'Expense' });
                  }
                })
              }
              .margin({ top: SpaceTokens.lg })
              Text('打卡会同步到日历和卡片')
                .fontSize(TypeTokens.overline.size)
                .fontWeight(450)
                .fontColor(ColorTokens.faint)
                .margin({ top: SpaceTokens.sm })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding(SpaceTokens.lg)
            .borderRadius(RadiusTokens.hero)
            .backgroundColor(ColorTokens.surfaceElevated)

            // 下一段：交通腿 + 天龙寺
            Column() {
              Row() {
                Column().width(52)
                Column()
                  .width(2)
                  .height(44)
                  .border({ width: { left: 2 }, color: ColorTokens.separator, style: BorderStyle.Dashed })
                Row({ space: SpaceTokens.xs }) {
                  SymbolGlyph($r('sys.symbol.car'))
                    .fontSize(14)
                    .fontColor([ColorTokens.icon])
                  Text('打车 18分钟 · 4.2km · ¥1,900')
                    .fontSize(TypeTokens.caption.size)
                    .fontWeight(450)
                    .fontColor(ColorTokens.muted)
                    .fontFeature("'tnum' on")
                }
                .padding({ left: SpaceTokens.sm })
              }
              .height(44)
              .alignItems(VerticalAlign.Center)

              Row({ space: SpaceTokens.sm }) {
                Text('11:30')
                  .fontSize(TypeTokens.time.size)
                  .fontWeight(600)
                  .fontColor(ColorTokens.ink)
                  .fontFeature("'tnum' on")
                  .width(52)
                Row({ space: SpaceTokens.xs }) {
                  Text('天龙寺')
                    .fontSize(TypeTokens.small.size)
                    .fontWeight(600)
                    .fontColor(ColorTokens.ink)
                  Text('需预约')
                    .fontSize(TypeTokens.overline.size)
                    .fontWeight(600)
                    .fontColor(ColorTokens.onPrimary)
                    .height(18)
                    .padding({ left: 6, right: 6 })
                    .borderRadius(RadiusTokens.pill)
                    .backgroundColor(ColorTokens.warning)
                }
                .layoutWeight(1)
              }
              .width('100%')
              .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })

              Text('建议停留 1小时 · 嵯峨野')
                .fontSize(TypeTokens.caption.size)
                .fontWeight(450)
                .fontColor(ColorTokens.muted)
                .margin({ left: 60 })
                .alignSelf(ItemAlign.Start)
            }
            .width('100%')
            .margin({ top: SpaceTokens.lg })

            Column() {
              Text('今日已打卡')
                .fontSize(TypeTokens.overline.size)
                .fontWeight(600)
                .fontColor(ColorTokens.muted)
                .alignSelf(ItemAlign.Start)
                .margin({ bottom: SpaceTokens.xs })
              Column() {
                ForEach(this.checked, (row: CheckedRow) => {
                  this.checkRow(row)
                }, (row: CheckedRow): string => `ck-${row.time}`)
              }
              .width('100%')
              .padding({ left: SpaceTokens.md, right: SpaceTokens.md })
              .borderRadius(RadiusTokens.card)
              .backgroundColor(ColorTokens.canvas)
            }
            .width('100%')
            .margin({ top: SpaceTokens.xl })
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
