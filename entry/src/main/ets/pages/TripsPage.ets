/**
 * 屏12 我的行程（帧 f037b5c4）+ 屏12b 空状态（按干净版 7991fe5b 抄，不抄 06190639 的 !important）。
 * 卡片：place serif 21 / 日期 meta / 动线 5 节点（必去金）/ 三统计 / 状态行+进度。
 * 状态切换由数据驱动（trips 为空即 12b），生产接 RDB 后自动生效。
 * §7 必改已落：booking-badge padding 2→0、card-footer gap 6→4、dock padding 10→8。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { ShadowTokens } from '../design/ShadowTokens';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { TripDao, TripSummary } from '../data/TripDao';
import { common } from '@kit.AbilityKit';

interface TripCardData {
  id: string;
  place: string;
  dateMeta: string;
  spots: string;
  walk: string;
  bookingNum: string;
  bookingBadge: string;
  badgeColor: Resource;
  statusLine: string;
  progress: number;
  mustIdx: number;
  onTrip: boolean;
  muted: boolean;
}

@Component
export struct TripsPage {
  private pathStack: NavPathStack = APP_NAV;
  @StorageProp('isDarkMode') isDark: boolean = false;
  @State private trips: TripCardData[] = [];

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    TripDao.listSummaries(ctx).then((rows: TripSummary[]) => {
      const list: TripCardData[] = [];
      for (const r of rows) {
        const t: TripCardData = {
          id: r.id, place: r.destination,
          dateMeta: `${r.startDate} – ${r.endDate} · ${r.people} 人`,
          spots: `${r.spotCount}`, walk: '—', bookingNum: '—',
          bookingBadge: r.totalCost > 0 ? `¥${r.totalCost}` : '',
          badgeColor: ColorTokens.success,
          statusLine: '已生成', progress: 100, mustIdx: -1,
          onTrip: false, muted: false
        };
        list.push(t);
      }
      this.trips = list;
    });
  }

  @Builder
  miniRoute(mustIdx: number) {
    Row() {
      ForEach([0, 1, 2, 3, 4], (i: number) => {
        if (i > 0) {
          Column().width(24).height(2).backgroundColor(ColorTokens.surfaceSunken)
        }
        Column() {
          Text(`${i + 1}`)
            .fontSize(TypeTokens.overline.size)
            .fontWeight(600)
            .fontColor(i === mustIdx ? ColorTokens.onPrimary : ColorTokens.body)
        }
        .width(20)
        .height(20)
        .justifyContent(FlexAlign.Center)
        .borderRadius(RadiusTokens.pill)
        .backgroundColor(i === mustIdx ? ColorTokens.bookmark : ColorTokens.surfaceSubtle)
      }, (i: number): string => `node-${i}`)
    }
    .margin({ top: SpaceTokens.md, bottom: SpaceTokens.md })
  }

  @Builder
  statCol(value: string, label: string, badge: string, badgeColor: Resource, muted: boolean) {
    Column() {
      if (badge.length > 0) {
        Row({ space: SpaceTokens.xs }) {
          Text(value)
            .fontSize(TypeTokens.headline.size)
            .fontWeight(600)
            .fontColor(muted ? ColorTokens.muted : ColorTokens.ink)
            .fontFeature("'tnum' on")
          Text(badge)
            .fontSize(TypeTokens.overline.size)
            .fontWeight(600)
            .fontColor(ColorTokens.onPrimary)
            .height(18)
            .padding({ left: 6, right: 6 })
            .borderRadius(RadiusTokens.pill)
            .backgroundColor(badgeColor)
        }
        .alignItems(VerticalAlign.Center)
      } else {
        Text(value)
          .fontSize(TypeTokens.headline.size)
          .fontWeight(600)
          .fontColor(muted ? ColorTokens.muted : ColorTokens.ink)
          .fontFeature("'tnum' on")
      }
      Text(label)
        .fontSize(TypeTokens.overline.size)
        .fontWeight(450)
        .fontColor(ColorTokens.muted)
        .margin({ top: 2 })
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  @Builder
  tripCard(t: TripCardData) {
    Column() {
      Column() {
        Text(t.place)
          .fontSize(TypeTokens.title.size)
          .fontWeight(700)
          .fontFamily(TypeTokens.title.family)
          .fontColor(ColorTokens.ink)
        Text(t.dateMeta)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .fontFeature("'tnum' on")
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      this.miniRoute(t.mustIdx)

      Row() {
        this.statCol(t.spots, '景点', '', ColorTokens.canvas, t.muted)
        this.statCol(t.walk, '步行', '', ColorTokens.canvas, t.muted)
        this.statCol(t.bookingNum, '需预约', t.bookingBadge, t.badgeColor, t.muted)
      }
      .width('100%')

      Column({ space: SpaceTokens.xs }) {
        Text(t.statusLine)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.body)
          .fontFeature("'tnum' on")
        Row() {
          Row()
            .height(4)
            .layoutWeight(Math.max(1, t.progress))
            .borderRadius(RadiusTokens.pill)
            .backgroundColor(ColorTokens.primary)
          Row()
            .height(4)
            .layoutWeight(Math.max(1, 100 - t.progress))
            .borderRadius(RadiusTokens.pill)
            .backgroundColor(ColorTokens.surfaceSunken)
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .margin({ top: SpaceTokens.md })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(SpaceTokens.lg)
    .borderRadius(RadiusTokens.card)
    .backgroundColor(ColorTokens.canvas)
    .shadow(this.isDark ? { radius: 0 } : ShadowTokens.card)
    .margin({ bottom: SpaceTokens.md })
    .onClick(() => {
      this.pathStack.pushPath({ name: t.onTrip ? 'OnTrip' : 'Itinerary', param: t.id });
    })
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          Text('我的行程')
            .fontSize(TypeTokens.body.size)
            .fontWeight(600)
            .fontColor(ColorTokens.ink)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(22)
            .fontColor([ColorTokens.ink])
        }
        .height(LayoutTokens.titleBarHeight)
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })

        if (this.trips.length === 0) {
          Column({ space: SpaceTokens.md }) {
            SymbolGlyph($r('sys.symbol.map'))
              .fontSize(48)
              .fontColor([ColorTokens.muted])
            Text('还没有行程')
              .fontSize(TypeTokens.title.size)
              .fontWeight(700)
              .fontFamily(TypeTokens.title.family)
              .fontColor(ColorTokens.ink)
            Text('从一座城市开始，让有径替你排好每天的路')
              .fontSize(TypeTokens.small.size)
              .fontColor(ColorTokens.body)
            YoujingButton({
              variant: YoujingButtonVariant.PRIMARY,
              label: '创建新行程',
              buttonWidth: 200,
              onAction: (): void => {
                this.pathStack.pushPath({ name: 'TripInput' });
              }
            })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column() {
              ForEach(this.trips, (t: TripCardData) => {
                this.tripCard(t)
              }, (t: TripCardData): string => t.id)
            }
            .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, bottom: LayoutTokens.bottomScrollReserve })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ColorTokens.canvas)
    }
    .hideTitleBar(true)
  }
}
