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
  /** 浮动 dock 宽 */
  floatingDockWidth: number;
  /** 浮动 dock 距底（另加安全区，见 dockBottomSafe） */
  floatingDockBottomMargin: number;
  /** 浮动 dock 左右距边 */
  floatingDockSideMargin: number;
  /** 通用底部滚动预留 */
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
  /** 追问选项间隙 */
  questionOptionGap: number;
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
  tabItemWidth: number;
  tabItemHeight: number;
  tabSideMargin: number;
  tabBottomGap: number;
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
  floatingDockBottomMargin: 28,
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
  questionOptionGap: 8,
  widget2x2Padding: 12,
  widget2x4Padding: 16,
  postCardPadding: 16,
  composeGenreCardHeight: 112,
  composeBodyHeight: 124,
  composeFieldHeight: 72,
  profileStatWidth: 72,
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
