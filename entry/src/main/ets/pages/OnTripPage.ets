/**
 * 屏15 旅行中模式（帧 fc4e40cd）。
 * §7 必改已落：badge padding 3→4、check-right gap 6→4、stop-row padding 10→8、scroll 72→94。
 * hero 站名走 sans 21/700（禁令 8：serif 不上站名）。
 *
 * 数据（RDB 已接真）：当日节点、当前时刻、进度、下一段通勤、行内金额与打卡状态全部取真值。
 * 打卡写 checkin 表（v4），行内金额取挂在该节点上的 expense 合计；
 * 底稿里「周一人少，10:00 后团队到达」「打车 ¥1,900」这类无来源文案不保留。
 */

import { ACTIVE_TRIP_KEY, APP_NAV } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { ImmersiveSurface } from '../components/ImmersiveSurface';
import { Activity, ActivityCategory, ActivityStatus, MealType, Trip, TripDay } from '../model/Trip';
import { ReplanDecision, ReplanOutcome } from '../model/Replan';
import { TripDao } from '../data/TripDao';
import { SkipPlanner } from '../data/SkipPlanner';
import { CheckinDao } from '../data/CheckinDao';
import { ExpenseDao } from '../data/ExpenseDao';
import { ReplanClient } from '../ai/ReplanClient';
import { DateUtils } from '../utils/DateUtils';
import { WidgetSync } from '../widget/TodayCard';
import { TransitSymbol } from '../utils/TransitSymbol';
import { Logger } from '../common/logger/Logger';
import { common } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';

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

function hoursText(start: string, end: string): string {
  const mins: number = Math.max(0, DateUtils.minutesOf(end) - DateUtils.minutesOf(start));
  return `${Math.round(mins / 6) / 10}`;
}

@Component
export struct OnTripPage {
  private pathStack: NavPathStack = APP_NAV;
  @Prop tripId: string = '';
  @State private rows: CheckedRow[] = [];
  @State private current: DayStop | null = null;
  @State private next: DayStop | null = null;
  @State private checkedIn: boolean = false;
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
  /** 「不去」只在今天提供；回看历史日不出现 */
  @State private isToday: boolean = false;
  /** 当前展示的整日；跳过/撤销都以它为输入 */
  private day: TripDay | null = null;
  /** 跳过前的深拷贝（只在本进程有效，方案 §3.6） */
  private skipSnapshot: TripDay | null = null;
  private skipSnapshotTripId: string = '';
  private skipSnapshotDayIndex: number = 0;

  aboutToAppear(): void {
    this.reload();
  }

  private ctx(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  private async reload(): Promise<void> {
    if (this.tripId.length === 0) {
      Logger.warn('Ui.OnTrip', '无 tripId，旅行中页保持空态');
      return;
    }
    const context: common.Context = this.ctx();
    const now: string = clockNow();
    this.clock = now;
    try {
      const trip: Trip | null = await TripDao.loadTrip(context, this.tripId);
      if (trip === null) {
        this.trip = null;
        this.day = null;
        this.current = null;
        this.next = null;
        this.rows = [];
        this.checkedIn = false;
        this.isToday = false;
        this.clearSkipState();
        this.notice = '';
        return;
      }
      this.trip = trip;
      AppStorage.setOrCreate(ACTIVE_TRIP_KEY, trip.id);
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
        this.next = null;
        this.totalMin = 0;
        this.elapsedMin = 0;
        this.nextLeg = '';
        this.checkedIn = false;
        this.isToday = false;
        this.canUndo = false;
        const emptyMarks: Record<string, number> = await CheckinDao.listForTrip(context, trip.id);
        await this.buildRows(emptyMarks);
        return;
      }
      this.isToday = day.date === DateUtils.todayIso();
      this.canUndo = this.skipSnapshot !== null && this.skipSnapshotTripId === trip.id &&
        this.skipSnapshotDayIndex === day.dayIndex;
      this.dayLabel = `进行中 · Day ${day.dayIndex}`;
      let cur: number = -1;
      for (let i = 0; i < stops.length; i++) {
        if (stops[i].sortMin <= DateUtils.minutesOf(now)) {
          cur = i;
        }
      }
      if (cur < 0) {
        cur = 0;
      }
      const curStop: DayStop = stops[cur];
      this.current = curStop;
      this.next = cur + 1 < stops.length ? stops[cur + 1] : null;
      // 进度条只在"这一站有结束时刻"时给：餐次没有 endTime，不拿一小时假装它的窗口
      if (!curStop.isMeal && curStop.endTime.length > 0) {
        const start: number = curStop.sortMin;
        const end: number = Math.max(start + 1, DateUtils.minutesOf(curStop.endTime));
        this.totalMin = end - start;
        this.elapsedMin = Math.max(0, Math.min(this.totalMin, DateUtils.minutesOf(now) - start));
      } else {
        this.totalMin = 0;
        this.elapsedMin = 0;
      }
      const nx: DayStop | null = this.next;
      this.nextLeg = nx !== null && nx.hasTransport
        ? `${nx.transportMode} ${nx.transportMin}分钟${nx.transportDetail.length > 0 ? ` · ${nx.transportDetail}` : ''}`
        : '';
      const marks: Record<string, number> = await CheckinDao.listForTrip(context, trip.id);
      this.checkedIn = marks[curStop.key] !== undefined;
      await this.buildRows(marks);
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
   * 跳过下一站：云函数决策 → 端侧排程 → 落库 → 刷新页面。
   * expectedStopId 来自实况窗按钮，用于拒绝「按钮已陈旧」的点击；页面内入口传 ''。
   */
  private async performSkip(expectedStopId: string): Promise<void> {
    const trip: Trip | null = this.trip;
    const day: TripDay | null = this.day;
    const next: DayStop | null = this.next;
    if (trip === null || day === null || next === null) {
      this.toast('没有可跳过的下一站');
      return;
    }
    if (this.replanning) {
      return;
    }
    if (!this.isToday) {
      this.toast('只能跳过今天的站点');
      return;
    }
    if (expectedStopId.length > 0 && expectedStopId !== next.key) {
      this.toast('下一站已变化，请重试');
      return;
    }
    if (next.isMeal || !SkipPlanner.isSkippable(next.category, next.status)) {
      this.toast('这一站不能跳过');
      return;
    }
    const skippedId: string = next.key;
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

  /** 撤销 = 把跳过前快照写回该日并落库；快照只在本进程、只保留一层 */
  private async undoSkip(): Promise<void> {
    const trip: Trip | null = this.trip;
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
        place: a.address.length > 0 ? a.address : a.location, isMeal: false, kind: '', cost: 0,
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
        place: m.location, isMeal: true, cost: m.estimatedCost,
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

  /** 今日已打卡的行；金额取挂在该节点上的开销合计 */
  private buildRows(marks: Record<string, number>): Promise<Record<string, number>> {
    const trip: Trip | null = this.trip;
    if (trip === null) {
      return Promise.resolve<Record<string, number>>({});
    }
    const day: TripDay | null = this.pickDay(trip);
    return ExpenseDao.sumGroupedByActivity(this.ctx(), trip.id)
      .then((sums: Record<string, number>): Record<string, number> => {
        const list: CheckedRow[] = [];
        if (day !== null) {
          for (const st of this.buildStops(day)) {
            if (marks[st.key] === undefined) {
              continue;
            }
            const paid: number | undefined = sums[st.key];
            const shown: number | undefined = paid === undefined ? (st.isMeal && st.cost > 0 ? st.cost : undefined) : paid;
            const row: CheckedRow = {
              // 无时刻的餐次拿餐次标签占住时间槽（不编 08:00 假时刻），名字列留给店名
              time: st.time.length > 0 ? st.time : st.kind,
              name: st.title,
              amount: shown === undefined ? '' : `¥${shown}`,
              ongoing: false
            };
            list.push(row);
          }
        }
        this.rows = list;
        return sums;
      });
  }

  private toggleCheckin(): void {
    const cur: DayStop | null = this.current;
    const trip: Trip | null = this.trip;
    if (cur === null || trip === null) {
      this.toast('当前无节点');
      return;
    }
    const target: boolean = !this.checkedIn;
    CheckinDao.set(this.ctx(), trip.id, cur.key, target).then((): void => {
      this.checkedIn = target;
      this.reload();
      this.toast(target ? `已打卡 ${cur.title}` : '已取消打卡');
    }).catch((err: Error) => {
      Logger.error('Ui.OnTrip', `打卡失败: ${err.message}`);
      this.toast('打卡失败');
    });
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
      return cur.cost > 0 ? `${head} · 预估 ¥${cur.cost}` : head;
    }
    return `${cur.time} 开始 · 建议 ${hoursText(cur.time, cur.endTime)}小时 · 已过 ${this.elapsedMin}分钟`;
  }

  private progressPct(): number {
    return Math.max(1, Math.min(100, Math.round((this.elapsedMin / Math.max(1, this.totalMin)) * 100)));
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
      const cost: string = next.cost > 0 ? ` ¥${next.cost}` : '';
      return `${next.place.length > 0 ? `${next.place}${cost}` : `预估${cost}`}`;
    }
    return `建议停留 ${hoursText(next.time, next.endTime)}小时 · ${next.place}`;
  }

  @Builder
  noticeBar() {
    Row({ space: SpaceTokens.sm }) {
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
    .padding(SpaceTokens.md)
    .borderRadius(RadiusTokens.card)
    .backgroundColor(ColorTokens.surfaceElevated)
  }

  @Builder
  groupHeader() {
    // 材质豁免：这条吸顶行住在卡片内（父 List 已 canvas 实色 + 圆角 clip），不是契约 §1024
    // 指的那条满宽"日分隔"玻璃栏；给它上材质等于在卡片里开玻璃，违 §1149。
    // 但它确实会压在滚动行上（sticky 无底板=文字叠文字），所以补一张与卡片同色的实底板。
    Text('今日已打卡')
      .fontSize(TypeTokens.overline.size)
      .fontWeight(600)
      .fontColor(ColorTokens.muted)
      .width('100%')
      .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.xs })
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
          .margin({ right: SpaceTokens.sm })
      }
      Text(row.ongoing ? '进行中' : '已打卡')
        .fontSize(TypeTokens.overline.size)
        .fontWeight(600)
        .fontColor(row.ongoing ? ColorTokens.primary : ColorTokens.success)
      if (!row.ongoing) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(IconSizes.control)
          .fontColor([ColorTokens.success])
          .margin({ left: SpaceTokens.xs })
      }
    }
    .width('100%')
    .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
      // 官方 List：hero / 下一段 / 打卡分组各占一个 ListItem，分组头吸顶、行间交给 .divider()
      List({ space: SpaceTokens.lg }) {
        if (this.notice.length > 0) {
          ListItem() {
            this.noticeBar()
          }
        }
        ListItem() {
          // hero 面板包一层官方 HDS 双边流光（HdsVisualComponent），不支持的设备自动退回实色
          ImmersiveSurface({ radius: RadiusTokens.hero, surfaceWidth: '100%' }) {
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
                .margin({ top: SpaceTokens.xs })
              // heroMeta 在空态下返回的就是上面那句「今日暂无安排」——
              // 同一张卡上下印两遍（实拍确认），空态时不出这一行
              if (this.current !== null) {
                Text(this.heroMeta())
                  .fontSize(TypeTokens.caption.size)
                  .fontWeight(450)
                  .fontColor(ColorTokens.body)
                  .fontFeature("'tnum' on")
              }
              // 进度条只在"这一站有结束时刻"时画。一餐没有 endTime，
              // 而 progressPct() 有 Math.max(1, …) 的下限——不关掉它会被夹成满格（真机实测 1.000000）。
              if (this.totalMin > 0) {
                Progress({ value: this.progressPct(), total: 100, type: ProgressType.Linear })
                  .color(ColorTokens.primary)
                  .width('100%')
                  .margin({ top: SpaceTokens.md })
              }
              if (this.current !== null && this.current.note !== undefined && this.current.note.length > 0) {
                Text(this.current.note)
                  .fontSize(TypeTokens.caption.size)
                  .fontWeight(450)
                  .fontColor(ColorTokens.warning)
                  .margin({ top: SpaceTokens.sm })
              }
              Row({ space: SpaceTokens.md }) {
                // 今天没有节点时「完成打卡」是个没有对象的可点按钮
                if (this.current !== null) {
                  YoujingButton({
                    variant: YoujingButtonVariant.SECONDARY,
                    label: this.checkedIn ? '已打卡' : '完成打卡',
                    buttonWidth: 140,
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
              .margin({ top: SpaceTokens.lg })
                Text('打卡与记账只存本机，不上传服务器')
                  .fontSize(TypeTokens.overline.size)
                  .fontWeight(450)
                  .fontColor(ColorTokens.muted)
                  .margin({ top: SpaceTokens.sm })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding(SpaceTokens.lg)
            .borderRadius(RadiusTokens.hero)
            .backgroundColor(ColorTokens.surfaceElevated)
          }
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
                Row({ space: SpaceTokens.xs }) {
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
                .padding({ left: SpaceTokens.sm })
              }
              .height(LayoutTokens.transitLegHeight)
              .alignItems(VerticalAlign.Center)
              }

              Row({ space: SpaceTokens.sm }) {
                Text(this.next === null ? '' : this.next.time)
                  .fontSize(TypeTokens.time.size)
                  .fontWeight(600)
                  .fontColor(ColorTokens.ink)
                  .fontFeature("'tnum' on")
                  .width(LayoutTokens.itineraryTimeGutter)
                Row({ space: SpaceTokens.xs }) {
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
                      .padding({ left: SpaceTokens.xs, right: SpaceTokens.xs })
                      .borderRadius(RadiusTokens.pill)
                      .backgroundColor(ColorTokens.warning)
                  }
                }
                .layoutWeight(1)
              }
              .width('100%')
              .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })

              Row({ space: SpaceTokens.sm }) {
                Text(this.nextMeta())
                  .fontSize(TypeTokens.caption.size)
                  .fontWeight(450)
                  .fontColor(ColorTokens.muted)
                  .fontFeature("'tnum' on")
                  .layoutWeight(1)
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
              .padding({ left: LayoutTokens.itineraryTimeGutter + SpaceTokens.sm })
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
                .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
            }
          }
          ForEach(this.rows, (row: CheckedRow) => {
            ListItem() {
              this.checkRow(row)
            }
          }, (row: CheckedRow): string => `ck-${row.time}-${row.name}-${row.amount}`)
        }
        .divider({ strokeWidth: LayoutTokens.hairlineWidth, color: ColorTokens.separator })
        .padding({ left: SpaceTokens.md, right: SpaceTokens.md })
        .backgroundColor(ColorTokens.canvas)
        .borderRadius(RadiusTokens.card)
        .clip(true)
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .sticky(StickyStyle.Header)
      .cachedCount(6)
      .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg,
            bottom: LayoutTokens.floatingDockClearance })
      .width('100%')
      .height('100%')
      .backgroundColor(ColorTokens.canvas)
    }
    .width('100%')
    .height('100%')
    }
    .titleBar(HdsChrome.bar({ mainTitle: this.dayLabel.length > 0 ? this.dayLabel : '旅行中', subTitle: this.clock }))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .onShown((): void => {
      this.reload();
    })
  }
}
