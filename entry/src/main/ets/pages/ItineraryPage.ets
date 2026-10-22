/**
 * 屏8 行程时间线主视图（帧 9c0acbcd）。
 * §7 必改已落：booking-badge padding 3→4、dock padding 10→8、
 * reason-block margin 10→8、scroll 底部预留 138→94、transit gap 6→4。
 * 顶栏/吸顶/分段栏/dock 四点位玻璃=系统材质（骨架期用 backgroundBlurStyle 回退档，
 * 精修批次换 EXQUISITE）；深色零阴影经 isDarkMode 门控。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { ShadowTokens } from '../design/ShadowTokens';
import { Activity, ActivityCategory, ActivityStatus, TripDay } from '../model/Trip';
import { MockTrip } from '../mock/MockTrip';
import { ImmersiveSegmentBar, SegmentedItem } from '../components/ImmersiveSegmentBar';
import { getSheetImmersiveMaterial } from '../utils/immersiveMaterial';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';

interface DockItem {
  symbol: Resource;
  label: string;
  route: string;
}

const ROW_HEIGHT: number = 76;

@Component
export struct ItineraryPage {
  private pathStack: NavPathStack = APP_NAV;
  @StorageProp('isDarkMode') isDark: boolean = false;
  @State private dayIndex: number = 0;
  @State private showDetail: boolean = false;
  @State private detailAct: Activity | undefined = undefined;
  private days: TripDay[] = MockTrip.TRIP.days;
  private segments: SegmentedItem[] = [
    { label: 'Day 1' }, { label: 'Day 2' }, { label: 'Day 3' }
  ];
  private dockItems: DockItem[] = [
    { symbol: $r('sys.symbol.calendar'), label: '行程', route: '' },
    { symbol: $r('sys.symbol.map'), label: '地图', route: 'Map' },
    { symbol: $r('sys.symbol.wallet'), label: '费用', route: 'Expense' },
    { symbol: $r('sys.symbol.person'), label: '我的', route: 'Trips' }
  ];

  private dotColor(cat: ActivityCategory): Resource {
    if (cat === ActivityCategory.FOOD) {
      return ColorTokens.bookmark;
    }
    if (cat === ActivityCategory.HOTEL) {
      return ColorTokens.accentMention;
    }
    if (cat === ActivityCategory.TRANSPORT) {
      return ColorTokens.icon;
    }
    if (cat === ActivityCategory.REST) {
      return ColorTokens.faint;
    }
    return ColorTokens.primary;
  }

  private bookingText(status: ActivityStatus): string {
    if (status === ActivityStatus.NOT_BOOKED) {
      return '需预约';
    }
    if (status === ActivityStatus.FULL) {
      return '约满';
    }
    if (status === ActivityStatus.BOOKED) {
      return '已约';
    }
    if (status === ActivityStatus.PENDING) {
      return '待定';
    }
    return '';
  }

  private bookingColor(status: ActivityStatus): Resource {
    if (status === ActivityStatus.FULL) {
      return ColorTokens.danger;
    }
    if (status === ActivityStatus.BOOKED) {
      return ColorTokens.success;
    }
    if (status === ActivityStatus.PENDING) {
      return ColorTokens.bookmark;
    }
    return ColorTokens.warning;
  }

  @Builder
  spineNode(cat: ActivityCategory) {
    Stack() {
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
        .backgroundColor(this.dotColor(cat))
    }
    .width(24)
    .height(24)
  }

  @Builder
  transitLeg(next: Activity) {
    Row() {
      Column().width(52)
      Column()
        .width(LayoutTokens.routeLineWidth)
        .height(LayoutTokens.transitLegHeight)
        .border({ width: { left: 2 }, color: ColorTokens.separator, style: BorderStyle.Dashed })
      Row({ space: SpaceTokens.xs }) {
        SymbolGlyph($r('sys.symbol.figure_walk'))
          .fontSize(14)
          .fontColor([ColorTokens.icon])
        Text(`${next.transport?.mode} ${next.transport?.duration}分钟 · ${next.transport?.detail}`)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .fontFeature("'tnum' on")
      }
      .alignItems(VerticalAlign.Center)
      .padding({ left: SpaceTokens.sm })
    }
    .width('100%')
    .height(LayoutTokens.transitLegHeight)
    .alignItems(VerticalAlign.Center)
  }

  private durationText(act: Activity): string {
    const t: string[] = act.time.split(':');
    const e: string[] = act.endTime.split(':');
    const mins: number = Number(e[0]) * 60 + Number(e[1]) - Number(t[0]) * 60 - Number(t[1]);
    const h: number = Math.floor(mins / 60);
    const m: number = mins % 60;
    if (h > 0 && m > 0) {
      return `${h}小时${m}分钟`;
    }
    return h > 0 ? `${h}小时` : `${m}分钟`;
  }

  @Builder
  stopRow(act: Activity, isLast: boolean) {
    Column() {
      Row() {
        Text(act.time)
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
            .height(isLast ? 12 : '100%')
            .backgroundColor(ColorTokens.surfaceSunken)
          this.spineNode(act.category)
        }
        .width(24)
        .height('100%')
        Column() {
          Row({ space: SpaceTokens.sm }) {
            Text(act.title)
              .fontSize(TypeTokens.headline.size)
              .fontWeight(600)
              .fontColor(ColorTokens.ink)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            if (this.bookingText(act.status).length > 0) {
              Text(this.bookingText(act.status))
                .fontSize(TypeTokens.overline.size)
                .fontWeight(600)
                .fontColor(ColorTokens.onPrimary)
                .height(22)
                .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm })
                .borderRadius(RadiusTokens.pill)
                .backgroundColor(this.bookingColor(act.status))
            }
            Column()
              .width(36)
              .height(48)
              .borderRadius(RadiusTokens.media)
              .backgroundColor(ColorTokens.surfaceSunken)
          }
          .alignItems(VerticalAlign.Center)

          Text(`建议停留 ${this.durationText(act)} · ${act.address.replace('京都 ', '')}`)
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
            .margin({ top: SpaceTokens.xs })
          if (act.reason !== undefined) {
            Column() {
              Text('为什么排在这里')
                .fontSize(TypeTokens.overline.size)
                .fontWeight(600)
                .fontColor(ColorTokens.muted)
              Text(act.reason)
                .fontSize(TypeTokens.small.size)
                .fontColor(ColorTokens.ink)
                .margin({ top: SpaceTokens.xs })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding(SpaceTokens.md)
            .borderRadius(RadiusTokens.reason)
            .backgroundColor(ColorTokens.surfacePanel)
            .border({ width: { left: 2 }, color: ColorTokens.primary })
            .margin({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .alignItems(VerticalAlign.Top)
      .width('100%')
      .height(ROW_HEIGHT + (act.reason !== undefined ? 84 : 0))
      .onClick(() => {
        this.detailAct = act;
        this.showDetail = true;
      })
    }
    .width('100%')
  }

  @Builder
  statCol(value: string, label: string) {
    Column() {
      Text(value)
        .fontSize(TypeTokens.small.size)
        .fontWeight(600)
        .fontColor(ColorTokens.ink)
        .fontFeature("'tnum' on")
      Text(label)
        .fontSize(TypeTokens.overline.size)
        .fontWeight(450)
        .fontColor(ColorTokens.muted)
        .margin({ top: 2 })
    }
    .layoutWeight(1)
  }

  @Builder
  hoursRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(TypeTokens.small.size)
        .fontColor(ColorTokens.muted)
      Blank()
      Text(value)
        .fontSize(TypeTokens.small.size)
        .fontWeight(600)
        .fontColor(ColorTokens.ink)
        .fontFeature("'tnum' on")
    }
    .width('100%')
    .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
  }

  @Builder
  miniNode(idx: number, meta: string, name: string, active: boolean) {
    Column({ space: SpaceTokens.xs }) {
      Stack() {
        Column()
          .width(24)
          .height(24)
          .borderRadius(RadiusTokens.pill)
          .backgroundColor(active ? ColorTokens.primary : ColorTokens.canvas)
          .border({ width: 2, color: active ? ColorTokens.primary : ColorTokens.ink })
        if (!active) {
          Text(`${idx}`)
            .fontSize(TypeTokens.caption.size)
            .fontWeight(600)
            .fontColor(ColorTokens.ink)
            .fontFeature("'tnum' on")
        }
      }
      Text(meta)
        .fontSize(TypeTokens.overline.size)
        .fontColor(active ? ColorTokens.primary : ColorTokens.muted)
        .fontFeature("'tnum' on")
      Text(name)
        .fontSize(TypeTokens.caption.size)
        .fontWeight(active ? 600 : 400)
        .fontColor(active ? ColorTokens.ink : ColorTokens.body)
    }
    .layoutWeight(1)
  }

  @Builder
  detailSheet() {
    Column() {
      if (this.detailAct !== undefined) {
        Scroll() {
          Column() {
            Row({ space: SpaceTokens.md }) {
              Column()
                .width(96)
                .height(120)
                .borderRadius(RadiusTokens.media)
                .backgroundColor(ColorTokens.surfaceSunken)
              Column() {
                Text(this.detailAct.title)
                  .fontSize(TypeTokens.headline.size)
                  .fontWeight(600)
                  .fontColor(ColorTokens.ink)
                Text(`${this.detailAct.address} · 山脚入口`)
                  .fontSize(TypeTokens.caption.size)
                  .fontWeight(450)
                  .fontColor(ColorTokens.muted)
                  .margin({ top: SpaceTokens.xs })
                Row({ space: SpaceTokens.xs }) {
                  Text('必去')
                    .fontSize(TypeTokens.overline.size)
                    .fontWeight(600)
                    .fontColor(ColorTokens.bookmark)
                    .height(22)
                    .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm })
                    .borderRadius(RadiusTokens.pill)
                    .backgroundColor(ColorTokens.surfaceSubtle)
                  if (this.detailAct.status === ActivityStatus.NOT_BOOKED) {
                    Text('需预约')
                      .fontSize(TypeTokens.overline.size)
                      .fontWeight(600)
                      .fontColor(ColorTokens.onPrimary)
                      .height(22)
                      .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm })
                      .borderRadius(RadiusTokens.pill)
                      .backgroundColor(ColorTokens.warning)
                  }
                }
                .margin({ top: SpaceTokens.sm })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .alignItems(VerticalAlign.Top)
            .width('100%')

            Row() {
              this.statCol(this.durationText(this.detailAct), '停留建议')
              this.statCol(this.detailAct.time, '计划到达')
              this.statCol('12分钟', '步行耗时')
              this.statCol('¥0', '门票费用')
            }
            .width('100%')
            .padding(SpaceTokens.md)
            .borderRadius(RadiusTokens.card)
            .backgroundColor(ColorTokens.surfaceElevated)
            .margin({ top: SpaceTokens.lg })

            Column() {
              this.hoursRow('开放时间', '全天（24小时）')
              Divider().strokeWidth(LayoutTokens.hairlineWidth).color(ColorTokens.separator)
              this.hoursRow('建议时段', '06:30–08:00 · 人少')
            }
            .width('100%')
            .padding({ left: SpaceTokens.md, right: SpaceTokens.md })
            .margin({ top: SpaceTokens.md })

            Text('红叶季周末 09:00 后山道拥挤')
              .fontSize(TypeTokens.caption.size)
              .fontWeight(450)
              .fontColor(ColorTokens.warning)
              .fontFeature("'tnum' on")
              .width('100%')
              .margin({ top: SpaceTokens.xs })

            if (this.detailAct.reason !== undefined) {
              Column() {
                Text('为什么排在这里')
                  .fontSize(TypeTokens.overline.size)
                  .fontWeight(600)
                  .fontColor(ColorTokens.muted)
                Text(this.detailAct.reason)
                  .fontSize(TypeTokens.small.size)
                  .fontColor(ColorTokens.ink)
                  .margin({ top: SpaceTokens.xs })
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding(SpaceTokens.md)
              .borderRadius(RadiusTokens.reason)
              .backgroundColor(ColorTokens.surfacePanel)
              .border({ width: { left: 2 }, color: ColorTokens.primary })
              .margin({ top: SpaceTokens.md })
            }

            Column() {
              Text('动线位置')
                .fontSize(TypeTokens.overline.size)
                .fontWeight(600)
                .fontColor(ColorTokens.muted)
                .alignSelf(ItemAlign.Start)
              Row() {
                this.miniNode(1, '上一站 06:50', '一条', false)
                this.miniNode(2, '当前站点', this.detailAct.title, true)
                this.miniNode(3, '下一站 10:20', '东福寺', false)
              }
              .width('100%')
              .padding({ top: SpaceTokens.md })
            }
            .width('100%')
            .padding(SpaceTokens.md)
            .borderRadius(RadiusTokens.card)
            .backgroundColor(ColorTokens.surfaceElevated)
            .margin({ top: SpaceTokens.md, bottom: SpaceTokens.xl })
          }
          .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)

        Row({ space: SpaceTokens.md }) {
          YoujingButton({
            variant: YoujingButtonVariant.SECONDARY,
            label: '换一个时间',
            buttonWidth: 160,
            onAction: (): void => {
              this.showDetail = false;
            }
          })
          YoujingButton({
            variant: YoujingButtonVariant.PRIMARY,
            label: '加入日历提醒',
            onAction: (): void => {
              this.showDetail = false;
            }
          })
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, top: SpaceTokens.sm, bottom: SpaceTokens.md })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ColorTokens.canvas)
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        Column() {
          // 顶栏（玻璃点位①：骨架期回退档）
          Column() {
            Row() {
              Text('京都 · 5天4晚')
                .fontSize(TypeTokens.headline.size)
                .fontWeight(600)
                .fontColor(ColorTokens.ink)
                .fontFeature("'tnum' on")
                .layoutWeight(1)
              SymbolGlyph($r('sys.symbol.share'))
                .fontSize(22)
                .fontColor([ColorTokens.ink])
                .onClick(() => {
                  this.pathStack.pushPath({ name: 'Share' });
                })
              SymbolGlyph($r('sys.symbol.ellipsis_circle'))
                .fontSize(22)
                .fontColor([ColorTokens.ink])
                .margin({ left: SpaceTokens.lg })
                .onClick(() => {
                  this.pathStack.pushPath({ name: 'EditItinerary' });
                })
            }
            .width('100%')
            .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })

            Row() {
              ImmersiveSegmentBar({
                items: this.segments,
                selectedIndex: $dayIndex,
                buttonVerticalPadding: 2.15
              })
            }
            .width('100%')
            .justifyContent(FlexAlign.Start)
            .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, bottom: SpaceTokens.sm })
          }
          .backgroundColor(ColorTokens.surfaceElevated)

          Scroll() {
            Column() {
              // 地图面板（route-paper 渐变占位）
              Stack({ alignContent: Alignment.BottomStart }) {
                Column()
                  .width('100%')
                  .height('100%')
                  .linearGradient({
                    angle: 180,
                    colors: [[ColorTokens.routeBgTop, 0], [ColorTokens.routeBgBottom, 1]]
                  })
                Text('步行 6.4km · 打车 1 段')
                  .fontSize(TypeTokens.caption.size)
                  .fontWeight(450)
                  .fontColor(ColorTokens.ink)
                  .fontFeature("'tnum' on")
                  .height(28)
                  .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm })
                  .borderRadius(RadiusTokens.pill)
                  .backgroundColor(ColorTokens.canvas)
                  .margin(LayoutTokens.mapOverlayInset - 8)
              }
              .width('100%')
              .height(LayoutTokens.mapHeightCompact)
              .borderRadius(RadiusTokens.card)
              .clip(true)
              .margin({ top: SpaceTokens.md })

              // 吸顶日标题（玻璃点位④：骨架期实色）
              Row() {
                Text(`Day ${this.days[this.dayIndex].dayIndex} · ${this.days[this.dayIndex].date.slice(5).replace('-', '月')}日`)
                  .fontSize(TypeTokens.body.size)
                  .fontWeight(600)
                  .fontColor(ColorTokens.ink)
                  .fontFeature("'tnum' on")
                Blank()
                Text(this.days[this.dayIndex].theme)
                  .fontSize(TypeTokens.caption.size)
                  .fontWeight(450)
                  .fontColor(ColorTokens.muted)
              }
              .width('100%')
              .height(LayoutTokens.dayDividerHeight)
              .margin({ top: SpaceTokens.md })

              Column() {
                ForEach(this.days[this.dayIndex].activities,
                  (act: Activity, idx: number) => {
                    this.stopRow(act, idx === this.days[this.dayIndex].activities.length - 1)
                    if (idx < this.days[this.dayIndex].activities.length - 1 &&
                      this.days[this.dayIndex].activities[idx + 1].transport !== undefined) {
                      this.transitLeg(this.days[this.dayIndex].activities[idx + 1])
                    }
                  }, (act: Activity): string => `itin-${this.dayIndex}-${act.id}`)
              }
              .width('100%')
            }
            .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, bottom: LayoutTokens.bottomScrollReserve })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
        }
        .width('100%')
        .height('100%')

        // 浮动 dock（玻璃点位③：骨架期实色 + floating 阴影，深色零阴影）
        Row() {
          ForEach(this.dockItems, (item: DockItem, idx: number) => {
            Column({ space: 2 }) {
              SymbolGlyph(item.symbol)
                .fontSize(22)
                .fontColor([idx === 0 ? ColorTokens.primary : ColorTokens.muted])
              Text(item.label)
                .fontSize(TypeTokens.overline.size)
                .fontWeight(idx === 0 ? 600 : 400)
                .fontColor(idx === 0 ? ColorTokens.primary : ColorTokens.muted)
            }
            .width(LayoutTokens.tabItemWidth)
            .height(LayoutTokens.tabItemHeight)
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              if (item.route.length > 0) {
                this.pathStack.pushPath({ name: item.route });
              }
            })
          }, (item: DockItem): string => `dock-${item.label}`)
        }
        .width(LayoutTokens.floatingDockWidth)
        .height(LayoutTokens.tabBarHeight)
        .justifyContent(FlexAlign.SpaceEvenly)
        .borderRadius(RadiusTokens.dock)
        .backgroundColor(ColorTokens.surfaceElevated)
        .border({ width: 1, color: ColorTokens.borderSubtle, radius: RadiusTokens.dock })
        .shadow(this.isDark ? { radius: 0 } : ShadowTokens.floating)
        .margin({ bottom: LayoutTokens.floatingDockBottomMargin })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ColorTokens.canvas)
      .bindSheet($$this.showDetail, this.detailSheet(), {
        height: '85%',
        backgroundColor: ColorTokens.canvas,
        showClose: true,
        systemMaterial: getSheetImmersiveMaterial()
      })
    }
    .hideTitleBar(true)
  }
}
