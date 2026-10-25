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
 * 待路由：深链指向非首屏 tab 时不能直接 push——那个 TabContent 还没建、
 * 它的 Navigation 也还没绑上栈，push 会丢。写这两个键，由该 tab 的宿主消费。
 */
export const PENDING_ROUTE_KEY: string = 'pendingTabRoute';
export const PENDING_PARAM_KEY: string = 'pendingTabParam';

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
