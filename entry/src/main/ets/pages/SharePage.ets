/**
 * 屏16 分享与导出（帧 074108e2）。
 * §7 必改已落：icon-btn margin 10→8、option-icon-box margin 6→4、scroll 76→94。
 * 真实分享（链接生成/ics 导出）在阶段 10 接入；复制链接按钮走系统无操作占位。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';

interface ShareOption {
  symbol: Resource;
  title: string;
  desc: string;
}

@Component
export struct SharePage {
  private pathStack: NavPathStack = APP_NAV;
  private options: ShareOption[] = [
    { symbol: $r('sys.symbol.link'), title: '分享链接', desc: '对方打开即看行程，不含你的账号信息' },
    { symbol: $r('sys.symbol.calendar'), title: '导出日历文件 (.ics)', desc: '含 3 个需预约提醒，可导入任意日历应用' }
  ];

  @Builder
  optionRow(opt: ShareOption, last: boolean) {
    Column() {
      Row({ space: SpaceTokens.md }) {
        Column() {
          SymbolGlyph(opt.symbol)
            .fontSize(22)
            .fontColor([ColorTokens.ink])
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .borderRadius(RadiusTokens.media)
        .backgroundColor(ColorTokens.surfaceSubtle)

        Column() {
          Text(opt.title)
            .fontSize(TypeTokens.small.size)
            .fontWeight(600)
            .fontColor(ColorTokens.ink)
          Text(opt.desc)
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(22)
          .fontColor([ColorTokens.faint])
      }
      .width('100%')
      .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })

      if (!last) {
        Divider().strokeWidth(LayoutTokens.hairlineWidth).color(ColorTokens.separator)
      }
    }
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        Column() {
          Row() {
            SymbolGlyph($r('sys.symbol.chevron_backward'))
              .fontSize(22)
              .fontColor([ColorTokens.ink])
              .onClick(() => {
                this.pathStack.pop();
              })
              .margin({ right: SpaceTokens.sm })
            Text('分享与导出')
              .fontSize(TypeTokens.body.size)
              .fontWeight(600)
              .fontColor(ColorTokens.ink)
            Blank()
          }
          .height(LayoutTokens.titleBarHeight)
          .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })

          Scroll() {
            Column() {
              Text('分享这份行程')
                .fontSize(TypeTokens.title.size)
                .fontWeight(700)
                .fontFamily(TypeTokens.title.family)
                .fontColor(ColorTokens.ink)
                .margin({ top: SpaceTokens.lg })
              Text('京都 5天4晚 · 16 个景点 · 步行 24.6km')
                .fontSize(TypeTokens.small.size)
                .fontColor(ColorTokens.body)
                .fontFeature("'tnum' on")
                .margin({ top: SpaceTokens.xs, bottom: SpaceTokens.xl })

              Column() {
                Column()
                  .width('100%')
                  .height(140)
                  .borderRadius(RadiusTokens.media)
                  .linearGradient({
                    angle: 180,
                    colors: [[ColorTokens.routeBgTop, 0], [ColorTokens.routeBgBottom, 1]]
                  })
                Row() {
                  this.stat('5', '天')
                  this.stat('16', '站')
                  this.stat('24.6km', '步行')
                }
                .width('100%')
                .justifyContent(FlexAlign.SpaceAround)
                .margin({ top: SpaceTokens.md })
              }
              .width('100%')
              .padding(SpaceTokens.lg)
              .borderRadius(RadiusTokens.card)
              .backgroundColor(ColorTokens.surfaceElevated)

              Column() {
                this.optionRow(this.options[0], false)
                this.optionRow(this.options[1], true)
              }
              .width('100%')
              .padding({ left: SpaceTokens.md, right: SpaceTokens.md })
              .borderRadius(RadiusTokens.card)
              .backgroundColor(ColorTokens.surfaceSubtle)
              .margin({ top: SpaceTokens.xl })
            }
            .alignItems(HorizontalAlign.Start)
            .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, bottom: 150 })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
        }
        .width('100%')
        .height('100%')

        Column({ space: SpaceTokens.sm }) {
          Row({ space: SpaceTokens.md }) {
            YoujingButton({
              variant: YoujingButtonVariant.SECONDARY,
              label: '导出 .ics',
              buttonWidth: 150
            })
            YoujingButton({
              variant: YoujingButtonVariant.PRIMARY,
              label: '复制链接',
              onAction: (): void => {
                this.pathStack.pop();
              }
            })
              .layoutWeight(1)
          }
          .width('100%')

          Text('链接 7 天内有效')
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
        }
        .width('100%')
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, bottom: SpaceTokens.xl })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ColorTokens.canvas)
    }
    .hideTitleBar(true)
  }

  @Builder
  stat(value: string, label: string) {
    Column() {
      Text(value)
        .fontSize(TypeTokens.headline.size)
        .fontWeight(600)
        .fontColor(ColorTokens.ink)
        .fontFeature("'tnum' on")
      Text(label)
        .fontSize(TypeTokens.overline.size)
        .fontWeight(450)
        .fontColor(ColorTokens.muted)
        .margin({ top: 2 })
    }
  }
}
