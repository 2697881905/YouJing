/**
 * 屏1 首启与静默登录（帧 77ed8d08）。
 * 必改表已落：bottom-section gap 10→8；preview-badge padding 2→0；
 * preview-foot padding 10→8；stop-body padding 10→8；
 * transit-leg margin-left 64→48、padding 10→8。
 * 状态栏 mock 为设备 chrome，不实现。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';

interface PreviewStop {
  time: string;
  name: string;
  meta: string;
  dotColor: Resource;
}

interface PreviewLeg {
  text: string;
}

// 预览动线行高：契约 itinerary-row-min-height，行内 spine 线取定值避免百分比循环
const ROW_HEIGHT: number = 76;

@Component
export struct YoujingStartPage {
  private pathStack: NavPathStack = APP_NAV;

  private stops: PreviewStop[] = [
    { time: '09:30', name: '清水寺', meta: '东山区 · 停留 1小时30分钟', dotColor: ColorTokens.primary },
    { time: '10:45', name: '二年坂', meta: '古街漫步 · 停留 45分钟', dotColor: ColorTokens.primary },
    { time: '12:10', name: '一番街 午餐', meta: '京料理定食 · 停留 1小时', dotColor: ColorTokens.bookmark }
  ];
  private legs: PreviewLeg[] = [
    { text: '步行 12分钟 · 750m' },
    { text: '步行 18分钟 · 1.2km' }
  ];

  @Builder
  spineNode(dotColor: Resource) {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width(24)
        .height(24)
        .borderRadius(RadiusTokens.pill)
        .backgroundColor(ColorTokens.canvas)
        .border({ width: 2, color: ColorTokens.ink })
      Column()
        .width(10)
        .height(10)
        .borderRadius(RadiusTokens.pill)
        .backgroundColor(dotColor)
    }
    .width(24)
    .height(24)
  }

  @Builder
  timelineRow(stop: PreviewStop, index: number) {
    Row() {
      Text(stop.time)
        .width(52)
        .fontSize(TypeTokens.time.size)
        .fontWeight(600)
        .fontColor(ColorTokens.ink)
        .textAlign(TextAlign.End)
        .fontFeature("'tnum' on")
        .padding({ right: SpaceTokens.md, top: SpaceTokens.xs })
      Stack({ alignContent: Alignment.Top }) {
        Column()
          .width(LayoutTokens.routeLineWidth)
          .height(index === this.stops.length - 1 ? 12 : ROW_HEIGHT)
          .backgroundColor(ColorTokens.surfaceSunken)
        this.spineNode(stop.dotColor)
      }
      .width(24)
      .height(ROW_HEIGHT)
      Column() {
        Text(stop.name)
          .fontSize(TypeTokens.headline.size)
          .fontWeight(600)
          .fontColor(ColorTokens.ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(stop.meta)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .fontFeature("'tnum' on")
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .padding({ left: SpaceTokens.sm, bottom: SpaceTokens.sm })
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
    .height(ROW_HEIGHT)
  }

  @Builder
  transitLeg(leg: PreviewLeg) {
    Row() {
      Row({ space: SpaceTokens.sm }) {
        SymbolGlyph($r('sys.symbol.figure_walk'))
          .fontSize(14)
          .fontColor([ColorTokens.icon])
        Text(leg.text)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .fontFeature("'tnum' on")
      }
      .height(LayoutTokens.transitLegHeight)
      .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm })
      .borderRadius(RadiusTokens.capsule)
      .border({ width: 2, style: BorderStyle.Dashed, color: ColorTokens.separator, radius: RadiusTokens.capsule })
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 48 })
    .margin({ bottom: SpaceTokens.sm })
  }

  build() {
    Column() {
      Column({ space: SpaceTokens.sm }) {
        Row() {
          Text('有径')
            .fontSize(TypeTokens.display.size)
            .fontWeight(700)
            .fontFamily(TypeTokens.display.family)
            .fontColor(ColorTokens.ink)
          Text('TRACEABLE ROUTES')
            .fontSize(TypeTokens.overline.size)
            .fontWeight(600)
            .fontColor(ColorTokens.primary)
            .letterSpacing(0)
            .margin({ left: SpaceTokens.sm })
            .offset({ y: -4 })
        }
        .alignItems(VerticalAlign.Bottom)

        Text('有迹可循，有径可行')
          .fontSize(TypeTokens.small.size)
          .fontColor(ColorTokens.body)
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ top: SpaceTokens.xs, bottom: SpaceTokens.lg })

      Column() {
        Row() {
          Text('Day 1 · 京都 东山步道')
            .fontSize(TypeTokens.title.size)
            .fontWeight(700)
            .fontFamily(TypeTokens.title.family)
            .fontColor(ColorTokens.ink)
            .layoutWeight(1)
          Text('规划预览')
            .fontSize(TypeTokens.overline.size)
            .fontWeight(600)
            .fontColor(ColorTokens.onPrimary)
            .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm })
            .height(22)
            .borderRadius(RadiusTokens.pill)
            .backgroundColor(ColorTokens.primary)
        }
        .alignItems(VerticalAlign.Center)
        .width('100%')
        .padding({ bottom: SpaceTokens.sm })
        .border({ width: { bottom: LayoutTokens.hairlineWidth }, color: ColorTokens.separator })

        Column() {
          ForEach(this.stops, (stop: PreviewStop, index: number) => {
            this.timelineRow(stop, index)
            if (index < this.legs.length) {
              this.transitLeg(this.legs[index])
            }
          }, (stop: PreviewStop, index: number): string => `start-preview-${index}-${stop.time}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ top: SpaceTokens.sm })

        Column() {
          Text('结构化路线承诺')
            .fontSize(TypeTokens.overline.size)
            .fontWeight(600)
            .fontColor(ColorTokens.muted)
          Text('基于本地精选数据库与步行动线计算，每个站点均明确耗时与预约状态。')
            .fontSize(TypeTokens.caption.size)
            .fontColor(ColorTokens.body)
            .lineHeight(18)
            .margin({ top: SpaceTokens.xs })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: SpaceTokens.md, right: SpaceTokens.md, top: SpaceTokens.sm, bottom: SpaceTokens.sm })
        .borderRadius(RadiusTokens.reason)
        .backgroundColor(ColorTokens.surfacePanel)
        .margin({ top: SpaceTokens.xs })
      }
      .padding(SpaceTokens.lg)
      .borderRadius(RadiusTokens.card)
      .backgroundColor(ColorTokens.surfaceElevated)
      .width('100%')

      Blank()

      Column({ space: SpaceTokens.sm }) {
        YoujingButton({
          variant: YoujingButtonVariant.PRIMARY,
          label: '华为账号一键登录',
          fullWidth: true,
          leadingSymbol: $r('sys.symbol.person_crop_circle_fill_1'),
          onAction: (): void => {
            this.pathStack.pushPath({ name: 'TripInput' });
          }
        })
        Row({ space: SpaceTokens.xs }) {
          SymbolGlyph($r('sys.symbol.lock'))
            .fontSize(12)
            .fontColor([ColorTokens.muted])
          Text('仅使用 UnionID 静默授权，行程数据保留于本地')
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
        }
      }
      .width('100%')
      .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, top: SpaceTokens.md })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })
    .backgroundColor(ColorTokens.canvas)
  }
}
