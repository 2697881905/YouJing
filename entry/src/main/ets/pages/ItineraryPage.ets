/**
 * 屏8 行程时间线主视图（帧 9c0acbcd）。
 * §7 必改已落：booking-badge padding 3→4、dock padding 10→8、
 * reason-block margin 10→8、scroll 底部预留 138→94、transit gap 6→4。
 * 顶栏/吸顶/分段栏/dock 四点位玻璃=系统材质（骨架期用 backgroundBlurStyle 回退档，
 * 精修批次换 EXQUISITE）；深色零阴影经 isDarkMode 门控。
 */

import { DurationCn } from '../utils/DurationCn';
import { ACTIVE_TRIP_KEY, APP_NAV, EditTarget } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { ShadowTokens } from '../design/ShadowTokens';
import { Activity, ActivityCategory, ActivityStatus, IntensityLevel, TripDay, Trip } from '../model/Trip';
import { TripDao, TripSummary } from '../data/TripDao';
import { ShareExporter } from '../data/ShareExporter';
import { WidgetSync } from '../widget/TodayCard';
import { MapStop, MapStops } from '../utils/MapStops';
import { IcsBuilder } from '../utils/IcsBuilder';
import { CategoryStyle } from '../utils/CategoryStyle';
import { TimeText } from '../utils/TimeText';
import { TimelineNode } from '../components/TimelineNode';
import { TripMapView } from '../components/TripMapView';
import { AccessFlags, CalendarSync, SyncResult } from '../data/CalendarSync';
import { EntitlementStore } from '../data/EntitlementStore';
import { Logger } from '../common/logger/Logger';
import { common } from '@kit.AbilityKit';
import { ImmersiveSegmentBar, SegmentedItem } from '../components/ImmersiveSegmentBar';
import { getSheetImmersiveMaterial, isSystemMaterialActive } from '../utils/immersiveMaterial';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';
import { DateUtils } from '../utils/DateUtils';
import { TransitSymbol } from '../utils/TransitSymbol';
import { KEY_CURRENT_BREAKPOINT } from '../utils/breakpointCenter';
import { longFormMaxWidth } from '../utils/responsive';
import { DayLoad, DayLoadCalc, LoadLevel } from '../utils/DayLoad';
import { TripSpan } from '../utils/TripSpan';
import { requestSystemBarRefresh } from '../utils/systemBar';

/** 负载微条 3vp（比通用 Progress 的 4vp 细一档，它读的是趋势不是数值） */
const LOAD_BAR_STYLE: LinearStyleOptions = { strokeWidth: 3, strokeRadius: 1.5 };

@Component
export struct ItineraryPage {
  /**
   * 这一屏可能被 push 在五条 tab 栈的任意一条上——从「行程」页签点开就走 TRIPS_NAV。
   * 原来硬用 APP_NAV：从「我的」页签进来时，分享/编辑/全图/记一笔全部推到
   * 看不见的 tab-0 栈上，点了没反应（独立复审查出的 P0，与 enterPlanningFlow 同一类，
   * 当时只修了入口没修这两页）。改由 NavDestination.onReady 拿**自己所属**的栈，
   * 与 ComingSoonPage 同法；保留 APP_NAV 作默认值，深链直启时行为不变。
   */
  private pathStack: NavPathStack = APP_NAV;
  @StorageProp('isDarkMode') isDark: boolean = false;
  /** 断点（唯一来源 utils/breakpointCenter.ets）：宽屏给时间轴一条可读上限 */
  @StorageProp(KEY_CURRENT_BREAKPOINT) bp: string = 'sm';
  /** 玻璃点位①③是否由系统材质接管（接管处撤自绘背景与阴影）；仅浅色模式下实验 */
  private glassOn: boolean = isSystemMaterialActive();
  @Prop tripId: string = '';
  @State @Watch('syncDayStops') private dayIndex: number = 0;
  @State private showDetail: boolean = false;
  @State private detailAct: Activity | undefined = undefined;
  @State private showSystemAccess: boolean = false;
  @State private syncCalendar: boolean = false;
  @State private syncCard: boolean = true;
  @State private syncRemind: boolean = false;
  @State private days: TripDay[] = [];
  /** 地图面板的当天落点（坐标不可用的站点已在 MapStops 里滤掉） */
  @State private dayStops: MapStop[] = [];
  @State private daySig: string = '';
  @State private bookingCount: number = 0;
  @State private dayCount: number = 0;
  /** 时间线滚动器：点地图落点要把对应行带回视野（切片1 A）。
   *  必须是 ListScroller——scrollToItemInGroup 只在子类上，基类 Scroller 没有这个方法 */
  private listScroller: ListScroller = new ListScroller();
  /** 顶栏磨砂两态：由**绝对**滚动偏移驱动（每帧增量会被松手回弹的负帧打灭，契约 §Translucency）。
   *  偏移直接读上面那枚 listScroller，不建第二个实例 */
  @State private barScrolled: boolean = false;
  /** 地图面板镜头指令，'focus:<index>:<seq>'，与地图页同一口径 */
  @State private mapRequest: string = '';
  /** 被地图落点点中的行，1.6s 后自动褪色——滚动本身在行已可见时给不出反馈 */
  @State private focusActId: string = '';
  private reqSeq: number = 0;
  private trip: Trip | null = null;
  // 中性占位：加载前不能报一个编造的目的地与天数
  @State private titleText: string = '行程详情';
  @State private segments: SegmentedItem[] = [
    { label: 'Day 1' }, { label: 'Day 2' }, { label: 'Day 3' }
  ];

  /** 编辑页返回后要吃回写的库数据，故加载挂在 onShown 而非 aboutToAppear */
  private reload(): void {
    if (this.tripId.length > 0) {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      TripDao.loadTrip(ctx, this.tripId).then((trip: Trip | null) => {
        if (trip !== null) {
          this.trip = trip;
          AppStorage.setOrCreate(ACTIVE_TRIP_KEY, trip.id);
          this.days = trip.days;
          this.syncDayStops();
          this.bookingCount = CalendarSync.bookingCount(trip);
          this.dayCount = trip.days.length;
          this.titleText = `${trip.destination} · ${TripSpan.text(trip.days.length)}`;
          this.segments = trip.days.map((d: TripDay): SegmentedItem => {
            const item: SegmentedItem = { label: `Day ${d.dayIndex}` };
            return item;
          });
        }
      }).catch((err: Error) => {
        Logger.error('Ui.Itinerary', `加载行程失败: ${err.message}`);
      });
      CalendarSync.loadFlags(ctx).then((f: AccessFlags): void => {
        this.syncCalendar = f.calendar;
        this.syncCard = f.card;
        this.syncRemind = f.remind;
      }).catch((err: Error) => {
        Logger.warn('Ui.Itinerary', `触达开关读取失败: ${err.message}`);
      });
    } else {
      // 外部拉起（深链 / 小艺 / 桌面卡片）可能只给屏名不给 tripId。
      // 屏11 早就退到最近一条行程，屏8 原来这里什么都不做——同一件事两屏行为不一样，
      // 用户从外部进来看到的是一页空白。按屏11 的口径补齐。
      const ctx2: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      TripDao.listSummaries(ctx2).then((rows: TripSummary[]): void => {
        if (rows.length > 0) {
          this.tripId = rows[0].id;
          this.reload();
        }
      }).catch((err: Error): void => {
        Logger.warn('Ui.Itinerary', `取最近行程失败: ${err.message}`);
      });
    }
  }

  /** 切天或编辑页回写后重算当天落点（地图面板与时间线必须同源） */
  syncDayStops(): void {
    // 高亮属于「刚才点中的那一行」，换天/换数据后它已经不在语境里
    this.focusActId = '';
    if (this.days.length === 0) {
      this.dayStops = [];
      this.daySig = '';
      return;
    }
    const stops: MapStop[] = MapStops.fromDay(this.curDay());
    this.dayStops = stops;
    this.daySig = MapStops.signature(stops);
  }

  /**
   * 屏8 列表↔地图联动（切片1 A）：点地图落点 → 镜头飞到该点 + 时间线滚到对应行并高亮。
   * 两件事必须同时做：只飞镜头，列表不动，用户看不出「这个点对应哪一行」。
   */
  private onMapStopTap(index: number): void {
    const inDay: number = MapStops.activityIndex(this.curDay(), index);
    if (inDay < 0) {
      return;
    }
    const act: Activity = this.curDay().activities[inDay];
    this.reqSeq += 1;
    this.mapRequest = `focus:${index}:${this.reqSeq}`;
    this.focusActId = act.id;
    // List 的组号：ListItem 也按组计数，地图卡在场时它与 ListItemGroup 各占一个
    const group: number = this.dayStops.length > 0 ? 1 : 0;
    // 组内下标：每个活动先出站点行、再出通勤腿，故站点行的组内序号 = 活动下标 × 2
    this.listScroller.scrollToItemInGroup(group, inDay * 2, true, ScrollAlign.CENTER);
    setTimeout((): void => {
      if (this.focusActId === act.id) {
        this.focusActId = '';
      }
    }, 1600);
  }

  /** 当日负载（三态条）：同一份数据只算一次，宿主宽度变化时自然重算 */
  private dayLoad(): DayLoad {
    return DayLoadCalc.of(this.curDay());
  }

  /** 微条走品牌色，只在高负载/超载时转语义色——常态不该是一条警示线 */
  private loadBarColor(): Resource {
    const level: LoadLevel = this.dayLoad().level;
    if (level === LoadLevel.OVER) {
      return ColorTokens.danger;
    }
    if (level === LoadLevel.WARN) {
      return ColorTokens.warning;
    }
    return ColorTokens.primary;
  }

  private loadTextColor(): Resource {
    const level: LoadLevel = this.dayLoad().level;
    if (level === LoadLevel.OVER) {
      return ColorTokens.danger;
    }
    if (level === LoadLevel.WARN) {
      return ColorTokens.warning;
    }
    return ColorTokens.muted;
  }

  @Builder
  loadStrip() {
    Row({ space: SpaceTokens.xs }) {
      Progress({ value: Math.min(100, this.dayLoad().ratio * 100), total: 100, type: ProgressType.Linear })
        .style(LOAD_BAR_STYLE)
        .color(this.loadBarColor())
        // 同上：吸顶日标题这一条压在画布上，sunken 差 5 档判不出来
        .backgroundColor(ColorTokens.hairline)
        .layoutWeight(1)
        // 条本身没有文字：读屏要能听到同一句读数
        .accessibilityText(DayLoadCalc.label(this.dayLoad()))
      Text(DayLoadCalc.label(this.dayLoad()))
        .fontSize(TypeTokens.caption.size)
        .fontWeight(450)
        .fontColor(this.loadTextColor())
        .fontFeature("'tnum' on")
        .maxLines(1)
      if (this.dayLoad().level === LoadLevel.OVER) {
        // 超窗口才出现：给一条直达屏9 的路，而不是让用户自己从右上角找编辑
        Button('去减一站')
          .fontSize(TypeTokens.caption.size)
          .fontWeight(600)
          .height(LayoutTokens.minTouchTarget)
          .type(ButtonType.Capsule)
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .padding({ left: SpaceTokens.xs, right: SpaceTokens.xs })
          .accessibilityText('当日安排超出建议时长，去编辑页减掉一站')
          .onClick((): void => {
            const target: EditTarget = { tripId: this.tripId, dayIndex: this.dayIndex };
            this.pathStack.pushPath({ name: 'EditItinerary', param: target });
          })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /** 屏14 预览取真实待写节点：优先详情面板选中的活动，否则当日首站 */
  private previewTarget(): Activity | undefined {
    if (this.detailAct !== undefined) {
      return this.detailAct;
    }
    const acts: Activity[] = this.curDay().activities;
    return acts.length > 0 ? acts[0] : undefined;
  }

  private previewWhen(): string {
    const act: Activity | undefined = this.previewTarget();
    if (act === undefined) {
      return '';
    }
    return `${this.curDay().date} ${act.time}–${act.endTime}`;
  }

  private previewWhat(): string {
    const act: Activity | undefined = this.previewTarget();
    return act === undefined ? '' : `${act.title} · ${CalendarSync.isBookingNode(act) ? '需预约' : '无需预约'}`;
  }

  private previewWhere(): string {
    const act: Activity | undefined = this.previewTarget();
    if (act === undefined) {
      return '';
    }
    return `地址 ${act.address.length > 0 ? act.address : act.location}`;
  }

  /** 与 CalendarSync 实际写入的 description 对齐，预览不承诺没写的东西 */
  private previewNote(): string {
    const act: Activity | undefined = this.previewTarget();
    if (act === undefined) {
      return '';
    }
    const desc: string = act.reason === undefined ? act.location : `${act.location} · ${act.reason}`;
    return `备注 ${desc}`;
  }

  /** 同意并写入：先申请权限，未授权不写任何数据；开关状态落 preferences */
  private writeToSystem(): void {
    const ctx: common.UIAbilityContext = this.ctx();
    const flags: AccessFlags = {
      calendar: this.syncCalendar, card: this.syncCard,
      // 提醒的载体是日历事件，没开日历同步就不落 remind
      remind: this.syncCalendar ? this.syncRemind : false
    };
    if (this.syncRemind && !this.syncCalendar) {
      this.toast('提醒要落在日历事件上，本次未开日历同步，未写入提醒');
    }
    CalendarSync.saveFlags(ctx, flags).then((): Promise<void> => {
      // 卡片开关要当场见效：关掉后立刻把桌面卡片打回空态，开启则马上回灌
      return WidgetSync.refreshAll(ctx);
    }).catch((err: Error) => {
      Logger.warn('Ui.Itinerary', `触达开关保存失败: ${err.message}`);
    });
    if (!flags.calendar) {
      this.toast('行程仅保存在本机');
      this.showSystemAccess = false;
      return;
    }
    const trip: Trip | null = this.trip;
    if (trip === null) {
      this.toast('行程数据未就绪，稍后再试');
      return;
    }
    CalendarSync.requestPermission(ctx).then((granted: boolean): Promise<SyncResult> => {
      if (!granted) {
        throw new Error('未授予日历权限');
      }
      if (!EntitlementStore.canExport(trip.id)) {
        throw new Error('导出需解锁通行证或订阅');
      }
      return CalendarSync.syncTrip(ctx, trip, flags);
    }).then((r: SyncResult): void => {
      this.toast(`已写入 ${r.bookingEvents} 个预约节点 + ${r.dayEvents} 天行程`);
    }).catch((err: Error) => {
      Logger.warn('Ui.Itinerary', `日历写入失败: ${err.message}`);
      this.toast(`日历写入失败：${err.message}`);
    }).finally((): void => {
      this.showSystemAccess = false;
    });
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1800 });
  }

  /**
   * 底稿屏10 的「换一个时间」：当日时间槽是既定集合，换时间＝把本站挪到另一站的位置，
   * 中间各站按槽顺延——与屏9 拖动排序同一套语义，不新造时间、不编通勤腿。
   */
  private pickNewTime(): void {
    const list: Activity[] = this.detailList();
    const from: number = this.detailIndex();
    if (from < 0) {
      this.toast('行程数据未就绪');
      return;
    }
    if (list.length < 2) {
      this.toast('当日只有一站，没有可换的时间');
      return;
    }
    const labels: string[] = [];
    const targets: number[] = [];
    for (let i = 0; i < list.length; i++) {
      if (i === from) {
        continue;
      }
      labels.push(`${list[i].time} · ${list[i].title}`);
      targets.push(i);
    }
    this.getUIContext().showTextPickerDialog({
      range: labels,
      selected: 0,
      onAccept: (res: TextPickerResult): void => {
        const pos: number = Array.isArray(res.index) ? res.index[0] : res.index;
        const target: number | undefined = targets[pos];
        if (target !== undefined) {
          this.applySlotMove(target);
        }
      }
    });
  }

  /** 重排后整份聚合根落库；槽位集合不变，节点逐位回占 */
  private applySlotMove(targetIdx: number): void {
    const trip: Trip | null = this.trip;
    const act: Activity | undefined = this.detailAct;
    if (trip === null || act === undefined || this.dayIndex >= trip.days.length) {
      return;
    }
    const list: Activity[] = trip.days[this.dayIndex].activities;
    const from: number = this.detailIndex();
    if (from < 0 || targetIdx < 0 || targetIdx >= list.length || targetIdx === from) {
      return;
    }
    const byTime: Activity[] = list.slice().sort((a: Activity, b: Activity): number =>
      a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
    const times: string[] = byTime.map((a: Activity): string => a.time);
    const ends: string[] = byTime.map((a: Activity): string => a.endTime);
    const order: Activity[] = list.slice();
    const node: Activity = order.splice(from, 1)[0];
    order.splice(targetIdx, 0, node);
    const kept: Activity[] = order.map((a: Activity, i: number): Activity => {
      const copy: Activity = {
        id: a.id, time: times[i], endTime: ends[i], title: a.title, location: a.location,
        address: a.address, longitude: a.longitude, latitude: a.latitude, status: a.status,
        category: a.category, note: a.note, reason: a.reason, transport: a.transport
      };
      return copy;
    });
    const days: TripDay[] = trip.days.slice();
    days[this.dayIndex].activities = kept;
    const updated: Trip = {
      id: trip.id, destination: trip.destination, startDate: trip.startDate,
      endDate: trip.endDate, people: trip.people, budget: trip.budget, style: trip.style,
      overview: trip.overview, days: days, tips: trip.tips
    };
    TripDao.saveTrip(this.ctx(), updated).then((): void => {
      this.trip = updated;
      this.days = updated.days;
      this.syncDayStops();
      this.detailAct = kept[targetIdx];
      // bindSheet 的自定义内容不随父组件 @State 重赋值重绘（真机实测：时间线已换槽，
      // 面板仍停在打开那一刻的 09:00），故应用后收起面板，再进就是真值。
      this.showDetail = false;
      Logger.info('Ui.Itinerary', `换时间 ${node.title} ${times[from]}→${times[targetIdx]}`);
      WidgetSync.refreshAll(this.ctx()).catch((err: Error) => {
        Logger.warn('Ui.Itinerary', `卡片刷新失败: ${err.message}`);
      });
      this.toast(`${node.title} 已改到 ${times[targetIdx]}`);
    }).catch((err: Error) => {
      Logger.error('Ui.Itinerary', `换时间保存失败: ${err.message}`);
      this.toast('保存失败，时间未改动');
    });
  }

  /** 底稿屏10 顶栏声明的「分享」：只发当前节点，本机现算文本，不含账号信息 */
  private shareNode(): void {
    const act: Activity | undefined = this.detailAct;
    if (act === undefined) {
      return;
    }
    ShareExporter.shareNode(this.ctx(), this.curDay(), act).catch((err: Error) => {
      Logger.warn('Ui.Itinerary', `节点分享失败: ${err.message}`);
      this.toast('分享面板拉起失败');
    });
  }

  private detailList(): Activity[] {
    return this.curDay().activities;
  }

  private detailIndex(): number {
    const act: Activity | undefined = this.detailAct;
    if (act === undefined) {
      return -1;
    }
    const list: Activity[] = this.detailList();
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === act.id) {
        return i;
      }
    }
    return -1;
  }

  private dayPos(): number {
    const i: number = this.detailIndex();
    return i < 0 ? 1 : i + 1;
  }

  /**
   * 屏10 帧 471fcea9 的地址槽是两段：「京都市伏見区深芝藪町 68 · 山脚入口」= address · 点位别称。
   * 真机 DB 实测旧数据里 location 96/96 行等于 address 或 title（提示词此前没定义它的语义），
   * 所以第二段先判"是不是同一个东西"再拼，否则会显示成「北京 东城区 · 故宫博物院」这种重复。
   */
  private detailAddressLine(): string {
    const act: Activity | undefined = this.detailAct;
    if (act === undefined) {
      return '';
    }
    const addr: string = act.address;
    const spot: string = act.location;
    if (addr.length === 0) {
      return spot;
    }
    if (spot.length === 0 || spot === addr || spot === act.title || addr.includes(spot)) {
      return addr;
    }
    return `${addr} · ${spot}`;
  }

  private statusChip(): string {
    const act: Activity | undefined = this.detailAct;
    if (act === undefined) {
      return '';
    }
    if (act.status === ActivityStatus.BOOKED) {
      return '已约';
    }
    if (act.status === ActivityStatus.FULL) {
      return '约满';
    }
    if (act.status === ActivityStatus.PENDING) {
      return '待定';
    }
    return '';
  }

  /** 与单节点分享同一口径（IcsBuilder.statusLabel） */
  private statusFullText(): string {
    const act: Activity | undefined = this.detailAct;
    return act === undefined ? '' : IcsBuilder.statusLabel(act);
  }

  private commuteText(): string {
    const act: Activity | undefined = this.detailAct;
    if (act === undefined || act.transport === undefined) {
      return '—';
    }
    return DurationCn.text(act.transport.duration);
  }

  private arrivalText(): string {
    const act: Activity | undefined = this.detailAct;
    if (act === undefined || act.transport === undefined) {
      return '当日首站，无通勤';
    }
    const detail: string = act.transport.detail.length > 0 ? ` · ${act.transport.detail}` : '';
    return `${act.transport.mode} ${DurationCn.text(act.transport.duration)}${detail}`;
  }

  private prevTitle(): string {
    const i: number = this.detailIndex();
    return i > 0 ? this.detailList()[i - 1].title : '今日首站';
  }

  private prevLabel(): string {
    const i: number = this.detailIndex();
    return i > 0 ? `上一站 ${this.detailList()[i - 1].time}` : '当日第 1 站';
  }

  private nextTitle(): string {
    const i: number = this.detailIndex();
    const list: Activity[] = this.detailList();
    return i >= 0 && i < list.length - 1 ? list[i + 1].title : '今日末站';
  }

  private nextLabel(): string {
    const i: number = this.detailIndex();
    const list: Activity[] = this.detailList();
    return i >= 0 && i < list.length - 1 ? `下一站 ${list[i + 1].time}` : '当日最后';
  }

  /** 通勤图标按模式取真图标（图标名已对本机 id_defined.json 核实），认不出的一律走步行 */
  /** 地图面板摘要：只报当日真实通勤段数与模式，底稿的「6.4km」无数据来源故不保留 */
  private dayRouteSummary(): string {
    const acts: Activity[] = this.curDay().activities;
    const order: string[] = [];
    const counts: Record<string, number> = {};
    for (const a of acts) {
      if (a.transport === undefined) {
        continue;
      }
      const mode: string = a.transport.mode.length > 0 ? a.transport.mode : '步行';
      if (counts[mode] === undefined) {
        counts[mode] = 0;
        order.push(mode);
      }
      counts[mode] = counts[mode] + 1;
    }
    if (acts.length === 0) {
      return '当日暂无安排';
    }
    if (order.length === 0) {
      return '当日仅一站，无通勤';
    }
    const parts: string[] = order.map((m: string): string => `${m} ${counts[m]} 段`);
    return parts.join(' · ');
  }

  private curDay(): TripDay {
    if (this.days.length === 0) {
      const placeholder: TripDay = {
        dayIndex: 1, date: '————', theme: '', intensity: IntensityLevel.LOW,
        dailyCost: 0, activities: [], meals: []
      };
      return placeholder;
    }
    return this.days[Math.min(this.dayIndex, this.days.length - 1)];
  }

  /** 类别 → 色名由 CategoryStyle 统一（屏13 桌面卡片同一口径），这里只做色名 → token */
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
      // 待定 = 需要用户行动，归 warning（需预约/需证件同族）；
      // 曾是 bookmark（必去金），用户会把「待定」读成「必去」
      return ColorTokens.warning;
    }
    return ColorTokens.warning;
  }

  @Builder
  spineNode(cat: ActivityCategory) {
    TimelineNode({ cat: cat })
  }

  @Builder
  transitLeg(next: Activity) {
    Row() {
      Column().width(LayoutTokens.itineraryTimeGutter)
      Column()
        .width(LayoutTokens.routeLineWidth)
        .height(LayoutTokens.transitLegHeight)
        .border({ width: { left: LayoutTokens.routeLineWidth }, color: ColorTokens.separator, style: BorderStyle.Dashed })
      Row({ space: SpaceTokens.xxs }) {
        SymbolGlyph(TransitSymbol.of(next.transport === undefined ? '' : next.transport.mode))
          .fontSize(IconSizes.control)
          .fontColor([ColorTokens.icon])
        Text(`${next.transport?.mode} ${DurationCn.text(next.transport?.duration ?? 0)} · ${next.transport?.detail}`)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .fontFeature("'tnum' on")
      }
      .alignItems(VerticalAlign.Center)
      .padding({ left: SpaceTokens.xs })
    }
    .width('100%')
    .height(LayoutTokens.transitLegHeight)
    .alignItems(VerticalAlign.Center)
  }

  private durationText(act: Activity): string {
    const text: string = TimeText.stayOf(act);
    return text.length > 0 ? text : '—';
  }

  @Builder
  stopRow(act: Activity, isLast: boolean) {
    Column() {
      Row() {
        Text(act.time)
          .width(LayoutTokens.itineraryTimeGutter)
          .fontSize(TypeTokens.time.size)
          .fontWeight(600)
          .fontColor(ColorTokens.ink)
          .textAlign(TextAlign.End)
          .fontFeature("'tnum' on")
          .padding({ right: SpaceTokens.sm, top: SpaceTokens.xxs })
        Stack({ alignContent: Alignment.Top }) {
          Column()
            .width(LayoutTokens.routeLineWidth)
            // 原来非末行写 '100%'：这一行没有定高，百分比按**视口高**解析，
            // 于是竖线从节点一路画进下方的黑里（实拍「时间轴断在半空」的真因）。
            // 换成与首启预览卡同一档的具名行高
            .height(isLast ? SpaceTokens.sm : LayoutTokens.itineraryRowMinHeight)
            .backgroundColor(ColorTokens.surfaceSunken)
          this.spineNode(act.category)
        }
        .width(LayoutTokens.itineraryNodeSize)
        .height(isLast ? SpaceTokens.sm : LayoutTokens.itineraryRowMinHeight)
        Column() {
          Row({ space: SpaceTokens.xs }) {
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
                .padding({ left: SpaceTokens.xs, right: SpaceTokens.xs })
                .borderRadius(RadiusTokens.pill)
                .backgroundColor(this.bookingColor(act.status))
            }
            // 原来这里挂着一个 36×48 的 surfaceSunken 方块当景点缩略位，
            // 但 Activity/AI 契约里根本没有图片字段——它永远填不上，
            // 实拍读起来就是「需预约」右边一块悬空的深色残留（§5 排版交错）
          }
          .alignItems(VerticalAlign.Center)

          Text(`建议停留 ${this.durationText(act)} · ${act.address}`)
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
            .fontFeature("'tnum' on")
            .margin({ top: SpaceTokens.xxs })
          if (act.reason !== undefined) {
            Column() {
              Text('为什么排在这里')
                .fontSize(TypeTokens.overline.size)
                .fontWeight(600)
                .fontColor(ColorTokens.muted)
              Text(act.reason)
                .fontSize(TypeTokens.small.size)
                .fontColor(ColorTokens.ink)
                .margin({ top: SpaceTokens.xxs })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding(SpaceTokens.sm)
            .borderRadius(RadiusTokens.reason)
            .backgroundColor(ColorTokens.surfacePanel)
            .border({ width: { left: 2 }, color: ColorTokens.primary })
            .margin({ top: SpaceTokens.xs, bottom: SpaceTokens.xs })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        // 节点槽宽 24、圆占 22，原来这一列没有任何左内缩，
        // 站名首字几乎贴着主轴圆（真机屏8 复拍可见）；补一档间距
        .padding({ left: SpaceTokens.xs })
      }
      .alignItems(VerticalAlign.Top)
      .width('100%')
      // 76px 是 minimum 不是 cap（DESIGN §7）：系统字号放大或长理由文案时行要能撑开
      .constraintSize({ minHeight: LayoutTokens.itineraryRowMinHeight })
      // 联动高亮：点地图落点后这一行亮一次（primary_tint 是品牌蓝 10%/20% 的既有档，
      // 不做新色值），1.6s 后由 onMapStopTap 的定时器褪回
      .backgroundColor(this.focusActId === act.id ? ColorTokens.primaryTint : Color.Transparent)
      .borderRadius(RadiusTokens.card)
      .onClick(() => {
        this.detailAct = act;
        this.showDetail = true;
      })
    }
    .width('100%')
  }

  /** 日标题右侧：主题 · 节奏（任一为空就只显另一个，不留悬空分隔符） */
  private dayMetaLine(): string {
    const day: TripDay = this.curDay();
    const pace: string = CategoryStyle.pace(day.intensity);
    const risk: string = day.risk === undefined ? '' : day.risk;
    const parts: string[] = [day.theme, pace, risk].filter((x: string): boolean => x.length > 0);
    return parts.join(' · ');
  }


  /**
   * 日标题的日期后缀：空数据占位（date='————'）时不渲染日期段，
   * 避免出现「Day 1 · 日」这种切空串的残句
   */
  private dayDateSuffix(): string {
    const date: string = this.curDay().date;
    if (!DateUtils.isValidIsoDate(date)) {
      return '';
    }
    return ` · ${date.slice(5).replace('-', '月')}日`;
  }

  /** 吸顶日标题（玻璃点位④：骨架期实色），挂在 ListItemGroup.header 上由 sticky 吸顶 */
  @Builder
  dayHeader() {
    // 原来是一行 Row{日标题, Blank(), meta}：meta「王府井-东城核心 出发 · 第 1 日 · 标准」
    // 加上 21vp 衬线日标题超出屏宽后，Blank 塌成 0，两段文字直接互撞、
    // 末尾的「主题·节奏」被裁出屏幕右沿（真机实拍）。拆成两行才装得下
    Column({ space: SpaceTokens.xxs }) {
      // day-label 档：serif 21/700（DESIGN Layout §3 日分隔 = serif day-label；
      // 此处曾是 body 16/600 sans，是 serif 该上而没上的位置）
      Text(`Day ${this.curDay().dayIndex}${this.dayDateSuffix()}`)
        .fontSize(TypeTokens.title.size)
        .fontWeight(700)
        .fontFamily(TypeTokens.title.family)
        .fontColor(ColorTokens.ink)
        .fontFeature("'tnum' on")
      Text(this.dayMetaLine())
        .fontSize(TypeTokens.caption.size)
        .fontWeight(450)
        .fontColor(ColorTokens.muted)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.dayLoad().minutes > 0) {
        this.loadStrip()
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .constraintSize({ minHeight: LayoutTokens.dayDividerHeight })
    .padding({ top: SpaceTokens.sm })
    // 玻璃点位③（契约 §1024 sticky 变体）：真机实测 systemMaterial 挂在 ListItemGroup
    // 的 sticky 组头上不出图（带内内容字 min=0，与带外无差别），落回官方组件级磨砂
    // backgroundBlurStyle(COMPONENT_THICK)——同样是系统绘制的模糊层，不是自绘玻璃。
    // 顶部悬浮档不投影：栏下就是滚动内容，投影会画在行上。深色档沿用 dock 取舍，落回实色。
    .backgroundBlurStyle(this.glassOn && !this.isDark ? BlurStyle.COMPONENT_THICK : BlurStyle.NONE)
    .backgroundColor(this.glassOn && !this.isDark ? Color.Transparent : ColorTokens.canvas)
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
    .padding({ top: SpaceTokens.xs, bottom: SpaceTokens.xs })
  }

  @Builder
  miniNode(idx: number, meta: string, name: string, active: boolean) {
    Column({ space: SpaceTokens.xxs }) {
      Stack() {
        Circle()
          .width(22)
          .height(22)
          .fill(active ? ColorTokens.primary : ColorTokens.canvas)
          .stroke(active ? ColorTokens.primary : ColorTokens.ink)
          .strokeWidth(2)
        if (!active && idx >= 1 && idx <= this.detailList().length) {
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
            Row({ space: SpaceTokens.sm }) {
              // 原来这里是一个 96×128 的 mediaThumb 占位块，但 Activity/AI 契约里
              // 没有图片字段，它永远是纯黑——还把站名挤成窄列、
              // 实拍折成「北京环球度 / 假区」两行（与屏8 行内那块同一判据）
              Column() {
                Text(this.detailAct.title)
                  // 帧 471fcea9 的节点名是 .serif-title 21/700 serif（不是 headline 18/600）
                  .fontSize(TypeTokens.title.size)
                  .fontWeight(TypeTokens.title.weight)
                  .fontFamily(TypeTokens.title.family)
                  .fontColor(ColorTokens.ink)
                Text(this.detailAddressLine())
                  .fontSize(TypeTokens.caption.size)
                  .fontWeight(450)
                  .fontColor(ColorTokens.muted)
                  .margin({ top: SpaceTokens.xxs })
                Row({ space: SpaceTokens.xxs }) {
                  if (this.statusChip() !== '') {
                    Text(this.statusChip())
                      .fontSize(TypeTokens.overline.size)
                      .fontWeight(600)
                      .fontColor(ColorTokens.bookmark)
                      .height(22)
                      .padding({ left: SpaceTokens.xs, right: SpaceTokens.xs })
                      .borderRadius(RadiusTokens.pill)
                      .backgroundColor(ColorTokens.surfaceSubtle)
                  }
                  if (this.detailAct.status === ActivityStatus.NOT_BOOKED) {
                    Text('需预约')
                      .fontSize(TypeTokens.overline.size)
                      .fontWeight(600)
                      .fontColor(ColorTokens.onPrimary)
                      .height(22)
                      .padding({ left: SpaceTokens.xs, right: SpaceTokens.xs })
                      .borderRadius(RadiusTokens.pill)
                      .backgroundColor(ColorTokens.warning)
                  }
                }
                .margin({ top: SpaceTokens.xs })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              // 底稿屏10 顶栏声明的分享；面板自带官方关闭钮，故分享落进内容区右上角
              Button() {
                SymbolGlyph($r('sys.symbol.share'))
                  .fontSize(IconSizes.control)
                  .fontColor([ColorTokens.icon])
              }
              .type(ButtonType.Circle)
              .buttonStyle(ButtonStyleMode.TEXTUAL)
              .width(LayoutTokens.minTouchTarget)
              .height(LayoutTokens.minTouchTarget)
              // 官方 showClose 的 ✕ 实测占 [961,543]-[1086,668]（px，密度 3.0），
              // 不左移两枚 44 热区会叠在一起（真机截图复现过）
              .margin({ right: SpaceTokens.xxl })
              .accessibilityText('分享此节点')
              .onClick((): void => {
                this.shareNode();
              })
            }
            .alignItems(VerticalAlign.Top)
            .width('100%')

            Row() {
              this.statCol(this.durationText(this.detailAct), '停留建议')
              this.statCol(this.detailAct.time, '计划到达')
              this.statCol(this.commuteText(), '到达耗时')
              // 原来还有第四格「门票费用」，值恒为「—」——`Activity` 模型里根本没有票价字段，
              // 它永远填不上，实拍就是面板里一个假数据位。删。
              // （三格也比四格稳：把断点钉成 lg 复拍时，四格在窄列里会整个竖排）
            }
            .width('100%')
            .padding(SpaceTokens.base)
            .borderRadius(RadiusTokens.card)
            // 契约：玻璃只有四处，sheet 内的卡片不是玻璃。
            // 原来挂的 barMaterial 在 bindSheet builder 内属生效范围外（immersiveMaterial 自书铁律），
            // glassOn 时还把底置透明——API 26 上这张卡既无材质也无底色。恒实色。
            .backgroundColor(ColorTokens.surfaceElevated)
            .margin({ top: SpaceTokens.base })

            Column() {
              this.hoursRow('预约状态', this.statusFullText())
              Divider().strokeWidth(LayoutTokens.hairlineWidth).color(ColorTokens.separator)
              this.hoursRow('到达方式', this.arrivalText())
            }
            .width('100%')
            .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm })
            .margin({ top: SpaceTokens.sm })

            if (this.detailAct.note !== undefined && this.detailAct.note.length > 0) {
              Text(this.detailAct.note)
                .fontSize(TypeTokens.caption.size)
                .fontWeight(450)
                .fontColor(ColorTokens.warning)
                .fontFeature("'tnum' on")
                .width('100%')
                .margin({ top: SpaceTokens.xxs })
            }

            // 预约硬信息口径（§3.2/§7）：以官方为准，不让用户把规划数据当实时准确
            if (this.detailAct.status === ActivityStatus.NOT_BOOKED ||
              this.detailAct.status === ActivityStatus.PENDING) {
              Text('预约状态与放票时间以官方为准')
                .fontSize(TypeTokens.overline.size)
                .fontWeight(400)
                .fontColor(ColorTokens.muted)
                .width('100%')
                .margin({ top: SpaceTokens.xxs })
            }

            if (this.detailAct.reason !== undefined) {
              Column() {
                Text('为什么排在这里')
                  .fontSize(TypeTokens.overline.size)
                  .fontWeight(600)
                  .fontColor(ColorTokens.muted)
                Text(this.detailAct.reason)
                  .fontSize(TypeTokens.small.size)
                  .fontColor(ColorTokens.ink)
                  .margin({ top: SpaceTokens.xxs })
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding(SpaceTokens.sm)
              .borderRadius(RadiusTokens.reason)
              .backgroundColor(ColorTokens.surfacePanel)
              .border({ width: { left: 2 }, color: ColorTokens.primary })
              .margin({ top: SpaceTokens.sm })
            }

            Column() {
              Text('动线位置')
                .fontSize(TypeTokens.overline.size)
                .fontWeight(600)
                .fontColor(ColorTokens.muted)
                .alignSelf(ItemAlign.Start)
              Row() {
                this.miniNode(this.dayPos() - 1, this.prevLabel(), this.prevTitle(), false)
                this.miniNode(this.dayPos(), '当前站点', this.detailAct.title, true)
                this.miniNode(this.dayPos() + 1, this.nextLabel(), this.nextTitle(), false)
              }
              .width('100%')
              .padding({ top: SpaceTokens.sm })
            }
            .width('100%')
            .padding(SpaceTokens.base)
            .borderRadius(RadiusTokens.card)
            .backgroundColor(ColorTokens.surfaceElevated)
            .margin({ top: SpaceTokens.sm, bottom: SpaceTokens.lg })
          }
          .padding({ left: SpaceTokens.base, right: SpaceTokens.base })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)

        Row({ space: SpaceTokens.sm }) {
          YoujingButton({
            variant: YoujingButtonVariant.SECONDARY,
            label: '换一个时间',
            buttonWidth: 160,
            onAction: (): void => {
              this.pickNewTime();
            }
          })
          // 权重只能挂在原生包装层上：`.layoutWeight` 写在自定义组件 YoujingButton 身上
          // 会被框架静默忽略，主键就一直是默认死宽、右缘不贴内容边（屏5/屏9 同族缺陷）
          Column() {
            YoujingButton({
              variant: YoujingButtonVariant.PRIMARY,
              label: '加入日历提醒',
              fullWidth: true,
              onAction: (): void => {
                this.showDetail = false;
                this.showSystemAccess = true;
              }
            })
          }
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: SpaceTokens.base, right: SpaceTokens.base, top: SpaceTokens.xs, bottom: SpaceTokens.sm })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ColorTokens.canvas)
  }

  @Builder
  accessRow(title: string, desc: string, on: boolean, setter: (v: boolean) => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(TypeTokens.small.size)
          .fontWeight(600)
          .fontColor(ColorTokens.ink)
        Text(desc)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .fontFeature("'tnum' on")
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: on })
        .selectedColor(ColorTokens.primary)
        .accessibilityText(`${title}开关`)
        .onChange((isOn: boolean) => {
          setter(isOn);
        })
    }
    .width('100%')
    .padding({ top: SpaceTokens.xs, bottom: SpaceTokens.xs })
  }

  @Builder
  systemAccessSheet() {
    Column() {
      Text('让行程走到系统里')
        .fontSize(TypeTokens.title.size)
        .fontWeight(700)
        .fontFamily(TypeTokens.title.family)
        .fontColor(ColorTokens.ink)
        .margin({ top: SpaceTokens.lg })
      Text('行程数据只存在本机，写入系统应用由你决定')
        .fontSize(TypeTokens.small.size)
        .fontColor(ColorTokens.body)
        .margin({ top: SpaceTokens.xxs, bottom: SpaceTokens.base })

      Column() {
        this.accessRow('日历同步', `写入 ${this.bookingCount} 个预约节点 + ${this.dayCount} 天行程`,
          this.syncCalendar,
          (v: boolean): void => {
            this.syncCalendar = v;
          })
        Divider().strokeWidth(LayoutTokens.hairlineWidth).color(ColorTokens.separator)
        this.accessRow('行程卡片', '常驻桌面，随系统周期刷新（最小 30 分钟）', this.syncCard,
          (v: boolean): void => {
            this.syncCard = v;
          })
        Divider().strokeWidth(LayoutTokens.hairlineWidth).color(ColorTokens.separator)
        // 提醒的载体是日历事件（reminderTime 提前 1440 分钟），所以文案把依赖写死在句子里：
        // @Builder 参数是值快照、bindSheet 内容又不随父 @State 重绘，面板内做不出"实时置灰"，
        // 未开日历同步时由 writeToSystem 落 remind=false 并 toast 说明。
        this.accessRow('提醒', '需预约节点提前 1 天提醒（随日历同步写入）', this.syncRemind,
          (v: boolean): void => {
            this.syncRemind = v;
          })
      }
      .width('100%')
      .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm })

      Column() {
        Text('写入内容预览')
          .fontSize(TypeTokens.overline.size)
          .fontWeight(600)
          .fontColor(ColorTokens.muted)
          .alignSelf(ItemAlign.Start)
        Text(this.previewWhen())
          .fontSize(TypeTokens.caption.size)
          .fontColor(ColorTokens.ink)
          .fontFeature("'tnum' on")
        Text(this.previewWhat())
          .fontSize(TypeTokens.caption.size)
          .fontColor(ColorTokens.ink)
        Text(this.previewWhere())
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
        Text(this.previewNote())
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .fontFeature("'tnum' on")
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(SpaceTokens.sm)
      .borderRadius(RadiusTokens.reason)
      .backgroundColor(ColorTokens.surfacePanel)
      .margin({ top: SpaceTokens.sm })

      Row({ space: SpaceTokens.sm }) {
        YoujingButton({
          variant: YoujingButtonVariant.SECONDARY,
          label: '仅本机保存',
          buttonWidth: 150,
          onAction: (): void => {
            const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
            // 「仅本机保存」= 一条系统通路都不走：桌面卡片也是系统面，一并关掉并立刻停供数
            this.syncCard = false;
            this.syncRemind = false;
            CalendarSync.saveFlags(ctx, { calendar: false, card: false, remind: false })
              .then((): Promise<void> => {
                return WidgetSync.refreshAll(ctx);
              })
              .catch((err: Error): void => {
                Logger.warn('Ui.Itinerary', `触达开关保存失败: ${err.message}`);
              });
            this.showSystemAccess = false;
          }
        })
        Column() {
          YoujingButton({
            variant: YoujingButtonVariant.PRIMARY,
            label: '同意并写入',
            fullWidth: true,
            onAction: (): void => {
              this.writeToSystem();
            }
          })
        }
        .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: SpaceTokens.lg })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: SpaceTokens.base, right: SpaceTokens.base, bottom: SpaceTokens.lg })
    .backgroundColor(ColorTokens.canvas)
  }

  /** 绝对滚动偏移 → 顶栏磨砂开关（>0 即开，静止归零）；偏移取自复用的 listScroller */
  private syncBarScroll(): void {
    const y: number = this.listScroller.currentOffset().yOffset;
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
        Column() {
          // Day 分段栏（官方 SegmentButton + 材质）；标题与分享/编辑已迁到官方标题栏。
          // 单日行程不挂：官方 SegmentButton 只有一项时首帧会改内部 buttonBorderRadius，
          // 触发「state changed during render」把整屏内容打断成空白（真机 2026-10-30：
          // 1 天行程的屏8 只剩标题栏）。一天也没有可切换的对象，日标题已带 Day 1。
          if (this.days.length > 1) {
            Column() {
              Row() {
                ImmersiveSegmentBar({
                  items: this.segments,
                  selectedIndex: $dayIndex,
                  buttonVerticalPadding: 2.15,
                  // 契约四处玻璃面之一：分段控件轨道走系统材质（handoff §5/§9）。
                  // 本页轨道下有 surfaceElevated 实色背板而非滚动内容，lightContent 保持 false
                  overrideTrackMaterial: true,
                  a11yLabel: '行程日期切换'
                })
              }
              .width('100%')
              .justifyContent(FlexAlign.Start)
              .padding({ left: SpaceTokens.base, right: SpaceTokens.base, bottom: SpaceTokens.xs })
            }
            .backgroundColor(ColorTokens.surfaceElevated)
          }

          // 官方 List：地图面板一个 ListItem，节点与通勤腿各成一个 ListItem，
          // 日标题走 ListItemGroup 的 header —— 底稿写的「吸顶日标题」由 sticky 真正兑现。
          // 行距 12px（itinerary-block-gap）：不传 space 时 List 默认 0，站点行与交通腿会紧贴
          List({ space: LayoutTokens.itineraryBlockGap, scroller: this.listScroller }) {
            // 当天没有落点时**整块地图卡不出**：原来它照样撑满 mapHeightCompact，
            // 只剩一个深蓝渐变空盒加角落一枚「当日暂无安排」——主屏三分之一的面积
            // 既没信息也不可点（实拍确认）
            if (this.dayStops.length > 0) {
            ListItem() {
              // 地图面板：有可用坐标就上真实底图（当天落点 + 分段动线）
              Stack({ alignContent: Alignment.BottomStart }) {
                TripMapView({
                  stops: this.dayStops,
                  signature: this.daySig,
                  request: this.mapRequest,
                  onStopClick: (index: number): void => {
                    this.onMapStopTap(index);
                  }
                })
                  .width('100%')
                  .height('100%')
                Row() {
                  Text(this.dayRouteSummary())
                    .fontSize(TypeTokens.caption.size)
                    .fontWeight(450)
                    .fontColor(ColorTokens.ink)
                    .fontFeature("'tnum' on")
                    .height(28)
                    .padding({ left: SpaceTokens.xs, right: SpaceTokens.xs })
                    .borderRadius(RadiusTokens.pill)
                    .backgroundColor(ColorTokens.canvas)
                    // 真模型会把通勤方式写全（「地铁+市郊铁路 1 段 · 步行 4 段 · 市郊铁路+地铁 1 段」46 字），
                    // mock 那句只有 14 字——所以这条只有在真数据下才暴露：胶囊不限宽，
                    // 把右侧「全图」顶到 origBounds 1009..1158 而 bounds 只剩 1009..1086（裁掉 23vp）。
                    // 让位给文字侧：可缩 + 单行省略，按钮保持原尺寸。
                    .flexShrink(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Blank()
                  // 与地图页 chip 同档的官方 Button（原来是裸 Text + onClick）。
                  // 走过 NORMAL 档：真机上胶囊表面在底图上完全不出色（量到与瓦片同色），
                  // 显式 backgroundColor 也被样式吃掉，所以用 EMPHASIZED 档——
                  // 实底胶囊压在瓦片上反而读得清，配色与地图页选中档一致
                  Button('全图')
                    .fontSize(TypeTokens.caption.size)
                    .fontWeight(500)
                    // 28 → 44：全仓扫「可点节点热区 < 44vp」时唯一的真命中，
                    // 低于平台最小热区。旁边那枚 28 高的是标签不是控件，
                    // 两者不再等高是应该的——高度差本身在说"这个能按"
                    .height(LayoutTokens.minTouchTarget)
                    .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm })
                    .type(ButtonType.Capsule)
                    .buttonStyle(ButtonStyleMode.EMPHASIZED)
                    .onClick(() => {
                      this.pathStack.pushPath({ name: 'Map', param: this.tripId });
                    })
                }
                .width('100%')
                // 原来是 `.width('100%')` + `.margin(inset - 8)`：百分比宽不扣边距，
                // 加了左 margin 就整体右移，md 实测这行的 orig 到 2018、父级内容右缘只有
                // 1993 —— 「全图」钮被地图卡的 clip 切掉 8vp（25px）。
                // 内缩改用 padding：占位仍在 100% 之内，钮不再被切。
                .padding({ left: LayoutTokens.mapOverlayInset - 8,
                  right: LayoutTokens.mapOverlayInset - 8,
                  bottom: LayoutTokens.mapOverlayInset - 8 })
              }
              .width('100%')
              .height(LayoutTokens.mapHeightCompact)
              .borderRadius(RadiusTokens.card)
              .clip(true)
              .margin({ top: SpaceTokens.sm })
            }
            }

            ListItemGroup({ header: this.dayHeader() }) {
              if (this.curDay().activities.length === 0) {
                ListItem() {
                  // 空白天原来只有一行 12vp 灰字，下面五成屏是纯黑，且**没有任何前进通路**
                  // ——用户站在这屏既加不了节点也退不出去。按契约 empty-state 规格补齐
                  Column({ space: SpaceTokens.sm }) {
                    SymbolGlyph($r('sys.symbol.map'))
                      .fontSize(IconSizes.display)
                      .fontColor([ColorTokens.muted])
                    Text('这一天还没有安排节点')
                      .fontSize(TypeTokens.title.size)
                      .fontWeight(700)
                      .fontFamily(TypeTokens.title.family)
                      .fontColor(ColorTokens.ink)
                      .textAlign(TextAlign.Center)
                    Text('AI 排好的动线里这一天是空的，去编辑页可以补选景点')
                      .fontSize(TypeTokens.small.size)
                      .fontColor(ColorTokens.body)
                      .textAlign(TextAlign.Center)
                      .constraintSize({ maxWidth: 240 })
                    YoujingButton({
                      variant: YoujingButtonVariant.PRIMARY,
                      label: '去添加景点',
                      buttonWidth: 200,
                      onAction: (): void => {
                        const target: EditTarget = { tripId: this.tripId, dayIndex: this.dayIndex };
                        this.pathStack.pushPath({ name: 'EditItinerary', param: target });
                      }
                    })
                  }
                  .alignItems(HorizontalAlign.Center)
                  .width('100%')
                  // 空态占满一屏可视高并居中：原来它贴在 List 顶上，
                  // 下面五成屏是纯黑，看着像页面没加载完（§5.5「断在半空」同一件事）
                  .height('100%')
                  .justifyContent(FlexAlign.Center)
                }
              }
              ForEach(this.curDay().activities,
                (act: Activity, idx: number) => {
                  ListItem() {
                    this.stopRow(act, idx === this.curDay().activities.length - 1)
                  }
                  if (idx < this.curDay().activities.length - 1 &&
                    this.curDay().activities[idx + 1].transport !== undefined) {
                    ListItem() {
                      this.transitLeg(this.curDay().activities[idx + 1])
                    }
                  }
                }, (act: Activity): string =>
                  `itin-${this.tripId}-${this.dayIndex}-${act.id}-${act.title}-` +
                  `${act.id === this.focusActId ? 'f' : 'n'}`)
            }
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .sticky(StickyStyle.Header)
          .cachedCount(6)
          .padding({ left: SpaceTokens.base, right: SpaceTokens.base,
            bottom: LayoutTokens.floatingDockClearance })
          // 时间轴是单列长内容，不能按断点分栏（会打断主轴竖线），
          // 所以宽屏走"收窄 + 居中"这条路
          .width(longFormMaxWidth(this.bp, LayoutTokens.contentMaxWidth))
          .onDidScroll((): void => {
            this.syncBarScroll();
          })
        }
        .width('100%')
        .height('100%')

        // 浮动 dock（玻璃点位③，共享组件；屏14 触达面板挂在这层壳上，
        // 因为一个节点只能挂一个 bindSheet，Stack 自己已经绑了屏10 详情面板）
        Column() {
        }
        .bindSheet($$this.showSystemAccess, this.systemAccessSheet(), {
          height: SheetSize.FIT_CONTENT,
          backgroundColor: ColorTokens.canvas,
          showClose: true,
          systemMaterial: getSheetImmersiveMaterial()
        })
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
    // HDS 深色档这层默认纯黑，透明栏会把它露成一条比画布暗一档的带（成因与实测见 Docs/INIT_REPORT.md §5ci 续 80）
    .backgroundColor(ColorTokens.canvas)
    .titleBar(HdsChrome.bar({
      mainTitle: this.titleText,
      scrolled: this.barScrolled,
      // 顺序按使用频率，不是按"导出/编辑/系统"的讲述顺序：真机实测 `menuMaxCount: 2`
      // 只直出**第一枚**（第二枚位置被官方「更多」占掉），所以第一枚必须是最高频动作。
      // 原来第一枚是「分享行程」，于是「编辑行程」——改行程的主路径——被收进溢出菜单，
      // 而溢出菜单在注入点击下不展开（hdc uiInput 打不开 HDS 的 ⋯），自动化也够不着它。
      menu: [
        HdsChrome.item($r('sys.symbol.square_and_pencil'), '编辑行程', (): void => {
          this.pathStack.pushPath({
            name: 'EditItinerary',
            param: { tripId: this.tripId, dayIndex: this.dayIndex } as EditTarget
          });
        }),
        HdsChrome.item($r('sys.symbol.share'), '分享行程', (): void => {
          this.pathStack.pushPath({ name: 'Share', param: this.tripId });
        }),
        HdsChrome.item($r('sys.symbol.calendar'), '写入系统与提醒', (): void => {
          this.showSystemAccess = true;
        })
      ],
      // 三枚全部直出（不给 ⋯）。两条实测理由：
      // ① 帧在屏10 顶栏**同时声明**了「分享」与「编辑」，`menuMaxCount: 2` 实测只直出第一枚，
      //    等于把另一条帧声明的动作藏进溢出菜单；
      // ② 官方 ⋯ 不吃注入点击（三种坐标都试过），藏进去的项自动化永远够不着。
      //    宽度实测够用：标题「北京 · 3天2晚」右缘 x=590，三枚槽位占 636–1086。
      menuMaxCount: 3
    }))
    .onReady((ctx: NavDestinationContext): void => {
      this.pathStack = ctx.pathStack;
    })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .onShown((): void => {
      this.reload();
    })
  }
}
