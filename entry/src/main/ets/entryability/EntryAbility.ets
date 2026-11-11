import {
  AbilityConstant, abilityAccessCtrl, Configuration, ConfigurationConstant, Permissions, skillManager, UIAbility, Want
} from '@kit.AbilityKit';
import { geoLocationManager } from '@kit.LocationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { display, window } from '@kit.ArkUI';
import { resourceManager } from '@kit.LocalizationKit';
import { initBreakpointCenter } from '../utils/breakpointCenter';
import { Logger } from '../common/logger/Logger';
import { stackOfRoute, tabOfRoute, isTabRoot, requestTab, TAB_INDEX_KEY, ACTIVE_TRIP_KEY, markDraftDirty } from '../common/constants/AppNav';
import { DataSeeder } from '../data/DataSeeder';
import { AccountStore } from '../data/AccountStore';
import { PlanDraft } from '../data/PlanDraft';
import {
  PaceOption, PlanParams, SelectedSpot, SpotPriority, TransitPreference, TravelStyle, TripBasicInput
} from '../model/PlanParams';
import { DateUtils } from '../utils/DateUtils';
import { SkillPrefill, SkillPrefillRecord } from '../data/SkillPrefill';
import { BuildConfig } from '../common/constants/BuildConfig';
import { BudgetConfig } from '../common/constants/BudgetConfig';
import { WidgetSync } from '../widget/TodayCard';
import { TopStrip } from '../utils/TopStrip';
import { initNavModeWatcher, refreshNavMode, publishNavAvoid, isThreeButtonNav } from '../utils/navMode';
import { setSystemBarRefresher } from '../utils/systemBar';
import { TripReminder } from '../data/TripReminder';
import { DeviceActivator } from '../data/DeviceActivator';
import { DeviceTokenStore } from '../data/DeviceTokenStore';
import { ApiConfig } from '../common/config/ApiConfig';
import { LlmClient } from '../ai/LlmClient';
import { PickClient } from '../ai/PickClient';
import { PickCandidate, PickResult } from '../model/Pick';
import { PlanRepository } from '../data/PlanRepository';
import { Spot } from '../model/Spot';
import { Area } from '../model/Area';
import { Activity, ActivityCategory, ActivityStatus, IntensityLevel, MealType, Trip, TripDay } from '../model/Trip';
import { ArrivalNotice } from '../common/location/ArrivalNotice';
import { ArrivalWatcher } from '../common/location/ArrivalWatcher';
import { Geo, GeoPoint } from '../utils/Geo';

interface CoordDistance {
  id: string;
  name: string;
  d: number;
  latitude: number;
  longitude: number;
}

export default class EntryAbility extends UIAbility {
  private pendingRoute: string = '';
  private pendingParam: string = '';
  /** 页面已 load 完（Navigation 可推栈） */
  private contentReady: boolean = false;
  /** 真正对用户可见：后台被 Skill 绑起时不能消费预填，否则进程一杀就丢 */
  private visible: boolean = false;
  /** 深浅档探针生效时**不能**再在 onWindowStageCreate 把 colorMode 复位成 NOT_SET，
   *  否则那次复位会把 App 级档位又翻回跟随系统——实测过：日志 isDarkMode=true、界面却仍是浅色 */
  private colorProbe: boolean = false;
  /** 主窗口句柄：上下两条系统栏带区的底色要在配置切换后重设一次 */
  private mainWin: window.Window | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    Logger.info('EntryAbility', 'Ability onCreate');
    // 深色档必须冷启就播种。isDarkMode 此前只在 onConfigurationUpdate 里写，
    // 而那个回调只在配置**变化**时才来：直接以深色档冷启时它不来，
    // 于是全仓 7 处 @StorageProp('isDarkMode') 一律按浅色走——
    // 深色零阴影门控失效、底图不换暗色主题、分段栏选中底色与文字色分支整段跳过。
    this.applyColorProbe(want);
    this.seedDarkMode();
    this.applyWant(want);
    this.maybeReminderProbe(want);
    this.maybeGeofenceProbe(want);
    this.maybeGenProbe(want);
    this.maybeArrivalProbe(want);
    this.maybeReminderSyncProbe(want);
    this.maybePickProbe(want);
    this.maybeCoordProbe(want);
  }

  /**
   * 杨凌坐标校准探针：`--ps coordprobe 1`
   * 站在景点里读一次 GPS，打印最近 3 个种子站与距离，用来回填 DataSeeder 坐标。
   */
  private maybeCoordProbe(want: Want): void {
    if (!BuildConfig.IS_DEBUG) {
      return;
    }
    const params: Record<string, Object> | undefined = want.parameters;
    if (params === undefined || EntryAbility.wantString(params, 'coordprobe') !== '1') {
      return;
    }
    this.runCoordProbe().catch((err: Error) => {
      Logger.error('Probe.Coord', `坐标探针失败: ${err.message}`);
    });
  }

  private async runCoordProbe(): Promise<void> {
    const tag: string = 'Probe.Coord';
    if (!canIUse('SystemCapability.Location.Location.Core')) {
      Logger.warn(tag, '本设备无定位能力');
      return;
    }
    try {
      if (!geoLocationManager.isLocationEnabled()) {
        Logger.warn(tag, '系统定位总开关关闭');
        return;
      }
    } catch (err) {
      Logger.warn(tag, `定位开关读取失败: ${(err as Error).message}`);
      return;
    }
    if (!await ArrivalWatcher.ensurePermission(this.context)) {
      Logger.warn(tag, '定位权限未授予');
      return;
    }
    const spots: Spot[] = await PlanRepository.loadSpots(this.context, '杨凌');
    if (spots.length === 0) {
      Logger.warn(tag, '杨凌景点库为空');
      return;
    }
    const request: geoLocationManager.CurrentLocationRequest = {
      priority: geoLocationManager.LocationRequestPriority.ACCURACY,
      scenario: geoLocationManager.LocationRequestScenario.DAILY_LIFE_SERVICE,
      maxAccuracy: 100,
      timeoutMs: 12000
    };
    try {
      const loc: geoLocationManager.Location =
        await geoLocationManager.getCurrentLocation(request);
      Logger.info(tag, `fix lat=${loc.latitude.toFixed(6)} lng=${loc.longitude.toFixed(6)} ` +
        `acc=${loc.accuracy.toFixed(0)}m`);
      const origin: GeoPoint = { latitude: loc.latitude, longitude: loc.longitude };
      const ranked: CoordDistance[] = spots.map((s: Spot): CoordDistance => {
        const target: GeoPoint = { latitude: s.latitude, longitude: s.longitude };
        return {
          id: s.id, name: s.name, d: Geo.distanceM(origin, target),
          latitude: s.latitude, longitude: s.longitude
        };
      }).sort((a: CoordDistance, b: CoordDistance): number => a.d - b.d);
      const top: number = Math.min(3, ranked.length);
      for (let i = 0; i < top; i++) {
        const r: CoordDistance = ranked[i];
        Logger.info(tag, `#${i + 1} ${r.name} 距离=${r.d.toFixed(0)}m ` +
          `seed=${r.latitude},${r.longitude}`);
      }
      if (ranked[0].d <= Geo.ARRIVAL_RADIUS_M) {
        Logger.info(tag, `最近站已在 ${Geo.ARRIVAL_RADIUS_M}m 内：${ranked[0].name}`);
      }
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      Logger.error(tag, `定位失败 code=${be.code} msg=${be.message}`);
    }
  }

  /**
   * P1 精选探针：`--ps pickprobe 1`
   * 用杨凌 10 站候选直接调 PickClient，验证 AGC/BFF/端侧直连三条通路的结构与理由。
   */
  private maybePickProbe(want: Want): void {
    if (!BuildConfig.IS_DEBUG) {
      return;
    }
    const params: Record<string, Object> | undefined = want.parameters;
    if (params === undefined || EntryAbility.wantString(params, 'pickprobe') !== '1') {
      return;
    }
    this.runPickProbe().catch((err: Error) => {
      Logger.error('Probe.Pick', `精选探针失败: ${err.message}`);
    });
  }

  private async runPickProbe(): Promise<void> {
    const spots: Spot[] = await PlanRepository.loadSpots(this.context, '杨凌');
    if (spots.length === 0) {
      Logger.error('Probe.Pick', '杨凌景点库为空');
      return;
    }
    const candidates: PickCandidate[] = [];
    for (const s of spots) {
      candidates.push({
        id: s.id, name: s.name, tag: s.tags.join('/'), brief: s.brief,
        district: s.district, popularity: s.popularity,
        suggestedDuration: s.suggestedDuration, requiresBooking: s.booking.requiresBooking
      });
    }
    const started: number = Date.now();
    // 探针在 onCreate 里跑，早于 Index 的设备激活；BFF 通路需要 Bearer token，先补一次激活
    if (ApiConfig.BFF_BASE_URL.length > 0 && !DeviceTokenStore.hasToken()) {
      const activated: boolean = await DeviceActivator.activate(this.context);
      Logger.info('Probe.Pick', `设备激活=${activated}`);
    }
    const result: PickResult | null = await PickClient.pickSpots(
      '杨凌', 1, 'standard', '农业科技、历史人文、亲子', candidates);
    if (result === null) {
      Logger.warn('Probe.Pick', `精选失败，已回退确定性规则 candidates=${candidates.length} ` +
        `ms=${Date.now() - started}`);
      return;
    }
    Logger.info('Probe.Pick', `精选成功 ranked=${result.ranked.length} ms=${Date.now() - started}`);
    for (let i = 0; i < result.ranked.length && i < 3; i++) {
      Logger.info('Probe.Pick', `#${i + 1} ${result.ranked[i].id} ${result.ranked[i].reason}`);
    }
    if (result.note.length > 0) {
      Logger.info('Probe.Pick', `note=${result.note}`);
    }
  }

  /**
   * P4 提醒全链路探针：`--ps remindsyncprobe 1`
   * 用一条带 advanceDays=7 预约节点的合成行程跑 TripReminder.syncTrip，
   * 验证受管控设备上能识别 blockedByCapability，而不是只报泛泛失败。
   */
  private maybeReminderSyncProbe(want: Want): void {
    if (!BuildConfig.IS_DEBUG) {
      return;
    }
    const params: Record<string, Object> | undefined = want.parameters;
    if (params === undefined || EntryAbility.wantString(params, 'remindsyncprobe') !== '1') {
      return;
    }
    this.runReminderSyncProbe().catch((err: Error) => {
      Logger.error('Probe.RemindSync', `提醒全链路探针失败: ${err.message}`);
    });
  }

  private async runReminderSyncProbe(): Promise<void> {
    const d: Date = new Date(Date.now() + 10 * 86400000);
    const iso: string = `${d.getFullYear()}-${`${d.getMonth() + 1}`.padStart(2, '0')}-` +
      `${d.getDate()}`.padStart(2, '0');
    const booking: Activity = {
      id: 'probe-booking', time: '09:00', endTime: '10:30',
      title: '农高会会址', location: '', address: '',
      longitude: 108.0600, latitude: 34.2600,
      status: ActivityStatus.NOT_BOOKED, category: ActivityCategory.SIGHT,
      advanceDays: 7
    };
    const trip: Trip = {
      id: `remindprobe-${Date.now()}`,
      destination: '杨凌', startDate: iso, endDate: iso, people: 2, budget: 800,
      style: 'leisure',
      overview: { totalCost: 100, highlights: [], summary: '提醒探针' },
      days: [{
        dayIndex: 1, date: iso, theme: '提醒探针', intensity: IntensityLevel.LOW,
        dailyCost: 100, activities: [booking],
        meals: [
          { type: MealType.LUNCH, time: '12:00', name: '午餐', location: '', estimatedCost: 50 },
          { type: MealType.DINNER, time: '18:00', name: '晚餐', location: '', estimatedCost: 50 }
        ]
      }],
      tips: []
    };
    const before: number = await TripReminder.clearAllForProbe();
    Logger.info('Probe.RemindSync', `清理前有效提醒=${before}`);
    const r = await TripReminder.syncTrip(this.context, trip);
    Logger.info('Probe.RemindSync', `scheduled=${r.scheduled} failed=${r.failed} ` +
      `notifications=${r.notificationsEnabled} blocked=${r.blockedByCapability} ` +
      `blockedLimit=${r.blockedByLimit}`);
  }

  /** P5 到站通知探针：`--ps arrivalprobe 1` 发一条到站本地通知，用于锁屏/退后台可见性验收 */
  private maybeArrivalProbe(want: Want): void {
    if (!BuildConfig.IS_DEBUG) {
      return;
    }
    const params: Record<string, Object> | undefined = want.parameters;
    if (params === undefined || EntryAbility.wantString(params, 'arrivalprobe') !== '1') {
      return;
    }
    this.runArrivalProbe().catch((err: Error) => {
      Logger.error('Probe.Arrival', `到站通知探针失败: ${err.message}`);
    });
  }

  private async runArrivalProbe(): Promise<void> {
    const day: TripDay = {
      dayIndex: 1, date: '2026-11-10', theme: '到站通知探针',
      intensity: IntensityLevel.LOW, dailyCost: 0, activities: [], meals: []
    };
    const stop: Activity = {
      id: 'yl-001', time: '09:00', endTime: '12:00',
      title: '西北农林科技大学博览园', location: '', address: '',
      longitude: 108.0700, latitude: 34.2680,
      status: ActivityStatus.NOT_BOOKED, category: ActivityCategory.SIGHT
    };
    const ok: boolean = await ArrivalNotice.publishForStop(day, stop);
    Logger.info('Probe.Arrival', `到站通知探针 ok=${ok}`);
  }

  /**
   * P0 生成探针：`aa start -a EntryAbility -b com.youjing.app --ps genprobe 1`
   * 用杨凌种子（10 站 / 5 片区）生成 1 天行程，验证端侧传输 + TripParser + 落库前回填。
   * 只在 debug 版生效；不带参数时零行为。
   */
  private maybeGenProbe(want: Want): void {
    if (!BuildConfig.IS_DEBUG) {
      return;
    }
    const params: Record<string, Object> | undefined = want.parameters;
    if (params === undefined || EntryAbility.wantString(params, 'genprobe') !== '1') {
      return;
    }
    this.runGenProbe().catch((err: Error) => {
      Logger.error('Probe.Gen', `杨凌生成探针失败: ${err.message}`);
    });
  }

  private async runGenProbe(): Promise<void> {
    const tag: string = 'Probe.Gen';
    await DataSeeder.seedIfEmpty(this.context);
    const spots: Spot[] = await PlanRepository.loadSpots(this.context, '杨凌');
    const areas: Area[] = await PlanRepository.loadAreas(this.context, '杨凌');
    if (spots.length === 0 || areas.length === 0) {
      Logger.error(tag, `杨凌种子为空 spots=${spots.length} areas=${areas.length}`);
      return;
    }
    let area: Area = areas[0];
    for (const a of areas) {
      if (a.name.indexOf('西农') >= 0) {
        area = a;
        break;
      }
    }
    const selected: SelectedSpot[] = [];
    const mustIds: string[] = ['yl-001', 'yl-002', 'yl-005'];
    for (const id of mustIds) {
      const s: Spot | undefined = spots.find((x: Spot): boolean => x.id === id);
      if (s !== undefined) {
        selected.push({ spotId: s.id, priority: SpotPriority.MUST });
      }
    }
    if (selected.length === 0) {
      for (let i = 0; i < spots.length && i < 3; i++) {
        selected.push({ spotId: spots[i].id, priority: SpotPriority.MUST });
      }
    }
    const d: Date = new Date(Date.now() + 86400000);
    const iso: string = `${d.getFullYear()}-${`${d.getMonth() + 1}`.padStart(2, '0')}-` +
      `${d.getDate()}`.padStart(2, '0');
    const params: PlanParams = {
      basic: { destination: '杨凌', startDate: iso, endDate: iso, people: 2, budget: 800 },
      style: TravelStyle.LEISURE,
      stayTier: 'comfort',
      transit: TransitPreference.PUBLIC,
      paces: [PaceOption.STANDARD],
      selectedSpots: selected,
      selectedArea: { areaId: area.id }
    };
    Logger.info(tag, `开始生成 杨凌 ${iso} 站点=${spots.length} 片区=${areas.length} ` +
      `必去=${selected.length} 片区=${area.name}`);
    const started: number = Date.now();
    const trip: Trip = await LlmClient.generateTrip(
      params, spots, area, undefined, this.context, 'genprobe');
    let acts: number = 0;
    for (const day of trip.days) {
      acts += day.activities.length;
    }
    Logger.info(tag, `杨凌生成成功 days=${trip.days.length} activities=${acts} ` +
      `totalCost=${trip.overview.totalCost} ms=${Date.now() - started}`);
    for (const day of trip.days) {
      Logger.info(tag, `D${day.dayIndex} ${day.date} 活动=${day.activities.length} 餐=${day.meals.length}`);
    }
  }

  /**
   * P5 围栏探针：`aa start ... --ps geoprobe 1` 用杨凌博览园坐标注册一个 100m 围栏。
   * 注册成功/失败码就是「AGC 围栏服务是否开通」的运行时证据；只在 debug 版生效。
   */
  private maybeGeofenceProbe(want: Want): void {
    if (!BuildConfig.IS_DEBUG) {
      return;
    }
    const params: Record<string, Object> | undefined = want.parameters;
    if (params === undefined || EntryAbility.wantString(params, 'geoprobe') !== '1') {
      return;
    }
    this.runGeofenceProbe();
  }

  private async runGeofenceProbe(): Promise<void> {
    const tag: string = 'Probe.Geofence';
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const perms: Permissions[] = ['ohos.permission.LOCATION', 'ohos.permission.APPROXIMATELY_LOCATION'];
      const grant = await atManager.requestPermissionsFromUser(this.context, perms);
      Logger.info(tag, `授权 authResults=${JSON.stringify(grant.authResults)}`);
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      Logger.error(tag, `授权异常 code=${be.code} ${be.message}`);
      return;
    }
    const fence: geoLocationManager.Geofence = {
      latitude: 34.2680, longitude: 108.0700, radius: 100, expiration: 600
    };
    const request: geoLocationManager.GnssGeofenceRequest = {
      geofence: fence,
      monitorTransitionEvents: [
        geoLocationManager.GeofenceTransitionEvent.GEOFENCE_TRANSITION_EVENT_ENTER,
        geoLocationManager.GeofenceTransitionEvent.GEOFENCE_TRANSITION_EVENT_DWELL
      ],
      loiterTimeMs: 10000,
      geofenceTransitionCallback: (err: BusinessError, transition: geoLocationManager.GeofenceTransition): void => {
        Logger.info(tag, `围栏事件 err=${err === null || err === undefined ? 0 : err.code} ` +
          `payload=${JSON.stringify(transition)}`);
      }
    };
    try {
      const id: number = await geoLocationManager.addGnssGeofence(request);
      Logger.info(tag, `围栏注册成功 id=${id}`);
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      Logger.error(tag, `围栏注册失败 code=${be.code} msg=${be.message}`);
    }
  }

  /**
   * 提醒探针：`aa start -a EntryAbility -b com.youjing.app --ps remindprobe 45`
   * 发一条 45 秒后的系统提醒，用于真机验收 P4「退后台/锁屏后提醒真的响」。
   * 只在 debug 版生效；不带参数时零行为。
   */
  private maybeReminderProbe(want: Want): void {
    if (!BuildConfig.IS_DEBUG) {
      return;
    }
    const params: Record<string, Object> | undefined = want.parameters;
    if (params === undefined) {
      return;
    }
    const raw: Object | undefined = params['remindprobe'];
    let seconds: number = 0;
    if (typeof raw === 'number') {
      seconds = raw as number;
    } else if (typeof raw === 'string') {
      seconds = Number(raw as string);
    }
    if (!(seconds > 0)) {
      return;
    }
    TripReminder.publishProbe(this.context, seconds).catch((err: Error) => {
      Logger.error('EntryAbility', `提醒探针失败: ${err.message}`);
    });
  }

  /**
   * 深浅档走查探针（只在 debug 版、只在显式带 `--ps darkprobe 1` 或 `--ps lightprobe 1` 时生效）。
   * 本机没有 `settings`/`uimode` 命令可以切系统深浅档（第 4 把尺因此只能量像素），
   * 而把用户的手机翻成深色或浅色去截图是一次他设备上的可见改动——所以走 **App 级** setColorMode：
   * 只把本 App 钉进指定档，系统主题一点不动。
   */
  private applyColorProbe(want: Want): void {
    if (!BuildConfig.IS_DEBUG) {
      return;
    }
    const params: Record<string, Object> | undefined = want.parameters;
    if (params === undefined) {
      return;
    }
    const dark: boolean = EntryAbility.wantString(params, 'darkprobe') === '1';
    const light: boolean = EntryAbility.wantString(params, 'lightprobe') === '1';
    if (!dark && !light) {
      return;
    }
    const mode: ConfigurationConstant.ColorMode = dark ?
      ConfigurationConstant.ColorMode.COLOR_MODE_DARK : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    try {
      this.context.getApplicationContext().setColorMode(mode);
      this.colorProbe = true;
      Logger.info('EntryAbility', `${dark ? 'darkprobe' : 'lightprobe'}=1：本 App 钉进${dark ? '深色' : '浅色'}档（系统主题未改）`);
    } catch (err) {
      Logger.warn('EntryAbility', `setColorMode 探针失败: ${(err as Error).message}`);
    }
  }

  /**
   * 小艺 Skill / 深链在 App 已存活时的入口：单例 UIAbility 复用当前页面栈，
   * 参数直接落到导航与屏2 草稿，不再重建窗口。
   */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const touched: boolean = this.applyWant(want);
    if (this.pendingRoute.length > 0) {
      this.routeTo(this.pendingRoute, this.pendingParam);
      this.pendingRoute = '';
      this.pendingParam = '';
    }
    Logger.info('EntryAbility', `onNewWant 外部拉起 touched=${touched}`);
  }

  /**
   * 外部拉起参数通道（开发文档 §6 阶段 9「语音唤起 App 并预填参数」）。
   * 键：route 落点屏名；destination/start/end/days/people 预填屏2 基础输入。
   * 例：aa start -a EntryAbility -b com.youjing.app --ps route TripInput \
   *        --ps destination 上海 --ps start 2026-08-01 --ps days 4 --ps people 3
   * 非法日期与 days 一律忽略，不覆盖已有草稿。
   */
  private applyWant(want: Want): boolean {
    const params: Record<string, Object> | undefined = want.parameters;
    if (params === undefined) {
      return false;
    }
    let touched: boolean = false;
    if (typeof params['route'] === 'string') {
      this.pendingRoute = params['route'] as string;
      this.pendingParam = EntryAbility.wantString(params, 'param');
      touched = true;
      /**
       * 冷启就要落对页签：`onCreate` 早于 `onWindowStageCreate` 的 `loadContent`，
       * 这里先写 `TAB_INDEX_KEY`，`Index` 的 `@StorageLink wantTab` 初值才是目标页签。
       *
       * 为什么必须提前写：`Tabs` 懒建 TabContent，只有**初始那个**页签的内容与它的
       * `HdsNavigation` 在首帧就绑上栈。等 `routePending()` 再写就来不及了 ——
       * `wantTab` 已经按默认值建完，HdsTabs 的初始 index 改不动（真机实测：
       * 三条路径调 `changeIndex()` 全停在 tab 0），而那会儿 push 进未绑定的栈会丢
       * （§4k ④ 探针实测 routerMap 收到空名）。
       */
      AppStorage.setOrCreate(TAB_INDEX_KEY, tabOfRoute(this.pendingRoute));
    }
    const draft: PlanDraft = PlanDraft.get();
    const basic: TripBasicInput = {
      destination: draft.basic.destination, startDate: draft.basic.startDate,
      endDate: draft.basic.endDate, people: draft.basic.people, budget: draft.basic.budget
    };
    const dest: string = EntryAbility.wantString(params, 'destination');
    if (dest.length > 0) {
      basic.destination = dest;
      touched = true;
    }
    const start: string = EntryAbility.wantString(params, 'start');
    if (DateUtils.isValidIsoDate(start)) {
      basic.startDate = start;
      touched = true;
    }
    const end: string = EntryAbility.wantString(params, 'end');
    if (DateUtils.isValidIsoDate(end)) {
      basic.endDate = end;
      touched = true;
    }
    const days: number = EntryAbility.wantNumber(params, 'days');
    if (days > 1 && DateUtils.isValidIsoDate(basic.startDate)) {
      basic.endDate = DateUtils.addDays(basic.startDate, days - 1);
      touched = true;
    }
    const people: number = EntryAbility.wantNumber(params, 'people');
    if (people > 0) {
      basic.people = people;
      touched = true;
    }
    if (touched) {
      draft.basic = basic;
      // 冷启时本段早于 bootstrap 水合：置外部写标记，水合不得用盘上旧快照覆盖这份预填
      PlanDraft.markExternalWrite();
      PlanDraft.flush();
      // 这条外部 Want 已带同一批参数，作废可能还躺在盘上的 Skill 预填
      SkillPrefill.clear(this.context);
      Logger.info('EntryAbility',
        `外部预填 route=${this.pendingRoute} ${basic.destination} ${basic.startDate}→${basic.endDate} ${basic.people}人`);
    }
    return touched;
  }

  private static wantString(params: Record<string, Object>, key: string): string {
    const raw: Object | undefined = params[key];
    return typeof raw === 'string' ? raw as string : '';
  }

  private static wantNumber(params: Record<string, Object>, key: string): number {
    const raw: Object | undefined = params[key];
    if (typeof raw === 'number') {
      return raw as number;
    }
    if (typeof raw === 'string') {
      const parsed: number = Number(raw as string);
      return Number.isNaN(parsed) ? 0 : parsed;
    }
    return 0;
  }

  /** ARGB 亮度（够用即可，不追求 sRGB 精确） */
  private static luma(argb: number): number {
    return 0.2126 * ((argb >> 16) & 0xFF) + 0.7152 * ((argb >> 8) & 0xFF) + 0.0722 * (argb & 0xFF);
  }

  /**
   * 深色档判定。不能只读 `config.colorMode`：那个字段是**可选的**，
   * 冷启时实测拿不到值（undefined / NOT_SET），于是 `=== COLOR_MODE_DARK` 恒 false，
   * 全仓 7 处 @StorageProp('isDarkMode') 在深色档下全按浅色走
   * ——真机证据：深色档里地图 tab 渲染的是亮色路网主题。
   * 兜底改用资源管线自己说真话：把 canvas 与 ink 按「当前生效配置」解出来比亮度，
   * 深色档 ink(#F2F2F4) 比 canvas(#121212) 亮，浅色档反过来——不依赖任何硬编码色值。
   *
   * ⚠ `this.context.config` 只在**冷启**时新鲜；系统深浅实时切换时它停留旧值
   * （真机实证 2026-11-10：系统浅→深后 onConfigurationUpdate 里 context.config.colorMode
   * 仍是 1=浅色 → isDarkMode 恒 false → 状态栏黑字压深底、地图不换夜色主题、
   * 深色零阴影门控失效）。所以 onConfigurationUpdate 必须把 **newConfig** 传进来，
   * 且 newConfig.colorMode 缺失时直接走资源法——不回退到陈旧的 context.config。
   * 档位**变化**时自增 `chromeThemeTick`，HdsChrome 的标题内容缓存键带 tick，
   * 翻档后各页 build 重跑即换新 ComponentContent（详见 HdsChrome.themeTick）。
   */
  private seedDarkMode(fresh?: Configuration): void {
    const cm: ConfigurationConstant.ColorMode | undefined =
      fresh !== undefined ? fresh.colorMode : this.context.config.colorMode;
    let dark: boolean;
    if (cm === ConfigurationConstant.ColorMode.COLOR_MODE_DARK) {
      dark = true;
    } else if (cm === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT) {
      dark = false;
    } else {
      dark = false;
      try {
        const rm: resourceManager.ResourceManager = this.context.resourceManager;
        const canvas: number = rm.getColorSync($r('app.color.canvas').id);
        const ink: number = rm.getColorSync($r('app.color.ink').id);
        dark = EntryAbility.luma(ink) > EntryAbility.luma(canvas);
      } catch (err) {
        Logger.warn('EntryAbility', `资源法判深色档失败，按浅色处理: ${(err as Error).message}`);
      }
    }
    const prev: boolean | undefined = AppStorage.get<boolean>('isDarkMode');
    AppStorage.setOrCreate('isDarkMode', dark);
    if (prev !== undefined && prev !== dark) {
      AppStorage.setOrCreate('chromeThemeTick', (AppStorage.get<number>('chromeThemeTick') ?? 0) + 1);
    }
    Logger.info('EntryAbility', `isDarkMode=${dark}（config.colorMode=${cm}，fresh=${fresh !== undefined}）`);
  }

  /**
   * 把窗口铺满物理屏。
   *
   * 不开全屏时窗口本身被系统按避让区裁掉：真机实测 `root` 是 `[0,106][1136,2690]`，
   * 顶部 33.9vp 根本不在 App 的窗口里（那一条由系统画，App 无从着色，只能"贴着涂色"），
   * 而页面容器 `TabContent` 只到 2603 —— 底部 27.8vp 是指示条避让区，内容进不去。
   * 一屏 860.8vp，页面实际能用的只有 799vp，再减掉给悬浮 dock 让的 112vp，
   * 只剩 687vp：用户读到的就是"内容区显示不全、上下被截断"。
   *
   * 全屏只是把窗口还给物理屏；组件默认仍按避让区让位，所以这一步不会把标题推到
   * 状态栏底下。真正把内容铺到屏底的是各滚动容器的 `expandSafeArea`（见 pages/Index）。
   */
  private makeImmersive(windowStage: window.WindowStage): void {
    windowStage.getMainWindow().then((win: window.Window): Promise<void> => {
      this.mainWin = win;
      // 先发布避让区高度再翻全屏：页面第一次 build 就要能读到 statusBarHeight，
      // 晚一步首帧就会把顶栏裁掉一截
      this.publishAvoidArea(win);
      return win.setWindowLayoutFullScreen(true);
    }).then((): void => {
      this.applySystemBarSurface();
      this.applyNavigationBarPolicy();
      Logger.info('EntryAbility', '窗口已铺满物理屏（layoutFullScreen）');
    }).catch((err: Error): void => {
      Logger.warn('EntryAbility', `全屏布局未生效，按非全屏继续: ${err.message}`);
    });
  }

  /**
   * 底部导航条显隐策略（2026-11-11 用户令「删掉底部小白栏」）：窗口已铺满物理屏后，
   * 手势指示条是底部唯一一块非应用画的 chrome，隐藏后内容真正贴到物理屏底。
   * 两层 API 各管一件事（真机实证）：
   *  - `setWindowSystemBarEnable(['status'])` 只控**三键导航栏**（SDK 注释明说 three-button），
   *    对手势胶囊条无效——留着是给三键用户兜底；
   *  - 手势条要 `setSpecificSystemBarEnabled('navigationIndicator', false)`（since 11）。
   * 三键导航必须保留（藏掉等于砍掉用户唯一导航）。回前台要重设（onForeground）：
   * 后台期间系统可能把导航条带回来，与 applySystemBarSurface 同一动机。
   * 上滑返回桌面是系统边缘手势，不依赖指示条显示，隐藏后照常可用。
   */
  private applyNavigationBarPolicy(): void {
    const win: window.Window | null = this.mainWin;
    if (win === null) {
      return;
    }
    if (isThreeButtonNav()) {
      win.setWindowSystemBarEnable(['status', 'navigation']).catch((err: Error): void => {
        Logger.warn('EntryAbility', `恢复三键导航栏失败: ${err.message}`);
      });
      return;
    }
    win.setWindowSystemBarEnable(['status']).catch((err: Error): void => {
      Logger.warn('EntryAbility', `设置系统栏显隐失败: ${err.message}`);
    });
    win.setSpecificSystemBarEnabled('navigationIndicator', false).catch((err: Error): void => {
      Logger.warn('EntryAbility', `隐藏手势指示条失败: ${err.message}`);
    });
  }

  /** 避让区高度（px + vp 两份）：vp 用屏幕密度换算，Ability 侧没有 UIContext.px2vp */
  private publishAvoidArea(win: window.Window): void {
    try {
      const density: number = display.getDefaultDisplaySync().densityPixels;
      const top: number = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).topRect.height;
      const nav: number = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR).bottomRect.height;
      AppStorage.setOrCreate('statusBarPx', top);
      AppStorage.setOrCreate('statusBarHeight', density > 0 ? top / density : 0);
      AppStorage.setOrCreate('navIndicatorPx', nav);
      AppStorage.setOrCreate('navIndicatorHeight', density > 0 ? nav / density : 0);
      // 把避让矩形的宽也交进 navMode：只看高度判不开手势条与三键栏（两者实测 27.9 / 27.8vp）
      publishNavAvoid(win);
      Logger.info('EntryAbility', `避让区 状态栏=${top}px 指示条=${nav}px 密度=${density}`);
    } catch (err) {
      Logger.warn('EntryAbility', `读避让区失败: ${(err as Error).message}`);
    }
  }

  /**
   * 上下两条系统栏带区的底色。
   *
   * 这一屏窗口不是全屏布局（契约 §4「状态栏不许玻璃化」把状态栏当设备 chrome，
   * 内容只让位、不铺进去），于是上下各留一条带区：顶部按 `statusBarColor`、
   * 底部在手势导航下**不透传系统栏色而透传窗口背景色**（官方论坛确认
   * `navigationBarColor` 手势导航下不生效，同族工程实测过）。两者默认都是纯黑，
   * 而深色档画布是 #121212 —— 差一档亮度，用户读到的就是"每屏上下都有黑边"。
   * 浅色档画布 #FFFFFF 与默认白条看不出差别，所以这条缺陷只在深色档暴露。
   *
   * 色值不硬编码：走资源管线按**当前生效配置**解 `app.color.canvas`，
   * 与 `seedDarkMode` 同一手法，深浅两档一次实现覆盖。
   */
  private applySystemBarSurface(): void {
    const win: window.Window | null = this.mainWin;
    if (win === null) {
      return;
    }
    // 涂哪个色由 TopStrip 单点决定（画布 / 底图基色），这里只负责在配置变化、
    // 回前台、HDS 挂载期回写之后按同一个口径重涂
    TopStrip.paint(win, this.context, TopStrip.current());
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    // 深色零阴影门控（契约 §4）：页面用 @StorageProp('isDarkMode') 决定是否挂 elevation。
    // 必须传 newConfig：实时切换下 context.config 是旧值（见 seedDarkMode 的真机实证）。
    this.seedDarkMode(newConfig);
    // 深浅档切换后画布色跟着换，带区不重设就会又露出另一档的颜色
    this.applySystemBarSurface();
  }

  onDestroy(): void {
    Logger.info('EntryAbility', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    Logger.info('EntryAbility', 'Ability onWindowStageCreate');
    // 断点中心必须在 loadContent 之前起：页面第一次 build 就要能读到 currentBreakpoint，
    // 否则宽屏首帧会先按手机档画一遍再跳列数（有据同一顺序：EntryAbility:85）
    initBreakpointCenter(this.context);
    // 全屏布局与避让区高度要在 loadContent **之前**发起：窗口一铺满物理屏，页面就从
    // 窗口 y=0 起排，而 TabContent 仍按安全区在 106px 处裁切——首帧读不到
    // statusBarHeight 的话，每一屏顶部都会少一截（真机实测「有径」标题被压成 50px 高）。
    this.makeImmersive(windowStage);
    // 注册补设器：HDS 挂载期与滚回顶部都会回写系统栏属性，只有 Ability 持有主窗口句柄
    setSystemBarRefresher((): void => {
      this.applySystemBarSurface();
    });
    // 导航方式与底部避让要在 loadContent 之前起：dock 第一次 build 就要读到现值
    initNavModeWatcher(this.context);

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        Logger.error('EntryAbility', `Failed to load the content. Cause: ${JSON.stringify(err)}`);
        return;
      }
      Logger.info('EntryAbility', 'Succeeded in loading the content.');
      this.registerSerifFont(windowStage);
      // getMainWindow() 是异步的，可能晚于首次 build；这里用同步句柄兜底再发布一次。
      // 回调之前 getMainWindowSync 会抛 1300002，所以只能在回调里取。
      try {
        const win: window.Window = windowStage.getMainWindowSync();
        this.mainWin = win;
        this.publishAvoidArea(win);
      } catch (e) {
        Logger.error('EntryAbility', `取主窗口失败，上下带区底色无法设置: ${(e as Error).message}`);
      }
      this.applySystemBarSurface();
      // HDS 标题栏/系统层在挂载期会回写系统栏属性，把首帧的设置盖掉（同族工程真机实证），
      // 所以首帧之后再补设一次
      setTimeout((): void => {
        this.applySystemBarSurface();
      }, 3000);
      this.bootstrap();
    });

    try {
      if (this.colorProbe) {
        Logger.info('EntryAbility', '深浅档探针在效：跳过 colorMode 复位，保持 App 级档位');
      } else {
        this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      }
    } catch (err) {
      Logger.error('EntryAbility', `Failed to set colorMode. Cause: ${JSON.stringify(err)}`);
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    Logger.info('EntryAbility', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // 页面可见后才消费预填，与 bootstrap 双路覆盖冷/热启动
    this.visible = true;
    // 后台期间别的窗口可能把系统栏属性改回去，回前台重设一次
    this.applySystemBarSurface();
    // 后台期间切换导航方式不会派发 avoidAreaChange，回前台必须重算一次
    refreshNavMode(this.context);
    // 导航条显隐最后设：要用 refreshNavMode 刚重算的导航方式做判定（系统可能带回来）
    this.applyNavigationBarPolicy();
    this.routePending();
  }

  onBackground(): void {
    // Ability has back to background
    this.visible = false;
    Logger.info('EntryAbility', 'Ability onBackground');
  }

  /** 登录态必须先于任何行程读写恢复：DAO 取分区键是同步的（阶段 8） */
  private async bootstrap(): Promise<void> {
    // 草稿水合必须先于 routePending：深链/小艺预填随后写草稿会覆盖水合值（外部意图优先）；
    // contentReady 在水合后才置位，堵住 onForeground→routePending 抢跑消费预填再被水合覆盖的窗口
    const draftRestored: boolean = await PlanDraft.hydrate(this.context);
    if (draftRestored) {
      // dirty 标记原只在 AppStorage，杀进程即丢——水合成功补广播，根页「续草稿」入口才活
      markDraftDirty(true);
    }
    this.contentReady = true;
    try {
      await AccountStore.init(this.context);
    } catch (err) {
      Logger.error('EntryAbility', `登录态恢复失败，按本机游客分区继续: ${(err as Error).message}`);
    }
    DataSeeder.seedIfEmpty(this.context).catch((err: Error) => {
      Logger.error('EntryAbility', `种子灌入失败: ${err.message}`);
    });
    this.logSkillProfiles();
    WidgetSync.refreshAll(this.context).catch((err: Error) => {
      Logger.warn('EntryAbility', `卡片刷新失败: ${err.message}`);
    });
    this.routePending();
  }

  /** 小艺 Skill 是否真的随 HAP 注册（debug 可查；发布包不查） */
  private async logSkillProfiles(): Promise<void> {
    if (!BuildConfig.IS_DEBUG) {
      return;
    }
    try {
      const infos: skillManager.SkillInfo[] = await skillManager.getSkillInfosForSelf(
        skillManager.SkillInfoFlag.GET_SKILL_INFO_WITH_SRC_ENTRIES);
      const names: string[] = infos.map((info: skillManager.SkillInfo): string => info.skillName);
      Logger.info('EntryAbility', `Skill 注册 ${infos.length} 个: ${names.join(',')}`);
    } catch (err) {
      Logger.error('EntryAbility', `Skill 查询失败: ${(err as Error).message}`);
    }
  }

  /**
   * 统一出口：want 通道优先，其次小艺 Skill 落盘的预填。
   * 预填只在「页面已挂载 + 用户真的看得见」时消费；后台被 Skill 绑起时留着，进程被杀也不丢。
   */
  /**
   * 四栈骨架下的深链落点：先定页签（Index 拿它当 HdsTabs 的初始 index）。
   * 行程 tab 的栈启动时就存在，直接推；其余 tab 的栈要等 TabContent 首次可见才绑上
   * Navigation，改写成待路由由该 tab 的宿主消费。
   */
  /**
   * 深链落点：先定页签（`applyWant` 冷启已写过一次，这里覆盖运行期的目标），
   * 再把子页 push 到它所属那条栈上。
   *
   * 判据是「这个路由是不是某个页签的根页」，不是「它属于哪个页签」：
   * 根页（地图/行程/费用/我的）内联在各自 TabContent 里（有据路线 B），
   * 切过去就是它，再 push 会多叠一层；而 Badges / Itinerary / TripInput 这些子页
   * 必须 push，否则切到页签只看到根页。
   * 旧写法是 `if (tab === TAB_ITINERARY) push` —— 那是四栈时代"只有 tab 0 的栈首帧就建好"
   * 的将就，五格重排后规划链不在 0 号了，照抄就会丢 push（现由 applyWant 提前定初始页签兜住）。
   */
  private routeTo(name: string, param: string): void {
    const tab: number = tabOfRoute(name);
    AppStorage.setOrCreate(TAB_INDEX_KEY, tab);
    // TAB_INDEX_KEY 只是 HdsTabs 的**初始**页签，App 已存活时改它不切页签
    // （Index 头注释记过实测：冷启只能靠 index 初值）。运行期这条另走 requestTab →
    // Index 的 @Watch → changeIndex。冷启时 @Watch 不会为初值触发，两条路不冲突。
    requestTab(tab);
    if (param.length > 0) {
      AppStorage.setOrCreate(ACTIVE_TRIP_KEY, param);
    }
    if (!isTabRoot(name)) {
      stackOfRoute(name).pushPath({ name: name, param: param });
    }
  }

  private routePending(): void {
    if (this.pendingRoute.length === 0 && this.contentReady && this.visible) {
      const prefill: SkillPrefillRecord | null = SkillPrefill.take(this.context);
      if (prefill !== null) {
        this.applySkillPrefill(prefill);
        this.pendingRoute = 'TripInput';
        this.pendingParam = '';
      }
    }
    if (this.pendingRoute.length > 0) {
      this.routeTo(this.pendingRoute, this.pendingParam);
    }
    this.pendingRoute = '';
    this.pendingParam = '';
  }

  private applySkillPrefill(prefill: SkillPrefillRecord): void {
    const draft: PlanDraft = PlanDraft.get();
    const basic: TripBasicInput = {
      destination: prefill.destination,
      startDate: prefill.start,
      endDate: DateUtils.addDays(prefill.start, prefill.days - 1),
      people: prefill.people,
      // 小艺开的是新行程：预算回到默认，不静默沿用上一段草稿
      budget: BudgetConfig.DEFAULT
    };
    draft.basic = basic;
    PlanDraft.flush();
    Logger.info('EntryAbility',
      `Skill 预填 ${basic.destination} ${basic.startDate}→${basic.endDate} ${basic.people}人 budget=${basic.budget}`);
  }

  onError(error: Error): void {
    Logger.error('EntryAbility', `未捕获异常: ${error.message}`);
  }


  // 内置 Noto Serif SC（OFL，沿用有据打包件）。契约 serif 仅 display/title 两档且均 700，
  // 只注册 Bold 一档（有据经验：一个 familyName 只能绑一个字体文件）。
  private registerSerifFont(windowStage: window.WindowStage): void {
    try {
      windowStage.getMainWindowSync().getUIContext().getFont().registerFont({
        familyName: 'NotoSerifSC',
        familySrc: $rawfile('fonts/NotoSerifSC-Bold.otf')
      });
    } catch (err) {
      Logger.error('EntryAbility', `衬线字体注册失败: ${(err as Error).message}`);
    }
  }
}