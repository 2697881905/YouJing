/**
 * 屏1 首启与静默登录（帧 77ed8d08）。
 * 必改表已落：bottom-section gap 10→8；preview-badge padding 2→0；
 * preview-foot padding 10→8；stop-body padding 10→8；
 * transit-leg margin-left 64→48、padding 10→8。
 * 状态栏 mock 为设备 chrome，不实现。
 */

import { APP_NAV, requestTab, TAB_MINE } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { ImmersiveSurface } from '../components/ImmersiveSurface';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { AccountStore } from '../data/AccountStore';
import { PlanDraft } from '../data/PlanDraft';
import { AccountKind, AccountState } from '../model/Account';
import { DateUtils } from '../utils/DateUtils';
import { TripDao, TripSummary } from '../data/TripDao';
import { WidgetSync } from '../widget/TodayCard';
import { Logger } from '../common/logger/Logger';
import { common } from '@kit.AbilityKit';

interface PreviewStop {
  time: string;
  name: string;
  meta: string;
  dotColor: Resource;
}

interface PreviewLeg {
  text: string;
}

/** 首页「最近行程」一行：只挑真字段显示，不编状态 */
interface RecentRow {
  id: string;
  place: string;
  meta: string;
  onTrip: boolean;
}

// 预览动线行高：契约 itinerary-row-min-height，行内 spine 线取定值避免百分比循环
const ROW_HEIGHT: number = LayoutTokens.itineraryRowMinHeight;

@Component
export struct YoujingStartPage {
  private pathStack: NavPathStack = APP_NAV;
  /** 最近三条真行程：这一屏此前只有营销预览，行程 tab 却看不到任何一条自己的行程 */
  @State private recent: RecentRow[] = [];
  /** 行程总条数：最近只展示三条，「查看全部」要说得出还剩多少 */
  @State private tripTotal: number = 0;

  aboutToAppear(): void {
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    TripDao.listSummaries(ctx).then((rows: TripSummary[]): void => {
      const today: string = DateUtils.todayIso();
      const list: RecentRow[] = [];
      for (let i = 0; i < rows.length && i < 3; i++) {
        const r: TripSummary = rows[i];
        list.push({
          id: r.id, place: r.destination,
          meta: `${r.startDate} – ${r.endDate} · ${r.spotCount} 站`,
          onTrip: today >= r.startDate && today <= r.endDate
        });
      }
      this.recent = list;
      this.tripTotal = rows.length;
    }).catch((err: Error): void => {
      Logger.warn('Ui.Start', `最近行程加载失败: ${err.message}`);
    });
  }

  /** 静默取 UnionID（失败即本机游客分区，不阻断），再把游客数据归户到登录账号 */
  private async enterApp(): Promise<void> {
    // 从首启页进规划 = 明确的新建意图，先丢掉上一段的草稿
    PlanDraft.fresh();
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const state: AccountState = await AccountStore.login(ctx);
      if (state.kind === AccountKind.HUAWEI) {
        await TripDao.adoptGuestData(ctx, state.uid);
        // 归户会换掉卡片可读的分区键，立刻回灌一次，别让桌面空等 30 分钟
        WidgetSync.refreshAll(ctx).catch((err: Error) => {
          Logger.warn('Ui.Start', `卡片刷新失败: ${err.message}`);
        });
      }
    } catch (err) {
      // 登录/归户失败不阻断进主链：按本机游客分区继续（EntryAbility.bootstrap 同一口径）。
      // 原来这里裸 await，一处 rejection 就让用户静默卡在首启页
      Logger.error('Ui.Start', `登录或归户失败，按游客分区继续: ${(err as Error).message}`);
    }
    this.pathStack.pushPath({ name: 'TripInput' });
  }

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
      Circle()
        .width(22)
        .height(22)
        .fill(ColorTokens.canvas)
        .stroke(ColorTokens.ink)
        .strokeWidth(2)
      Circle()
        .width(LayoutTokens.itineraryNodeDot)
        .height(LayoutTokens.itineraryNodeDot)
        .fill(dotColor)
    }
    .width(LayoutTokens.itineraryNodeSize)
    .height(LayoutTokens.itineraryNodeSize)
  }

  @Builder
  timelineRow(stop: PreviewStop, index: number) {
    Row() {
      Text(stop.time)
        .width(LayoutTokens.itineraryTimeGutter)
        .fontSize(TypeTokens.time.size)
        .fontWeight(600)
        .fontColor(ColorTokens.ink)
        .textAlign(TextAlign.End)
        .fontFeature("'tnum' on")
        .padding({ right: SpaceTokens.md, top: SpaceTokens.xs })
      Stack({ alignContent: Alignment.Top }) {
        Column()
          .width(LayoutTokens.routeLineWidth)
          .height(index === this.stops.length - 1 ? SpaceTokens.md : ROW_HEIGHT)
          .backgroundColor(ColorTokens.surfaceSunken)
        this.spineNode(stop.dotColor)
      }
      .width(LayoutTokens.itineraryNodeSize)
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
          .fontSize(IconSizes.control)
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
      .border({ width: LayoutTokens.routeLineWidth, style: BorderStyle.Dashed, color: ColorTokens.separator, radius: RadiusTokens.capsule })
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: SpaceTokens.fiveXl })
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

      // 主操作放在首屏可见处：原来钉在屏底，dock 一浮上来就压住它，
      // 列表一长更是把它整个挤出屏幕（实拍复验时踩到）
      Column() {
        YoujingButton({
          variant: YoujingButtonVariant.PRIMARY,
          label: '开始规划新行程',
          fullWidth: true,
          trailingSymbol: $r('sys.symbol.arrow_right'),
          onAction: (): void => {
            this.enterApp();
          }
        })
      }
      .width('100%')
      .margin({ bottom: SpaceTokens.lg })

      // 预览卡是「还没有行程」时的首启演示。已经有真行程就让它让位——
      // 一张编出来的京都动线吃掉六成屏高，真数据只剩半屏
      if (this.recent.length === 0) {
      ImmersiveSurface({ radius: RadiusTokens.card, surfaceWidth: '100%' }) {
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
              .lineHeight(TypeTokens.caption.lineHeight)
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
      }
      }

      if (this.recent.length > 0) {
        Column({ space: SpaceTokens.sm }) {
          Text('最近行程')
            .fontSize(TypeTokens.overline.size)
            .fontWeight(600)
            .fontColor(ColorTokens.muted)
          ForEach(this.recent, (row: RecentRow) => {
            Button({ type: ButtonType.Normal, stateEffect: true }) {
              Row() {
                Column({ space: SpaceTokens.xs }) {
                  Text(row.place)
                    .fontSize(TypeTokens.headline.size)
                    .fontWeight(600)
                    .fontColor(ColorTokens.ink)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(row.meta)
                    .fontSize(TypeTokens.caption.size)
                    .fontWeight(450)
                    .fontColor(ColorTokens.muted)
                    .fontFeature("'tnum' on")
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                if (row.onTrip) {
                  Text('旅行中')
                    .fontSize(TypeTokens.overline.size)
                    .fontWeight(600)
                    .fontColor(ColorTokens.onPrimary)
                    .height(22)
                    .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm })
                    .borderRadius(RadiusTokens.pill)
                    .backgroundColor(ColorTokens.primary)
                    .margin({ right: SpaceTokens.sm })
                }
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(IconSizes.control)
                  .fontColor([ColorTokens.muted])
              }
              .width('100%')
              .padding(SpaceTokens.md)
              .borderRadius(RadiusTokens.capsule)
              .backgroundColor(ColorTokens.surfaceElevated)
            }
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .width('100%')
            .padding(0)
            .borderRadius(RadiusTokens.capsule)
            .accessibilityText(`打开 ${row.place} 的行程`)
            .onClick((): void => {
              this.pathStack.pushPath({ name: row.onTrip ? 'OnTrip' : 'Itinerary', param: row.id });
            })
          }, (row: RecentRow): string => `recent-${row.id}-${row.meta}-${row.onTrip}`)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .margin({ top: SpaceTokens.xl })

        Button({ type: ButtonType.Normal, stateEffect: true }) {
          Row() {
            Text(`查看全部 ${this.tripTotal} 条行程`)
              .fontSize(TypeTokens.small.size)
              .fontWeight(600)
              .fontColor(ColorTokens.primary)
              .fontFeature("'tnum' on")
              .layoutWeight(1)
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(IconSizes.control)
              .fontColor([ColorTokens.primary])
          }
          .width('100%')
          .height(LayoutTokens.minTouchTarget)
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .width('100%')
        .padding(0)
        .accessibilityText('打开我的行程列表')
        .onClick((): void => {
          requestTab(TAB_MINE);
        })
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    // 这一屏挂在有悬浮 dock 的 tab 上且自身不滚动：整页给 dock 让出净空，
    // 最后一行才不会藏到 dock 底下
    .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, bottom: LayoutTokens.floatingDockClearance })
    .backgroundColor(ColorTokens.canvas)
  }
}
