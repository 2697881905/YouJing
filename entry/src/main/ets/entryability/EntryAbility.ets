import { AbilityConstant, Configuration, ConfigurationConstant, skillManager, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { initBreakpointCenter } from '../utils/breakpointCenter';
import { Logger } from '../common/logger/Logger';
import { stackOfRoute, tabOfRoute, TAB_INDEX_KEY, TAB_ITINERARY, ACTIVE_TRIP_KEY } from '../common/constants/AppNav';
import { DataSeeder } from '../data/DataSeeder';
import { AccountStore } from '../data/AccountStore';
import { PlanDraft } from '../data/PlanDraft';
import { TripBasicInput } from '../model/PlanParams';
import { DateUtils } from '../utils/DateUtils';
import { SkillPrefill, SkillPrefillRecord } from '../data/SkillPrefill';
import { BuildConfig } from '../common/constants/BuildConfig';
import { BudgetConfig } from '../common/constants/BudgetConfig';
import { WidgetSync } from '../widget/TodayCard';

export default class EntryAbility extends UIAbility {
  private pendingRoute: string = '';
  private pendingParam: string = '';
  /** 页面已 load 完（Navigation 可推栈） */
  private contentReady: boolean = false;
  /** 真正对用户可见：后台被 Skill 绑起时不能消费预填，否则进程一杀就丢 */
  private visible: boolean = false;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    Logger.info('EntryAbility', 'Ability onCreate');
    // 深色档必须冷启就播种。isDarkMode 此前只在 onConfigurationUpdate 里写，
    // 而那个回调只在配置**变化**时才来：直接以深色档冷启时它不来，
    // 于是全仓 7 处 @StorageProp('isDarkMode') 一律按浅色走——
    // 深色零阴影门控失效、底图不换暗色主题、分段栏选中底色与文字色分支整段跳过。
    AppStorage.setOrCreate('isDarkMode',
      this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    this.applyWant(want);
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

  onConfigurationUpdate(newConfig: Configuration): void {
    // 深色零阴影门控（契约 §4）：页面用 @StorageProp('isDarkMode') 决定是否挂 elevation
    AppStorage.setOrCreate('isDarkMode',
      newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
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

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        Logger.error('EntryAbility', `Failed to load the content. Cause: ${JSON.stringify(err)}`);
        return;
      }
      Logger.info('EntryAbility', 'Succeeded in loading the content.');
      this.registerSerifFont(windowStage);
      this.bootstrap();
    });

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
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
    this.routePending();
  }

  onBackground(): void {
    // Ability has back to background
    this.visible = false;
    Logger.info('EntryAbility', 'Ability onBackground');
  }

  /** 登录态必须先于任何行程读写恢复：DAO 取分区键是同步的（阶段 8） */
  private async bootstrap(): Promise<void> {
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
  private routeTo(name: string, param: string): void {
    const tab: number = tabOfRoute(name);
    AppStorage.setOrCreate(TAB_INDEX_KEY, tab);
    if (param.length > 0) {
      AppStorage.setOrCreate(ACTIVE_TRIP_KEY, param);
    }
    if (tab === TAB_ITINERARY) {
      stackOfRoute(name).pushPath({ name: name, param: param });
    }
    // 地图/费用/我的三个 tab 的根页现在内联在各自 TabContent 里（有据路线 B）：
    // 切过去就是它，不再 push。原先那条「写待路由 → 宿主 push」的路，
    // 宿主是在自己的 Navigation 绑上栈之前推的，落点解析不出来
    // （真机探针实测 routerMap 收到的是空名，§4k ④）。
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