/**
 * 全局导航栈单例（§12 路由表）。
 * @Provide/@Consumer 仅 @ComponentV2 可用，V1 工程统一经本单例取栈；
 * 页面路由名以 handoff §12 路由表为准。
 */

export const APP_NAV: NavPathStack = new NavPathStack();
/** 地图 tab 的栈 */
export const MAP_NAV: NavPathStack = new NavPathStack();
/** 费用 tab 的栈 */
export const EXPENSE_NAV: NavPathStack = new NavPathStack();
/** 我的（行程列表）tab 的栈 */
export const MINE_NAV: NavPathStack = new NavPathStack();

/** tab 序号，与 Index 里 TabContent 的顺序一致 */
export const TAB_ITINERARY: number = 0;
export const TAB_MAP: number = 1;
export const TAB_EXPENSE: number = 2;
export const TAB_MINE: number = 3;
/** AppStorage 键：外部深链要落到哪个 tab（Index 用它当 HdsTabs 的初始页签） */
export const TAB_INDEX_KEY: string = 'dockTabIndex';
/** AppStorage 键：当前活跃行程，地图/费用 tab 的根页靠它选路 */
export const ACTIVE_TRIP_KEY: string = 'activeTripId';
/**
 * AppStorage 键：运行期切页签的请求（冷启那条路只认 HdsTabs 的 index 初值，
 * 见 Index 头注释；这里管的是 App 已存活时、从别的页签发起的跳转）。
 * 值带时间戳，同一个目标连发两次也能触发 @Watch。
 */
export const TAB_SWITCH_KEY: string = 'dockTabSwitchRequest';

/**
 * AppStorage 键：dock 刚切到某个页签的通知（由 Index 的 HdsTabs.onChange 发）。
 *
 * 四个 tab 根页原来只在 `aboutToAppear` 取一次数：在别处新建/编辑完行程、
 * 或记了一笔费用之后切回页签，看到的还是第一次进入时那份数据（主链复审 P1）。
 * 根页 `@StorageProp` + `@Watch` 这个键，序号对上才重取。
 */
export const TAB_SHOWN_KEY: string = 'dockTabShownTick';

/** 请求把 dock 切到某个页签，由 Index 的 @Watch 调 changeIndex 落地 */
export function requestTab(index: number): void {
  AppStorage.setOrCreate(TAB_SWITCH_KEY, `${index}:${Date.now()}`);
}

/** dock 切完页签后广播一次，值带时间戳，同一页签连切两次也能触发 @Watch */
export function announceTabShown(index: number): void {
  AppStorage.setOrCreate(TAB_SHOWN_KEY, `${index}:${Date.now()}`);
}

/** 根页侧判定：这条广播是不是发给我的页签 */
export function isTabShownTick(value: string, index: number): boolean {
  return value.startsWith(`${index}:`);
}

/**
 * 建行程主链的唯一入口。
 * 主链 16 个页面全往 APP_NAV push；从「我的」页签把它 push 到 MINE_NAV 上，
 * 下一跳就会落到看不见的 tab-0 栈里——真机表现为「点开始规划没反应」。
 * 所以入口一律：先切回行程 tab，再把第一页推进 APP_NAV。
 */
export function enterPlanningFlow(name: string): void {
  requestTab(TAB_ITINERARY);
  APP_NAV.pushPath({ name: name });
}

/** 路由名 → 归属栈 */
export function stackOfRoute(name: string): NavPathStack {
  if (name === 'Map') {
    return MAP_NAV;
  }
  if (name === 'Expense') {
    return EXPENSE_NAV;
  }
  if (name === 'Trips') {
    return MINE_NAV;
  }
  return APP_NAV;
}

export function tabOfRoute(name: string): number {
  if (name === 'Map') {
    return TAB_MAP;
  }
  if (name === 'Expense') {
    return TAB_EXPENSE;
  }
  if (name === 'Trips') {
    return TAB_MINE;
  }
  return TAB_ITINERARY;
}

/**
 * 屏9 编辑页的路由参数（NavDestination 的 param 是 object，这里给一个显式形状，
 * 免得页面各自约定字符串前缀）。dayIndex 从 0 起，与屏8 当前展示的日一致。
 */
export interface EditTarget {
  tripId: string;
  dayIndex: number;
}

/**
 * 屏7 生成受阻的路由参数：把真实错误码与原始诊断带过去，
 * 页面不再念底稿里编造的「伏见稻荷与宇治步行超 90 分钟」。
 */
export interface FailInfo {
  code: number;
  detail: string;
}
