/**
 * 色彩 tokens · 契约源：设计底稿 v1 handoff §2（DESIGN.md md5 7c715d63）。
 *
 * 实现机制（方案 A，2026-10-22 定）：色值全部落 resources/base + resources/dark
 * 两份 color.json，本文件只导出 $r 引用；深色由系统 ColorMode 自动切换，页面零分支。
 * 稿件 CSS 的 rgba() 已换算为 #AARRGGBB（alpha 在前），换算由脚本完成。
 *
 * 玻璃面规则（handoff §5 + §9）：顶栏/分段控件/浮动 dock/吸顶日标题四处玻璃
 * 不翻成色值，一律走系统材质档位（backgroundEffect / systemMaterial，
 * 要折射必须 EXQUISITE(0)）；弹层不是玻璃，用实色 surface_elevated + floating 阴影
 * + modal_scrim 遮罩。glass-* 系列 CSS 色值不入库。
 *
 * 禁令对照（§8）：不许用 opacity 表达状态；语义色五个封闭；
 * 深色下实心语义色上的标签用 on_primary（#121212 墨字，非白字，AA 决议）。
 */

export interface ColorTokensType {
  // 画布与表面
  canvas: Resource;
  surfaceElevated: Resource;
  surfaceSubtle: Resource;
  surfacePanel: Resource;
  surfaceSunken: Resource;
  skeletonBase: Resource;
  skeletonHighlight: Resource;
  // 文字与图标
  ink: Resource;
  body: Resource;
  muted: Resource;
  faint: Resource;
  icon: Resource;
  onDark: Resource;
  /** 白字降级档 60%（分段栏未选项压深色背板时用，源自有据 ImmersiveSegmentBar 实测口径） */
  onDarkDegraded: Resource;
  // 品牌与语义
  primary: Resource;
  primaryPress: Resource;
  primaryTint: Resource;
  /** dock 光晕外缘：alpha 0 但保留品牌蓝色相，避免渐变往灰里褪 */
  primaryGlowEdge: Resource;
  onPrimary: Resource;
  accentMention: Resource;
  success: Resource;
  warning: Resource;
  danger: Resource;
  like: Resource;
  bookmark: Resource;
  // 线与遮罩
  hairline: Resource;
  /** 次按钮描边（契约 rgba(196,196,202,0.40) / 深色 rgba(69,69,75,0.32)） */
  borderSubtle: Resource;
  hairlineStrong: Resource;
  separator: Resource;
  modalScrim: Resource;
  // 路线图（浅色 paper / 深色 night 同名双值自动切换）
  routePath: Resource;
  routePathSoft: Resource;
  routeNodeFill: Resource;
  routeNodeStroke: Resource;
  routeContour: Resource;
  routeWater: Resource;
  routeLand: Resource;
  routeGold: Resource;
  routeBgTop: Resource;
  routeBgBottom: Resource;
  // 星图（widget/空状态）
  starInk: Resource;
  starRing: Resource;
  starIcon: Resource;
  starGold: Resource;
  starBadge: Resource;
  starBgTop: Resource;
  starBgBottom: Resource;
}

export const ColorTokens: ColorTokensType = {
  canvas: $r('app.color.canvas'),
  surfaceElevated: $r('app.color.surface_elevated'),
  surfaceSubtle: $r('app.color.surface_subtle'),
  surfacePanel: $r('app.color.surface_panel'),
  surfaceSunken: $r('app.color.surface_sunken'),
  skeletonBase: $r('app.color.skeleton_base'),
  skeletonHighlight: $r('app.color.skeleton_highlight'),
  ink: $r('app.color.ink'),
  body: $r('app.color.body'),
  muted: $r('app.color.muted'),
  faint: $r('app.color.faint'),
  icon: $r('app.color.icon'),
  onDark: $r('app.color.on_dark'),
  onDarkDegraded: $r('app.color.on_dark_degraded'),
  primary: $r('app.color.primary'),
  primaryPress: $r('app.color.primary_press'),
  primaryTint: $r('app.color.primary_tint'),
  primaryGlowEdge: $r('app.color.primary_glow_edge'),
  onPrimary: $r('app.color.on_primary'),
  accentMention: $r('app.color.accent_mention'),
  success: $r('app.color.success'),
  warning: $r('app.color.warning'),
  danger: $r('app.color.danger'),
  like: $r('app.color.like'),
  bookmark: $r('app.color.bookmark'),
  hairline: $r('app.color.hairline'),
  borderSubtle: $r('app.color.border_subtle'),
  hairlineStrong: $r('app.color.hairline_strong'),
  separator: $r('app.color.separator'),
  modalScrim: $r('app.color.modal_scrim'),
  routePath: $r('app.color.route_path'),
  routePathSoft: $r('app.color.route_path_soft'),
  routeNodeFill: $r('app.color.route_node_fill'),
  routeNodeStroke: $r('app.color.route_node_stroke'),
  routeContour: $r('app.color.route_contour'),
  routeWater: $r('app.color.route_water'),
  routeLand: $r('app.color.route_land'),
  routeGold: $r('app.color.route_gold'),
  routeBgTop: $r('app.color.route_bg_top'),
  routeBgBottom: $r('app.color.route_bg_bottom'),
  starInk: $r('app.color.star_ink'),
  starRing: $r('app.color.star_ring'),
  starIcon: $r('app.color.star_icon'),
  starGold: $r('app.color.star_gold'),
  starBadge: $r('app.color.star_badge'),
  starBgTop: $r('app.color.star_bg_top'),
  starBgBottom: $r('app.color.star_bg_bottom')
};
