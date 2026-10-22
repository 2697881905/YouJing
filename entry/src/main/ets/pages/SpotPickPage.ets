/**
 * 屏4 景点挑选与优先级（帧 7d6e58d6）。
 * §10 必改三件套已落：底栏按画板收回（Stack 底部对齐 + 内容 padding 预留，
 * CTA 距底 ≥16）、状态栏无玻璃、底栏材质走规则（实色 canvas，非玻璃）。
 * §7 必改：badge-booking padding 2→0（高 22 定高）、summary-strip gap 6→4。
 * 优先级圈按帧 CSS：选中 = bookmark 金底白字「必」，未选 = 空心环。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { ShadowTokens } from '../design/ShadowTokens';
import { Spot } from '../model/Spot';
import { MockSpots } from '../mock/MockData';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';

interface SpotGroup {
  overline: string;
  spots: Spot[];
}

@Component
export struct SpotPickPage {
  private pathStack: NavPathStack = APP_NAV;
  @StorageProp('isDarkMode') isDark: boolean = false;
  @State private mustIds: string[] = ['s-kiyomizu'];
  private groups: SpotGroup[] = [
    { overline: '文化', spots: MockSpots.CULTURE },
    { overline: '美食', spots: MockSpots.FOOD },
    { overline: '自然', spots: MockSpots.NATURE }
  ];
  private totalSpots: number = 9;

  private toggleMust(id: string): void {
    const next: string[] = this.mustIds.slice();
    const at: number = next.indexOf(id);
    if (at >= 0) {
      next.splice(at, 1);
    } else {
      next.push(id);
    }
    this.mustIds = next;
  }

  private durationText(mins: number): string {
    const h: number = Math.floor(mins / 60);
    const m: number = mins % 60;
    if (h > 0 && m > 0) {
      return `${h}小时${m}分钟`;
    }
    return h > 0 ? `${h}小时` : `${m}分钟`;
  }

  @Builder
  spotRow(sp: Spot) {
    Row({ space: SpaceTokens.md }) {
      Column()
        .width(36)
        .height(48)
        .borderRadius(RadiusTokens.media)
        .backgroundColor(ColorTokens.surfaceSunken)
      Column() {
        Row({ space: SpaceTokens.sm }) {
          Text(sp.name)
            .fontSize(TypeTokens.body.size)
            .fontWeight(600)
            .fontColor(ColorTokens.ink)
          if (sp.booking.requiresBooking) {
            Text('需预约')
              .fontSize(TypeTokens.caption.size)
              .fontWeight(600)
              .fontColor(ColorTokens.onPrimary)
              .height(22)
              .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm })
              .borderRadius(RadiusTokens.pill)
              .backgroundColor(ColorTokens.warning)
          }
        }
        Text(`${sp.district} · 建议停留 ${this.durationText(sp.suggestedDuration)}`)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .fontFeature("'tnum' on")
          .margin({ top: SpaceTokens.xs })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Column() {
        if (this.mustIds.indexOf(sp.id) >= 0) {
          Text('必')
            .fontSize(TypeTokens.caption.size)
            .fontWeight(600)
            .fontColor(ColorTokens.onPrimary)
        }
      }
      .width(24)
      .height(24)
      .justifyContent(FlexAlign.Center)
      .borderRadius(RadiusTokens.pill)
      .backgroundColor(this.mustIds.indexOf(sp.id) >= 0 ? ColorTokens.bookmark : ColorTokens.canvas)
      .border({
        width: 1,
        color: this.mustIds.indexOf(sp.id) >= 0 ? ColorTokens.bookmark : ColorTokens.hairlineStrong,
        radius: RadiusTokens.pill
      })
    }
    .width('100%')
    .constraintSize({ minHeight: LayoutTokens.itineraryRowMinHeight })
    .padding({ top: SpaceTokens.md, bottom: SpaceTokens.md })
    .onClick(() => {
      this.toggleMust(sp.id);
    })
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        Column() {
        // 顶栏
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_backward'))
            .fontSize(22)
            .fontColor([ColorTokens.ink])
            .onClick(() => {
              this.pathStack.pop();
            })
          Text('选想去的地方')
            .fontSize(TypeTokens.body.size)
            .fontWeight(600)
            .fontColor(ColorTokens.ink)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          Text('推荐更多')
            .fontSize(TypeTokens.small.size)
            .fontColor(ColorTokens.primary)
            .width(64)
        }
        .height(LayoutTokens.titleBarHeight)
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })

        // 容量摘要条
        Column({ space: SpaceTokens.xs }) {
          Text(`已选 ${this.mustIds.length} / 可用 4.2 天 · 建议上限 ${this.totalSpots + 7} 个`)
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.body)
            .fontFeature("'tnum' on")
          Row() {
            Row()
              .height(4)
              .layoutWeight(30 + this.mustIds.length * 2)
              .borderRadius(RadiusTokens.pill)
              .backgroundColor(ColorTokens.primary)
            Row()
              .height(4)
              .layoutWeight(40 - this.mustIds.length * 2)
              .borderRadius(RadiusTokens.pill)
              .backgroundColor(ColorTokens.surfaceSunken)
          }
          .width('100%')
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .height(56)
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })
        .backgroundColor(ColorTokens.surfacePanel)

        Scroll() {
          Column() {
            Column({ space: SpaceTokens.xs }) {
              Text('时间偏紧')
                .fontSize(TypeTokens.overline.size)
                .fontWeight(600)
                .fontColor(ColorTokens.warning)
              Text('按现在的节奏，建议给景点标优先级，行程会自动取舍')
                .fontSize(TypeTokens.caption.size)
                .fontColor(ColorTokens.body)
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding({ left: SpaceTokens.md, right: SpaceTokens.md, top: SpaceTokens.md, bottom: SpaceTokens.md })
            .borderRadius(RadiusTokens.reason)
            .backgroundColor(ColorTokens.surfacePanel)
            .margin({ top: SpaceTokens.md, bottom: SpaceTokens.md })

            ForEach(this.groups, (group: SpotGroup) => {
              Column() {
                Text(`${group.overline} · ${group.spots.length}`)
                  .fontSize(TypeTokens.overline.size)
                  .fontWeight(600)
                  .fontColor(ColorTokens.muted)
                  .margin({ bottom: SpaceTokens.xs })
                Column() {
                  ForEach(group.spots, (sp: Spot, idx: number) => {
                    this.spotRow(sp)
                    if (idx < group.spots.length - 1) {
                      Divider()
                        .strokeWidth(LayoutTokens.hairlineWidth)
                        .color(ColorTokens.separator)
                    }
                  }, (sp: Spot): string => sp.id)
                }
                .padding({ left: SpaceTokens.md, right: SpaceTokens.md })
                .borderRadius(RadiusTokens.card)
                .backgroundColor(ColorTokens.canvas)
                .shadow(this.isDark ? { radius: 0 } : ShadowTokens.card)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ bottom: SpaceTokens.lg })
            }, (group: SpotGroup): string => group.overline)
          }
          .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, bottom: 110 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
        .width('100%')
        .height('100%')

        // 底栏：实色 canvas（非玻璃），悬浮于滚动区之上，CTA 距底 ≥16
        Column() {
        Row({ space: SpaceTokens.md }) {
          YoujingButton({
            variant: YoujingButtonVariant.SECONDARY,
            label: '跳过选择',
            buttonWidth: 120,
            onAction: (): void => {
              this.pathStack.pushPath({ name: 'StayPick' });
            }
          })
          YoujingButton({
            variant: YoujingButtonVariant.PRIMARY,
            label: '确认选择',
            onAction: (): void => {
              this.pathStack.pushPath({ name: 'StayPick' });
            }
          })
            .layoutWeight(1)
        }
      }
      .width('100%')
      .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, top: SpaceTokens.md, bottom: SpaceTokens.lg })
      .backgroundColor(ColorTokens.canvas)
      }
    }
    .hideTitleBar(true)
  }
}
