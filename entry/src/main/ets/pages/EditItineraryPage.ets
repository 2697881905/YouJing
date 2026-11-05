/**
 * 屏9 行程编辑 · 拖动与替换（帧 ebe57eac）。
 * 拖拽配方（有据实证 + 项目记忆）：List.onItemDragStart 自定义拖影、
 * 把手只挂把手、onItemDrop 带 insertIndex 落位（onItemDragEnd 不存在）。
 *
 * 数据（RDB 已接真）：吃屏8 传进来的 tripId + 当前日，改动在「完成」时整份聚合根回写 RDB。
 * 拖动语义 = 改游览顺序：当日的时间槽不变，节点按新顺序重新占槽
 * （否则把 18:30 的站拖到第二位会留下 09:00→18:30→13:15 的乱序时间线）。
 * 替换语义 = 换节点不换槽：保留该位置的时间、结束时间与到达通勤。
 */

import { DurationCn } from '../utils/DurationCn';
import { APP_NAV, EditTarget } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { ShadowTokens } from '../design/ShadowTokens';
import { Activity, Trip, TripDay } from '../model/Trip';
import { DateUtils } from '../utils/DateUtils';
import { TimelineNode } from '../components/TimelineNode';
import { TimeText } from '../utils/TimeText';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { ActivityCategory, ActivityStatus } from '../model/Trip';
import { Spot } from '../model/Spot';
import { TripDao } from '../data/TripDao';
import { WidgetSync } from '../widget/TodayCard';
import { PlanRepository } from '../data/PlanRepository';
import { getSheetImmersiveMaterial } from '../utils/immersiveMaterial';
import { Logger } from '../common/logger/Logger';
import { mintEditActivityId } from '../utils/ActivityIds';
import { common } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import type { HdsNavigationMenuItemOptions, HdsNavigationTitleBarOptions } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';

/**
 * 六点把手的几何（帧 ebe57eac：viewBox 24 里 r=2 的圆点，画在 22×22 盒内）。
 * 换算到 22vp：直径 ≈ 3.7vp 取 4；行间距（同列两圆边缘）≈ 1.5vp 取 2；
 * 列间距 ≈ 3.7vp 取 4 —— 行比列紧是帧自己的比例。
 */
const GRIP_DOT_VP: number = 4;
const GRIP_ROW_GAP_VP: number = 2;
const GRIP_COL_GAP_VP: number = 4;

@Component
export struct EditItineraryPage {
  private pathStack: NavPathStack = APP_NAV;
  /** 顶栏磨砂两态：由**绝对**滚动偏移驱动（每帧增量会被松手回弹的负帧打灭，契约 §Translucency） */
  @State private barScrolled: boolean = false;
  private barScroller: Scroller = new Scroller();
  @Prop tripId: string = '';
  @Prop dayIndex: number = 0;
  @State private acts: Activity[] = [];
  @State private dragIdx: number = -1;
  @State private showReplace: boolean = false;
  /**
   * 底稿屏9 的容量提示：「移走后第 1 天空 2.5 小时，可补一个可选景点」+「补一个」。
   * 这屏原来删完什么反馈都没有——用户不知道自己刚掏空了多长时间。
   */
  @State private gapNote: string = '';
  /** -1 = 补选模式（往当日末尾追加），>=0 = 替换该位置 */
  @State private replaceIdx: number = -1;
  @State private candidates: Spot[] = [];
  /** 底稿屏9 声明了「撤销修改」：删除/替换/拖动都是破坏性编辑，没有回退就等于不敢点 */
  private history: Activity[][] = [];
  private trip: Trip | null = null;

  private snapshot(): void {
    this.history.push(this.acts.slice());
  }

  private undo(): void {
    this.gapNote = '';
    const last: Activity[] | undefined = this.history.pop();
    if (last === undefined) {
      this.toast('还没有可撤销的改动');
      return;
    }
    this.acts = last;
  }

  aboutToAppear(): void {
    if (this.tripId.length === 0) {
      return;
    }
    TripDao.loadTrip(this.ctx(), this.tripId).then((trip: Trip | null): void => {
      if (trip === null || this.dayIndex >= trip.days.length) {
        Logger.warn('Ui.Edit', `行程或当日不存在 trip=${this.tripId} day=${this.dayIndex}`);
        return;
      }
      this.trip = trip;
      this.acts = trip.days[this.dayIndex].activities.slice();
    }).catch((err: Error) => {
      Logger.error('Ui.Edit', `加载失败: ${err.message}`);
    });
  }

  private ctx(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1600 });
  }

  /** 时间槽不变，节点按新顺序重占槽 */
  private reflowTimes(): void {
    const slots: Activity[] = this.acts.slice().sort((a: Activity, b: Activity): number =>
      a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
    const next: Activity[] = this.acts.map((act: Activity, i: number): Activity => {
      const slot: Activity = slots[i];
      const kept: Activity = {
        id: act.id, time: slot.time, endTime: slot.endTime, title: act.title,
        location: act.location, address: act.address, longitude: act.longitude,
        latitude: act.latitude, status: act.status, category: act.category,
        note: act.note, reason: act.reason, transport: act.transport
      };
      return kept;
    });
    this.acts = next;
  }

  private move(from: number, to: number): void {
    if (from === to || from < 0 || to < 0) {
      return;
    }
    this.snapshot();
    const next: Activity[] = this.acts.slice();
    const moved: Activity = next.splice(from, 1)[0];
    next.splice(to, 0, moved);
    this.acts = next;
    this.reflowTimes();
  }

  private removeAt(idx: number): void {
    this.snapshot();
    const gone: Activity = this.acts[idx];
    const next: Activity[] = this.acts.slice();
    next.splice(idx, 1);
    this.acts = next;
    this.reflowTimes();
    const freed: string = TimeText.stayOf(gone);
    this.gapNote = freed.length > 0
      ? `移走后第 ${this.dayIndex + 1} 天空 ${freed}，可补一个可选景点` : '';
  }

  /** 打开替换面板：列本城景点库，排除当日已在的站 */
  private openReplace(idx: number): void {
    this.loadCandidates(idx);
  }

  /** 底稿屏9 的「补选景点」：当日只能减不能加是缺通路，复用同一张候选面板 */
  private openAdd(): void {
    this.loadCandidates(-1);
  }

  private loadCandidates(idx: number): void {
    const trip: Trip | null = this.trip;
    if (trip === null) {
      this.toast('行程未就绪');
      return;
    }
    this.replaceIdx = idx;
    PlanRepository.loadSpots(this.ctx(), trip.destination).then((spots: Spot[]): void => {
      const taken: string[] = this.acts.map((a: Activity): string => a.title);
      this.candidates = spots.filter((s: Spot): boolean => taken.indexOf(s.name) < 0);
      this.showReplace = true;
    }).catch((err: Error) => {
      Logger.warn('Ui.Edit', `景点库加载失败: ${err.message}`);
      this.toast('景点库加载失败');
    });
  }

  private static minsOf(hhmm: string): number {
    const parts: string[] = hhmm.split(':');
    if (parts.length < 2) {
      return 9 * 60;
    }
    return Number(parts[0]) * 60 + Number(parts[1]);
  }

  private static hhmm(mins: number): string {
    const clamped: number = Math.max(0, Math.min(23 * 60 + 45, mins));
    const h: string = `${Math.floor(clamped / 60)}`.padStart(2, '0');
    const m: string = `${clamped % 60}`.padStart(2, '0');
    return `${h}:${m}`;
  }

  /**
   * 屏8 的 meta 行读的是 `act.address`，而生成链路（utils/TripEnrich.backfillActivityPlaces）
   * 写进去的是「城市 区」两段。编辑链路此前只写区，于是替换/补选过的站在同一屏里
   * 比别的站少一段城市（真机实拍：同行「北京 延庆区」，替换后只剩「东城区」）。
   * 口径收成一个函数，与回填那处同形。
   */
  private static placeOf(spot: Spot): string {
    return spot.city.length > 0 && spot.district.length > 0
      ? `${spot.city} ${spot.district}` : spot.district;
  }

  private applyReplace(spot: Spot): void {
    const idx: number = this.replaceIdx;
    this.snapshot();
    if (idx < 0) {
      this.applyAdd(spot);
      return;
    }
    if (idx >= this.acts.length) {
      return;
    }
    const old: Activity = this.acts[idx];
    const replacement: Activity = {
      // 不能复用 spot.id：同景点在行程里出现两次会撞 TripDao 主键；也不复用 old.id，
      // 否则新景点会继承旧节点的打卡记录。
      id: mintEditActivityId('rep'), time: old.time, endTime: old.endTime, title: spot.name,
      location: EditItineraryPage.placeOf(spot), address: EditItineraryPage.placeOf(spot),
      longitude: spot.longitude, latitude: spot.latitude,
      status: spot.booking.requiresBooking ? ActivityStatus.NOT_BOOKED : ActivityStatus.NO_NEED,
      category: ActivityCategory.SIGHT, note: old.note, reason: old.reason, transport: old.transport
    };
    const next: Activity[] = this.acts.slice();
    next[idx] = replacement;
    this.acts = next;
    this.showReplace = false;
    this.replaceIdx = -1;
  }

  /** 补选：接在当日末尾，开始时间取上一站的结束时间 + 15 分钟缓冲 */
  private applyAdd(spot: Spot): void {
    const acts: Activity[] = this.acts.slice();
    const last: Activity | undefined = acts.length > 0 ? acts[acts.length - 1] : undefined;
    const start: number = last === undefined ? 9 * 60 : EditItineraryPage.minsOf(last.endTime) + 15;
    const added: Activity = {
      id: mintEditActivityId('add'), time: EditItineraryPage.hhmm(start),
      endTime: EditItineraryPage.hhmm(start + spot.suggestedDuration),
      title: spot.name,
      location: EditItineraryPage.placeOf(spot), address: EditItineraryPage.placeOf(spot),
      longitude: spot.longitude, latitude: spot.latitude,
      status: spot.booking.requiresBooking ? ActivityStatus.NOT_BOOKED : ActivityStatus.NO_NEED,
      category: ActivityCategory.SIGHT,
      note: spot.booking.requiresBooking ? `预约：${spot.booking.bookingMethod ?? '官方渠道'}（以官方为准）` : undefined,
      reason: undefined,
      // 不编通勤腿：补选进来的站点没有真实距离，缺 transport 时时间线本就不画这一段
      transport: undefined
    };
    acts.push(added);
    this.acts = acts;
    this.reflowTimes();
    this.showReplace = false;
    this.replaceIdx = -1;
    this.toast(`已补选 ${spot.name}`);
  }

  /** 完成：回写当日节点并整份聚合根落库 */
  private finish(): void {
    const trip: Trip | null = this.trip;
    if (trip === null || this.dayIndex >= trip.days.length) {
      this.pathStack.pop();
      return;
    }
    const days = trip.days.slice();
    const kept: Activity[] = this.acts.map((a: Activity): Activity => {
      const copy: Activity = {
        id: a.id, time: a.time, endTime: a.endTime, title: a.title, location: a.location,
        address: a.address, longitude: a.longitude, latitude: a.latitude, status: a.status,
        category: a.category, note: a.note, reason: a.reason, transport: a.transport
      };
      return copy;
    });
    days[this.dayIndex].activities = kept;
    const updated: Trip = {
      id: trip.id, destination: trip.destination, startDate: trip.startDate,
      endDate: trip.endDate, people: trip.people, budget: trip.budget, style: trip.style,
      overview: trip.overview, days: days, tips: trip.tips
    };
    TripDao.saveTrip(this.ctx(), updated).then((): void => {
      Logger.info('Ui.Edit', `保存 Day ${this.dayIndex + 1} 共 ${kept.length} 站`);
      WidgetSync.refreshAll(this.ctx()).catch((err: Error) => {
        Logger.warn('Ui.Edit', `卡片刷新失败: ${err.message}`);
      });
      this.toast(`已保存 ${kept.length} 站`);
      this.pathStack.pop();
    }).catch((err: Error) => {
      Logger.error('Ui.Edit', `保存失败: ${err.message}`);
      this.toast('保存失败，改动未落库');
    });
  }

  /**
   * 拖拽把手（帧 ebe57eac：22×22 盒内 2 列 × 3 行 r=2 圆点，fill `#69696E`）。
   *
   * 官方符号表里没有六点把手（最接近的 `dot_grid_2x2` 是四个点），所以按帧画。
   * 颜色取 `muted` 而不是 `faint`：帧给的 `#69696E` 就是浅色档的 muted；
   * 抄成 faint 后浅色档对行底只有 **2.49:1**（非文本控件要求 3:1），这个把手基本是隐形的。
   *
   * 命中区收窄不到把手上 —— `onItemDragStart` 只能挂在 List 级做整行长按，
   * 所以它是「这一行可重排」的提示，不是「拖我」的靶子；手势本身靠 accessibilityText 念出来。
   */
  @Builder
  handle() {
    Column({ space: GRIP_ROW_GAP_VP }) {
      Row({ space: GRIP_COL_GAP_VP }) {
        this.gripDot()
        this.gripDot()
      }
      Row({ space: GRIP_COL_GAP_VP }) {
        this.gripDot()
        this.gripDot()
      }
      Row({ space: GRIP_COL_GAP_VP }) {
        this.gripDot()
        this.gripDot()
      }
    }
    .width(24)
    .height(LayoutTokens.minTouchTarget)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .accessibilityText('长按拖动调整顺序')
  }

  @Builder
  gripDot() {
    Circle({ width: GRIP_DOT_VP, height: GRIP_DOT_VP })
      .fill(ColorTokens.muted)
  }

  @Builder
  rowPreview(act: Activity) {
    Row({ space: SpaceTokens.xs }) {
      Text(act.time)
        .fontSize(TypeTokens.time.size)
        .fontWeight(600)
        .fontColor(ColorTokens.primary)
        .fontFeature("'tnum' on")
      Text(act.title)
        .fontSize(TypeTokens.small.size)
        .fontWeight(600)
        .fontColor(ColorTokens.ink)
    }
    .padding(SpaceTokens.base)
    .borderRadius(RadiusTokens.card)
    // 拖动抬起的预览行：填 canvas 时深色档与底同色，抬起来看不出区别（同 TripsPage/StayPickPage 那批）
    .backgroundColor(ColorTokens.surfaceElevated)
    .shadow(ShadowTokens.floating)
  }

  @Builder
  editRow(act: Activity, idx: number) {
    Row({ space: SpaceTokens.xs }) {
      this.handle()
      Text(act.time)
        .width(LayoutTokens.itineraryTimeGutter)
        .fontSize(TypeTokens.time.size)
        .fontWeight(600)
        // 拖动态字色恒为 ink：tint 底上压 primary 蓝字双端 sub-AA（DESIGN §9）；
        // 「正在拖」由 tint 底 + 左侧 primary 竖条表达，不靠蓝字
        .fontColor(ColorTokens.ink)
        .textAlign(TextAlign.End)
        .fontFeature("'tnum' on")
        .padding({ right: SpaceTokens.xs })
      // 底稿这屏每行时间右侧有节点圆环、环后有连续脊线；实现里两者都没有，
      // 三张卡片是"散着的"（§5y 对表第三项）。做法与屏8 一致：
      // 脊线定高走具名行高，不用 '100%'（无定高容器里百分比按视口解析，见屏8 注释）
      Stack({ alignContent: Alignment.Top }) {
        Column()
          .width(LayoutTokens.routeLineWidth)
          .height(this.isLastRow(idx) ? SpaceTokens.base : LayoutTokens.itineraryRowMinHeight)
          .backgroundColor(ColorTokens.surfaceSunken)
        TimelineNode({ cat: act.category })
      }
      .width(LayoutTokens.itineraryNodeSize)
      .height(this.isLastRow(idx) ? SpaceTokens.base : LayoutTokens.itineraryRowMinHeight)
      Column() {
        Text(act.title)
          .fontSize(TypeTokens.small.size)
          .fontWeight(600)
          .fontColor(ColorTokens.ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(act.address.length > 0 ? act.address : act.location)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 底稿这两个动作叫「替换景点 / 移除景点」。原来是裸 SymbolGlyph + onClick：
      // 22px 触点低于平台最小热区，也不可聚焦、读屏念不出动作。
      // 换成官方 Button（Circle + TEXTUAL 档，不出额外表面），图标与配色原样。
      Button() {
        SymbolGlyph($r('sys.symbol.arrow_2_circlepath'))
          .fontSize(IconSizes.control)
          .fontColor([ColorTokens.icon])
      }
      .type(ButtonType.Circle)
      .buttonStyle(ButtonStyleMode.TEXTUAL)
      .padding(0)
      .width(LayoutTokens.minTouchTarget)
      .height(LayoutTokens.minTouchTarget)
      .accessibilityText('替换景点')
      .onClick(() => {
        this.openReplace(idx);
      })

      Button() {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(IconSizes.control)
          .fontColor([ColorTokens.muted])
      }
      .type(ButtonType.Circle)
      .buttonStyle(ButtonStyleMode.TEXTUAL)
      .padding(0)
      .width(LayoutTokens.minTouchTarget)
      .height(LayoutTokens.minTouchTarget)
      .accessibilityText('移除景点')
      .onClick(() => {
        this.removeAt(idx);
      })
    }
    .width('100%')
    .padding({ top: SpaceTokens.xs, bottom: SpaceTokens.xs })
    .borderRadius(RadiusTokens.card)
    .backgroundColor(this.dragIdx === idx ? ColorTokens.primaryTint : ColorTokens.surfaceElevated)
    // 拖动态的左竖条：2px primary（契约 route-line 同宽），补上蓝字让位后的状态表达
    .border({
      width: { left: this.dragIdx === idx ? LayoutTokens.routeLineWidth : 0 },
      color: ColorTokens.primary
    })
  }

  @Builder
  replaceSheet() {
    Column() {
      Text(this.replaceIdx < 0 ? '补选景点' : '换一个')
        .fontSize(TypeTokens.title.size)
        .fontWeight(700)
        .fontFamily(TypeTokens.title.family)
        .fontColor(ColorTokens.ink)
        .margin({ top: SpaceTokens.lg, bottom: SpaceTokens.xxs })
      Text(this.replaceIdx < 0 ? '补选接在当日末尾，时间与通勤按新顺序重排' :
        '替换只换站点，该位置的时间与通勤保持不变')
        .fontSize(TypeTokens.caption.size)
        .fontColor(ColorTokens.muted)
        .margin({ bottom: SpaceTokens.sm })

      List({ space: SpaceTokens.xxs }) {
        if (this.candidates.length === 0) {
          // 空态：本城景点库已全部在当日（或库为空），别给一张空 List 不吭声
          ListItem() {
            Column({ space: SpaceTokens.xs }) {
              SymbolGlyph($r('sys.symbol.checkmark_circle'))
                .fontSize(IconSizes.display)
                .fontColor([ColorTokens.muted])
              Text(this.replaceIdx < 0 ? '本城景点都已在这天里了' : '没有可替换的其它景点')
                .fontSize(TypeTokens.small.size)
                .fontColor(ColorTokens.muted)
            }
            .width('100%')
            .padding({ top: SpaceTokens.lg, bottom: SpaceTokens.lg })
            .justifyContent(FlexAlign.Center)
          }
        }
        ForEach(this.candidates, (spot: Spot) => {
          ListItem() {
            // 候选项整块可点：官方 Button 承载（裸 Column 无按压态、读屏进不去）
          Button({ type: ButtonType.Normal, stateEffect: true }) {
          Column() {
              Text(spot.name)
                .fontSize(TypeTokens.small.size)
                .fontWeight(600)
                .fontColor(ColorTokens.ink)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`${spot.district} · 建议 ${Math.round(spot.suggestedDuration / 60 * 10) / 10}小时` +
                `${spot.booking.requiresBooking ? ' · 需预约' : ''}`)
                .fontSize(TypeTokens.caption.size)
                .fontWeight(450)
                .fontColor(ColorTokens.muted)
                .fontFeature("'tnum' on")
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding(SpaceTokens.base)
            .borderRadius(RadiusTokens.card)
            .backgroundColor(ColorTokens.surfacePanel)
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .width('100%')
          .padding(0)
          .borderRadius(RadiusTokens.card)
          .accessibilityText(`替换为 ${spot.name}，${spot.district}`)
          .onClick(() => {
            this.applyReplace(spot);
          })          }
        }, (spot: Spot): string => `rep-${spot.id}`)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
    .padding({ left: SpaceTokens.base, right: SpaceTokens.base, bottom: SpaceTokens.lg })
    .backgroundColor(ColorTokens.canvas)
  }

  /**
   * 契约 屏9 的 Day 头（底稿 `Day 1 · 10月12日 周六` + 右侧 `东山区 · 步行 5.2km`）。
   * 实拍这一屏**整行没有**，三张卡片直接顶到标题栏下面，
   * 用户在这屏不知道自己改的是哪一天（§6 对表查出的 must-fix）。
   * 取词与屏8 同一套（`Day N · M月D日`），不另造格式。
   */
  @Builder
  dayHeader() {
    Column({ space: SpaceTokens.xxs }) {
      Text(this.dayHeadline())
        .fontSize(TypeTokens.title.size)
        .fontWeight(700)
        .fontFamily(TypeTokens.title.family)
        .fontColor(ColorTokens.ink)
        .fontFeature("'tnum' on")
      Text(this.daySubline())
        .fontSize(TypeTokens.caption.size)
        .fontColor(ColorTokens.muted)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: SpaceTokens.base, right: SpaceTokens.base,
      top: SpaceTokens.sm, bottom: SpaceTokens.xs })
  }

  private isLastRow(idx: number): boolean {
    return idx + 1 >= this.acts.length;
  }

  /** 底稿在相邻两站之间挂「步行 12分钟 · 750m」；实现里这屏完全没有站间信息 */
  @Builder
  legRow(act: Activity) {
    if (act.transport !== undefined) {
      Row({ space: SpaceTokens.xxs }) {
        Text(this.legText(act))
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .fontFeature("'tnum' on")
      }
      .width('100%')
      .padding({ left: LayoutTokens.itineraryTimeGutter + SpaceTokens.xs,
        top: SpaceTokens.xxs, bottom: SpaceTokens.xxs })
    }
  }

  private legText(act: Activity): string {
    if (act.transport === undefined) {
      return '';
    }
    const mode: string = act.transport.mode.length > 0 ? act.transport.mode : '步行';
    const detail: string = act.transport.detail.length > 0 ? ` · ${act.transport.detail}` : '';
    return `${mode} ${DurationCn.text(act.transport.duration)}${detail}`;
  }

  private curDay(): TripDay | null {
    const trip: Trip | null = this.trip;
    if (trip === null || this.dayIndex >= trip.days.length) {
      return null;
    }
    return trip.days[this.dayIndex];
  }

  private dayHeadline(): string {
    const head: string = `Day ${this.dayIndex + 1}`;
    const day: TripDay | null = this.curDay();
    if (day === null || !DateUtils.isValidIsoDate(day.date)) {
      return head;
    }
    return `${head} · ${day.date.slice(5).replace('-', '月')}日`;
  }

  private daySubline(): string {
    const day: TripDay | null = this.curDay();
    const parts: string[] = [];
    if (day !== null && day.theme.length > 0) {
      parts.push(day.theme);
    }
    parts.push(`${this.acts.length} 个节点`);
    return parts.join(' · ');
  }

  /**
   * 契约 屏9 的钉底操作条：撤销（次级）+ 保存修改（实心主）。
   * 实拍这一屏底部 60% 是空白、主操作只藏在标题栏的三枚图标里——
   * 与禁令 1 一起看：整屏唯一实心主按钮放在这里。
   */
  @Builder
  actionBar() {
    Row({ space: SpaceTokens.sm }) {
      YoujingButton({
        variant: YoujingButtonVariant.SECONDARY,
        label: '撤销',
        buttonWidth: 120,
        onAction: (): void => {
          this.undo();
        }
      })
      // `fullWidth: true` 在 Row 里等于"父级 100%"（sm 内容宽 331.5vp），
      // 同排还有一颗 120vp 的「撤销」+ 16vp 间距 → 必然溢出，真机实测主键
      // 可见 215.4vp、右缘正好压在屏幕 1136px 上（被切掉约 136vp）。
      // 与屏3/屏5 同一根因的第三种表现：权重只能挂在原生件上，
      // 所以这里用原生 Column 吃剩余宽，主键再填满它。
      Column() {
        YoujingButton({
          variant: YoujingButtonVariant.PRIMARY,
          label: '保存修改',
          fullWidth: true,
          onAction: (): void => {
            this.finish();
          }
        })
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: SpaceTokens.base, right: SpaceTokens.base, top: SpaceTokens.xs })
    .margin({ bottom: LayoutTokens.floatingDockClearance })
  }

  /** 官方标题栏：补选景点走 content.menu；完成/撤销已下到底部操作条，不再两处各一份 */
  private titleBarOptions(): HdsNavigationTitleBarOptions {
    const items: Array<HdsNavigationMenuItemOptions> = [
      HdsChrome.item($r('sys.symbol.plus_circle'), '补选景点', (): void => {
        this.openAdd();
      })];
    return HdsChrome.bar({ mainTitle: '编辑行程', menu: items, scrolled: this.barScrolled });
  }

  /** 绝对滚动偏移 → 顶栏磨砂开关（>0 即开，静止归零） */
  private syncBarScroll(): void {
    const y: number = this.barScroller.currentOffset().yOffset;
    const on: boolean = y > 0;
    if (on !== this.barScrolled) {
      this.barScrolled = on;
    }
  }

  build() {
    HdsNavDestination() {
      Column() {

        if (this.acts.length === 0) {
          // 「未指定行程」是说给开发者听的话：用户站在这屏只知道一片黑，
          // 而顶栏三颗钮（完成/添加/撤销）看着全都能点。改成说清缺什么、去哪儿补
          Column({ space: SpaceTokens.xs }) {
            Text(this.tripId.length === 0 ? '没有带进行程' : '这一天还没有节点')
              .fontSize(TypeTokens.title.size)
              .fontWeight(700)
              .fontFamily(TypeTokens.title.family)
              .fontColor(ColorTokens.ink)
              .textAlign(TextAlign.Center)
            Text(this.tripId.length === 0 ? '从「行程」页选一条行程再进来' : '点右上角 ⊕ 可以补选景点')
              .fontSize(TypeTokens.small.size)
              .fontColor(ColorTokens.body)
              .textAlign(TextAlign.Center)
              .constraintSize({ maxWidth: 240 })
          }
          .alignItems(HorizontalAlign.Center)
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Column() {
          this.dayHeader()
          List({ space: SpaceTokens.xxs, scroller: this.barScroller }) {
            ForEach(this.acts, (act: Activity, idx: number) => {
              ListItem() {
                Column() {
                  if (idx > 0) {
                    this.legRow(act)
                  }
                  this.editRow(act, idx)
                }
                .width('100%')
              }
            // key 只用稳定 id：拖动会改 time，带 time 的 key 会让整项重建、丢掉拖动态
            }, (act: Activity): string => `edit-${act.id}`)
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .padding({ left: SpaceTokens.base, right: SpaceTokens.base,
            bottom: LayoutTokens.floatingDockClearance })
          .onItemDragStart((event: ItemDragInfo, itemIndex: number): CustomBuilder => {
            // 官方 API 限制：onItemDragStart 挂在 List 级（整行长按触发），
            // 与「把手只挂把手」的视觉约定有差距——拖影由本函数自定义，
            // 命中区收窄做不到，靠长按 + 拖影反馈兜底
            this.dragIdx = itemIndex;
            const act: Activity = this.acts[itemIndex];
            return (): void => {
              this.rowPreview(act);
            };
          })
          .onItemDrop((event: ItemDragInfo, itemIndex: number, insertIndex: number,
            isSuccess: boolean): void => {
            if (isSuccess && insertIndex >= 0) {
              this.move(itemIndex, insertIndex > itemIndex ? insertIndex - 1 : insertIndex);
            }
            this.dragIdx = -1;
          })
          .onDidScroll((): void => {
            this.syncBarScroll();
          })
          if (this.gapNote.length > 0) {
            Row({ space: SpaceTokens.xs }) {
              Text(this.gapNote)
                .fontSize(TypeTokens.caption.size)
                .fontWeight(450)
                .fontColor(ColorTokens.warning)
                .fontFeature("'tnum' on")
                .layoutWeight(1)
              Button('补一个')
                .fontSize(TypeTokens.caption.size)
                .fontWeight(600)
                .fontColor(ColorTokens.primary)
                .backgroundColor(Color.Transparent)
                .type(ButtonType.Capsule)
                .buttonStyle(ButtonStyleMode.TEXTUAL)
                .height(LayoutTokens.minTouchTarget)
                .onClick((): void => {
                  this.openAdd();
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .padding({ left: SpaceTokens.base, right: SpaceTokens.base, top: SpaceTokens.xs })
          }
          this.actionBar()
          }
          .width('100%')
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ColorTokens.canvas)
      .bindSheet($$this.showReplace, this.replaceSheet(), {
        height: '70%',
        backgroundColor: ColorTokens.canvas,
        showClose: true,
        systemMaterial: getSheetImmersiveMaterial()
      })
    }
    // HDS 深色档这层默认纯黑，透明栏会把它露成一条比画布暗一档的带（成因与实测见 Docs/INIT_REPORT.md §5ci 续 80）
    .backgroundColor(ColorTokens.canvas)
    .titleBar(this.titleBarOptions())
    .onReady((ctx: NavDestinationContext): void => {
      // 屏8 现在可能住在四条 tab 栈的任意一条上（从「我的」点开行程再进编辑），
      // 写死 APP_NAV 会让 :219 / :243 两处 pop 弹在看不见的栈上——返回按钮点了没反应
      this.pathStack = ctx.pathStack;
    })
    .titleMode(HdsNavDestinationTitleMode.MINI)
  }
}
