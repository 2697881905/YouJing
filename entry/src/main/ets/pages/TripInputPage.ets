/**
 * 屏2 行程基础输入（帧 7d2eafa8）。
 * 必改表已落：budget-container gap 10→8；budget-track-wrapper gap 6→4；field-col gap 2→0。
 * 目的地/日期选择器与预算滑杆交互在批次 4 接入，本批为静态展示态 + 可选人数。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';

@Component
export struct TripInputPage {
  private pathStack: NavPathStack = APP_NAV;
  @State private party: number = 2;
  private partyOptions: number[] = [1, 2, 4];

  @Builder
  fieldLabel(label: string) {
    Text(label)
      .fontSize(TypeTokens.overline.size)
      .fontWeight(600)
      .fontColor(ColorTokens.muted)
  }

  @Builder
  chevron() {
    SymbolGlyph($r('sys.symbol.chevron_right'))
      .fontSize(22)
      .fontColor([ColorTokens.faint])
  }

  @Builder
  partyChip(count: number) {
    Column() {
      Text(count.toString())
        .width(24)
        .height(24)
        .fontSize(TypeTokens.small.size)
        .fontWeight(600)
        .fontColor(ColorTokens.ink)
        .textAlign(TextAlign.Center)
        .borderRadius(RadiusTokens.pill)
        .backgroundColor(this.party === count ? ColorTokens.primaryTint : ColorTokens.surfaceSubtle)
        .border({
          width: this.party === count ? 1 : 0,
          color: ColorTokens.primary,
          radius: RadiusTokens.pill
        })
    }
    .width(LayoutTokens.minTouchTarget)
    .height(LayoutTokens.minTouchTarget)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.party = count;
    })
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_backward'))
            .fontSize(22)
            .fontColor([ColorTokens.ink])
            .onClick(() => {
              this.pathStack.pop();
            })
          Text('有径')
            .fontSize(TypeTokens.body.size)
            .fontWeight(600)
            .fontColor(ColorTokens.ink)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          Column().width(44)
        }
        .height(LayoutTokens.titleBarHeight)
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })

        Scroll() {
          Column() {
            Column() {
              Text('开启一次有迹可循的旅程')
                .fontSize(TypeTokens.title.size)
                .fontWeight(700)
                .fontFamily(TypeTokens.title.family)
                .fontColor(ColorTokens.ink)
              Text('设定出行基础参数，AI 将基于本地精选数据库构建动线')
                .fontSize(TypeTokens.small.size)
                .fontColor(ColorTokens.body)
                .margin({ top: SpaceTokens.xs })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .margin({ top: SpaceTokens.lg, bottom: SpaceTokens.xl })

            Column({ space: SpaceTokens.md }) {
              // 目的地
              Row() {
                Column() {
                  this.fieldLabel('目的地')
                  Text('京都 · 日本')
                    .fontSize(TypeTokens.headline.size)
                    .fontWeight(600)
                    .fontColor(ColorTokens.ink)
                    .margin({ top: SpaceTokens.xs })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                this.chevron()
              }
              .width('100%')
              .padding(SpaceTokens.lg)
              .borderRadius(RadiusTokens.card)
              .backgroundColor(ColorTokens.surfaceSubtle)

              // 出行日期
              Row() {
                Column() {
                  this.fieldLabel('出行日期')
                  Text('6月10日 – 6月14日')
                    .fontSize(TypeTokens.headline.size)
                    .fontWeight(600)
                    .fontColor(ColorTokens.ink)
                    .fontFeature("'tnum' on")
                    .margin({ top: SpaceTokens.xs })
                  Text('5天4晚')
                    .fontSize(TypeTokens.caption.size)
                    .fontWeight(450)
                    .fontColor(ColorTokens.muted)
                    .margin({ top: SpaceTokens.xs })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                this.chevron()
              }
              .width('100%')
              .padding(SpaceTokens.lg)
              .borderRadius(RadiusTokens.card)
              .backgroundColor(ColorTokens.surfaceSubtle)

              // 同行人数
              Row() {
                Column() {
                  this.fieldLabel('同行人数')
                  Text(`${this.party} 位成人`)
                    .fontSize(TypeTokens.headline.size)
                    .fontWeight(600)
                    .fontColor(ColorTokens.ink)
                    .fontFeature("'tnum' on")
                    .margin({ top: SpaceTokens.xs })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Row({ space: SpaceTokens.xs }) {
                  ForEach(this.partyOptions, (count: number) => {
                    this.partyChip(count)
                  }, (count: number): string => `party-${count}`)
                }
              }
              .width('100%')
              .padding(SpaceTokens.lg)
              .borderRadius(RadiusTokens.card)
              .backgroundColor(ColorTokens.surfaceSubtle)

              // 预算档位
              Column({ space: SpaceTokens.sm }) {
                Row() {
                  Column() {
                    this.fieldLabel('预算档位')
                    Text('¥8,000 / 人')
                      .fontSize(TypeTokens.headline.size)
                      .fontWeight(600)
                      .fontColor(ColorTokens.ink)
                      .fontFeature("'tnum' on")
                      .margin({ top: SpaceTokens.xs })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  this.chevron()
                }
                .width('100%')

                Row() {
                  Column()
                    .height(4)
                    .layoutWeight(55)
                    .borderRadius(RadiusTokens.pill)
                    .backgroundColor(ColorTokens.primary)
                  Column()
                    .height(4)
                    .layoutWeight(45)
                    .borderRadius(RadiusTokens.pill)
                    .backgroundColor(ColorTokens.hairline)
                }
                .width('100%')

                Row() {
                  Text('经济')
                    .fontSize(TypeTokens.caption.size)
                    .fontWeight(450)
                    .fontColor(ColorTokens.muted)
                  Text('舒适')
                    .fontSize(TypeTokens.caption.size)
                    .fontWeight(450)
                    .fontColor(ColorTokens.muted)
                }
                .width('100%')
                .justifyContent(FlexAlign.SpaceBetween)
              }
              .width('100%')
              .padding(SpaceTokens.lg)
              .borderRadius(RadiusTokens.card)
              .backgroundColor(ColorTokens.surfaceSubtle)
            }
          }
          .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, bottom: LayoutTokens.bottomScrollReserve })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)

        Column() {
          YoujingButton({
            variant: YoujingButtonVariant.PRIMARY,
            label: '开始规划',
            fullWidth: true,
            trailingSymbol: $r('sys.symbol.arrow_right'),
            onAction: (): void => {
              this.pathStack.pushPath({ name: 'PreferenceQA' });
            }
          })
        }
        .width('100%')
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, top: SpaceTokens.md, bottom: SpaceTokens.md })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ColorTokens.canvas)
    }
    .hideTitleBar(true)
  }
}
