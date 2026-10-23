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
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { ShadowTokens } from '../design/ShadowTokens';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { FloatingDock } from '../components/FloatingDock';
import { TripDao, TripSummary } from '../data/TripDao';
import { PlanDraft } from '../data/PlanDraft';
import { DateUtils } from '../utils/DateUtils';
import { common } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';
import { Logger } from '../common/logger/Logger';
import { WidgetSync } from '../widget/TodayCard';

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
  /** 官方 Search 的关键词：目的地或日期串命中即保留 */
  @State private keyword: string = '';
  @State private refreshing: boolean = false;

  /** 列表数据只从 RDB 取，刷新动作与首启共用一条路径（Refresh 需要 Promise 收尾） */
  private reload(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    return TripDao.listSummaries(ctx).then((rows: TripSummary[]) => {
      const list: TripCardData[] = [];
      for (const r of rows) {
        const span: number = DateUtils.spanDays(r.startDate, r.endDate);
        const today: string = DateUtils.todayIso();
        // ISO 串可直接比大小；不能用 spanDays 的差值判在途——它含首尾且下限为 1，
        // 会把「还没出发」的未来行程误判成旅行中
        const onTrip: boolean = today >= r.startDate && today <= r.endDate;
        let progress: number = 100;
        if (today < r.startDate) {
          progress = 0;
        } else if (onTrip) {
          progress = Math.min(100, Math.round((DateUtils.spanDays(r.startDate, today) / span) * 100));
        }
        const t: TripCardData = {
          id: r.id, place: r.destination,
          dateMeta: `${r.startDate} – ${r.endDate} · ${r.people} 人`,
          spots: `${r.spotCount}`, walk: `${r.legCount} 段`, bookingNum: `${r.bookingCount}`,
          bookingBadge: r.totalCost > 0 ? `¥${r.totalCost}` : '',
          badgeColor: ColorTokens.success,
          statusLine: onTrip ? '旅行中' : '已生成', progress: progress, mustIdx: -1,
          onTrip: onTrip, muted: false
        };
        list.push(t);
      }
      this.trips = list;
    });
  }

  aboutToAppear(): void {
    this.reload().catch((err: Error) => {
      Logger.error('Ui.Trips', `行程列表加载失败: ${err.message}`);
    });
  }

  private visibleTrips(): TripCardData[] {
    const k: string = this.keyword.trim();
    if (k.length === 0) {
      return this.trips;
    }
    return this.trips.filter((t: TripCardData): boolean => t.place.includes(k) || t.dateMeta.includes(k));
  }

  /** 官方行级动作：左滑出删除钮，删除前走系统对话框二次确认（TripDao.deleteTrip 此前无调用方） */
  @Builder
  deleteAction(t: TripCardData) {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(IconSizes.control)
          .fontColor([ColorTokens.onPrimary])
      }
      .width(56)
      .height(56)
      .type(ButtonType.Circle)
      .backgroundColor(ColorTokens.danger)
      .onClick((): void => {
        this.confirmDelete(t);
      })
    }
    .justifyContent(FlexAlign.End)
    .alignItems(VerticalAlign.Center)
    .width(84)
    .height('100%')
    .padding({ left: SpaceTokens.md, right: SpaceTokens.md })
  }

  private confirmDelete(t: TripCardData): void {
    this.getUIContext().showAlertDialog({
      title: '删除这条行程',
      message: `${t.place} · ${t.dateMeta}\n只删本机记录，不可恢复；日历里已写入的事件不会自动删除。`,
      primaryButton: {
        value: '取消',
        action: (): void => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: ColorTokens.danger,
        action: (): void => {
          this.doDelete(t.id);
        }
      }
    });
  }

  private doDelete(id: string): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    TripDao.deleteTrip(ctx, id).then((): void => {
      this.getUIContext().getPromptAction().showToast({ message: '已删除该行程' });
      this.reload().catch((err: Error): void => {
        Logger.error('Ui.Trips', `删除后重载失败: ${err.message}`);
      });
      WidgetSync.refreshAll(ctx).catch((err: Error): void => {
        Logger.warn('Ui.Trips', `卡片刷新失败: ${err.message}`);
      });
    }).catch((err: Error): void => {
      Logger.error('Ui.Trips', `删除行程失败: ${err.message}`);
      this.getUIContext().getPromptAction().showToast({ message: '删除失败，详见日志' });
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
            .padding({ left: SpaceTokens.xs, right: SpaceTokens.xs })
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
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      this.miniRoute(t.mustIdx)

      Row() {
        this.statCol(t.spots, '景点', '', ColorTokens.canvas, t.muted)
        this.statCol(t.walk, '通勤', '', ColorTokens.canvas, t.muted)
        this.statCol(t.bookingNum, '需预约', t.bookingBadge, t.badgeColor, t.muted)
      }
      .width('100%')

      Column({ space: SpaceTokens.xs }) {
        Text(t.statusLine)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.body)
          .fontFeature("'tnum' on")
        Progress({ value: t.progress, total: 100, type: ProgressType.Linear })
          .color(ColorTokens.primary)
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
    .onClick(() => {
      this.pathStack.pushPath({ name: t.onTrip ? 'OnTrip' : 'Itinerary', param: t.id });
    })
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        // 官方 Search：目的地或日期关键词过滤（此前右上角放大镜是个没有动作的死控件）
        Search({ value: this.keyword, placeholder: '搜索目的地或日期' })
          .onChange((v: string): void => {
            this.keyword = v;
          })
          .margin({ left: SpaceTokens.lg, right: SpaceTokens.lg, top: SpaceTokens.sm })

        if (this.trips.length === 0) {
          Column({ space: SpaceTokens.md }) {
            SymbolGlyph($r('sys.symbol.map'))
              .fontSize(IconSizes.display)
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
                PlanDraft.fresh();
                this.pathStack.pushPath({ name: 'TripInput' });
              }
            })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          // 官方 Refresh + List：下拉重读 RDB，列表项走 ListItem（原来是 Scroll+Column 手排）
          Refresh({ refreshing: $$this.refreshing }) {
            List({ space: 12 }) {
              ForEach(this.visibleTrips(), (t: TripCardData) => {
                ListItem() {
                  this.tripCard(t)
                }
                .swipeAction({ end: this.deleteAction(t), edgeEffect: SwipeEdgeEffect.Spring })
              }, (t: TripCardData): string => `trip-${t.id}-${t.statusLine}-${t.progress}`)
              if (this.visibleTrips().length === 0) {
                ListItem() {
                  Text(`没有匹配「${this.keyword}」的行程`)
                    .fontSize(TypeTokens.small.size)
                    .fontColor(ColorTokens.muted)
                    .width('100%')
                    .textAlign(TextAlign.Center)
                    .padding({ top: SpaceTokens.xl, bottom: SpaceTokens.xl })
                }
              }
            }
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
            .cachedCount(4)
            .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, bottom: LayoutTokens.bottomScrollReserve })
          }
          .onRefreshing((): void => {
            this.reload().then((): void => {
              this.refreshing = false;
            }).catch((err: Error): void => {
              Logger.error('Ui.Trips', `下拉刷新失败: ${err.message}`);
              this.refreshing = false;
            });
          })
        }
      }
      .width('100%')
      .height('100%')
      .layoutWeight(1)
      .backgroundColor(ColorTokens.canvas)
      FloatingDock({ activeIndex: 3, tripId: '' })
    }
    .width('100%')
    .height('100%')
    }
    .titleBar(HdsChrome.bar({ mainTitle: '我的行程', subTitle: this.trips.length > 0 ? `${this.trips.length} 条` : '' }))
    .titleMode(HdsNavDestinationTitleMode.MINI)
  }
}
