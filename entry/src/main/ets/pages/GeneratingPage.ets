/**
 * 屏6 行程生成中（帧 35c7d3b4）。
 * §7 必改已落：scroll-content padding 104→94。
 * 骨架屏 shimmer 是禁令 10 的唯一 opacity 豁免场景。
 * 骨架完成（模拟 4 阶段推进）后 replacePath 进屏8；真实 LLM 管线在阶段 6 接入，
 * 失败分支进屏7 GenerateFailed（批次 4）。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';

@Component
export struct GeneratingPage {
  private pathStack: NavPathStack = APP_NAV;
  @State private stage: number = 0;
  @State private progress: number = 0.25;
  private stages: string[] = ['筛选景点', '排布每日动线', '校验开放时间与预约', '估算步行耗时'];
  private timer: number = -1;

  aboutToAppear(): void {
    this.timer = setInterval(() => {
      if (this.stage < this.stages.length) {
        this.stage += 1;
        this.progress = (this.stage + 1) / (this.stages.length + 1);
      }
      if (this.stage >= this.stages.length) {
        clearInterval(this.timer);
        this.timer = -1;
        this.pathStack.replacePath({ name: 'Itinerary' });
      }
    }, 900);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
    }
  }

  @Builder
  skeletonBlock(w: Length, h: number, weight: number) {
    Column()
      .width(w)
      .height(h)
      .borderRadius(RadiusTokens.media)
      .backgroundColor(ColorTokens.skeletonBase)
      .opacity(0.6)
      .animation({ duration: 800, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate })
  }

  @Builder
  skeletonRow() {
    Row({ space: SpaceTokens.sm }) {
      this.skeletonBlock(40, 14, 0)
      Column()
        .width(24)
        .height(24)
        .borderRadius(RadiusTokens.pill)
        .backgroundColor(ColorTokens.skeletonBase)
      Column({ space: SpaceTokens.xs }) {
        this.skeletonBlock('70%', 14, 0)
        this.skeletonBlock('45%', 10, 0)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
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
            Text('生成行程')
              .fontSize(TypeTokens.body.size)
              .fontWeight(600)
              .fontColor(ColorTokens.ink)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
            Column().width(44)
          }
          .height(LayoutTokens.titleBarHeight)
          .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })

          Column() {
            Text('正在为你规划 5 天行程')
              .fontSize(TypeTokens.title.size)
              .fontWeight(700)
              .fontFamily(TypeTokens.title.family)
              .fontColor(ColorTokens.ink)
            Text('已选好 16 个景点 · 2 个住宿区域')
              .fontSize(TypeTokens.caption.size)
              .fontWeight(450)
              .fontColor(ColorTokens.muted)
              .fontFeature("'tnum' on")
              .margin({ top: SpaceTokens.xs, bottom: SpaceTokens.md })
            Row() {
              Row()
                .height(4)
                .layoutWeight(Math.max(1, Math.round(this.progress * 100)))
                .borderRadius(RadiusTokens.pill)
                .backgroundColor(ColorTokens.primary)
              Row()
                .height(4)
                .layoutWeight(Math.max(1, 100 - Math.round(this.progress * 100)))
                .borderRadius(RadiusTokens.pill)
                .backgroundColor(ColorTokens.hairline)
            }
            .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .margin({ top: SpaceTokens.xl })

          Column({ space: SpaceTokens.sm }) {
            ForEach(this.stages, (name: string, idx: number) => {
              Row({ space: SpaceTokens.sm }) {
                SymbolGlyph(idx < this.stage ? $r('sys.symbol.checkmark_circle_fill') :
                  (idx === this.stage ? $r('sys.symbol.arrow_clockwise') : $r('sys.symbol.circle')))
                  .fontSize(22)
                  .fontColor([idx < this.stage ? ColorTokens.success :
                    (idx === this.stage ? ColorTokens.primary : ColorTokens.faint)])
                Text(name)
                  .fontSize(TypeTokens.small.size)
                  .fontWeight(idx === this.stage ? 600 : 400)
                  .fontColor(idx <= this.stage ? ColorTokens.ink : ColorTokens.muted)
              }
            }, (name: string, idx: number): string => `stage-${idx}-${this.stage}`)
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .margin({ top: SpaceTokens.xl })

          Column() {
            Column() {
              this.skeletonRow()
              this.skeletonRow()
              this.skeletonRow()
            }
            .padding(SpaceTokens.md)
            .borderRadius(RadiusTokens.card)
            .backgroundColor(ColorTokens.surfaceElevated)
            .width('100%')
            .margin({ bottom: SpaceTokens.md })

            Column() {
              this.skeletonRow()
              this.skeletonRow()
            }
            .padding(SpaceTokens.md)
            .borderRadius(RadiusTokens.card)
            .backgroundColor(ColorTokens.surfaceElevated)
            .width('100%')
          }
          .width('100%')
          .margin({ top: SpaceTokens.xl })
          .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })

        Column({ space: SpaceTokens.sm }) {
          Text('全程在本机生成，无需等待网络')
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
          YoujingCancel()
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
}

@Component
struct YoujingCancel {
  private pathStack: NavPathStack = APP_NAV;

  build() {
    Text('取消')
      .fontSize(TypeTokens.body.size)
      .fontColor(ColorTokens.body)
      .width('100%')
      .height(LayoutTokens.minTouchTarget)
      .textAlign(TextAlign.Center)
      .onClick(() => {
        this.pathStack.pop();
      })
  }
}
