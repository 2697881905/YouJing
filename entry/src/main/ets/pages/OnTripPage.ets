/**
 * 屏15 旅行中模式（帧 fc4e40cd）。
 * §7 必改已落：badge padding 3→4、check-right gap 6→4、stop-row padding 10→8、scroll 72→94。
 * hero 站名走 sans 21/700（禁令 8：serif 不上站名）。
 *
 * 数据（RDB 已接真）：当日节点、当前时刻、进度、下一段通勤、行内金额与打卡状态全部取真值。
 * 打卡写 checkin 表（v4），行内金额取挂在该节点上的 expense 合计；
 * 底稿里「周一人少，10:00 后团队到达」「打车 ¥1,900」这类无来源文案不保留。
 */

import { DurationCn } from '../utils/DurationCn';
import { ACTIVE_TRIP_KEY, APP_NAV } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { MoneyText } from '../utils/MoneyText';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { KEY_WINDOW_WIDTH_VP, BP_MD_MIN_VP } from '../utils/breakpointCenter';
import { symmetricInsetForCap } from '../utils/responsive';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { TimelineNode } from '../components/TimelineNode';
import { Activity, ActivityCategory, ActivityStatus, MealType, Trip, TripDay } from '../model/Trip';
import { ReplanAction, ReplanDecision, ReplanOutcome } from '../model/Replan';
import { Spot } from '../model/Spot';
import { SpotDao } from '../data/SpotDao';
import { CompanionEngine } from '../companion/CompanionEngine';
import { CompanionPrefs } from '../companion/CompanionPrefs';
import { CompanionStore } from '../companion/CompanionStore';
import { CompanionAction, CompanionPrompt, UnplannedInput } from '../companion/CompanionTypes';
import { PlanRepository } from '../data/PlanRepository';
import { mintEditActivityId } from '../utils/ActivityIds';
import { getSheetImmersiveMaterial } from '../utils/immersiveMaterial';
import { WeatherBrief, WeatherDay } from '../model/Weather';
import { TripDao } from '../data/TripDao';
import { SkipPlanner } from '../data/SkipPlanner';
import { WeatherAdvisor } from '../data/WeatherAdvisor';
import { WeatherStore } from '../data/WeatherStore';
import {
  SignalAction, SignalContext, SignalKind, TripSignals, TripSuggestion
} from '../data/TripSignals';
import { CheckinDao, CheckinEvidence } from '../data/CheckinDao';
import { BadgeDao } from '../data/BadgeDao';
import { Badge, BadgeGroup, BadgeRecord, badgeSourceText, badgeTotal, buildBadgeBoard, findBadge } from '../utils/BadgeBoard';
import { BadgeEarnedDialog } from '../components/BadgeEarnedDialog';
import { ExpenseDao } from '../data/ExpenseDao';
import { ReplanClient } from '../ai/ReplanClient';
import { DateUtils } from '../utils/DateUtils';
import { Geo, GeoPoint } from '../utils/Geo';
import { ArrivalWatcher, LocationFix } from '../common/location/ArrivalWatcher';
import { GeofenceManager } from '../common/location/GeofenceManager';
import { ArrivalNotice } from '../common/location/ArrivalNotice';
import { FenceSpec } from '../utils/GeofencePlan';
import { WidgetSync } from '../widget/TodayCard';
import { TransitSymbol } from '../utils/TransitSymbol';
import { NodeOwe, OweItem } from '../utils/NodeOwe';
import { Logger } from '../common/logger/Logger';
import { common } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode, HideMode } from '@kit.UIDesignKit';
import type { HdsNavigationMenuItemOptions, HdsNavigationTitleBarOptions } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';
import { requestSystemBarRefresh } from '../utils/systemBar';

/**
 * 当日站点：活动 ∪ 餐次（屏15 帧把「07:40 早餐 ¥900 已打卡」和节点排在同一列里）。
 * 餐次可能没有时刻（AI 可省略、存量行程也没有），那种情况排序按餐次档位、
 * 显示留空——不拿 08:00 这类假时刻填进界面。
 */
interface DayStop {
  /** 打卡主键：活动用 Activity.id，餐次用派生 key `meal-{dayIndex}-{type}` */
  key: string;
  /** 界面上显示的时刻；无时刻的餐次为 '' */
  time: string;
  /** 排位用的分钟数（无时刻的餐次按早/午/晚档位给槽位） */
  sortMin: number;
  title: string;
  /** 餐次标签（早餐/午餐/晚餐）；活动为空串。无时刻的餐次拿它占时间槽，名字列留给店名 */
  kind: string;
  endTime: string;
  note: string;
  place: string;
  /** 站点坐标；餐次没有坐标（0 = 没有），到站判定只对活动生效 */
  lat: number;
  lng: number;
  isMeal: boolean;
  /** 活动分类；餐次为 null——「不去」入口按它和 status 判定 */
  category: ActivityCategory | null;
  cost: number;
  status: ActivityStatus | null;
  transportMode: string;
  transportMin: number;
  transportDetail: string;
  hasTransport: boolean;
}

interface CheckedRow {
  time: string;
  name: string;
  amount: string;
  ongoing: boolean;
}

function clockNow(): string {
  const d: Date = new Date();
  const h: string = `${d.getHours()}`;
  const m: string = `${d.getMinutes()}`;
  return `${h.length < 2 ? `0${h}` : h}:${m.length < 2 ? `0${m}` : m}`;
}

/** 同类建议「忽略」后的静默窗口（分钟） */
const SIGNAL_MUTE_MIN: number = 30;

/**
 * 建议停留时长。原来打小数（`4.5小时`），而屏5 选点、屏8 行程纸同一件事写 `4小时30分钟`
 * ——两套说法并排出现时，用户会以为一个是"排定"一个是"实测"。
 * 无结束时刻（一餐没有 endTime）退成 `—`，与屏8 `durationText` 同口径。
 */
function stayText(start: string, end: string): string {
  const mins: number = DateUtils.minutesOf(end) - DateUtils.minutesOf(start);
  return mins > 0 ? DurationCn.text(mins) : '—';
}

@Component
export struct OnTripPage {
  // 深浅档代 tick：翻档时 EntryAbility 自增，@StorageProp 变化带动本页 build 重跑，
  // 把新 tick 传进 HdsChrome.bar → 标题内容换新 ComponentContent 重挂载、按当前档重解色
  // （官方 HdsTitleBar 自绘内容不随配置切换重渲染，真机实证见 HdsChrome.themeTick）
  @StorageProp('chromeThemeTick') chromeThemeTick: number = 0;

  /** 窗口实测宽（vp），由断点中心一处测量；0 = 尚未测到，按不收窄处理 */
  @StorageProp(KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 0;

  /** 宽屏下的左右内缩：手机档原样返回 base（等于没改），折叠屏展开把内容收成 600vp 一栏 */
  private wideInset(): number {
    return symmetricInsetForCap(this.windowWidthVp, BP_MD_MIN_VP, SpaceTokens.base);
  }
  /**
   * 这一屏可能被 push 在五条 tab 栈的任意一条上——从「行程」页签点开就走 TRIPS_NAV。
   * 原来硬用 APP_NAV：从「我的」页签进来时，分享/编辑/全图/记一笔全部推到
   * 看不见的 tab-0 栈上，点了没反应（独立复审查出的 P0，与 enterPlanningFlow 同一类，
   * 当时只修了入口没修这两页）。改由 NavDestination.onReady 拿**自己所属**的栈，
   * 与 ComingSoonPage 同法；保留 APP_NAV 作默认值，深链直启时行为不变。
   */
  private pathStack: NavPathStack = APP_NAV;
  @Prop tripId: string = '';
  @State private rows: CheckedRow[] = [];
  @State private current: DayStop | null = null;
  /**
   * 「你欠着的那一站」——打卡列表的「进行中」行与建议条共用它。
   * 与 `current`（hero 的钟点节点）回答的是**两个不同的问题**，所以是两个字段：
   * 用户准时时两者重合，一落后就分叉。空串 = 没有欠站。
   */
  private owedKey: string = '';
  @State private next: DayStop | null = null;
  @State private checkedIn: boolean = false;
  /** IMP-10：打卡进行中闸——原来 DAO 回执前按钮可连点；checkedIn 翻转时机不变（不做乐观更新） */
  @State private checkinBusy: boolean = false;
  @State private elapsedMin: number = 0;
  @State private totalMin: number = 0;
  @State private dayLabel: string = '';
  @State private clock: string = '';
  @State private nextLeg: string = '';
  private trip: Trip | null = null;
  @State private replanning: boolean = false;
  /** 顶部提示：正在重排 / 重排结果 / 失败原因 */
  @State private notice: string = '';
  @State private canUndo: boolean = false;
  /** 加一站面板（屏9 同一套候选逻辑：排除当日已在的站） */
  @State private showAdd: boolean = false;
  @State private addCandidates: Spot[] = [];
  /** P3 对话式接管：输入 → 预演 → 用户确认后才落库 */
  @State private showIntent: boolean = false;
  @State private intentText: string = '';
  @State private intentPreview: string = '';
  @State private intentBusy: boolean = false;
  /** 预演已就绪（可点「确认执行」）；false 时按钮是「理解并预演」 */
  @State private intentReady: boolean = false;
  private intentOutcome: ReplanOutcome | null = null;
  private intentSnapshot: TripDay | null = null;
  /** add 动作不在预演里改行程，确认后打开加一站面板 */
  private intentOpenAdd: boolean = false;
  /** 「不去」只在今天提供；回看历史日不出现 */
  @State private isToday: boolean = false;
  /** 当前展示的整日；跳过/撤销都以它为输入 */
  private day: TripDay | null = null;
  /** 到站检测（切片2 T1）：前台定位算出的文案与状态；无权限时保持空/否 */
  @State private arrivalText: string = '';
  @State private arrived: boolean = false;
  /** 顶栏磨砂两态：由**绝对**滚动偏移驱动（每帧增量会被松手回弹的负帧打灭，契约 §Translucency） */
  @State private barScrolled: boolean = false;
  private barScroller: Scroller = new Scroller();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  private watcher: ArrivalWatcher = new ArrivalWatcher();
  private watcherActive: boolean = false;
  /** P5 到站围栏：注册成功才走系统事件，失败静默降级为前台定位 */
  private geofence: GeofenceManager = new GeofenceManager();
  private geofenceDayKey: string = '';
  /** 权限弹窗还没回来：避免 reload 连点导致重复 start */
  private watcherStarting: boolean = false;
  private lastFix: LocationFix | null = null;
  /** 跳过前的深拷贝（只在本进程有效，方案 §3.6） */
  private skipSnapshot: TripDay | null = null;
  private skipSnapshotTripId: string = '';
  private skipSnapshotDayIndex: number = 0;
  /** 「收下勋章」弹窗；每次收章新建一个，关闭即丢（不复用，避免带上上一枚的内容） */
  private badgeDialog: CustomDialogController | null = null;
  /** 页面已离开：迟到的勋章查询不再开弹窗 */
  private disposed: boolean = false;

  /** 切片3 T1：今日天气（只有「今天 + 取到」才出行）；数值走 tnum */
  @State private weatherText: string = '';
  @State private weatherAdvice: string = '';
  /** 切片3 T2：建议条文案；空串 = 不出条 */
  @State private signalTitle: string = '';
  @State private signalDetail: string = '';
  @State private signalLabel: string = '';
  private weather: WeatherDay | null = null;
  private signal: TripSuggestion | null = null;
  /** 「忽略」只静默同类信号 30 分钟；换类立即重判 */
  private mutedKind: SignalKind | null = null;
  private mutedAtMin: number = -1;
  /** 静默态只在同一行程同一天内有效，切天自动清 */
  private signalDayKey: string = '';
  /** 当前展示日的可打卡站点（buildStops 结果），信号动作按 key 反查目标 */
  private stops: DayStop[] = [];
  /** 当日打卡记录 key → 金额；信号判定要读已打卡站 */
  private marks: Record<string, number> = {};

  aboutToAppear(): void {
    this.disposed = false;
    CompanionStore.registerExecutor((action: CompanionAction): void => {
      this.handleCompanionAction(action);
    });
    this.reload();
  }

  aboutToDisappear(): void {
    this.disposed = true;
    CompanionStore.clearExecutor();
    this.watcher.stop();
    this.watcherActive = false;
    this.watcherStarting = false;
    this.geofence.stop();
    this.geofenceDayKey = '';
    this.closeBadgeDialog();
  }

  /** 弹窗的关闭权在宿主：@CustomDialog 里的 controller 成员没有注入，不能由弹窗自己 close */
  private closeBadgeDialog(): void {
    const dialog: CustomDialogController | null = this.badgeDialog;
    this.badgeDialog = null;
    if (dialog !== null) {
      dialog.close();
    }
  }

  private ctx(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  /** 串行化 reload：快速连点只保留最后一次的结果 */
  private reloadSeq: number = 0;
  // 伴随助手·规划外到访（Phase3）：本城景点缓存 + 停留追踪 + 去重 + 偏好
  private citySpots: Spot[] = [];
  private unplannedSpotName: string = '';
  private unplannedSinceMs: number = 0;
  private shownUnplannedId: string = '';
  private companionPrefs: CompanionPrefs = CompanionStore.prefs;
  /** 伴随跨天挪移的整程撤销快照（区别于 skipSnapshot 的单日快照） */
  private companionUndoTrip: Trip | null = null;

  private async reload(): Promise<void> {
    if (this.tripId.length === 0) {
      Logger.warn('Ui.OnTrip', '无 tripId，旅行中页保持空态');
      return;
    }
    const mySeq: number = ++this.reloadSeq;
    const context: common.Context = this.ctx();
    const now: string = clockNow();
    this.clock = now;
    try {
      const trip: Trip | null = await TripDao.loadTrip(context, this.tripId);
      if (mySeq !== this.reloadSeq) {
        return;
      }
      if (trip === null) {
        this.trip = null;
        this.day = null;
        this.current = null;
        this.owedKey = '';
        this.next = null;
        this.rows = [];
        this.stops = [];
        this.marks = {};
        this.checkedIn = false;
        this.isToday = false;
        this.clearSkipState();
        this.clearWeather();
        this.clearSignal();
        this.notice = '';
        return;
      }
      this.trip = trip;
      AppStorage.setOrCreate(ACTIVE_TRIP_KEY, trip.id);
      // 伴随助手：加载本城景点供「规划外到访」识别（失败静默，不阻塞行中）
      SpotDao.loadByCity(context, trip.destination).then((spots: Spot[]): void => {
        this.citySpots = spots;
      }).catch((): void => {
        this.citySpots = [];
      });
      if (this.skipSnapshotTripId.length > 0 && this.skipSnapshotTripId !== trip.id) {
        this.clearSkipState();
        this.notice = '';
      }
      const day: TripDay | null = this.pickDay(trip);
      this.day = day;
      const stops: DayStop[] = day === null ? [] : this.buildStops(day);
      if (day === null || day.activities.length === 0 || stops.length === 0) {
        this.dayLabel = '旅行中';
        this.current = null;
        this.owedKey = '';
        this.next = null;
        this.stops = [];
        this.totalMin = 0;
        this.elapsedMin = 0;
        this.nextLeg = '';
        this.checkedIn = false;
        this.isToday = false;
        this.canUndo = false;
        this.clearWeather();
        this.clearSignal();
        const emptyMarks: Record<string, number> = await CheckinDao.listForTrip(context, trip.id);
        this.marks = emptyMarks;
        await this.buildRows(emptyMarks);
        this.syncArrivalWatcher();
        return;
      }
      this.isToday = day.date === DateUtils.todayIso();
      this.stops = stops;
      const dayKey: string = `${trip.id}:${day.dayIndex}`;
      if (dayKey !== this.signalDayKey) {
        this.signalDayKey = dayKey;
        this.mutedKind = null;
        this.mutedAtMin = -1;
      }
      this.canUndo = this.skipSnapshot !== null && this.skipSnapshotTripId === trip.id &&
        this.skipSnapshotDayIndex === day.dayIndex;
      this.dayLabel = `进行中 · Day ${day.dayIndex}`;
      const nowMin: number = DateUtils.minutesOf(now);
      const marks: Record<string, number> = await CheckinDao.listForTrip(context, trip.id);
      this.marks = marks;
      // hero 回答的是「按原计划现在该在哪」：时刻已到的最后一站，一站都还没开始就取第一站。
      // 「完成打卡」的落点、进度条与到站订阅全都吃它。
      let cur: number = -1;
      for (let i = 0; i < stops.length; i++) {
        if (stops[i].sortMin <= nowMin) {
          cur = i;
        }
      }
      if (cur < 0) {
        cur = 0;
      }
      const curStop: DayStop = stops[cur];
      this.current = curStop;
      this.checkedIn = marks[curStop.key] !== undefined;
      this.next = cur + 1 < stops.length ? stops[cur + 1] : null;
      /**
       * 「哪一站该做而没做」是**另一个问题**，单独算，喂给打卡列表的「进行中」行
       * 与建议条。用户准时时它和 hero 同一站，一落后就不是 —— 所以两处各自的措辞
       * 必须分清在回答哪个问题，不能都叫「当前」。
       * 只在可操作站点上算（`oweItemsOf` 已排除交通与住宿）。
       */
      const oweItems: OweItem[] = this.oweItemsOf(stops);
      const owedIdx: number = NodeOwe.indexOf(oweItems, Object.keys(marks), nowMin);
      this.owedKey = owedIdx >= 0 ? oweItems[owedIdx].key : '';
      // 进度条只在"这一站有结束时刻"时给：餐次没有 endTime，不拿一小时假装它的窗口
      if (!curStop.isMeal && curStop.endTime.length > 0) {
        const start: number = curStop.sortMin;
        const end: number = Math.max(start + 1, DateUtils.minutesOf(curStop.endTime));
        this.totalMin = end - start;
        this.elapsedMin = Math.max(0, Math.min(this.totalMin, nowMin - start));
      } else {
        this.totalMin = 0;
        this.elapsedMin = 0;
      }
      const nx: DayStop | null = this.next;
      this.nextLeg = nx !== null && nx.hasTransport
        ? `${nx.transportMode} ${DurationCn.text(nx.transportMin)}${nx.transportDetail.length > 0 ? ` · ${nx.transportDetail}` : ''}`
        : '';
      await this.buildRows(marks);
      if (mySeq !== this.reloadSeq) {
        return;
      }
      this.syncArrivalWatcher();
      this.refreshWeather(day);
    } catch (err) {
      Logger.error('Ui.OnTrip', `加载失败: ${(err as Error).message}`);
    }
  }

  /** 「不去」只对「今天 + 可跳过的下一站」显示；餐次/交通/住宿/已预约/空闲一律不给 */
  private canSkipNext(): boolean {
    const next: DayStop | null = this.next;
    return this.isToday && !this.replanning && next !== null && !next.isMeal &&
      SkipPlanner.isSkippable(next.category, next.status);
  }

  /**
   * 跳过指定站点：云函数决策 → 端侧排程 → 落库 → 刷新页面。
   * expectedStopId 来自建议条/实况窗按钮，用于拒绝「按钮已陈旧」的点击；
   * 页面内「不去下一站」传 ''，取当前下一站。
   */
  private async performSkip(expectedStopId: string): Promise<void> {
    const trip: Trip | null = this.trip;
    const day: TripDay | null = this.day;
    if (trip === null || day === null) {
      this.toast('今日暂无安排');
      return;
    }
    if (this.replanning) {
      return;
    }
    if (!this.isToday) {
      this.toast('只能跳过今天的站点');
      return;
    }
    const target: DayStop | null = expectedStopId.length > 0
      ? this.stopOf(expectedStopId) : this.next;
    if (target === null) {
      this.toast('这一站已变化，请重试');
      return;
    }
    if (target.isMeal || !SkipPlanner.isSkippable(target.category, target.status)) {
      this.toast('这一站不能跳过');
      return;
    }
    const skippedId: string = target.key;
    const nowMin: number = DateUtils.minutesOf(clockNow());
    const snapshot: TripDay = SkipPlanner.cloneDay(day);
    this.replanning = true;
    this.notice = '正在重排今日剩余行程…';
    let outcome: ReplanOutcome | null = null;
    try {
      const decision: ReplanDecision | null =
        await ReplanClient.requestDecision(day, skippedId, nowMin);
      outcome = SkipPlanner.plan(day, skippedId, nowMin, decision);
    } catch (err) {
      this.replanning = false;
      this.notice = '重排失败，行程未改动';
      Logger.error('Ui.OnTrip', `重排失败: ${(err as Error).message}`);
      return;
    }
    if (outcome === null) {
      this.replanning = false;
      this.notice = '重排失败，行程未改动';
      return;
    }
    await this.commitDay(trip, snapshot, outcome);
  }

  /** 打开加一站面板：候选口径与屏9 补选完全一致（本城景点库 − 当日已在的站）。 */
  private openAddSheet(): void {
    const trip: Trip | null = this.trip;
    const day: TripDay | null = this.day;
    if (trip === null || day === null || !this.isToday || this.replanning) {
      return;
    }
    PlanRepository.loadSpots(this.ctx(), trip.destination).then((spots: Spot[]): void => {
      const taken: string[] = day.activities.map((a: Activity): string => a.title);
      this.addCandidates = spots.filter((s: Spot): boolean => taken.indexOf(s.name) < 0);
      this.showAdd = true;
    }).catch((err: Error): void => {
      Logger.warn('Ui.OnTrip', `景点库加载失败: ${err.message}`);
      this.toast('景点库加载失败');
    });
  }

  /** 选中候选后：云函数决策 → 端侧排程（含 480min 预算闸）→ 复用 commitDay 的撤销链路。 */
  private async performAdd(spot: Spot): Promise<void> {
    const trip: Trip | null = this.trip;
    const day: TripDay | null = this.day;
    if (trip === null || day === null || !this.isToday || this.replanning) {
      return;
    }
    this.showAdd = false;
    const nowMin: number = DateUtils.minutesOf(clockNow());
    const newStop: Activity = this.candidateActivity(spot, nowMin);
    const snapshot: TripDay = SkipPlanner.cloneDay(day);
    this.replanning = true;
    this.notice = '正在把新站排进今日行程…';
    let outcome: ReplanOutcome;
    try {
      const decision: ReplanDecision | null =
        await ReplanClient.requestAddDecision(day, newStop, nowMin);
      outcome = SkipPlanner.planWithAddition(day, newStop, nowMin, decision);
    } catch (err) {
      this.replanning = false;
      this.notice = '加站失败，行程未改动';
      Logger.error('Ui.OnTrip', `加站失败: ${(err as Error).message}`);
      return;
    }
    Logger.info('Ui.OnTrip', `加站 ${spot.name} changed=${outcome.changed} fallback=${outcome.usedFallback} note=${outcome.note}`);
    if (outcome.changed !== true) {
      this.replanning = false;
      this.notice = '';
      this.toast(outcome.note);
      return;
    }
    await this.commitDay(trip, snapshot, outcome);
  }

  /** 候选景点 → 当日活动：先给临时槽，真实落位由 SkipPlanner 重算。 */
  private candidateActivity(spot: Spot, nowMin: number): Activity {
    const duration: number = Math.max(15, Math.min(240, spot.suggestedDuration));
    const start: number = Math.max(nowMin, this.maxEndOfDay() + 15);
    const place: string = spot.city.length > 0 && spot.district.length > 0
      ? `${spot.city} ${spot.district}` : spot.district;
    const act: Activity = {
      id: mintEditActivityId('add'),
      time: DateUtils.hhmmOf(start),
      endTime: DateUtils.hhmmOf(start + duration),
      title: spot.name,
      location: place,
      address: place,
      longitude: spot.longitude,
      latitude: spot.latitude,
      status: spot.booking.requiresBooking ? ActivityStatus.NOT_BOOKED : ActivityStatus.NO_NEED,
      category: ActivityCategory.SIGHT,
      advanceDays: spot.booking.advanceDays,
      note: spot.booking.requiresBooking
        ? `预约：${spot.booking.bookingMethod ?? '官方渠道'}（以官方为准）` : undefined,
      reason: undefined,
      transport: undefined
    };
    return act;
  }

  private maxEndOfDay(): number {
    const day: TripDay | null = this.day;
    let maxEnd: number = DateUtils.minutesOf(clockNow());
    if (day === null) {
      return maxEnd;
    }
    for (const a of day.activities) {
      const start: number = DateUtils.minutesOf(a.time);
      const end: number = DateUtils.minutesOf(a.endTime);
      if (start >= 0) {
        maxEnd = Math.max(maxEnd, end > start ? end : start + 60);
      }
    }
    return maxEnd;
  }

  // ---- P3 对话式接管 ----

  private openIntent(): void {
    if (!this.isToday || this.replanning) {
      return;
    }
    this.intentText = '';
    this.intentPreview = '';
    this.intentBusy = false;
    this.intentReady = false;
    this.intentOutcome = null;
    this.intentSnapshot = null;
    this.intentOpenAdd = false;
    this.showIntent = true;
  }

  private closeIntent(): void {
    if (this.intentBusy) {
      return;
    }
    this.showIntent = false;
    this.intentReady = false;
    this.intentOutcome = null;
    this.intentSnapshot = null;
    this.intentOpenAdd = false;
  }

  /** 只预演，不落库；用户点「确认执行」才 commitDay */
  private async prepareIntent(): Promise<void> {
    const trip: Trip | null = this.trip;
    const day: TripDay | null = this.day;
    if (trip === null || day === null || this.replanning || this.intentBusy) {
      return;
    }
    const text: string = this.intentText.trim();
    if (text.length === 0) {
      this.toast('先说一句你想怎么改');
      return;
    }
    this.intentBusy = true;
    this.intentReady = false;
    this.intentOutcome = null;
    this.intentSnapshot = null;
    this.intentOpenAdd = false;
    this.intentPreview = '正在理解…';
    try {
      const candidates: Activity[] = await this.intentCandidates(trip, day);
      const nowMin: number = DateUtils.minutesOf(clockNow());
      const decision: ReplanDecision | null =
        await ReplanClient.requestIntentDecision(day, text, candidates, nowMin);
      if (decision === null) {
        this.previewLocalIntent(day, text, candidates, nowMin);
      } else {
        this.applyIntentDecision(day, decision, candidates, nowMin);
      }
    } finally {
      this.intentBusy = false;
    }
  }

  /** 候选池：本城景点库 − 当日已在的站；最多 8 个，够换站选择即可 */
  private async intentCandidates(trip: Trip, day: TripDay): Promise<Activity[]> {
    const list: Activity[] = [];
    try {
      const spots: Spot[] = await PlanRepository.loadSpots(this.ctx(), trip.destination);
      const taken: string[] = day.activities.map((a: Activity): string => a.title);
      const nowMin: number = DateUtils.minutesOf(clockNow());
      for (const s of spots) {
        if (taken.indexOf(s.name) >= 0) {
          continue;
        }
        list.push(this.candidateActivity(s, nowMin));
        if (list.length >= 8) {
          break;
        }
      }
    } catch (err) {
      Logger.warn('Ui.OnTrip', `意图候选加载失败: ${(err as Error).message}`);
    }
    return list;
  }

  private applyIntentDecision(day: TripDay, d: ReplanDecision, candidates: Activity[],
    nowMin: number): void {
    if (d.action === undefined || d.action === ReplanAction.SKIP) {
      if (d.targetId === undefined) {
        this.intentPreview = d.note.length > 0 ? d.note : '没听懂，换个说法再试';
        return;
      }
      if (d.skipRemaining === true) {
        this.previewOutcome(day, SkipPlanner.skipRemaining(day, nowMin));
      } else {
        this.previewOutcome(day, SkipPlanner.plan(day, d.targetId, nowMin, null));
      }
      return;
    }
    if (d.action === ReplanAction.SHIFT) {
      const minutes: number = d.shiftMinutes === undefined ? 30 : d.shiftMinutes;
      this.previewOutcome(day, SkipPlanner.shiftRemaining(day, nowMin, minutes));
      return;
    }
    if (d.action === ReplanAction.ADD) {
      this.intentPreview = d.note.length > 0 ? d.note : '好的，去选要加的站';
      this.intentOpenAdd = true;
      this.intentReady = true;
      return;
    }
    if (d.action === ReplanAction.REPLACE) {
      const newStop: Activity | undefined =
        candidates.find((c: Activity): boolean => c.id === d.newStopId);
      if (d.targetId === undefined || newStop === undefined) {
        this.intentPreview = '没听懂要换哪一站，换个说法再试';
        return;
      }
      this.previewOutcome(day, SkipPlanner.planWithReplacement(day, d.targetId, newStop));
      return;
    }
    this.intentPreview = '这句还没接住，换个说法再试';
  }

  private previewOutcome(day: TripDay, outcome: ReplanOutcome): void {
    const changed: boolean = outcome.changed === true;
    this.intentOutcome = changed ? outcome : null;
    this.intentSnapshot = changed ? SkipPlanner.cloneDay(day) : null;
    this.intentPreview = outcome.note;
    this.intentReady = changed;
  }

  /** 云函数未配置/失败时的本地规则：只做最确定的三种意图，不猜细节 */
  private previewLocalIntent(day: TripDay, text: string, candidates: Activity[],
    nowMin: number): void {
    if (text.indexOf('累') >= 0 || text.indexOf('酒店') >= 0 || text.indexOf('不想') >= 0 ||
      text.indexOf('结束') >= 0) {
      this.previewOutcome(day, SkipPlanner.skipRemaining(day, nowMin));
      return;
    }
    if (text.indexOf('加') >= 0 || text.indexOf('再来') >= 0) {
      this.intentPreview = '好的，去选要加的站';
      this.intentOpenAdd = true;
      this.intentReady = true;
      return;
    }
    if (text.indexOf('换') >= 0 || text.indexOf('室内') >= 0) {
      const next: DayStop | null = this.next;
      const museum: Activity | undefined = candidates.find((c: Activity): boolean =>
        c.title.indexOf('博览园') >= 0 || c.title.indexOf('规划馆') >= 0 || c.title.indexOf('会址') >= 0);
      if (next !== null && !next.isMeal && museum !== undefined) {
        this.previewOutcome(day, SkipPlanner.planWithReplacement(day, next.key, museum));
        return;
      }
    }
    this.intentPreview = '这句需要联网理解；也可以直接点「加一站」或「不去下一站」';
  }

  private async confirmIntent(): Promise<void> {
    if (this.intentBusy) {
      return;
    }
    if (this.intentOpenAdd) {
      this.showIntent = false;
      this.intentReady = false;
      this.intentOpenAdd = false;
      this.openAddSheet();
      return;
    }
    const trip: Trip | null = this.trip;
    const snapshot: TripDay | null = this.intentSnapshot;
    const outcome: ReplanOutcome | null = this.intentOutcome;
    if (trip === null || snapshot === null || outcome === null || outcome.changed !== true) {
      this.toast('还没有可执行的改动');
      return;
    }
    this.showIntent = false;
    this.intentReady = false;
    await this.commitDay(trip, snapshot, outcome);
  }

  @Builder
  intentSheet() {
    Column({ space: SpaceTokens.sm }) {
      Text('说一句，改行程')
        .fontSize(TypeTokens.title.size)
        .fontWeight(700)
        .fontFamily(TypeTokens.title.family)
        .fontColor(ColorTokens.ink)
        .margin({ top: SpaceTokens.lg })
      Text('例如：我累了想回酒店 / 换个室内的 / 加一站')
        .fontSize(TypeTokens.caption.size)
        .fontColor(ColorTokens.muted)
      TextInput({ placeholder: '说说你现在想怎么改', text: this.intentText })
        .fontSize(TypeTokens.body.size)
        .height(48)
        .maxLength(200)
        .borderRadius(RadiusTokens.card)
        .backgroundColor(ColorTokens.surfacePanel)
        .onChange((v: string): void => {
          this.intentText = v;
          this.intentReady = false;
          this.intentPreview = '';
        })
      if (this.intentBusy) {
        Row({ space: SpaceTokens.xs }) {
          LoadingProgress().width(18).height(18).color(ColorTokens.primary)
          Text('正在理解…')
            .fontSize(TypeTokens.caption.size)
            .fontColor(ColorTokens.muted)
        }
      }
      if (this.intentPreview.length > 0) {
        Text(this.intentPreview)
          .fontSize(TypeTokens.small.size)
          .fontColor(ColorTokens.body)
          .width('100%')
          .padding(SpaceTokens.sm)
          .borderRadius(RadiusTokens.reason)
          .backgroundColor(ColorTokens.surfacePanel)
      }
      Row({ space: SpaceTokens.sm }) {
        YoujingButton({
          variant: YoujingButtonVariant.SECONDARY,
          label: '取消',
          buttonWidth: 120,
          onAction: (): void => {
            this.closeIntent();
          }
        })
        Column() {
          YoujingButton({
            variant: YoujingButtonVariant.PRIMARY,
            label: this.intentReady ? '确认执行' : '理解并预演',
            fullWidth: true,
            disabled: this.intentBusy,
            onAction: (): void => {
              if (this.intentReady) {
                this.confirmIntent();
              } else {
                this.prepareIntent();
              }
            }
          })
        }
        .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: SpaceTokens.sm })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
    .padding({ left: SpaceTokens.base, right: SpaceTokens.base, bottom: SpaceTokens.lg })
    .backgroundColor(ColorTokens.canvas)
  }

  @Builder
  addSheet() {
    Column() {
      Text('加一站')
        .fontSize(TypeTokens.title.size)
        .fontWeight(700)
        .fontFamily(TypeTokens.title.family)
        .fontColor(ColorTokens.ink)
        .margin({ top: SpaceTokens.lg, bottom: SpaceTokens.xxs })
      Text('从本城景点库里补一站，接在今日末尾；活动超过 8 小时就不加')
        .fontSize(TypeTokens.caption.size)
        .fontColor(ColorTokens.muted)
        .margin({ bottom: SpaceTokens.sm })

      List({ space: SpaceTokens.xxs }) {
        if (this.addCandidates.length === 0) {
          ListItem() {
            Column({ space: SpaceTokens.xs }) {
              SymbolGlyph($r('sys.symbol.checkmark_circle'))
                .fontSize(IconSizes.display)
                .fontColor([ColorTokens.muted])
              Text('本城景点都已在这天里了')
                .fontSize(TypeTokens.small.size)
                .fontColor(ColorTokens.muted)
            }
            .width('100%')
            .padding({ top: SpaceTokens.lg, bottom: SpaceTokens.lg })
            .justifyContent(FlexAlign.Center)
          }
        }
        ForEach(this.addCandidates, (spot: Spot) => {
          ListItem() {
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
            .accessibilityText(`加入 ${spot.name}，${spot.district}`)
            .onClick(() => {
              this.performAdd(spot);
            })
          }
        }, (spot: Spot): string => `add-${spot.id}`)
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
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
   * 用户确认「顺延 N 分钟」：确定性算术，不调云函数/LLM。
   * 与跳过共用快照/撤销/落库/卡片刷新链路。
   */
  private async performShift(deltaMin: number): Promise<void> {
    const trip: Trip | null = this.trip;
    const day: TripDay | null = this.day;
    if (trip === null || day === null || !this.isToday || this.replanning) {
      return;
    }
    const nowMin: number = DateUtils.minutesOf(clockNow());
    const snapshot: TripDay = SkipPlanner.cloneDay(day);
    this.replanning = true;
    this.notice = '正在顺延今日剩余行程…';
    const outcome: ReplanOutcome = SkipPlanner.shiftRemaining(day, nowMin, deltaMin);
    if (outcome.changed !== true) {
      this.replanning = false;
      this.notice = '';
      this.toast(outcome.note);
      return;
    }
    await this.commitDay(trip, snapshot, outcome);
  }

  /** 落库 + 快照 + 结果提示：跳过与顺延共用 */
  private async commitDay(trip: Trip, snapshot: TripDay, outcome: ReplanOutcome): Promise<void> {
    const updated: Trip = this.replaceDay(trip, outcome.day);
    try {
      await TripDao.saveTrip(this.ctx(), updated);
    } catch (err) {
      this.replanning = false;
      this.notice = '保存失败，行程未改动';
      Logger.error('Ui.OnTrip', `保存重排失败: ${(err as Error).message}`);
      return;
    }
    this.skipSnapshot = snapshot;
    this.skipSnapshotTripId = trip.id;
    this.skipSnapshotDayIndex = outcome.day.dayIndex;
    this.trip = updated;
    this.replanning = false;
    this.notice = outcome.note;
    this.canUndo = true;
    await this.reload();
    this.refreshWidget();
  }

  /** 信号动作的目标反查：找不到说明界面已陈旧，绝不按 key 猜站 */
  private stopOf(key: string): DayStop | null {
    for (const s of this.stops) {
      if (s.key === key) {
        return s;
      }
    }
    return null;
  }

  /** 撤销 = 把跳过前快照写回该日并落库；快照只在本进程、只保留一层 */
  private async undoSkip(): Promise<void> {
    const trip: Trip | null = this.trip;
    // 伴随跨天挪移：整程快照优先（区别于单日 skipSnapshot）
    if (trip !== null && this.companionUndoTrip !== null && this.companionUndoTrip.id === trip.id) {
      const restore: Trip = this.companionUndoTrip;
      this.companionUndoTrip = null;
      try {
        await TripDao.saveTrip(this.ctx(), restore);
      } catch (err) {
        this.notice = '撤销失败，行程未改动';
        Logger.error('Ui.OnTrip', `伴随撤销失败: ${(err as Error).message}`);
        return;
      }
      this.trip = restore;
      this.canUndo = false;
      this.notice = '已撤销挪移';
      await this.reload();
      this.refreshWidget();
      return;
    }
    const snapshot: TripDay | null = this.skipSnapshot;
    if (trip === null || snapshot === null || this.skipSnapshotTripId !== trip.id) {
      this.toast('没有可撤销的重排');
      return;
    }
    if (this.replanning) {
      return;
    }
    this.replanning = true;
    this.notice = '正在撤销…';
    const updated: Trip = this.replaceDay(trip, SkipPlanner.cloneDay(snapshot));
    try {
      await TripDao.saveTrip(this.ctx(), updated);
    } catch (err) {
      this.replanning = false;
      this.notice = '撤销失败，行程未改动';
      Logger.error('Ui.OnTrip', `撤销失败: ${(err as Error).message}`);
      return;
    }
    this.trip = updated;
    this.clearSkipState();
    this.replanning = false;
    this.notice = '已撤销重排';
    await this.reload();
    this.refreshWidget();
  }

  /** 用改写后的整天替换 trip.days 的同一 dayIndex；其余天原引用不动 */
  private replaceDay(trip: Trip, day: TripDay): Trip {
    const days: TripDay[] = [];
    for (const d of trip.days) {
      days.push(d.dayIndex === day.dayIndex ? day : d);
    }
    const updated: Trip = {
      id: trip.id, destination: trip.destination, startDate: trip.startDate, endDate: trip.endDate,
      people: trip.people, budget: trip.budget, style: trip.style, overview: trip.overview,
      days: days, tips: trip.tips
    };
    return updated;
  }

  private clearSkipState(): void {
    this.skipSnapshot = null;
    this.skipSnapshotTripId = '';
    this.skipSnapshotDayIndex = 0;
    this.canUndo = false;
  }

  private refreshWidget(): void {
    WidgetSync.refreshAll(this.ctx()).catch((err: Error): void => {
      Logger.warn('Ui.OnTrip', `卡片刷新失败: ${err.message}`);
    });
  }

  /** 喂给 NodeOwe 的当日节点表（`buildStops` 已按 sortMin 升序排好） */
  private oweItemsOf(stops: DayStop[]): OweItem[] {
    const items: OweItem[] = [];
    for (const st of stops) {
      // 交通与住宿不参与「欠」：它们既不能跳过也不是顺延目标，
      // 把欠站落在住宿上会让建议条整个哑掉（真机实测过这个失效模式）。
      if (st.category === ActivityCategory.TRANSPORT || st.category === ActivityCategory.HOTEL) {
        continue;
      }
      const item: OweItem = { key: st.key, startMin: st.sortMin };
      items.push(item);
    }
    return items;
  }

  /** 一餐的稳定身份：一天一餐次唯一，打卡与 ForEach key 都用它，不新增数据库列 */
  private mealKey(dayIndex: number, type: MealType): string {
    return `meal-${dayIndex}-${type}`;
  }

  /** 无时刻餐次的排位档位（只用于排序，不进界面） */
  private mealSlot(type: MealType): number {
    if (type === MealType.BREAKFAST) {
      return 8 * 60;
    }
    return type === MealType.LUNCH ? 12 * 60 : 18 * 60;
  }

  private mealLabel(type: MealType): string {
    if (type === MealType.BREAKFAST) {
      return '早餐';
    }
    return type === MealType.LUNCH ? '午餐' : '晚餐';
  }

  /** 活动 ∪ 餐次，按时间并排 */
  private buildStops(day: TripDay): DayStop[] {
    const stops: DayStop[] = [];
    for (const a of day.activities) {
      // 跳过改写出的「空闲」不是可打卡站点；它仍是排程锚点（SkipPlanner 读原 day）
      if (SkipPlanner.isSkippedMarker(a)) {
        continue;
      }
      const t = a.transport;
      stops.push({
        key: a.id, time: a.time, sortMin: Math.max(0, DateUtils.minutesOf(a.time)), title: a.title,
        endTime: a.endTime, note: a.note === undefined ? '' : a.note,
        place: a.address.length > 0 ? a.address : a.location,
        lat: a.latitude, lng: a.longitude, isMeal: false, kind: '', cost: 0,
        category: a.category,
        status: a.status, transportMode: t === undefined ? '' : t.mode,
        transportMin: t === undefined ? 0 : t.duration,
        transportDetail: t === undefined ? '' : t.detail, hasTransport: t !== undefined
      });
    }
    for (const m of day.meals) {
      const shown: string = m.time === undefined ? '' : m.time;
      stops.push({
        key: this.mealKey(day.dayIndex, m.type), time: shown,
        sortMin: shown.length > 0 ? Math.max(0, DateUtils.minutesOf(shown)) : this.mealSlot(m.type),
        title: m.name.length > 0 ? m.name : this.mealLabel(m.type),
        kind: this.mealLabel(m.type), endTime: '', note: '',
        place: m.location, lat: 0, lng: 0, isMeal: true, cost: m.estimatedCost,
        category: null,
        status: null, transportMode: '', transportMin: 0, transportDetail: '',
        hasTransport: false
      });
    }
    stops.sort((x: DayStop, y: DayStop): number => x.sortMin - y.sortMin);
    return stops;
  }

  /** 今天落在行程区间内就取那天；不在区间（提前查看/回放）取第一天 */
  private pickDay(trip: Trip): TripDay | null {
    if (trip.days.length === 0) {
      return null;
    }
    const today: string = DateUtils.todayIso();
    for (const d of trip.days) {
      if (d.date === today) {
        return d;
      }
    }
    return trip.days[0];
  }

  /**
   * 今日进度行：已打卡的 + **当前这一站（还没打卡）**。
   *
   * 底稿帧（屏15 fc4e40cd）在这一节里排的是「07:40 早餐 已打卡 / 08:30 渡月桥 已打卡 /
   * 09:00 竹林 进行中」——三行两态，`check-status-ongoing` 有独立样式（时间与标签都走
   * `#0066CC`、不带对勾）。所以这一节的语义是"今天走到哪了"，不是字面只有已打卡；
   * 分组头因此按真值两态走（有打卡行=帧的原句「今日已打卡」，一行都没打卡=「今日进度」），
   * 帧的原句只在它成立的那个态里保留。
   * 金额取挂在该节点上的开销合计。
   */
  private buildRows(marks: Record<string, number>): Promise<Record<string, number>> {
    const trip: Trip | null = this.trip;
    if (trip === null) {
      return Promise.resolve<Record<string, number>>({});
    }
    const day: TripDay | null = this.pickDay(trip);
    const owedKey: string = this.owedKey;
    return ExpenseDao.sumGroupedByActivity(this.ctx(), trip.id)
      .then((sums: Record<string, number>): Record<string, number> => {
        const list: CheckedRow[] = [];
        if (day !== null) {
          for (const st of this.buildStops(day)) {
            const checked: boolean = marks[st.key] !== undefined;
            const ongoing: boolean = !checked && st.key === owedKey;
            if (!checked && !ongoing) {
              continue;
            }
            const paid: number | undefined = sums[st.key];
            const shown: number | undefined = paid === undefined ? (st.isMeal && st.cost > 0 ? st.cost : undefined) : paid;
            const row: CheckedRow = {
              // 无时刻的餐次拿餐次标签占住时间槽（不编 08:00 假时刻），名字列留给店名
              time: st.time.length > 0 ? st.time : st.kind,
              name: st.title,
              amount: shown === undefined ? '' : MoneyText.yuan(shown),
              ongoing: ongoing
            };
            list.push(row);
          }
        }
        this.rows = list;
        return sums;
      });
  }

  /** 只有「今天 + 当前站有坐标」才订阅前台定位；其余情况一律退订并清状态 */
  private syncArrivalWatcher(): void {
    this.syncGeofences();
    const cur: DayStop | null = this.current;
    const need: boolean = this.isToday && cur !== null && Geo.usable(cur.lat, cur.lng);
    if (!need) {
      this.watcher.stop();
      this.watcherActive = false;
      this.watcherStarting = false;
      this.lastFix = null;
      this.arrivalText = '';
      this.arrived = false;
      this.refreshSignal();
      return;
    }
    if (this.watcherActive || this.watcherStarting) {
      this.refreshArrival();
      this.refreshSignal();
      this.refreshCompanion();
      return;
    }
    this.watcherStarting = true;
    this.watcher.start(this.ctx(), (fix: LocationFix): void => {
      this.lastFix = fix;
      this.refreshArrival();
      this.refreshSignal();
      this.refreshCompanion();
    }).then((ok: boolean): void => {
      this.watcherStarting = false;
      this.watcherActive = ok;
      if (ok) {
        this.refreshArrival();
        this.refreshSignal();
        this.refreshCompanion();
      }
    });
  }

  /** 今天才注册围栏；同一天只注册一次，注册失败下次 reload 会重试 */
  private syncGeofences(): void {
    const day: TripDay | null = this.day;
    if (!this.isToday || day === null) {
      this.geofence.stop();
      this.geofenceDayKey = '';
      return;
    }
    const key: string = day.date;
    if (this.geofence.isActive() && this.geofenceDayKey === key) {
      return;
    }
    if (this.geofence.isStarting()) {
      return;
    }
    this.geofenceDayKey = key;
    const nowMin: number = DateUtils.minutesOf(clockNow());
    this.geofence.start(this.ctx(), day, nowMin, (spec: FenceSpec): void => {
      this.onGeofenceEnter(spec);
    }).then((count: number): void => {
      if (count === 0) {
        Logger.info('Ui.OnTrip', '到站围栏未注册（AGC 未开通或无权限），保留前台定位');
      }
    }).catch((err: Error): void => {
      Logger.warn('Ui.OnTrip', `到站围栏启动失败: ${err.message}`);
    });
  }

  /** 系统围栏到站：不自动打卡，只把「可以打卡了」推到 hero/提示条，用户确认后落库 */
  private onGeofenceEnter(spec: FenceSpec): void {
    if (this.disposed) {
      return;
    }
    this.arrived = true;
    this.arrivalText = `已进入「${spec.title}」围栏`;
    this.notice = `已到「${spec.title}」，可以打卡了`;
    this.toast(`已到站：${spec.title}`);
    const day: TripDay | null = this.day;
    if (day !== null) {
      const act: Activity | undefined =
        day.activities.find((a: Activity): boolean => a.id === spec.activityId);
      if (act !== undefined) {
        ArrivalNotice.publishForStop(day, act).catch((err: Error): void => {
          Logger.warn('Ui.OnTrip', `到站通知失败: ${err.message}`);
        });
      }
    }
  }

  /** 用最近一次前台定位刷新 hero 的到站状态；没有定位就不出这一行 */
  private refreshArrival(): void {
    const cur: DayStop | null = this.current;
    const fix: LocationFix | null = this.lastFix;
    if (cur === null || fix === null || !Geo.usable(cur.lat, cur.lng)) {
      this.arrivalText = '';
      this.arrived = false;
      return;
    }
    const from: GeoPoint = { latitude: fix.latitude, longitude: fix.longitude };
    const to: GeoPoint = { latitude: cur.lat, longitude: cur.lng };
    const distance: number = Geo.distanceM(from, to);
    const text: string = Geo.distanceText(distance);
    if (text.length === 0) {
      this.arrivalText = '';
      this.arrived = false;
      return;
    }
    this.arrived = Geo.arrived(distance);
    this.arrivalText = this.arrived ? `已到站 · 距站点 ${text}` : `距此站 ${text}`;
  }

  /**
   * 伴随助手·规划外到访：每次定位 fix 比对计划 vs 现实。
   * 停留够 + 落在规划外已知景点 + 有后果 → 浮出请示卡（CompanionStore）。
   * 无后果安静吸收；同卡去重；路过（停留不够）不打扰。
   */
  private refreshCompanion(): void {
    const day: TripDay | null = this.day;
    const fix: LocationFix | null = this.lastFix;
    if (day === null || fix === null || !this.isToday) {
      return;
    }
    const point: GeoPoint = { latitude: fix.latitude, longitude: fix.longitude };
    const nowMs: number = Date.now();
    const candidate: Spot | null = CompanionEngine.matchUnplannedSpot(point, day, this.citySpots);
    if (candidate === null) {
      this.unplannedSpotName = '';
      this.unplannedSinceMs = 0;
      return;
    }
    if (candidate.name !== this.unplannedSpotName) {
      this.unplannedSpotName = candidate.name;
      this.unplannedSinceMs = nowMs;
    }
    const dwellMin: number = (nowMs - this.unplannedSinceMs) / 60000;
    const nowMin: number = DateUtils.minutesOf(clockNow());
    const input: UnplannedInput | null =
      CompanionEngine.detectUnplanned(point, day, this.citySpots, nowMin, dwellMin);
    if (input === null) {
      return;
    }
    const prompt: CompanionPrompt | null = CompanionEngine.unplannedArrival(input, this.companionPrefs);
    if (prompt === null || prompt.id === this.shownUnplannedId) {
      return;
    }
    this.shownUnplannedId = prompt.id;
    CompanionStore.show(prompt);
  }

  /**
   * 伴随选项执行（浮层经 CompanionStore 委托到此）：
   * move_tomorrow 真正跨天挪移 + 整程快照可撤销；其余选项是「我来处理」类，确认即可、不改行程。
   */
  private async handleCompanionAction(action: CompanionAction): Promise<void> {
    const trip: Trip | null = this.trip;
    const day: TripDay | null = this.day;
    if (trip === null || day === null || this.replanning) {
      return;
    }
    if (action.kind !== 'move_tomorrow') {
      this.notice = '好的，按你说的来';
      return;
    }
    let arrIdx: number = -1;
    for (let i = 0; i < trip.days.length; i++) {
      if (trip.days[i].dayIndex === day.dayIndex) {
        arrIdx = i;
        break;
      }
    }
    const updated: Trip | null = CompanionEngine.moveToTomorrow(trip, arrIdx, action.targetId);
    if (updated === null) {
      this.toast('明天不在行程里，挪不了');
      return;
    }
    this.companionUndoTrip = trip;
    try {
      await TripDao.saveTrip(this.ctx(), updated);
    } catch (err) {
      this.companionUndoTrip = null;
      this.notice = '保存失败，行程未改动';
      Logger.error('Ui.OnTrip', `伴随挪移保存失败: ${(err as Error).message}`);
      return;
    }
    this.trip = updated;
    this.canUndo = true;
    this.notice = '已挪到明天，可撤销';
    await this.reload();
    this.refreshWidget();
  }

  /** 今日天气：命中缓存立即返回；请求/解析失败静默（不出天气行，不阻塞页面） */
  private refreshWeather(day: TripDay | null): void {
    if (day === null || !this.isToday) {
      this.clearWeather();
      this.refreshSignal();
      return;
    }
    WeatherStore.load(this.ctx(), day).then((weather: WeatherDay | null): void => {
      if (this.disposed) {
        return;
      }
      this.weather = weather;
      if (weather === null) {
        this.weatherText = '';
        this.weatherAdvice = '';
      } else {
        const brief: WeatherBrief = WeatherAdvisor.brief(weather);
        this.weatherText = brief.text;
        this.weatherAdvice = brief.advice;
      }
      this.refreshSignal();
    }).catch((err: Error): void => {
      if (this.disposed) {
        return;
      }
      Logger.warn('Ui.OnTrip', `天气读取失败: ${err.message}`);
      this.clearWeather();
      this.refreshSignal();
    });
  }

  private clearWeather(): void {
    this.weather = null;
    this.weatherText = '';
    this.weatherAdvice = '';
  }

  /** 被动建议：一次只出一条；同类被「忽略」后 30 分钟内不再弹，换类立即重判 */
  private refreshSignal(): void {
    const day: TripDay | null = this.day;
    if (day === null || !this.isToday) {
      this.clearSignal();
      return;
    }
    const fix: LocationFix | null = this.lastFix;
    let point: GeoPoint | null = null;
    if (fix !== null) {
      const p: GeoPoint = { latitude: fix.latitude, longitude: fix.longitude };
      point = p;
    }
    const nowMin: number = DateUtils.minutesOf(clockNow());
    const ctx: SignalContext = {
      isToday: this.isToday,
      nowMin: nowMin,
      fix: point,
      checkedIds: Object.keys(this.marks),
      // 建议条说的是「你还欠哪一站」，与 hero 的「现在该在哪」不是同一个问题，
      // 所以喂 owedKey 而不是 current 的键名。两条规则各自只有一处实现。
      currentKey: this.owedKey,
      weather: this.weather
    };
    const suggestion: TripSuggestion | null = TripSignals.suggest(day, ctx);
    if (suggestion === null) {
      this.clearSignal();
      return;
    }
    if (this.mutedKind !== null && suggestion.kind === this.mutedKind &&
      nowMin - this.mutedAtMin < SIGNAL_MUTE_MIN) {
      this.clearSignal();
      return;
    }
    this.signal = suggestion;
    this.signalTitle = suggestion.title;
    this.signalDetail = suggestion.detail;
    this.signalLabel = suggestion.actionLabel;
  }

  private clearSignal(): void {
    this.signal = null;
    this.signalTitle = '';
    this.signalDetail = '';
    this.signalLabel = '';
  }

  private muteSignal(): void {
    const s: TripSuggestion | null = this.signal;
    if (s !== null) {
      this.mutedKind = s.kind;
      this.mutedAtMin = DateUtils.minutesOf(clockNow());
    }
    this.clearSignal();
  }

  /** 建议条唯一动作入口：顺延走确定性排程，跳过复用既有重排链路 */
  private runSignalAction(): void {
    const s: TripSuggestion | null = this.signal;
    if (s === null) {
      return;
    }
    this.mutedKind = null;
    this.mutedAtMin = -1;
    if (s.action === SignalAction.SHIFT) {
      this.performShift(s.deltaMin);
      return;
    }
    this.performSkip(s.targetId);
  }

  /**
   * 到站凭证：只有「当前已判定到站」才给。没到站照样能打卡（原来就有这个按钮），
   * 但那一笔按手动打卡记，不给坐标——行后勋章按 source 区分。
   */
  private evidenceNow(cur: DayStop): CheckinEvidence | null {
    const fix: LocationFix | null = this.lastFix;
    if (!this.arrived || fix === null || !Geo.usable(cur.lat, cur.lng)) {
      return null;
    }
    const from: GeoPoint = { latitude: fix.latitude, longitude: fix.longitude };
    const to: GeoPoint = { latitude: cur.lat, longitude: cur.lng };
    const distance: number = Geo.distanceM(from, to);
    if (distance < 0) {
      return null;
    }
    const evidence: CheckinEvidence = {
      latitude: fix.latitude, longitude: fix.longitude, accuracyM: fix.accuracyM, distanceM: distance
    };
    return evidence;
  }

  private toggleCheckin(): void {
    const cur: DayStop | null = this.current;
    const trip: Trip | null = this.trip;
    if (cur === null || trip === null) {
      this.toast('当前无节点');
      return;
    }
    if (this.checkinBusy) {
      return;
    }
    this.checkinBusy = true;
    const target: boolean = !this.checkedIn;
    const evidence: CheckinEvidence | null = target ? this.evidenceNow(cur) : null;
    CheckinDao.set(this.ctx(), trip.id, cur.key, target, evidence).then((): void => {
      this.checkinBusy = false;
      this.checkedIn = target;
      this.reload();
      if (target && !cur.isMeal) {
        // 活动打卡才可能收章：餐次没有 activity 行，联表取不到，不为它编一枚
        this.offerBadge(trip, cur);
        return;
      }
      this.toast(target ? (evidence === null ? `已打卡 ${cur.title}` : `已到站打卡 ${cur.title}`) : '已取消打卡');
    }).catch((err: Error) => {
      this.checkinBusy = false;
      Logger.error('Ui.OnTrip', `打卡失败: ${err.message}`);
      this.toast('打卡失败');
    });
  }

  /**
   * 打卡完成后的收章判定：只有「这一笔就是这枚章的首次收下」才弹窗。
   * 同一景点重复到访（同名同城已合并成一枚）不再打扰，只留一条打卡提示。
   */
  private offerBadge(trip: Trip, cur: DayStop): void {
    BadgeDao.listMine(this.ctx()).then((rows: BadgeRecord[]): void => {
      if (this.disposed) {
        return;
      }
      const groups: BadgeGroup[] = buildBadgeBoard(rows);
      const badge: Badge | null = findBadge(groups, trip.destination, cur.title);
      if (badge === null || badge.firstCheckinId !== `${trip.id}:${cur.key}`) {
        this.toast(`已打卡 ${cur.title}`);
        return;
      }
      this.openBadgeDialog(badge, badgeTotal(groups));
    }).catch((err: Error): void => {
      Logger.error('Ui.OnTrip', `勋章读取失败: ${err.message}`);
      this.toast(`已打卡 ${cur.title}`);
    });
  }

  private openBadgeDialog(badge: Badge, total: number): void {
    const controller: CustomDialogController = new CustomDialogController({
      builder: BadgeEarnedDialog({
        spotName: badge.spotName,
        city: badge.city,
        sourceLabel: badgeSourceText(badge),
        total: total,
        onViewWall: (): void => {
          this.closeBadgeDialog();
          this.pathStack.pushPath({ name: 'Badges' });
        },
        onDismiss: (): void => {
          this.closeBadgeDialog();
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      // 点遮罩/返回键关掉时也要清引用，否则下次 aboutToDisappear 会去关一个已关的弹窗
      cancel: (): void => {
        this.badgeDialog = null;
      }
    });
    this.badgeDialog = controller;
    controller.open();
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1500 });
  }

  private heroMeta(): string {
    const cur: DayStop | null = this.current;
    if (cur === null) {
      return '今日暂无安排';
    }
    if (cur.isMeal) {
      const head: string = cur.time.length > 0 ? `${cur.time} · ${cur.kind}` : cur.kind;
      return cur.cost > 0 ? `${head} · 预估 ${MoneyText.yuan(cur.cost)}` : head;
    }
    // 分钟数原样打出来是「已过 162分钟」——用户得自己做除法；过 1 小时就拆成时/分
    // 分钟数原样打出来是「已过 162分钟」——用户得自己做除法；过 1 小时就拆成时/分
    // 单位间距全仓统一走 TimeText/DurationCn 的紧凑写法（「5小时」而不是「5 小时」）
    return `${cur.time} 开始 · 建议 ${stayText(cur.time, cur.endTime)} · 已过 ${DurationCn.text(this.elapsedMin)}`;
  }

  private progressPct(): number {
    return Math.max(1, Math.min(100, Math.round((this.elapsedMin / Math.max(1, this.totalMin)) * 100)));
  }

  private nextSlotLabel(): string {
    const nx: DayStop | null = this.next;
    if (nx === null) {
      return '';
    }
    return nx.time.length > 0 ? nx.time : nx.kind;
  }

  /**
   * 下一站的类别。`DayStop` 上没有 category——餐次靠 `kind` 非空识别
   * （活动那份 `kind` 恒为空串），所以这里按 kind 判，不猜字段。
   */
  private nextCategory(): ActivityCategory {
    const nx: DayStop | null = this.next;
    if (nx === null) {
      return ActivityCategory.SIGHT;
    }
    return nx.kind.length > 0 ? ActivityCategory.FOOD : ActivityCategory.SIGHT;
  }

  private nextTitle(): string {
    const next: DayStop | null = this.next;
    return next === null ? '' : next.title;
  }

  private nextNeedsBooking(): boolean {
    const next: DayStop | null = this.next;
    return next !== null && next.status !== null && (next.status === ActivityStatus.NOT_BOOKED ||
      next.status === ActivityStatus.PENDING || next.status === ActivityStatus.FULL);
  }

  private nextMeta(): string {
    const next: DayStop | null = this.next;
    if (next === null) {
      return '';
    }
    if (next.isMeal) {
      // 一餐没有"停留建议"（模型不给 endTime），只报地点与预估，不编时长
      const cost: string = next.cost > 0 ? ` ${MoneyText.yuan(next.cost)}` : '';
      return `${next.place.length > 0 ? `${next.place}${cost}` : `预估${cost}`}`;
    }
    return `建议停留 ${stayText(next.time, next.endTime)} · ${next.place}`;
  }

  @Builder
  noticeBar() {
    Row({ space: SpaceTokens.xs }) {
      Text(this.notice)
        .fontSize(TypeTokens.caption.size)
        .fontWeight(450)
        .fontColor(ColorTokens.body)
        .layoutWeight(1)
      if (this.canUndo && !this.replanning) {
        YoujingButton({
          variant: YoujingButtonVariant.TEXT,
          label: '撤销',
          buttonWidth: 72,
          onAction: (): void => {
            this.undoSkip();
          }
        })
      }
    }
    .width('100%')
    .padding(SpaceTokens.base)
    .borderRadius(RadiusTokens.card)
    .backgroundColor(ColorTokens.surfaceElevated)
  }

  @Builder
  signalBar() {
    // 这一屏已经有 hero 的「记一笔费用」实心主按钮（禁令 1：一屏只许一个），
    // 所以建议动作走 SECONDARY，「忽略」走 TEXT。
    Column() {
      Text(this.signalTitle)
        .fontSize(TypeTokens.small.size)
        .fontWeight(600)
        .fontColor(ColorTokens.warning)
        .fontFeature("'tnum' on")
      Text(this.signalDetail)
        .fontSize(TypeTokens.caption.size)
        .fontWeight(450)
        .fontColor(ColorTokens.body)
        .fontFeature("'tnum' on")
        .margin({ top: SpaceTokens.xxs })
      Row({ space: SpaceTokens.xs }) {
        YoujingButton({
          variant: YoujingButtonVariant.SECONDARY,
          label: this.signalLabel,
          buttonWidth: 150,
          onAction: (): void => {
            this.runSignalAction();
          }
        })
        YoujingButton({
          variant: YoujingButtonVariant.TEXT,
          label: '忽略',
          buttonWidth: 72,
          onAction: (): void => {
            this.muteSignal();
          }
        })
      }
      .margin({ top: SpaceTokens.xs })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(SpaceTokens.base)
    .borderRadius(RadiusTokens.card)
    .backgroundColor(ColorTokens.surfaceElevated)
  }

  /** 这一节里是否真有打卡记录（只有「进行中」占位行时不算） */
  private hasCheckedIn(): boolean {
    return this.rows.some((r: CheckedRow): boolean => !r.ongoing);
  }

  @Builder
  groupHeader() {
    // 材质豁免：这条吸顶行住在卡片内（父 List 已 canvas 实色 + 圆角 clip），不是契约 §1024
    // 指的那条满宽"日分隔"玻璃栏；给它上材质等于在卡片里开玻璃，违 §1149。
    // 但它确实会压在滚动行上（sticky 无底板=文字叠文字），所以自带一张与卡片同色的实底板，
    // 带高照有据钉成一条、不靠 padding 凑（PublishTagPanel.ets:83-86 height + alignItems Center）。
    // 标题按真值走：底稿帧那句「今日已打卡」的前提是这一节里确有打卡行；
    // 一行都没打卡时整节只剩「进行中」，标题再说「已打卡」就是空口白话（2026-11-04 真机实拍）。
    Row() {
      Text(this.hasCheckedIn() ? '今日已打卡' : '今日进度')
        .fontSize(TypeTokens.overline.size)
        .fontWeight(600)
        .fontColor(ColorTokens.muted)
    }
    .width('100%')
    .height(LayoutTokens.stickyHeaderHeight)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(ColorTokens.canvas)
  }

  @Builder
  checkRow(row: CheckedRow) {
    Row() {
      Text(row.time)
        .fontSize(TypeTokens.time.size)
        .fontWeight(600)
        .fontColor(row.ongoing ? ColorTokens.primary : ColorTokens.muted)
        .fontFeature("'tnum' on")
        .width(LayoutTokens.itineraryTimeGutter)
      Text(row.name)
        .fontSize(TypeTokens.small.size)
        .fontWeight(row.ongoing ? 600 : 400)
        .fontColor(ColorTokens.ink)
        .layoutWeight(1)
      if (row.amount.length > 0) {
        Text(row.amount)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.body)
          .fontFeature("'tnum' on")
          .margin({ right: SpaceTokens.xs })
      }
      Text(row.ongoing ? '进行中' : '已打卡')
        .fontSize(TypeTokens.overline.size)
        .fontWeight(600)
        .fontColor(row.ongoing ? ColorTokens.primary : ColorTokens.success)
      if (!row.ongoing) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(IconSizes.control)
          .fontColor([ColorTokens.success])
          .margin({ left: SpaceTokens.xxs })
      }
    }
    .width('100%')
    .padding({ top: SpaceTokens.xs, bottom: SpaceTokens.xs })
  }

  /**
   * 屏15 的标题栏。补「完整行程」这一条：
   * 从「我的」点开一条**旅行中**的行程只会落到这一屏，而它原来没有任何入口
   * 能进行程详情/编辑——用户点开就"困"在打卡页里（本轮走链复拍屏9 时撞上）。
   */
  private titleBarOptions(): HdsNavigationTitleBarOptions {
    const items: Array<HdsNavigationMenuItemOptions> = [
      HdsChrome.item($r('sys.symbol.list_bullet'), '完整行程', (): void => {
        this.pathStack.pushPath({ name: 'Itinerary', param: this.tripId });
      })];
    return HdsChrome.bar({ themeTick: this.chromeThemeTick, 
      mainTitle: this.dayLabel.length > 0 ? this.dayLabel : '旅行中',
      subTitle: this.clock,
      menu: items,
      scrolled: this.barScrolled
    });
  }

  /** 绝对滚动偏移 → 顶栏磨砂开关（>0 即开，静止归零） */
  private syncBarScroll(): void {
    const y: number = this.barScroller.currentOffset().yOffset;
    const on: boolean = y > 0;
    if (on !== this.barScrolled) {
      this.barScrolled = on;
      if (!on) {
        // 偏移回到 0：HDS 在这一帧回写系统栏内容色，补设通道连发四发压住它（utils/systemBar.ets）
        requestSystemBarRefresh();
      }
    }
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
      // 官方 List：hero / 下一段 / 打卡分组各占一个 ListItem，分组头吸顶、行间交给 .divider()
      List({ space: SpaceTokens.base, scroller: this.barScroller }) {
        if (this.notice.length > 0) {
          ListItem() {
            this.noticeBar()
          }
        }
        if (this.signalTitle.length > 0 && !this.replanning) {
          ListItem() {
            this.signalBar()
          }
        }
        ListItem() {
            Column() {
              Text('当前节点')
                .fontSize(TypeTokens.overline.size)
                .fontWeight(600)
                .fontColor(ColorTokens.muted)
              Text(this.current === null ? '今日暂无安排' : this.current.title)
                .fontSize(TypeTokens.title.size)
                .fontWeight(700)
                // 帧 fc4e40cd 的当前节点名是 serif 档；ArkUI 的 fontFamily 不会随档位自动带上，
                // 只写 size/weight 就还是 sans
                .fontFamily(TypeTokens.title.family)
                .fontColor(ColorTokens.ink)
                .margin({ top: SpaceTokens.xxs })
              // heroMeta 在空态下返回的就是上面那句「今日暂无安排」——
              // 同一张卡上下印两遍（实拍确认），空态时不出这一行
              if (this.current !== null) {
                Text(this.heroMeta())
                  .fontSize(TypeTokens.caption.size)
                  .fontWeight(450)
                  .fontColor(ColorTokens.body)
                  .fontFeature("'tnum' on")
              }
              // 到站状态：拿到前台定位且当前站有坐标才出这一行，没有权限就整行不显示
              if (this.arrivalText.length > 0) {
                Text(this.arrivalText)
                  .fontSize(TypeTokens.caption.size)
                  .fontWeight(450)
                  .fontColor(this.arrived ? ColorTokens.success : ColorTokens.muted)
                  .fontFeature("'tnum' on")
                  .margin({ top: SpaceTokens.xxs })
              }
              // 今日天气（切片3 T1）：只在「今天」且取到天气时出现；有建议时追加降水窗口
              if (this.weatherText.length > 0) {
                Text(this.weatherAdvice.length > 0
                  ? `${this.weatherText} · ${this.weatherAdvice}` : this.weatherText)
                  .fontSize(TypeTokens.caption.size)
                  .fontWeight(450)
                  .fontColor(ColorTokens.muted)
                  .fontFeature("'tnum' on")
                  .margin({ top: SpaceTokens.xxs })
              }
              // 进度条只在"这一站有结束时刻"时画。一餐没有 endTime，
              // 而 progressPct() 有 Math.max(1, …) 的下限——不关掉它会被夹成满格（真机实测 1.000000）。
              if (this.totalMin > 0) {
                Progress({ value: this.progressPct(), total: 100, type: ProgressType.Linear })
                  .color(ColorTokens.primary)
                  .backgroundColor(ColorTokens.surfaceSunken)
                  .width('100%')
                  .margin({ top: SpaceTokens.sm })
                  .accessibilityText(`本程已完成 ${Math.round(this.progressPct())}%`)
              }
              if (this.current !== null && this.current.note !== undefined && this.current.note.length > 0) {
                Text(this.current.note)
                  .fontSize(TypeTokens.caption.size)
                  .fontWeight(450)
                  .fontColor(ColorTokens.warning)
                  .margin({ top: SpaceTokens.xs })
              }
              Row({ space: SpaceTokens.sm }) {
                // 今天没有节点时「完成打卡」是个没有对象的可点按钮
                if (this.current !== null) {
                  YoujingButton({
                    variant: YoujingButtonVariant.SECONDARY,
                    label: this.checkinBusy ? '打卡中…' : (this.checkedIn ? '已打卡' : '完成打卡'),
                    buttonWidth: 140,
                    disabled: this.checkinBusy,
                    onAction: (): void => {
                      this.toggleCheckin();
                    }
                  })
                }
                YoujingButton({
                  variant: YoujingButtonVariant.PRIMARY,
                  label: '记一笔费用',
                  buttonWidth: 150,
                  onAction: (): void => {
                    this.pathStack.pushPath({ name: 'Expense', param: this.tripId });
                  }
                })
              }
              .margin({ top: SpaceTokens.base })
                Text('打卡与记账只存本机，不上传服务器')
                  .fontSize(TypeTokens.overline.size)
                  .fontWeight(450)
                  .fontColor(ColorTokens.muted)
                  .margin({ top: SpaceTokens.xs })
                if (this.isToday && !this.replanning) {
                  YoujingButton({
                    variant: YoujingButtonVariant.TEXT,
                    label: '说一句，改行程',
                    fullWidth: true,
                    onAction: (): void => {
                      this.openIntent();
                    }
                  })
                    .margin({ top: SpaceTokens.xs })
                }
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding(SpaceTokens.base)
            .borderRadius(RadiusTokens.hero)
            .backgroundColor(ColorTokens.surfaceElevated)
        }

        // 下一段：真实通勤腿 + 下一节点
        if (this.next !== null) {
          ListItem() {
            Column() {
              // 没有通勤数据时整条腿不出：原来虚线段与交通图标照画，
              // 只把文字留空，实拍就是一个悬空的步行小人配一段虚线，读不出任何信息
              if (this.nextLeg.length > 0) {
              Row() {
                Column().width(LayoutTokens.itineraryTimeGutter)
                Column()
                  .width(LayoutTokens.routeLineWidth)
                  .height(LayoutTokens.transitLegHeight)
                  .border({ width: { left: LayoutTokens.routeLineWidth }, color: ColorTokens.separator, style: BorderStyle.Dashed })
                Row({ space: SpaceTokens.xxs }) {
                  // 按下一段的真实模式取图标（原来是写死的汽车，地铁/公交段会显示错图标）
                  SymbolGlyph(TransitSymbol.of(this.next.transportMode))
                    .fontSize(IconSizes.control)
                    .fontColor([ColorTokens.icon])
                  Text(this.nextLeg)
                    .fontSize(TypeTokens.caption.size)
                    .fontWeight(450)
                    .fontColor(ColorTokens.muted)
                    .fontFeature("'tnum' on")
                }
                .padding({ left: SpaceTokens.xs })
              }
              .height(LayoutTokens.transitLegHeight)
              .alignItems(VerticalAlign.Center)
              }

              Row({ space: SpaceTokens.xs }) {
                // 无时刻的餐次拿 kind（早餐/午餐/晚餐）占时间槽：
                // 列表行早就这么做（见 DayStop.kind 注释），但「下一站」这一行漏了，
                // 实拍整列时间空白、标题像飘在半空
                Text(this.nextSlotLabel())
                  .fontSize(TypeTokens.time.size)
                  .fontWeight(600)
                  .fontColor(ColorTokens.ink)
                  .fontFeature("'tnum' on")
                  .width(LayoutTokens.itineraryTimeGutter)
                // 底稿这一行左侧有节点圆环、环上下接脊线；实现里只有文字，
                // 下一站像是"飘在列表中间"。用与屏8/屏9 同一个 TimelineNode。
                Stack({ alignContent: Alignment.Top }) {
                  Column()
                    .width(LayoutTokens.routeLineWidth)
                    .height(LayoutTokens.itineraryRowMinHeight)
                    .backgroundColor(ColorTokens.surfaceSunken)
                  TimelineNode({ cat: this.nextCategory() })
                }
                .width(LayoutTokens.itineraryNodeSize)
                .height(LayoutTokens.itineraryRowMinHeight)
                Row({ space: SpaceTokens.xxs }) {
                  Text(this.nextTitle())
                    .fontSize(TypeTokens.small.size)
                    .fontWeight(600)
                    .fontColor(ColorTokens.ink)
                  if (this.nextNeedsBooking()) {
                    Text('需预约')
                      .fontSize(TypeTokens.overline.size)
                      .fontWeight(600)
                      .fontColor(ColorTokens.onPrimary)
                      .height(18)
                      .padding({ left: SpaceTokens.xxs, right: SpaceTokens.xxs })
                      .borderRadius(RadiusTokens.pill)
                      .backgroundColor(ColorTokens.warning)
                  }
                }
                .layoutWeight(1)
              }
              .width('100%')
              .padding({ top: SpaceTokens.xs, bottom: SpaceTokens.xs })

              Row({ space: SpaceTokens.xs }) {
                Text(this.nextMeta())
                  .fontSize(TypeTokens.caption.size)
                  .fontWeight(450)
                  .fontColor(ColorTokens.muted)
                  .fontFeature("'tnum' on")
                  .layoutWeight(1)
                if (this.isToday && !this.replanning) {
                  YoujingButton({
                    variant: YoujingButtonVariant.TEXT,
                    label: '加一站',
                    buttonWidth: 88,
                    onAction: (): void => {
                      this.openAddSheet();
                    }
                  })
                }
                if (this.canSkipNext()) {
                  YoujingButton({
                    variant: YoujingButtonVariant.TEXT,
                    label: '不去下一站',
                    buttonWidth: 108,
                    onAction: (): void => {
                      this.performSkip(this.next === null ? '' : this.next.key);
                    }
                  })
                }
              }
              .width('100%')
              .padding({ left: LayoutTokens.itineraryTimeGutter + SpaceTokens.xs })
            }
            .width('100%')
          }
        }

        ListItemGroup({ header: this.groupHeader() }) {
          if (this.rows.length === 0) {
            ListItem() {
              Text('今天还没有走过任何节点，打卡后会出现在这里')
                .fontSize(TypeTokens.caption.size)
                .fontColor(ColorTokens.muted)
                .width('100%')
                .padding({ top: SpaceTokens.xs, bottom: SpaceTokens.xs })
            }
          }
          ForEach(this.rows, (row: CheckedRow) => {
            ListItem() {
              this.checkRow(row)
            }
          }, (row: CheckedRow): string => `ck-${row.time}-${row.name}-${row.amount}`)
        }
        .divider({ strokeWidth: LayoutTokens.hairlineWidth, color: ColorTokens.separator })
        .padding({ left: SpaceTokens.base, right: SpaceTokens.base })
        .backgroundColor(ColorTokens.canvas)
        .borderRadius(RadiusTokens.card)
        .clip(true)
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .sticky(StickyStyle.Header)
      .cachedCount(6)
      .padding({ left: this.wideInset(), right: this.wideInset() })
      // 穿底让位（2026-11-08 对标有据）：让位从 padding 移到 contentStartOffset，
      // 只挪首屏起点；滚动后内容才穿得到标题栏下被材质糊掉（padding 压的是视口）。
      .contentStartOffset(HdsChrome.contentTopInset(this.statusBarHeight))
      .width('100%')
      .height('100%')
      .onDidScroll((): void => {
        this.syncBarScroll();
      })
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showAdd, this.addSheet(), {
      height: '70%',
      backgroundColor: ColorTokens.canvas,
      showClose: true,
      systemMaterial: getSheetImmersiveMaterial()
    })
    }
    // 不收栏（2026-11-08）：NavDestination 内容区恒预留 56vp 栏位、收栏后不回收，收起只留一条 175px 白带
    .bindToScrollable([this.barScroller])
    .clip(false)
    // HDS 深色档这层默认纯黑，透明栏会把它露成一条比画布暗一档的带（成因与实测见 Docs/INIT_REPORT.md §5ci 续 80）
    .backgroundColor(ColorTokens.canvas)
    .bindSheet($$this.showIntent, this.intentSheet(), {
      height: '60%',
      backgroundColor: ColorTokens.canvas,
      showClose: true,
      systemMaterial: getSheetImmersiveMaterial()
    })
    .titleBar(this.titleBarOptions())
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .onReady((ctx: NavDestinationContext): void => {
      this.pathStack = ctx.pathStack;
    })
    .onShown((): void => {
      // 上一轮在这里放弃过这一屏的带色，理由是"顶边实测 0，一个静态 token 配不了两种顶边"。
      // 那个 0 不是这一屏的天性，是 HDS 给 NavDestination 的深色默认底（见上面
      // .backgroundColor 那条）—— 钉成画布之后顶边就是 18，和其余各屏一致，缝随之闭合。
      this.reload();
    })
  }
}
