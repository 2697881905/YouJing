/**
 * Layout 具名 tokens · 契约 handoff §4 layout 表，单位 vp。
 * 屏专属滚动预留按 DESIGN.md §9 决议 6 具名，允许离开通用间距阶梯。
 */

export interface LayoutTokensType {
  /** 行程时间槽宽（帧 .time-gutter 52） */
  itineraryTimeGutter: number;
  /** 主轴节点占位（帧 .node-circle 24） */
  itineraryNodeSize: number;
  /** 主轴节点内圈活动色点（帧 .node-dot 10） */
  itineraryNodeDot: number;
  /** 节点详情缩略位宽（帧 .media-thumb 96，比例 3:4） */
  mediaThumbWidth: number;
  /** 节点详情缩略位高（帧 .media-thumb 128） */
  mediaThumbHeight: number;
  /** 屏4/屏5 吸底 CTA 条的滚动预留（通用 94 之外还要盖住吸底条） */
  stickyBarScrollReserve: number;
  /** 屏16 分享吸底动作条的滚动预留（两行动作，比 CTA 条高） */
  shareBarScrollReserve: number;
  /** 基线网格 */
  gridBaseline: number;
  /** 页面左右内缩 */
  pagePadding: number;
  /** 宽屏页面左右内缩 */
  pagePaddingWide: number;
  /** 条目间隙 */
  itemGap: number;
  /** 区块间隙 */
  blockGap: number;
  /** 分区间隙 */
  sectionGap: number;
  /** 内容最大宽（宽屏约束） */
  contentMaxWidth: number;
  /** 最小命中区 */
  minTouchTarget: number;
  /** 顶栏高 */
  titleBarHeight: number;
  /** 分段控件轨道高 */
  segmentedControlHeight: number;
  /** 底部 tab 栏高 */
  tabBarHeight: number;
  /**
   * dock 板宽（vp）＝契约 `Floating dock 300 × 64px` 的**输入值**，不是读数。
   * `HdsTabs.barFloatingStyle.barWidth.smallWidth` 直接吃它：不设 barWidth 时官方自己按
   * 内容算，真机实测会排成 328.3vp（旧版就是这样），比契约和「有据」都宽 28vp。
   * 有据侧同位实测量到 [99,2427][1037,2602] ÷ 3.125 = 300.2vp（`utils/cardTokens` 注释）。
   */
  floatingDockWidth: number;
  /** 440–600vp 窗口的 medium 档板宽（有据 `Index.barFloatingStyle` 同值 420） */
  floatingDockMediumWidth: number;
  /**
   * 600vp 以上窗口的 medium/large 两档**取同值** 560（照有据）：官方规则是 600–840vp 按
   * Tabs 宽高比在 medium/large 间二选一，含资料区的页面会把宽高比压跌破 0.8，
   * 于是切页时底栏忽长忽短（有据的用户实测反馈）。两档同值后跳档不存在。
   */
  floatingDockWideWidth: number;
  /**
   * 浮动 dock 距底基线（不含底部避让量；避让量由 `utils/navMode` 单源给出，见 `pages/Index` 的 `dockNavInset`）。
   * dock 真渲染尺寸：328.3 × 56vp，左右各离边 17.6vp（实测，非本文件算出）。
   */
  floatingDockBottomMargin: number;
  /** 浮动 dock 栏体高（有据真值；2026-11-05 真机 dock 板 56vp 实测） */
  floatingDockBarHeight: number;
  /**
   * 玻璃栏面把内容淡进去的那段遮罩高（vp）。契约 §Shapes/Translucency 三处栏面
   * （顶栏 / 悬浮 dock / 吸顶日栏）统一 **92px gradient mask**；
   * 顶栏那条由 `ScrollEffectType.IMMERSIVE_GRADIENT_BLUR` 自带，dock 要显式声明
   * （`HdsTabs.barFloatingStyle.gradientMask`），此前漏了。
   */
  barGradientMaskHeight: number;
  /**
   * 钉底按钮条必须给悬浮 dock 让出的净空（vp）。
   * 构成 = `floatingDockBarHeight`(56) + `floatingDockBottomMargin`(28) + 底部避让量。
   * 手势档避让量 0 ⇒ 84vp（真机实测 (2690-2427)÷3.125 = 84.2vp，与公式对上）；
   * 三键档 ≈ 28.8vp ⇒ 需要 112.8vp。
   * 此前屏2 的「开始规划」钉底条只留 md=16，被 dock 直接压住（实拍可见蓝条叠在按钮上）。
   * ⚠ 现值按**最大档**钉 112，不是随手留大：按 84 钉在手势档刚好，但在三键档会把末行压进
   * dock 底下 28.8vp（84 < 112.8 是算术，不是猜测），而多出来的那 28vp 只是滚动区底部空白。
   * 按档派生要等 24 处消费点都能直读 `dockNavInset`，属本层之后的活。
   */
  floatingDockClearance: number;
  /** 契约 `layout.floating-dock-side-margin` 的镜像值；实现走 `barSideMargin: pagePadding`（同为 16） */
  floatingDockSideMargin: number;
  /**
   * 通用底部滚动预留（契约 `Bottom scroll reserve = 94px + nav inset`，DESIGN.md:1014）。
   * 消费方必须写成 `bottomScrollReserve + dockNavInset`（第 19 把尺 R3 钉住）：
   * 94 只盖得住手势档的 dock（84+10 余量），三键档 dock 整条下移 27.8vp 后末行会藏进栏底。
   */
  bottomScrollReserve: number;
  /** 行分隔线宽（唯一允许的分隔线宽） */
  hairlineWidth: number;
  /** 玻璃描边宽 */
  glassBorderWidth: number;
  /** 弹层 sheet 宽（画布 360 内） */
  sheetPanelWidth: number;
  /** 弹层 sheet 内缩 */
  sheetPanelPadding: number;
  /** 行程主轴宽 */
  itinerarySpineWidth: number;
  /** 行程行最小高 */
  itineraryRowMinHeight: number;
  /** 行程区块间隙 */
  itineraryBlockGap: number;
  /** 交通腿高（虚线、无背景填充） */
  transitLegHeight: number;
  /** 动线宽 */
  routeLineWidth: number;
  /** 地图浮层内缩 */
  mapOverlayInset: number;
  /** 紧凑地图高 */
  mapHeightCompact: number;
  /** 日分割线区高（吸顶日标题） */
  dayDividerHeight: number;
  /**
   * 单行吸顶组头带高。契约对这一形状**没有**写档（DESIGN.md 只给 `day-header.height =
   * layout.day-divider-height`，:468-475；单行组头无条目），所以按有据同位取值：
   * `height(LayoutTokens.segmentedHeight)` ＝ 36（`PublishTagPanel.ets:83`）。
   * 本仓单列一个名字而不是复用 `segmentedControlHeight`：两个 36 一旦互相绑定，
   * 改分段控件会静默改到吸顶带，而尺也没法分辨组头里是不是恰好装了个分段条。
   */
  stickyHeaderHeight: number;
  /** 追问选项间隙 */
  questionOptionGap: number;
  /** 追问进度圆点直径（契约 question-progress-dot 6） */
  questionProgressDot: number;
  /** 活动类型色点直径（契约 activity-type-dot 8） */
  activityDotSize: number;
  /** 2×2 卡片内缩 */
  widget2x2Padding: number;
  /** 2×4 卡片内缩 */
  widget2x4Padding: number;
  /** 家族契约沿用具名值（post/compose/profile/tab） */
  postCardPadding: number;
  composeGenreCardHeight: number;
  composeBodyHeight: number;
  composeFieldHeight: number;
  profileStatWidth: number;
  /** 「我的」页资料区头像直径（官方符号 + 圆底，不用位图资源） */
  profileAvatarSize: number;
  tabItemWidth: number;
  tabItemHeight: number;
  tabSideMargin: number;
  tabBottomGap: number;
  /** 追问选项卡最小高（契约 option-chip minHeight 56） */
  questionOptionMinHeight: number;
  /** 屏4 景点行缩略位（3:4 媒体比例） */
  spotThumbWidth: number;
  spotThumbHeight: number;
  /** 状态栏安全区兜底值（env(safe-area-inset-bottom, 12px) 的 12） */
  safeAreaFallback: number;
}

export const LayoutTokens: LayoutTokensType = {
  gridBaseline: 4,
  pagePadding: 16,
  pagePaddingWide: 20,
  itemGap: 12,
  blockGap: 16,
  sectionGap: 24,
  contentMaxWidth: 720,
  minTouchTarget: 44,
  titleBarHeight: 60,
  segmentedControlHeight: 36,
  tabBarHeight: 64,
  floatingDockWidth: 300,
  floatingDockMediumWidth: 420,
  floatingDockWideWidth: 560,
  floatingDockBottomMargin: 28,
  floatingDockBarHeight: 56,
  barGradientMaskHeight: 92,
  floatingDockClearance: 112,
  floatingDockSideMargin: 16,
  bottomScrollReserve: 94,
  hairlineWidth: 0.5,
  glassBorderWidth: 1,
  sheetPanelWidth: 344,
  sheetPanelPadding: 20,
  itinerarySpineWidth: 2,
  itineraryTimeGutter: 52,
  itineraryNodeSize: 24,
  itineraryNodeDot: 10,
  mediaThumbWidth: 96,
  mediaThumbHeight: 128,
  stickyBarScrollReserve: 110,
  shareBarScrollReserve: 150,
  itineraryRowMinHeight: 76,
  itineraryBlockGap: 12,
  transitLegHeight: 44,
  routeLineWidth: 2,
  mapOverlayInset: 16,
  mapHeightCompact: 200,
  dayDividerHeight: 44,
  stickyHeaderHeight: 36,
  questionOptionGap: 8,
  questionProgressDot: 6,
  activityDotSize: 8,
  questionOptionMinHeight: 56,
  spotThumbWidth: 36,
  spotThumbHeight: 48,
  widget2x2Padding: 12,
  widget2x4Padding: 16,
  postCardPadding: 16,
  composeGenreCardHeight: 112,
  composeBodyHeight: 124,
  composeFieldHeight: 72,
  profileStatWidth: 72,
  profileAvatarSize: 64,
  tabItemWidth: 58,
  tabItemHeight: 50,
  tabSideMargin: 18,
  tabBottomGap: 18,
  safeAreaFallback: 12
};

/**
 * 图标只有两档（§8 禁令 7）：22×22 控制档、48×48 展示档；44 是命中盒不是图形。
 * 14/16px 只允许出现在状态栏 mock（设备 chrome，决议 1）。
 */
export const IconSizes: IconSizesType = { control: 22, display: 48 };

export interface IconSizesType {
  control: number;
  display: number;
}
