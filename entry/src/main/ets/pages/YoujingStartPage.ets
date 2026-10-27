/**
 * 屏1 首启与静默登录（帧 77ed8d08）。
 * 必改表已落：bottom-section gap 10→8；preview-badge padding 2→0；
 * preview-foot padding 10→8；stop-body padding 10→8；
 * transit-leg margin-left 64→48、padding 10→8。
 * 状态栏 mock 为设备 chrome，不实现。
 */

import { APP_NAV, requestTab, enterPlanningFlow, markDraftDirty, DRAFT_DIRTY_KEY, isDraftDirty, TAB_SHOWN_KEY, isTabShownTick, TAB_ITINERARY, TAB_MINE } from '../common/constants/AppNav';
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
import { KEY_WINDOW_WIDTH_VP, BP_MD_MIN_VP } from '../utils/breakpointCenter';
import { symmetricInsetForCap } from '../utils/responsive';

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
  /** dock 切回这一页时重取最近行程（广播见 AppNav.TAB_SHOWN_KEY，主链复审 P1） */
  @StorageProp(TAB_SHOWN_KEY) @Watch('onDockShown') dockTick: string = '';
  /** 窗口实测宽（vp），由断点中心一处测量；0 = 尚未测到，按不收窄处理 */
  @StorageProp(KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 0;

  private onDockShown(): void {
    if (isTabShownTick(this.dockTick, TAB_ITINERARY)) {
      this.reloadRecent();
    }
  }

  /** 最近三条真行程：这一屏此前只有营销预览，行程 tab 却看不到任何一条自己的行程 */
  @State private recent: RecentRow[] = [];
  /** 行程总条数：最近只展示三条，「查看全部」要说得出还剩多少 */
  @State private tripTotal: number = 0;
  /** 主 CTA 的进行中状态：游客路径要等账号往返，没有反馈会被当成"按了没反应" */
  @State private starting: boolean = false;
  /** 有可续的规划？由写草稿的一方广播（`DRAFT_DIRTY_KEY`），不是这一屏自己轮询 */
  @StorageProp(DRAFT_DIRTY_KEY) @Watch('onDraftTick') draftTick: string = '0:0';
  @State private draftDirty: boolean = false;

  private onDraftTick(): void {
    this.draftDirty = isDraftDirty(this.draftTick);
  }

  aboutToAppear(): void {
    this.draftDirty = isDraftDirty(this.draftTick);
    this.reloadRecent();
  }

  private reloadRecent(): void {
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

  /**
   * 进主链。游客分区才需要静默登录 + 归户。
   *
   * 原来无条件跑 `AccountStore.login()`：`Index` 的登录闸门已经保证走到这里时
   * 分区状态是确定的，真账号用户点主 CTA 还要再等一次账号接口往返——
   * 真机实测 8 秒（00:05:19 按下 → 00:05:27「静默登录成功」）期间**界面零反馈**，
   * 用户只会认为"按了没反应"再按一次；日志里还有该往返报
   * `Incorrect context parameter type` 后静默退回游客分区的记录。
   * 所以：已登录直接进，游客才登录并归户，并且给按钮一个进行中的状态。
   */
  private async enterApp(): Promise<void> {
    // 从首启页进规划 = 明确的新建意图，先丢掉上一段的草稿
    PlanDraft.fresh();
    markDraftDirty(false);
    if (this.starting) {
      return;
    }
    this.starting = true;
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      if (AccountStore.isGuest()) {
        const state: AccountState = await AccountStore.login(ctx);
        if (state.kind === AccountKind.HUAWEI) {
          await TripDao.adoptGuestData(ctx, state.uid);
          // 归户会换掉卡片可读的分区键，立刻回灌一次，别让桌面空等 30 分钟
          WidgetSync.refreshAll(ctx).catch((err: Error) => {
            Logger.warn('Ui.Start', `卡片刷新失败: ${err.message}`);
          });
        }
      }
    } catch (err) {
      // 登录/归户失败不阻断进主链：按本机游客分区继续（EntryAbility.bootstrap 同一口径）。
      // 原来这里裸 await，一处 rejection 就让用户静默卡在首启页
      Logger.error('Ui.Start', `登录或归户失败，按游客分区继续: ${(err as Error).message}`);
    }
    this.starting = false;
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
          label: this.starting ? '正在准备…' : '开始规划新行程',
          fullWidth: true,
          trailingSymbol: $r('sys.symbol.arrow_right'),
          disabled: this.starting,
          onAction: (): void => {
            this.enterApp();
          }
        })

      // 次级档（禁令 1：一屏只许一颗实心主按钮）。草稿被动过时才出现。
      // 点它**不 fresh()**：屏2/屏3/屏4/屏5 都从 `PlanDraft` 起值，
      // 所以从屏2 重进就是接着上次的进度走（§5q/§5w 那条主链缺口的收口）
      if (this.draftDirty) {
        YoujingButton({
          variant: YoujingButtonVariant.SECONDARY,
          label: '继续未完成的规划',
          fullWidth: true,
          onAction: (): void => {
            enterPlanningFlow('TripInput');
          }
        })
          .margin({ top: SpaceTokens.sm })
      }
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
    // 最后一行才不会藏到 dock 底下。
    // 左右内缩走对称内缩而不是 maxWidth：这屏的卡片子级全是 width('100%')，
    // 给父 Column 加 constraintSize.maxWidth 只会左贴边、右侧空出一条（实测更坏）。
    // 折叠屏展开（窗口 707vp）时预览卡原本通铺 642vp、三行节点右侧 55% 全白。
    .padding({
      left: symmetricInsetForCap(this.windowWidthVp, BP_MD_MIN_VP, SpaceTokens.lg),
      right: symmetricInsetForCap(this.windowWidthVp, BP_MD_MIN_VP, SpaceTokens.lg),
      bottom: LayoutTokens.floatingDockClearance
    })
    .backgroundColor(ColorTokens.canvas)
  }
}
