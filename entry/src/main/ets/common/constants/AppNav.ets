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
/**
 * 「行程」格（`TripsPage` 历史/最近列表）的栈。
 * 原名 `TRIPS_NAV`：那之前它挂在「我的」页签上。五格分工后它归「行程」，
 * 名字跟着改——留着会指反义（`TAB_MINE` 现在指新「我的」页，不是这条栈）。
 */
export const TRIPS_NAV: NavPathStack = new NavPathStack();
/** 新「我的」页（个人信息 + 勋章卡 + 设置）的栈 */
export const PROFILE_NAV: NavPathStack = new NavPathStack();
/**
 * 壳层宿主栈（对齐「有据」`Index` 的 `pageStack`：外层 `Navigation` 只做宿主，
 * 不承载任何一格的导航）。
 * ⚠ 它**不能**等于任何一格自己的栈：一个 `NavPathStack` 只能被一个 `Navigation` 持有，
 * 外层若绑 `APP_NAV`，规划格那个 `HdsNavigation(APP_NAV)` 的绑定会被抢走，
 * 向导链就会从「页签内」改成「盖住 dock 的全屏」——那是观感回归不是重构。
 */
export const HOST_NAV: NavPathStack = new NavPathStack();

/**
 * tab 序号，与 `Index` 里 TabContent 的顺序、以及 `DOCK_TABS` 的下标**必须同时改**。
 * 三者错位不会崩，只会让某个根页的 `isTabShownTick` 永远对不上而静默不刷新，
 * 或让深链落错页签 —— `NavStackRouting.test` 里有穷举断言拦这件事。
 */
export const TAB_MAP: number = 0;
/** 「行程」= 历史/最近行程的查看与编辑（`TripsPage`） */
export const TAB_ITINERARY: number = 1;
/** 「规划」= 主功能入口（`YoujingStartPage` 门面 + 屏2→屏6 向导链），五格里居中最顺手位 */
export const TAB_PLAN: number = 2;
export const TAB_EXPENSE: number = 3;
/** 「我的」= 个人信息 / 勋章 / 设置（`MinePage`） */
export const TAB_MINE: number = 4;

/**
 * dock 每一格长什么样。**这里是格数与顺序的唯一真值来源**，
 * `Index` 的 `TabContent`、`.tabBar(this.tabLabel(i))`、运行期切页签的越界判定
 * 全部读它，不再各写一份。
 *
 * 为什么值得收到一处：上一版格数与 label 只写在 `Index:43-48`，
 * 而 `TAB_*` 序号、`stackOfTab`、`tabOfRoute` 是另外三张手写的表。
 * 四格改五格时它们必须同步变，漏一处不会崩，只会让深链落错 tab、
 * 或让某个根页的 `isTabShownTick` 永远对不上而**静默不刷新**——
 * 这类缺陷本仓已经返工过多次（§4j 的"push 到看不见的栈"同族）。
 */
export interface DockTab {
  label: string;
  symbol: Resource;
}

export const DOCK_TABS: DockTab[] = [
  { label: '地图', symbol: $r('sys.symbol.map') },
  { label: '行程', symbol: $r('sys.symbol.calendar') },
  { label: '规划', symbol: $r('sys.symbol.list_bullet_square') },
  { label: '费用', symbol: $r('sys.symbol.wallet') },
  { label: '我的', symbol: $r('sys.symbol.person') }
];
/** AppStorage 键：外部深链要落到哪个 tab（Index 用它当 HdsTabs 的初始页签） */
export const TAB_INDEX_KEY: string = 'dockTabIndex';
/** AppStorage 键：当前活跃行程。2026-10-27 起地图/费用根页真的跟它走（此前只写不读，见 INIT_REPORT §5p） */
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
 * AppStorage 键：规划草稿是否已被用户动过（`1:<ts>` / `0:<ts>`）。
 * 由**写草稿的那一方**广播，首页 `@Watch` 取值——
 * 首页只在 `aboutToAppear` 和 dock 广播时刷新，从屏2 返回时两条都不触发，
 * 让读的一方自己判断就会出"按钮该出现却没出现"（§5w 那次回退的根因）。
 */
export const DRAFT_DIRTY_KEY: string = 'planDraftDirty';

/** 写草稿的一方调用：true = 有可续的规划；false = 已作废/已交付 */
export function markDraftDirty(dirty: boolean): void {
  AppStorage.setOrCreate(DRAFT_DIRTY_KEY, `${dirty ? 1 : 0}:${Date.now()}`);
}

export function isDraftDirty(value: string): boolean {
  return value.startsWith('1:');
}

/**
 * 取「用户最后打开的那条行程」，没有则空串。
 * 这个键原来写 5 处、读 0 处（只在 Index 判空），注释承诺的"当前活动行程"没有消费方。
 * 现在地图/费用两个根页切回时跟它走：刚看完行程 B 再切「地图」，该显示 B，
 * 而不是永远停在第一次进页签时兜底挑中的那条。
 */
export function activeTripId(): string {
  return AppStorage.get<string>(ACTIVE_TRIP_KEY) ?? '';
}

/**
 * 建行程主链的唯一入口。
 * 主链 16 个页面全往 APP_NAV push；从别的页签把它 push 到自己那条栈上，
 * 下一跳就会落到看不见的栈里——真机表现为「点开始规划没反应」（§4j 那条 P0）。
 * 所以入口一律：先切到规划 tab，再把第一页推进 APP_NAV（规划 tab 的栈）。
 */
export function enterPlanningFlow(name: string): void {
  requestTab(TAB_PLAN);
  APP_NAV.pushPath({ name: name });
}

/**
 * 路由名 → 归属栈。
 *
 * ⚠ 必须与 `tabOfRoute` 逐分支对齐：`EntryAbility.routeTo` 先用 `tabOfRoute` 决定
 * 初始页签、再用 `stackOfRoute` 决定 push 到哪条栈。两者一旦错位，
 * 深链就会把页面 push 进**当前不可见**的那条栈 —— 冷启白屏、点了没反应，
 * 且不报错。`NavStackRouting.test` 里有一条
 * `stackOfTab(tabOfRoute(n)) === stackOfRoute(n)` 的不变量断言专门锁这件事。
 */
export function stackOfRoute(name: string): NavPathStack {
  if (name === 'Map') {
    return MAP_NAV;
  }
  if (name === 'Expense') {
    return EXPENSE_NAV;
  }
  if (name === 'Trips') {
    return TRIPS_NAV;
  }
  if (name === 'Badges' || name === 'Mine') {
    return PROFILE_NAV;
  }
  return APP_NAV;
}

/**
 * dock 页签序号 → 这条页签自己的栈。
 * 重点当前页签时要把它收回根页（系统惯例），所以按序号取，不按路由名。
 */
export function stackOfTab(index: number): NavPathStack {
  if (index === TAB_MAP) {
    return MAP_NAV;
  }
  if (index === TAB_ITINERARY) {
    return TRIPS_NAV;
  }
  if (index === TAB_EXPENSE) {
    return EXPENSE_NAV;
  }
  if (index === TAB_MINE) {
    return PROFILE_NAV;
  }
  return APP_NAV;
}

/**
 * 这个路由名是不是某个页签的**根页**。
 *
 * 深链要靠它决定"切过去就行"还是"还要 push"：四个根页现在内联在各自 TabContent 里
 * （路线 B），切到那个页签就是它，再 push 一次会多叠一层。
 * 而 Badges / Itinerary / TripInput 这些是**子页**，必须 push 到所属栈上。
 */
export function isTabRoot(name: string): boolean {
  return name === 'Map' || name === 'Expense' || name === 'Trips' || name === 'Mine';
}

/**
 * 路由名 → 该落在哪个页签（与 `stackOfRoute` 同分支，理由见上）
 */
export function tabOfRoute(name: string): number {
  if (name === 'Map') {
    return TAB_MAP;
  }
  if (name === 'Expense') {
    return TAB_EXPENSE;
  }
  if (name === 'Trips') {
    return TAB_ITINERARY;
  }
  if (name === 'Badges' || name === 'Mine') {
    return TAB_MINE;
  }
  return TAB_PLAN;
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
