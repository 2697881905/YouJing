/**
 * 应用根 · 官方 HdsTabs 四页签骨架（对齐「有据」定稿：底部悬浮页签是导航的一部分，不是页面自己贴的条）。
 *
 * 四条栈 = 四个 TabContent：`APP_NAV` 仍是**行程 tab**（主链 16 个文件都往它 push，
 * 名字不动以维持最小改动），地图/费用/我的各一条。切页签由官方组件自己管，
 * 每 tab 的返回栈互不干扰。
 *
 * 冷启深链为什么用 `index` 而不是 `changeIndex`：上一版在 aboutToAppear / onDidBuild /
 * @StorageLink+@Watch 三条路径里都调过 `hdsController.changeIndex()`，真机 dumpLayout
 * 实测全部停在 tab 0——Tabs 建完再切这条路在本机不成立。`HdsTabsOptions extends TabsOptions`
 * 且 `index?: number`（默认 0），所以把外部深链要落的页签**作为初始值**传进构造参数，
 * 首帧就在目标 tab；运行期（App 已存活时的 onNewWant）才用 changeIndex。
 */

import { HOST_NAV, ACTIVE_TRIP_KEY, TAB_INDEX_KEY, TAB_SWITCH_KEY, DOCK_TABS, announceTabShown, stackOfTab, TAB_PLAN, TAB_ITINERARY, TAB_MAP, TAB_EXPENSE, TAB_MINE } from '../common/constants/AppNav';
import { setSharedUiContext } from '../utils/longTake/cardRect';
import { TripDao, TripSummary } from '../data/TripDao';
import { AUTH_STATE_KEY } from '../data/AccountStore';
import { ConsentStore, CONSENT_AGREED_KEY } from '../utils/ConsentStore';
import { PrivacyConsentDialog } from '../components/PrivacyConsentDialog';
import { LoginView } from './LoginView';
import { Logger } from '../common/logger/Logger';
import { AccountStore } from '../data/AccountStore';
import { AccountState } from '../model/Account';
import { EntitlementStore } from '../data/EntitlementStore';
import { DeviceTokenStore } from '../data/DeviceTokenStore';
import { DeviceActivator } from '../data/DeviceActivator';
import { common } from '@kit.AbilityKit';
import { YoujingStartPage } from './YoujingStartPage';
import { MapPage } from './MapPage';
import { ExpensePage } from './ExpensePage';
import { TripsPage } from './TripsPage';
import { MinePage } from './MinePage';
import { HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { MotionCurves, MotionTokens } from '../design/MotionTokens';
import { HdsMiniBarButton } from '../components/HdsMiniBarButton';
import { HDS_MATERIAL_LEVEL_EXQUISITE, HDS_MATERIAL_TYPE_IMMERSIVE,
  isImmersiveLightSenseSupported } from '../utils/immersiveMaterial';
import { BottomTabBar, BottomTabItem } from '../components/BottomTabBar';
import { TopStrip, TOP_STRIP_KEY, STRIP_CANVAS, STRIP_MAP } from '../utils/TopStrip';
import { BOTTOM_NAV_INSET_KEY } from '../utils/navMode';
import { consumeOverlayBackFor, OVERLAY_GUARD_EXPENSE_TAB, OVERLAY_GUARD_PLAN_TAB } from '../utils/overlayBackGuard';
import { KEY_CURRENT_BREAKPOINT } from '../utils/breakpointCenter';

const TAG: string = 'Index';

/** 覆盖层与槽位的窗口矩形（vp），全部来自 `onAreaChange` */
interface DockArea {
  x: number;
  y: number;
  w: number;
  h: number;
}

/** 胶囊的一帧几何：中心点相对覆盖层左上角，单位 vp */
interface DockPillFrame {
  cx: number;
  cy: number;
  w: number;
  h: number;
}

// —— dock 液态选中胶囊（照「有据」§7.6.32，家族里第五个件见 components/HdsMiniBarButton）——
// 官方 HdsTabs 的 attrs 全表没有任何选中指示器属性，选中态只换 fillColor：
// 深蓝 #0A84FF 压在带白叠加的玻璃面上，正是原文说的「通透背景下辨识度不足」。
// 尺寸按参照图的**比例**来而不是往槽位里塞：胶囊宽 ≈ 1.22 倍实测槽距、高 ≈ 0.96 倍实测槽高，
// 它是盖过槽位的——做成"槽位内缩"会比内容还窄，玻璃的体积感无从谈起（有据第一版就是这么错的）。
const DOCK_PILL_W_RATIO: number = 1.22;
const DOCK_PILL_H_RATIO: number = 0.96;
/** 行进中的额外放大（鼓包），落定由 springBounce 收回静止尺寸 */
const DOCK_PILL_BULGE: number = 10;
/** HdsMiniBarButton 容器的 contentPadding 补偿：容器 size = 玻璃条 + padding×4，
 *  玻璃在容器内居中，所以 `.position()` 要反向补 padding×2=16，副本与官方份才逐像素重合
 *  （有据上一版只补 8，残差偏下 8vp 致底部溢出栏沿）。 */
const DOCK_PILL_MINI_PAD: number = 16;
/** 覆盖层与槽位谁先布局不固定，量不到就按帧重试这么多回 */
const DOCK_PILL_MEASURE_RETRIES: number = 6;

// —— 页签槽位（照「有据」`Index.tabBarBuilder`，2026-11-08 全量迁移）——
// 尺寸只对**上报**有意义：系统仍按 barWidth 档把五格压成实测 55.4×48.3vp，
// 但 `dockPillFrameOf` 读的就是 onAreaChange 上报的这块矩形。
// 有据挂在固定 64×54 的 Stack 上 → 胶囊高 54×0.96=51.8vp；
// 有径原先挂在自适应的 Column 上 → 只报 48.3×0.96=46.4vp，胶囊矮 5.4vp（真机实测差 17px）。
const DOCK_TAB_SLOT_W: number = 64;
const DOCK_TAB_SLOT_H: number = 54;
/** 图标容器（有据 28×28 的 Stack）：给未读红点留位，同时把图标与文字的基线推到有据同位 */
const DOCK_TAB_ICON_BOX: number = 28;
/** 图标与文字间距（有据 `Column({ space: 3 })`；本仓 SpaceTokens.xxs 是 4） */
const DOCK_TAB_CONTENT_GAP: number = 3;

// —— 拖拽液态交互参数（有据 DockPillDragProtoPage 真机定档 2026-10-26 移植）——
/** 速度形变上限（vp）：快甩的拉扯感 */
const DOCK_PILL_SPEED_MAX_DEFORM: number = 22;
/** 反方向（回拉）交叉形变系数：回拉收宽涨高 */
const DOCK_PILL_DEFORM_CROSS: number = 0.5;
/** 速度归一基准（vp/s）：轻甩约 400-600、快甩约 1200-1800 */
const DOCK_PILL_SPEED_NORMALIZE_VP: number = 1200;
/** 速度低于此值不形变（滤手抖噪声） */
const DOCK_PILL_SPEED_MIN_VP: number = 120;
/** 速度指数平滑因子 */
const DOCK_PILL_SPEED_SMOOTH: number = 0.3;
/** 停顿判定：超过 90ms 无 200vp/s 以上速度视为停顿，重置形变方向 */
const DOCK_PILL_PAUSE_MS: number = 90;
const DOCK_PILL_PAUSE_SPEED_VP: number = 200;
/** 边缘阻尼：首/尾槽往界外拖的跟手衰减 */
const DOCK_PILL_EDGE_DAMPING: number = 0.3;

@Entry
@Component
struct Index {
  /** 外部深链（小艺 / 卡片 / aa start）写这个键；作为 HdsTabs 的**初始页签**消费 */
  @StorageLink(TAB_INDEX_KEY) wantTab: number = TAB_PLAN;
  @State private currentTab: number = TAB_PLAN;
  /** 运行期切页签的请求（AppNav.enterPlanningFlow 写）；冷启不走这条路 */
  @StorageProp(TAB_SWITCH_KEY) @Watch('applyTabSwitch') tabSwitch: string = '';
  /**
   * 底部避让量（vp）：唯一来源是 `utils/navMode` 的判定结果，不在这里按「指示条高度」自己算。
   *  ⚠ 必须 @StorageLink **并且在 build 的属性里直读**——只挂 link 不进 build，ArkUI 不为它
   *  建立更新绑定，刷新全是空操作（有据 navMode 文件头写明的踩坑）。
   *  旧写法 `floatingDockBottomMargin + navIndicatorHeight` 在看不到三键栏的机型上会多垫 27.8vp。
   */
  @StorageLink(BOTTOM_NAV_INSET_KEY) @Watch('onDockNavInsetChange') dockNavInset: number = 0;
  /** 断点（唯一来源 utils/breakpointCenter.ets）：只用来选 dock 的 barWidth 档 */
  @StorageProp(KEY_CURRENT_BREAKPOINT) bp: string = 'sm';
  /**
   * 顶部该用哪个底色资源名（画布 / 底图基色），与系统带同源、由 TopStrip 写。
   * 壳层 Column 必须跟着换：栏是透明的，栏区露的就是这层的底色 ——
   * 只换系统带不换这里，顶边会多出第二条色差（真机实测带子 56、栏区 18）。
   */
  @StorageProp(TOP_STRIP_KEY) stripName: string = STRIP_CANVAS;
  /** 胶囊 ready 前不画：画一个坐标错的色块比缺一个色块更像 bug（有据同款判据） */
  @State private dockPillReady: boolean = false;
  /** 胶囊当前盖住（并代替官方那份显示清晰副本）的页签下标；-1 = 还没落位 */
  @State private dockPillCovered: number = -1;
  /** 手指正按在玻璃上：按压缩放反馈 */
  @State private dockPillPressed: boolean = false;
  @State private dockPillX: number = 0;
  @State private dockPillY: number = 0;
  @State private dockPillW: number = 0;
  @State private dockPillH: number = 0;
  /** 五颗槽位的窗口矩形（vp），由 tabLabel 的 onAreaChange 逐颗上报 */
  private dockSlotAreas: DockArea[] = [];
  /** 覆盖层自己的窗口矩形：胶囊坐标换算成它的相对值 */
  private dockLayerArea: DockArea | null = null;
  private dockPillMeasureTries: number = 0;
  /** 落定在途的定时器：手指接管或再次切页都要先打断，否则旧回弹会把新位移拽回去 */
  private dockPillSettleTimer: number = -1;
  // —— 玻璃珠拖拽（照「有据」原型页验证过的交互，2026-11-08 迁移）——
  /** 拖拽实时偏移：逐帧直写跟手，travel 里随 animateTo 归零插值 */
  @State private dockPillDragOffsetX: number = 0;
  /**
   * 拖拽形变的 scale 变换（1 = 无形变）。
   * ⚠ 形变绝不能直写 dockPillW/H——那是 HdsMiniBarButton 内部真 HdsTabs 的布局尺寸，
   * 逐帧直写 = 每帧重布局 + 材质重采样（拖动中卡顿/闪烁的根因）；scale 是 GPU 合成变换。
   */
  @State private dockPillDeformScaleX: number = 1;
  @State private dockPillDeformScaleY: number = 1;
  /** 拖拽过程量（非渲染态）：采样点 / 平滑速度 / 形变方向 / 停顿检测 */
  private dockPillLastGestureX: number = 0;
  private dockPillLastGestureTs: number = 0;
  private dockPillSmoothedVp: number = 0;
  private dockPillInitialDirection: number = 0;
  private dockPillLastActiveTs: number = 0;
  private dockPillPauseDetected: boolean = false;
  /** 实测槽距缓存：拖拽松手换算「拖了几个槽」（dockPillFrameOf 成功路径顺带回填） */
  private dockPillPitch: number = 0;
  private hdsController: HdsTabsController = new HdsTabsController();
  /** 低 SDK 降级分支专用：官方 HdsTabs 的 barFloatingStyle 自 API 23 起才存在 */
  private legacyController: TabsController = new TabsController();
  @State private useHdsDock: boolean = true;

  /** 解析 'index:timestamp' 并切到该页签；同页签或解析不出就什么都不做 */
  private applyTabSwitch(): void {
    const head: string = this.tabSwitch.split(':')[0];
    const target: number = Number(head);
    if (Number.isNaN(target) || target < 0 || target >= DOCK_TABS.length || target === this.currentTab) {
      return;
    }
    this.hdsController.changeIndex(target);
    this.currentTab = target;
  }

  /**
   * 系统返回手势 / 返回键。
   *
   * 2026-11-08 真机验收（§6）实测：原样交给系统时，从「我的」按一次 Back 整个 App
   * 直接退到后台（dump 从 com.youjing.app 掉成 com.youju.app）。根页不在栈上，
   * 系统就按"入口页"处理了——但用户的原话是「Back 不该退出 App」。
   *
   * 所以分四步，顺序就是优先级：
   * ① 当前页签栈里有页（如 我的 → 我的勋章）→ 交给 Navigation 自己 pop，不抢；
   * ② 根页的弹层/就地文书开着 → 交给页内守卫关掉（utils/overlayBackGuard）；
   * ③ 不在「地图」格 → 切回「地图」并吃掉这次返回（这是"上一级"的本意）；
   * ④ 已在「地图」格 → 交还系统（退后台），保留唯一一个符合平台习惯的出口。
   */
  onBackPress(): boolean {
    // ① 页签栈里有页 → 交给 Navigation pop，不抢
    if (stackOfTab(this.currentTab).size() > 0) {
      return false;
    }
    // ② 根页上的弹层不在栈里，也不由 Navigation 托管：先问它们要不要关
    //（费用「记一笔」实测过被"回地图"抢走返回；「我的」的法务文书已迁到 SettingsPage
    //  的 bindSheet，由系统收返回，不再需要页内守卫）
    const guardId: string = this.currentTab === TAB_EXPENSE ? OVERLAY_GUARD_EXPENSE_TAB
      : (this.currentTab === TAB_PLAN ? OVERLAY_GUARD_PLAN_TAB : '');
    if (guardId.length > 0 && consumeOverlayBackFor(guardId)) {
      return true;
    }
    // ③ 已在「地图」格 → 交还系统（退后台），保留唯一一个符合平台习惯的出口
    if (this.currentTab === TAB_MAP) {
      return false;
    }
    // ④ 其它页签 → 回「地图」格
    if (this.useHdsDock) {
      this.hdsController.changeIndex(TAB_MAP);
    } else {
      this.legacyController.changeIndex(TAB_MAP);
    }
    this.currentTab = TAB_MAP;
    return true;
  }

  aboutToAppear(): void {
    // 一镜到底的量测/截图 util 没有 this.getUIContext()，从这里共享（与有据同法）
    setSharedUiContext(this.getUIContext());
    // 2026-11-07 全量对齐：按有据的 API 23+ 门禁分流 dock。
    // 本工程 compatibleSdk 26 ⇒ 当前设备恒走官方 HdsTabs，自绘 BottomTabBar 分支不可达，
    // 仅作为未来降 SDK 时的预留兼容分支（差异表 P-09，不宣称已真机验证）。
    this.useHdsDock = isImmersiveLightSenseSupported();
    this.currentTab = this.wantTab;
    this.syncTopStrip(this.wantTab);
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    ConsentStore.init(ctx)
      .then((agreed: boolean): void => {
        if (agreed) {
          this.bootstrap(ctx);
        } else {
          this.consentDialog.open();
        }
      })
      .catch((): void => {
        this.consentDialog.open();
      });
  }

  private bootstrap(ctx: common.Context): void {
    // 顺序有讲究：激活要用「当前账号的 idToken」，而 AccountStore 的登录态是异步恢复的。
    // 三者并行时曾在亚稳态下把已登录用户按游客激活（D10 之后游客与账号是不同 BFF 账号）。
    const accountReady: Promise<AccountState> = AccountStore.init(ctx);
    accountReady
      .then((): Promise<void> => DeviceTokenStore.init(ctx))
      .then((): Promise<boolean> => DeviceActivator.activate(ctx))
      .catch((): void => {});
    EntitlementStore.init(ctx).catch((): void => {});
    accountReady
      .then((): Promise<TripSummary[]> => TripDao.listSummaries(ctx))
      .then((rows: TripSummary[]): void => {
        if (rows.length > 0) {
          AppStorage.setOrCreate(ACTIVE_TRIP_KEY, rows[0].id);
        }
      })
      .catch((): void => {
      });
  }

  /**
   * dock 五个页签。**选中态用蓝色 `primary` 是用户 2026-10-26 明确拍的板**
   * （「深色 dock 选中蓝 4.46:1，差 AA 0.04，维持 #0A84FF 不改」，且选中蓝是深色帧定的值），
   * 不要为了让对比度尺变绿把它换掉。
   * 2026-11-01 逐屏走查补一条新事实供裁决：dock 是半透明材质，透的是底下那块屏 ——
   * 画布上玻璃底 lum 0.016、**地图格上 0.056（亮约三倍）**，实测选中蓝在这两处是
   * 4.39:1 与 **3.05:1**，未选中 `muted` 在地图格上是 4.24~4.77:1。当年那次决定量的是
   * 画布那一侧（4.46），地图格这一侧从没进过视野。
   */
  /**
   * 记录某个页签槽位的窗口矩形（vp）。五颗各回调一次，齐了才定位。
   * ⚠ 坐标只能用 `onAreaChange` 的 `globalPosition`：`componentUtils.getRectangleById`
   * 对 TabBar 子树返回的 y 比实际渲染低 88px（真机实测槽位在 y=2439、接口回 2527），
   * 照它画会把胶囊整个甩到 dock 底下（有据 2026-10-27 踩过，同一条也写进本仓记忆）。
   */
  private recordDockSlotArea(index: number, area: Area): void {
    this.dockSlotAreas[index] = {
      x: Number(area.globalPosition.x),
      y: Number(area.globalPosition.y),
      w: Number(area.width),
      h: Number(area.height)
    };
    this.dockPillSnapOrRetry(this.currentTab);
  }

  /** 量出 index 号槽位上胶囊的一帧几何；任一环缺数据返回 null——宁可这一帧不画 */
  private dockPillFrameOf(index: number): DockPillFrame | null {
    const count: number = DOCK_TABS.length;
    const layer: DockArea | null = this.dockLayerArea;
    const first: DockArea | undefined = this.dockSlotAreas[0];
    const last: DockArea | undefined = this.dockSlotAreas[count - 1];
    const slot: DockArea | undefined = this.dockSlotAreas[index];
    if (layer === null || layer.w <= 0 || first === undefined || last === undefined
      || slot === undefined || slot.w <= 0 || index < 0 || index >= count) {
      return null;
    }
    // 一律换算到覆盖层自己的坐标系：两者都是窗口坐标，差值就是 .position() 要的相对值
    const firstCx: number = first.x - layer.x + first.w / 2;
    const lastCx: number = last.x - layer.x + last.w / 2;
    const cx: number = slot.x - layer.x + slot.w / 2;
    // Y 锚 dock 栏体几何中心，只用本页传给系统的两个已知量算，不吃任何上报偏差。
    // ⚠ 这里的避让量必须和 barFloatingStyle.barBottomMargin 读同一个 @StorageLink（dockNavInset）：
    // 两处各自调 bottomNavInset() 会一个停在旧值、一个跟到新值（有据模拟器实测差 31.7vp）。
    const cy: number = layer.h - (LayoutTokens.floatingDockBottomMargin + this.dockNavInset)
      - LayoutTokens.floatingDockBarHeight / 2;
    // 槽距由两端中心反算（不写死）：换 dock 宽度档、换导航方式、转屏都会变
    const pitch: number = count > 1 ? (lastCx - firstCx) / (count - 1) : first.w;
    // 拖拽松手要按它算「拖了几个槽」：成功路径顺带回填，失败不留脏值
    this.dockPillPitch = pitch;
    const frame: DockPillFrame = {
      cx: cx,
      cy: cy,
      w: pitch * DOCK_PILL_W_RATIO,
      h: slot.h * DOCK_PILL_H_RATIO
    };
    return frame;
  }

  /** 即时贴到 index 号槽位（无动画）。覆盖层与槽位谁先布局不固定，量不到就按帧重试几回 */
  private dockPillSnapOrRetry(index: number): void {
    const frame: DockPillFrame | null = this.dockPillFrameOf(index);
    if (frame === null) {
      if (this.dockPillMeasureTries < DOCK_PILL_MEASURE_RETRIES) {
        this.dockPillMeasureTries += 1;
        setTimeout((): void => {
          this.dockPillSnapOrRetry(index);
        }, 60);
      }
      return;
    }
    this.dockPillX = frame.cx;
    this.dockPillY = frame.cy;
    this.dockPillW = frame.w;
    this.dockPillH = frame.h;
    this.dockPillCovered = index;
    this.dockPillReady = true;
  }

  /** 切页：先鼓包 + 位移（行进），到点再 spring 收回静止尺寸——「液态」观感的 tap 分支 */
  private dockPillTravel(index: number): void {
    const frame: DockPillFrame | null = this.dockPillFrameOf(index);
    if (frame === null) {
      return;
    }
    if (!this.dockPillReady) {
      this.dockPillSnapOrRetry(index);
      return;
    }
    // 同一次切换会被 onTabBarClick 与 onAnimationStart 各触发一次；已经到位且无拖拽
    // 残留就不要再发一遍动画（否则胶囊会在终点上重新鼓一次包）。
    if (this.dockPillCovered === index && Math.abs(this.dockPillDragOffsetX) < 0.5
      && Math.abs(this.dockPillX - frame.cx) < 0.5) {
      return;
    }
    // 「落定才接管」（有据 2026-10-26 用户拍板：图标不跟玻璃跑）：行进期间玻璃珠是纯光标，
    // 官方份全部显示、图标留在槽位里（玻璃扫过谁、谁的图标在磨砂下短暂糊化）；settle
    // 到点才由玻璃接管目标槽——真磨砂下选中槽不接管则图标不可读，落定接管是唯一兼顾。
    this.dockPillCovered = -1;
    // 行进曲线用 emphasized（无过冲）：springSoft 带 ~10% 位置过冲，拖拽松手时玻璃珠
    // 会冲过目标槽再弹回，读作「弹一下」；吸附要的是"利落到位"，弹动感由落定的
    // springBounce 尺寸果冻承担。
    this.getUIContext().animateTo({ duration: MotionTokens.dockTravel, curve: MotionCurves.emphasized }, (): void => {
      this.dockPillX = frame.cx;
      this.dockPillY = frame.cy;
      this.dockPillW = frame.w + DOCK_PILL_BULGE;
      this.dockPillH = frame.h + DOCK_PILL_BULGE;
      this.dockPillDragOffsetX = 0;
    });
    if (this.dockPillSettleTimer >= 0) {
      clearTimeout(this.dockPillSettleTimer);
    }
    const restW: number = frame.w;
    const restH: number = frame.h;
    this.dockPillSettleTimer = setTimeout((): void => {
      this.dockPillSettleTimer = -1;
      this.getUIContext().animateTo({ duration: MotionTokens.dockSettle, curve: MotionCurves.springBounceYu }, (): void => {
        this.dockPillW = restW;
        this.dockPillH = restH;
      });
      // 落定即接管：目标槽官方份隐掉、玻璃内清晰副本顶上（与官方份逐像素重合，无跳变）
      this.dockPillCovered = index;
    }, MotionTokens.dockTravel);
  }

  /**
   * 页签状态同步（不含胶囊动画）：五格共用的「切到第 index 格」副作用都在这里。
   * 与 `dockPillTravel` 拆开是因为外部深链（applyTabSwitch）会先把 currentTab 写好，
   * 合并写会让那条路径的玻璃珠不飞——travel 必须无条件被调，去重交给它自己。
   */
  private applyTabState(index: number): void {
    if (this.currentTab === index) {
      return;
    }
    this.currentTab = index;
    AppStorage.setOrCreate(TAB_INDEX_KEY, index);
    this.syncTopStrip(index);
    // 五个 tab 根页只在 aboutToAppear 取一次数：在别处新建/编辑完行程、记完费用
    // 再切回页签，看到的还是第一次进入那份。广播一条，根页序号对上才重取
    announceTabShown(index);
  }

  /** 切页统一入口（拖拽松手走这条；照有据 `selectTab`）：状态 + 胶囊飞行一起做 */
  private selectTab(index: number): void {
    this.applyTabState(index);
    this.dockPillTravel(index);
  }

  // —— 玻璃珠拖拽三阶段（照「有据」原型页真机验证版）——
  // 手势只挂在玻璃珠本体（覆盖层 hitTest None + 珠体 Transparent），与整页左右滑
  // 分区共存：内容区滑动归 HdsTabs，Dock 上的横向拖拽归玻璃珠。
  // 拖拽中玻璃珠是纯光标（官方份全显、图标原位），松手过半格吸附、边缘阻尼。

  private handleDockPillDragStart(): void {
    // 打断在途 settle：手指接管，一切以手势为准
    if (this.dockPillSettleTimer >= 0) {
      clearTimeout(this.dockPillSettleTimer);
      this.dockPillSettleTimer = -1;
    }
    this.dockPillLastGestureX = 0;
    this.dockPillLastGestureTs = 0;
    this.dockPillSmoothedVp = 0;
    this.dockPillInitialDirection = 0;
    this.dockPillLastActiveTs = 0;
    this.dockPillPauseDetected = false;
    // 拖拽即纯光标：官方份全部露出，图标留在槽位里
    this.dockPillCovered = -1;
    // 拖拽全程基准尺寸恒定（rest+BULGE），形变由 deformScale 承担
    this.dockPillDeformScaleX = 1;
    this.dockPillDeformScaleY = 1;
    // 起手鼓包：从静止尺寸"被拿起"（一记明显轻弹）
    const frame: DockPillFrame | null = this.dockPillFrameOf(this.currentTab);
    if (frame === null) {
      return;
    }
    this.getUIContext().animateTo({ duration: MotionTokens.press, curve: MotionCurves.springBounceYu }, (): void => {
      this.dockPillW = frame.w + DOCK_PILL_BULGE;
      this.dockPillH = frame.h + DOCK_PILL_BULGE;
    });
  }

  private handleDockPillDragUpdate(event: GestureEvent): void {
    if (!this.dockPillReady || this.dockPillPitch <= 0) {
      return;
    }
    const x: number = event.offsetX;
    const now: number = Date.now();
    // 速度按 vp/s 归一（不依赖手势回调帧率），指数平滑滤抖
    if (this.dockPillLastGestureTs > 0) {
      const dt: number = Math.max(now - this.dockPillLastGestureTs, 1);
      const instVp: number = (x - this.dockPillLastGestureX) / dt * 1000;
      this.dockPillSmoothedVp = this.dockPillSmoothedVp * (1 - DOCK_PILL_SPEED_SMOOTH)
        + instVp * DOCK_PILL_SPEED_SMOOTH;
    }
    this.dockPillLastGestureX = x;
    this.dockPillLastGestureTs = now;
    // 停顿检测：短促停顿后视为新一轮甩动，重置形变方向
    if (Math.abs(this.dockPillSmoothedVp) >= DOCK_PILL_PAUSE_SPEED_VP) {
      this.dockPillLastActiveTs = now;
    }
    if (this.dockPillLastActiveTs > 0 && Math.abs(this.dockPillSmoothedVp) < DOCK_PILL_PAUSE_SPEED_VP
      && now - this.dockPillLastActiveTs >= DOCK_PILL_PAUSE_MS) {
      this.dockPillPauseDetected = true;
      this.dockPillInitialDirection = 0;
      this.dockPillLastActiveTs = 0;
    }
    // 速度 → 形变：sqrt 缓动，同向拉宽缩高、反向收宽涨高
    const absV: number = Math.abs(this.dockPillSmoothedVp);
    let deformW: number = 0;
    let deformH: number = 0;
    if (absV >= DOCK_PILL_SPEED_MIN_VP) {
      if (this.dockPillInitialDirection === 0 || this.dockPillPauseDetected) {
        this.dockPillInitialDirection = this.dockPillSmoothedVp > 0 ? 1 : -1;
        this.dockPillPauseDetected = false;
      }
      const eased: number = Math.sqrt(Math.min(absV / DOCK_PILL_SPEED_NORMALIZE_VP, 1));
      const deform: number = eased * DOCK_PILL_SPEED_MAX_DEFORM;
      const sameDir: boolean = (this.dockPillSmoothedVp > 0 ? 1 : -1) === this.dockPillInitialDirection;
      if (sameDir) {
        deformW = deform;
        deformH = -deform * DOCK_PILL_DEFORM_CROSS;
      } else {
        deformW = -deform * DOCK_PILL_DEFORM_CROSS;
        deformH = deform;
      }
    }
    const frame: DockPillFrame | null = this.dockPillFrameOf(this.currentTab);
    if (frame === null) {
      return;
    }
    const baseW: number = frame.w + DOCK_PILL_BULGE;
    const baseH: number = frame.h + DOCK_PILL_BULGE;
    this.dockPillDeformScaleX = (baseW + deformW) / baseW;
    this.dockPillDeformScaleY = (baseH + deformH) / baseH;
    // 边缘阻尼：首槽往左/尾槽往右拖时跟手衰减（rubber-band 手感）
    const lastIndex: number = DOCK_TABS.length - 1;
    if ((this.currentTab === 0 && x < 0) || (this.currentTab === lastIndex && x > 0)) {
      this.dockPillDragOffsetX = x * DOCK_PILL_EDGE_DAMPING;
    } else {
      this.dockPillDragOffsetX = x;
    }
  }

  private handleDockPillDragEnd(): void {
    // 按实测槽距取整：过半格吸附
    const slots: number = this.dockPillPitch > 0 ? Math.round(this.dockPillDragOffsetX / this.dockPillPitch) : 0;
    const lastIndex: number = DOCK_TABS.length - 1;
    const target: number = Math.max(0, Math.min(lastIndex, this.currentTab + slots));
    // ⚠ 落袋为安：玻璃视觉位置 = dockPillX(position) + dragOffsetX(translate) 两个属性之和。
    // 松手瞬间先把合成位置一次性写入 dockPillX（直写）、dragOffsetX 同帧清零（直写）——
    // 同帧两次直写只渲染一次，视觉零跳变；之后 travel 只需动画 dockPillX 单属性。
    // 不能依赖 travel 的 animateTo 同时插值两个属性：translate 的归零若未按预期走动画，
    // 玻璃会先跳回锚点再滑向目标——「从原来的方向重新滑过来」（有据真机实证 2026-10-26）。
    this.dockPillX = this.dockPillX + this.dockPillDragOffsetX;
    this.dockPillDragOffsetX = 0;
    // 形变随飞行同步收回（scale 与位置同一批 animateTo，emphasized 曲线）
    this.getUIContext().animateTo({ duration: MotionTokens.dockTravel, curve: MotionCurves.emphasized }, (): void => {
      this.dockPillDeformScaleX = 1;
      this.dockPillDeformScaleY = 1;
    });
    if (target === this.currentTab) {
      // 未过半格：回弹到当前槽（travel 从快照位插回锚点，去重条件已含拖拽偏移判断）
      this.dockPillTravel(target);
      return;
    }
    // 过半格吸附：走 selectTab 统一链路（状态 + 玻璃珠飞行 + 落定接管）
    this.selectTab(target);
    // ⚠ 页面切换必须显式 changeIndex：HdsTabs 非受控（无 index 绑定），点页签由官方
    // 内部切页、整页左右滑由官方手势切页，唯独拖拽路径官方一无所知——不补 changeIndex
    // 则页面内容停在旧页，玻璃状态与页面状态失步，后续任何切页都会让玻璃珠跳变。
    this.hdsController.changeIndex(target);
  }

  /**
   * 三层结构（全部居中叠放），照「有据」§7.6.32 的终解：
   * ① 玻璃渲染层 = HdsMiniBarButton，只出玻璃、内容槽留空（自绘 tint/rim/blur 复刻不出
   *    玻璃折射，做成"色块贴片"就是这条路的第一个错）；
   * ② 清晰副本层落在 **V1 上下文**（本 Stack 的直接子节点）——绝不能画进 ① 的尾随闭包：
   *    那是 @ComponentV2，闭包里读页面 V1 @State 不触发它的渲染更新，副本会停在旧值
   *    （真机实证「胶囊飞到消息里画的还是首页」）；也不能直接 `this.tabLabel(i)` 传参：
   *    @Builder 的参数是**值快照**，所以用 key 随 covered 变化的单元素 ForEach 强制重建；
   * ③ 命中层独占玻璃区域的触摸（①的 bar 是 HdsTabs 的 native 渲染层，手势挂在玻璃上收不到）。
   */
  @Builder
  dockSelectionPill() {
    Stack({ alignContent: Alignment.Center }) {
      HdsMiniBarButton({
        maskColor: '#00ffffff',
        barWidth: this.dockPillW,
        barHeight: this.dockPillH,
        materialType: HDS_MATERIAL_TYPE_IMMERSIVE,
        materialLevel: HDS_MATERIAL_LEVEL_EXQUISITE
      }) {
        Column()
      }
      Column() {
        // ⚠ 必须有这道守卫：行进期间 `dockPillCovered` 是 -1（玻璃珠当纯光标、官方份全显），
        // 没有它就会拿 DOCK_TABS[-1].symbol 去渲染 —— `Cannot read property symbol of undefined`
        // 直接把进程带崩（2026-11-08 真机实证，有据原件里本来就有这道 if，移植时漏了）。
        if (this.dockPillCovered >= 0) {
          ForEach([this.dockPillCovered], (i: number) => {
            this.tabItemContent(i)
          }, (i: number): string => String(i))
        }
      }
      .width(this.dockPillW)
      // 与玻璃条同高、内容显式居中：官方那份被 Stack 居中，这里 Column 主轴默认从顶排，
      // 漏写居中实测会高 9px（有据 §7.6.32 同款结论）。
      // 实测残差：副本比官方那份低约 4px（1.3vp）——有据用的是同一条公式，残差同源，
      // 我试过按「官方内容盒 50vp vs 槽位 48.3vp」再平移一次，结果被推到容器外 88px，
      // 说明 globalPosition 的语义不支持那套推算，故退回与有据逐字一致的写法。
      .height(this.dockPillH)
      // 副本必须与官方那份逐像素重合，否则落位瞬间图标会跳一下：
      // 官方那份被 Stack 居中，这里 Column 主轴默认从顶排，必须显式居中（实测漏写高 9px）
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      Column()
        .width(this.dockPillW + DOCK_PILL_MINI_PAD * 2)
        .height(this.dockPillH + DOCK_PILL_MINI_PAD * 2)
        .onTouch((event: TouchEvent): void => {
          const pressed: boolean = event.type === TouchType.Down || event.type === TouchType.Move;
          if (pressed !== this.dockPillPressed) {
            // 按压反馈的平滑：显式 animateTo（外层胶囊不挂 .animation，
            // 否则拖拽形变会被属性动画平滑、滞后于手势）
            this.getUIContext().animateTo({
              duration: MotionTokens.press,
              curve: MotionCurves.springInteract
            }, (): void => {
              this.dockPillPressed = pressed;
            });
          }
        })
        // 拖拽切页（照「有据」2026-10-26 真机定档）：横向拖玻璃珠跟手位移 + 速度形变，
        // 松手过半格吸附。与整页左右滑分区共存——内容区滑动归 HdsTabs，Dock 上归这里。
        .gesture(
          PanGesture({ direction: PanDirection.Horizontal, fingers: 1, distance: 5 })
            .onActionStart((): void => {
              this.handleDockPillDragStart();
            })
            .onActionUpdate((event: GestureEvent): void => {
              this.handleDockPillDragUpdate(event);
            })
            .onActionEnd((): void => {
              this.handleDockPillDragEnd();
            })
        )
    }
    .clip(false)
    // HdsMiniBarButton 容器 size = 玻璃条 + contentPadding×4，玻璃在容器内居中，
    // 所以 .position() 以容器左上角为锚时要反向补 padding×2=16（只补 8 会整体偏下 8vp）
    .position({
      x: this.dockPillX - this.dockPillW / 2 - DOCK_PILL_MINI_PAD,
      y: this.dockPillY - this.dockPillH / 2 - DOCK_PILL_MINI_PAD
    })
    // 按压（0.94）× 拖拽形变合成缩放；材质自带落影，自绘 shadow 不再叠加。
    .scale({
      x: (this.dockPillPressed ? MotionTokens.pressSlideScale : 1) * this.dockPillDeformScaleX,
      y: (this.dockPillPressed ? MotionTokens.pressSlideScale : 1) * this.dockPillDeformScaleY
    })
    // ⚠ 不挂 .animation：deformScale 拖拽中逐帧直写必须即时生效（挂了会被属性动画平滑、
    // 形变滞后于手势）。拖拽跟手与 travel 归零插值都走这一个 translate。
    .translate({ x: this.dockPillDragOffsetX })
    // ⚠ 必须是 Transparent 而不是 None：把命中收进来的同时，让玻璃区域以外的点击
    // 透给下层官方页签——改完这一档必须真点一次切页，确认没吃掉官方页签的点击
    .hitTestBehavior(HitTestMode.Transparent)
  }

  /**
   * 页签格的内容本体（图标 + 标签）。**不带任何上报**——胶囊里的清晰副本也复用这一份，
   * 若把 `onAreaChange` 写在这里，副本那一次回调会把自己所在的胶囊坐标当成槽位写回去，
   * 定位就自指了（有据把这两层拆成 `tabItemContent` / `tabBar` 正是为此）。
   *
   * 2026-11-08 按有据全量对齐：图标外包 28×28 容器（给红点留位、把基线推到有据同位）、
   * 间距 3（SpaceTokens.xxs 是 4）、选中不再加字重（有据只换颜色）。
   * 图标资产是唯一没迁的：有据用 `app.media.nav_*` 的细线 SVG，有径用系统符号（用户 2026-11-08 裁定保留）。
   */
  @Builder
  tabItemContent(idx: number) {
    Column({ space: DOCK_TAB_CONTENT_GAP }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(DOCK_TABS[idx].symbol)
          .fontSize(IconSizes.control)
          .fontColor([this.currentTab === idx ? ColorTokens.primary : ColorTokens.icon])
      }
      .width(DOCK_TAB_ICON_BOX)
      .height(DOCK_TAB_ICON_BOX)

      Text(DOCK_TABS[idx].label)
        .fontSize(TypeTokens.navLabel.size)
        .fontWeight(TypeTokens.navLabel.weight)
        .fontColor(this.currentTab === idx ? ColorTokens.primary : ColorTokens.muted)
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * 官方页签格。尺寸必须有：`dockPillFrameOf` 的胶囊高度只读这里的 `onAreaChange` 上报值，
   * 有据给的就是 64×54（系统仍会按 barWidth 档压成实测 55.4×48.3，但高度上报按 54 算，
   * 胶囊才是有据那颗 51.8vp 而不是 46.4vp）。
   * 被玻璃胶囊盖住的那一颗整份隐掉：胶囊是真磨砂，留着它只会在玻璃下面糊出一团同色光晕，
   * 清晰的那份由胶囊自己带（有据 `tabBarBuilder` 同一道 gate；漏掉它就是我这份移植的缺陷）。
   */
  @Builder
  tabLabel(idx: number) {
    Stack({ alignContent: Alignment.Center }) {
      this.tabItemContent(idx)
    }
    .width(DOCK_TAB_SLOT_W)
    .height(DOCK_TAB_SLOT_H)
    .opacity(this.dockPillCovered === idx ? 0 : 1)
    .accessibilityText(`${DOCK_TABS[idx].label}页签`)
    .onAreaChange((_o: Area, n: Area): void => {
      this.recordDockSlotArea(idx, n);
    })
  }

  /** 登录态：'' 水合中 / guest / huawei（AccountStore 推的 AppStorage 键） */
  @StorageProp(AUTH_STATE_KEY) authState: string = '';
  @StorageProp(CONSENT_AGREED_KEY) consentAgreed: string = '0';
  /** 本次会话内主动选了游客空间——冷启仍然先看登录页，不做静默跳过 */
  @State private guestChosen: boolean = false;
  private consentDialog: CustomDialogController = new CustomDialogController({
    builder: PrivacyConsentDialog({
      onAgree: (): void => {
        ConsentStore.agree().catch((): void => {});
        this.consentDialog.close();
        const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
        this.bootstrap(ctx);
      },
      onDecline: (): void => {
        ConsentStore.decline();
        (this.getUIContext().getHostContext() as common.UIAbilityContext).terminateSelf();
      },
      onOpenDoc: (kind: string): void => {
        // 正文已在弹窗内就地展开，这里只留一条埋点
        Logger.info(TAG, `查看协议原文 kind=${kind}`);
      }
    }),
    autoCancel: false,
    // 同意前 Back / Esc / 侧滑都不许把闸门关掉：否则「退出应用」那条出口被绕过，
    // 用户没同意也能继续用（真机实测 Back 能直接关掉，同意态仍是未同意）
    onWillDismiss: (action: DismissDialogAction): void => {
      if (ConsentStore.isAgreed()) {
        action.dismiss();
      }
    },
    alignment: DialogAlignment.Center
  });

  /**
   * 顶部系统带跟着页签换色：只有地图格是满铺底图，带子涂画布会在它上面压出一条
   * 硬色差（真机实测带子 18、底图 56~75）；其余四格顶边就是画布，涂画布才对。
   * 但"在地图格"还不够 —— 从地图栏上压进屏15 之后，屏幕顶上是**那一页**的栏带（画布），
   * 带子若仍留蓝灰就在 y=106 撞出一道 Δ38 的缝，所以还要问一句栈顶是不是地图自己。
   * 栈内那一跳由 MapPage 的 interception 负责（见 pages/MapPage.bindStripToStackTop）。
   */
  private syncTopStrip(index: number): void {
    TopStrip.apply(this.getUIContext().getHostContext() as common.UIAbilityContext,
      index === TAB_MAP && stackOfTab(TAB_MAP).size() === 0 ? STRIP_MAP : STRIP_CANVAS);
  }

  /**
   * 避让量变了（首帧实测回写 / 系统里切换导航方式）→ 胶囊立刻按新边距重贴。
   * `barFloatingStyle.barBottomMargin` 由 @StorageLink 自己刷新，这一路只补命令式的那份：
   * 胶囊的 cy 是在 `dockPillFrameOf` 里用 dockNavInset 算出来的，不重贴就会停在旧边距上
   *（有据模拟器实测差 31.7vp，玻璃珠整体偏上）。
   */
  private onDockNavInsetChange(): void {
    this.dockPillSnapOrRetry(this.currentTab);
  }

  /**
   * 五格 + 悬浮 dock 的容器层。dock 选中胶囊必须与 dock **同层**才能盖在它上面，
   * 所以这里是一层 Stack：底下是官方 HdsTabs（dock 由它自己排），上面是覆盖式胶囊。
   * 覆盖层自己的窗口矩形由这里的 `onAreaChange` 上报，胶囊坐标一律换算到它的相对系，
   * 这样转屏 / 换 dock 宽度档 / 换导航方式都不用重算公式。
   */
  @Builder
  mainTabs() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 低 SDK 降级分支：官方 HdsTabs.barFloatingStyle @since 23，API 20–22 走内置 Tabs +
      // 自绘悬浮玻璃药丸（有据 Index.ets:2081 同形态）。当前 compatibleSdk 26 下不可达。
      if (this.useHdsDock) {
        this.dockTabsBody()
      } else {
        this.legacyTabsBody()
      }
      if (this.dockPillReady && this.useHdsDock) {
        this.dockSelectionPill()
      }
    }
    .width('100%')
    .height('100%')
    // 覆盖层自己不参与命中，把触摸让给下层官方页签；胶囊那层单独收命中
    .hitTestBehavior(HitTestMode.None)
    .onAreaChange((_o: Area, n: Area): void => {
      this.dockLayerArea = {
        x: Number(n.globalPosition.x),
        y: Number(n.globalPosition.y),
        w: Number(n.width),
        h: Number(n.height)
      };
      this.dockPillSnapOrRetry(this.currentTab);
    })
  }

  @Builder
  dockTabsBody() {
    HdsTabs({ controller: this.hdsController, index: this.wantTab }) {
      // 顺序必须与 AppNav 的 TAB_* 常量、DOCK_TABS 下标逐一对齐，三者错位的后果见 AppNav 注释
      TabContent() {
        MapPage({ rootMode: true })
      }
      .tabBar(this.tabLabel(TAB_MAP))

      TabContent() {
        TripsPage({ rootMode: true })
      }
      .tabBar(this.tabLabel(TAB_ITINERARY))

      // 规划 tab：门面 + 屏2→屏6 向导链都走 APP_NAV（主链 16 个文件的字段不动）。
      // 2026-11-05 五格同构：`HdsNavigation(APP_NAV)` 与它的 titleBar 都搬进页面自己挂，
      // 壳层不再替这一格代管顶栏（以前只有它是异形，滚动状态还得经 AppStorage 递一层）。
      TabContent() {
        YoujingStartPage()
      }
      .tabBar(this.tabLabel(TAB_PLAN))

      TabContent() {
        ExpensePage({ rootMode: true })
      }
      .tabBar(this.tabLabel(TAB_EXPENSE))

      TabContent() {
        MinePage({ rootMode: true })
      }
      .tabBar(this.tabLabel(TAB_MINE))
    }
    .barPosition(BarPosition.End)
    .vertical(false)
    // 左右滑动切页：与有据一致（有据 `Index.ets:2020` 开着，它的四个 Tab 根页没有任何行级横向手势）。
    // 有径的差异是 `ExpensePage.ets:901` 有 `.swipeAction` 收据删除、`TripsPage.ets:648` 选择模式下
    // 也有行级 swipe——真机上「行内横滑」与「Tabs 横滑」谁吃手势要靠手指验（见 Docs §5ci 续 221）；
    // 若行内被 Tabs 抢走，就把这里改回 false（一处开关，无连带）。
    .scrollable(true)
    .barOverlap(true)
    .barFloatingStyle({
      // 材质走官方数值（IMMERSIVE=101 / EXQUISITE=0）：不静态 import hdsMaterial，
      // 该模块在低版本设备上不存在，import 即崩（immersiveMaterial.ets 的兼容性铁律）
      systemMaterialEffect: {
        materialType: HDS_MATERIAL_TYPE_IMMERSIVE,
        materialLevel: HDS_MATERIAL_LEVEL_EXQUISITE
      },
      barBottomMargin: LayoutTokens.floatingDockBottomMargin + this.dockNavInset,
      barSideMargin: LayoutTokens.pagePadding,
      // 板宽显式给档（照「有据」`Index.barFloatingStyle.barWidth`）：不给的话官方按内容自己排，
      // 真机实测排成 328.3vp——契约与有据都是 300（有据同位实量 [99,2427][1037,2602]÷3.125=300.2vp），
      // 两台机器并排放就是两条长短不同的玻璃条。600vp 以上把 medium/large 取同值 560 的理由见
      // LayoutTokens.floatingDockWideWidth 注释（有据的用户实测"切页底栏忽长忽短"）。
      barWidth: {
        smallWidth: LayoutTokens.floatingDockWidth,
        mediumWidth: this.bp === 'sm' ? LayoutTokens.floatingDockMediumWidth : LayoutTokens.floatingDockWideWidth,
        largeWidth: LayoutTokens.floatingDockWideWidth
      },
      // 契约 §Translucency：三处玻璃栏面都带 92px 渐变遮罩把内容淡进栏里。
      // 顶栏那条由 IMMERSIVE_GRADIENT_BLUR 自带，dock 这条官方件不默认给，必须显式声明
      //（照「有据」`Index.barFloatingStyle` 同一份配方；色值走资源，深浅两档各一档）。
      gradientMask: {
        maskColor: $r('app.color.glass_bar_gradient_mask'),
        maskHeight: LayoutTokens.barGradientMaskHeight
      }
    })
    // 胶囊起飞点挂在 `onAnimationStart` 而不是 `onChange`（照有据 `:2021` 的理由）：
    // onChange 是**落定之后**才发，滑过去时玻璃会晚半拍；动画起点触发才与翻页同批。
    // 拖拽途中的指纹跟踪做不到——HdsTabsAttribute 没留逐帧回调（有据枚举过 28 个方法）。
    .onAnimationStart((index: number, targetIndex: number): void => {
      this.dockPillTravel(targetIndex);
    })
    .onChange((index: number): void => {
      this.applyTabState(index);
      // 胶囊跟着落位：行进 300ms + 落定回弹 400ms（观感收口要真人看，这里只保证几何对）
      this.dockPillTravel(index);
    })
    // 重点**当前**页签时 onChange 不触发（同值），系统惯例是"再点一次 = 回到这一页签的根"。
    // 原来这条路径上什么都不发生：从「我的」点开行程后再点「我的」，界面纹丝不动，
    // 用户读到的就是"dock 坏了"（§5m 记的 P2）。Tabs 继承来的 onTabBarClick 每次都触发。
    .onTabBarClick((index: number): void => {
      if (index !== this.currentTab) {
        return;
      }
      const stack: NavPathStack = stackOfTab(index);
      if (stack.size() > 0) {
        stack.clear();
      }
      this.syncTopStrip(index);
      // 回根和切页签一样算「这一页重新露面」：刚生成的行程要在首页立刻出现
      announceTabShown(index);
    })
    .width('100%')
    .height('100%')
    // 状态栏避让交给栏体自己做，不在壳层垫。
    // 为什么：`HdsChrome.bar` 早就双开了 `avoidLayoutSafeArea: true` + `enableComponentSafeArea: true`
    // （有据首页同一配方），但这道 padding 把整个 HdsNavigation 往下挪了 34vp——
    // 栏体避让的是它自己坐标系里已经不存在的安全区，而带子归壳层涂。
    // 于是深色档滚动时栏体的渐变遮罩只压暗 y=106 以下，带子仍是画布：
    // 真机量到带子 L=18 / 栏体 L=11 一条硬台阶（用户长期报的「通知栏有色差、布局没撑满」）。
    // 撤掉 padding 后栏体从窗口 0 排起，遮罩与带子是同一层，缝没有第二个来源。
    // 壳层不读任何避让区：顶部让位归栏体（HdsChrome.bar 的 avoidLayoutSafeArea），
    // 底部让位归 navMode 发布的 dockNavInset，两处各只有一个来源。
  }

  /**
   * 低版本分支的页签数据：`DOCK_TABS` 是 {label, symbol}，这里补 `key` 供 ForEach 复用、
   * 并把 `label` 改名成 `title`（有据 `BottomTabBar` 的 BottomTabItem 形状）。
   */
  private legacyTabItems(): BottomTabItem[] {
    return [
      { key: 'map', title: DOCK_TABS[TAB_MAP].label, symbol: DOCK_TABS[TAB_MAP].symbol },
      { key: 'itinerary', title: DOCK_TABS[TAB_ITINERARY].label, symbol: DOCK_TABS[TAB_ITINERARY].symbol },
      { key: 'plan', title: DOCK_TABS[TAB_PLAN].label, symbol: DOCK_TABS[TAB_PLAN].symbol },
      { key: 'expense', title: DOCK_TABS[TAB_EXPENSE].label, symbol: DOCK_TABS[TAB_EXPENSE].symbol },
      { key: 'mine', title: DOCK_TABS[TAB_MINE].label, symbol: DOCK_TABS[TAB_MINE].symbol }
    ];
  }

  /**
   * 低 SDK（API 20–22）降级分支：内置 Tabs 承载五格内容，底栏用自绘悬浮玻璃药丸。
   * 与有据 `Index.ets:2081` 同形态。compatibleSdk 26 下由 useHdsDock 恒为 true 而不可达；
   * 本分支只作预留兼容，未做真机 A/B（差异表 P-09）。
   */
  @Builder
  legacyTabsBody() {
    Stack({ alignContent: Alignment.Bottom }) {
      Tabs({ controller: this.legacyController, index: this.wantTab }) {
        TabContent() {
          MapPage({ rootMode: true })
        }
        .tabBar('')

        TabContent() {
          TripsPage({ rootMode: true })
        }
        .tabBar('')

        TabContent() {
          YoujingStartPage()
        }
        .tabBar('')

        TabContent() {
          ExpensePage({ rootMode: true })
        }
        .tabBar('')

        TabContent() {
          MinePage({ rootMode: true })
        }
        .tabBar('')
      }
      .barHeight(0)
      .scrollable(true)
      .onChange((index: number): void => {
        this.currentTab = index;
        AppStorage.setOrCreate(TAB_INDEX_KEY, index);
        this.syncTopStrip(index);
        announceTabShown(index);
      })
      .width('100%')
      .height('100%')

      BottomTabBar({
        items: this.legacyTabItems(),
        currentIndex: $currentTab,
        onSelect: (index: number): void => {
          this.legacyController.changeIndex(index);
        }
      })
        .margin({ bottom: LayoutTokens.floatingDockBottomMargin + this.dockNavInset })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Column() {
      if (this.consentAgreed !== '1') {
        Blank()
      } else if (this.authState === '') {
        Blank()
      } else if (this.authState !== 'huawei' && !this.guestChosen) {
        LoginView({
          onSignedIn: (): void => {
            Logger.info(TAG, '登录完成，进入主界面');
          },
          onGuest: (): void => {
            this.guestChosen = true;
            Logger.info(TAG, '用户主动选择本机游客空间');
          },
          onOpenDoc: (kind: string): void => {
            // 正文由登录页自己的半模态承载，这里只留一条埋点
            Logger.info(TAG, `登录页查看协议原文 kind=${kind}`);
          }
        })
      } else {
        // 外层宿主（有据形态）：Navigation 只包住五格，标题栏收起、模式显式 Stack
        // （默认 Auto 在宽屏会切 Split，整页被关进 240vp 窄列）。
        // 绑 `HOST_NAV` 而不是任何一格的栈：一个 NavPathStack 只能被一个 Navigation 持有，
        // 抢绑 `APP_NAV` 会把规划格的绑定夺走，向导链就从「页签内」变成「盖住 dock 的全屏」。
        Navigation(HOST_NAV) {
          this.mainTabs()
        }
        .mode(NavigationMode.Stack)
        .hideTitleBar(true)
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    // ⚠ 这道按页签涂色别试着交给栏体：2026-11-05 试过 `HdsChrome.bar({ barBackground })`
    // 并撤掉这里，栏体涂不出那层不透明底（dump 的 TitleBar 仍 #00000000），
    // 地图格顶边从「平 L=55/56」变成「透底图渐变」，同机位复拍为证（§5ci 续 198）。
    .backgroundColor(this.stripName === STRIP_MAP ? $r('app.color.map_strip_base') : $r('app.color.canvas'))
  }
}
