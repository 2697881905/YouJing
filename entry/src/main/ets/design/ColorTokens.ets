/**
 * 色彩 tokens · 契约源：设计底稿 v1 handoff §2（DESIGN.md md5 7c715d63）。
 *
 * 实现机制（方案 A，2026-10-22 定）：色值全部落 resources/base + resources/dark
 * 两份 color.json，本文件只导出 $r 引用；深色由系统 ColorMode 自动切换，页面零分支。
 * 稿件 CSS 的 rgba() 已换算为 #AARRGGBB（alpha 在前），换算由脚本完成。
 *
 * 2026-11-07 全量对齐（以有据源码为准，见 Docs/superpowers/specs/2026-11-07-表现层全量对齐-差异表.md）：
 * - 玻璃点位不再封闭为四处栏面；卡片 / 输入框 / 弹窗 / 浮层可用自绘玻璃件，
 *   点位与档位以差异表 §6 登记为准。三处栏面仍走系统材质 50 + scrolled 门控。
 * - 状态表达允许 opacity：禁用 0.45、按下 0.92（配方见 MotionTokens / Pressable）。
 * - 语义色仍五个封闭；新增 brandSolid / onBrand / dangerTint 与一组玻璃栏面色，
 *   逐件在 resources/{base,dark}/element/color.json 成对登记，契约 ledger 同步。
 * - 「官方件优先、禁自绘」禁令已废止；材质生效时自绘 border/shadow/blur 归零的避让仍有效。
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
  /** 有据 ds_brand_solid：选中胶囊 / 主按钮实心底（深色 #0050A0 上白字 7.91:1） */
  brandSolid: Resource;
  /** 有据 ds_on_brand：实心品牌底上的字 */
  onBrand: Resource;
  /**
   * 地图 Day chip 选中实心底：中性深灰、非品牌蓝（用户 2026-11-10 定「深色即可，不是黑色」）。
   * 两档同值 #47474E（先试 #2B2B31/#313137，真机上贴着夜图读成近黑，提一档才是"深灰"）；
   * 白字 9.1:1；深档比夜图玻璃珠合成底（实测约 #2B3A4F）亮且无蓝色相，实心 vs 半透一眼分清。
   */
  chipSolid: Resource;
  /** 有据 dangerTint：SoftChip DANGER 档 */
  dangerTint: Resource;
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
  /**
   * 栏面投影成对色（契约 v2 `bar_shadow`）：浅色 #2E1A1A1E / 深色 #8C000000，
   * 逐字取契约 glass-bar-shadow 的十六进制列（DESIGN.md:703/714）。
   * T10 只落**资源与 token**，本轮不建任何 `.shadow(` 消费点——带 `bar_shadow` 的
   * 栏面件与 elevation 判据反转必须同原子批（简报 §0.1/§0.3）。
   */
  barShadow: Resource;
  /** 有据玻璃栏面族：自绘玻璃件在内容区 / 低版本设备上的表面与描边兜底 */
  glassBarSurface: Resource;
  glassBarBorder: Resource;
  /** 性别徽章四件套（值 1:1 取自有据 ds_gender_*，共享资料卡视觉） */
  genderMaleSurface: Resource;
  genderMaleText: Resource;
  genderFemaleSurface: Resource;
  genderFemaleText: Resource;
  /** ── 有据同名字段别名（ProfileHeader/ProfileIdentity/GlassPillButton 等搬运件
   *  原样引用；值逐个核对过与有径现有资源同源，改色需两仓同步）── */
  secondary: Resource;
  tertiary: Resource;
  sunken: Resource;
  glassClear: ResourceColor;
  glassWhite: ResourceColor;
  barTabSelectedBg: Resource;
  brand: Resource;
  brandTint: Resource;
  brandPress: Resource;
  barSurface: Resource;
  barBorder: Resource;
  glassBarBg: Resource;
  glassCardBg: Resource;
  glassSegmentBg: Resource;
  glassSegmentBorder: Resource;
  glassPillFill: Resource;
  glassPillRim: Resource;
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
  // 性别徽章四件套：值 1:1 取自有据（ds_gender_*）——资料卡与有据共享视觉，改色需两仓同步
  genderMaleSurface: $r('app.color.gender_male_surface'),
  genderMaleText: $r('app.color.gender_male_text'),
  genderFemaleSurface: $r('app.color.gender_female_surface'),
  genderFemaleText: $r('app.color.gender_female_text'),
  // 有据同名别名（逐值核对：secondary=ds_text_secondary=body；tertiary=ds_text_tertiary=muted；
  // sunken=ds_sunken=surfaceSunken；brand/brandTint/brandPress=primary/primaryTint/primaryPress；
  // barSurface/barBorder=glassBarSurface/glassBarBorder；glassClear/barTabSelectedBg 为新增）
  secondary: $r('app.color.body'),
  tertiary: $r('app.color.muted'),
  sunken: $r('app.color.surface_sunken'),
  glassClear: '#00FFFFFF',
  glassWhite: '#FFFFFF',
  barTabSelectedBg: $r('app.color.bar_tab_selected_bg'),
  brand: $r('app.color.primary'),
  brandTint: $r('app.color.primary_tint'),
  brandPress: $r('app.color.primary_press'),
  barSurface: $r('app.color.glass_bar_surface'),
  barBorder: $r('app.color.glass_bar_border'),
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
  brandSolid: $r('app.color.brand_solid'),
  onBrand: $r('app.color.on_brand'),
  chipSolid: $r('app.color.chip_solid'),
  dangerTint: $r('app.color.danger_tint'),
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
  barShadow: $r('app.color.bar_shadow'),
  glassBarSurface: $r('app.color.glass_bar_surface'),
  glassBarBorder: $r('app.color.glass_bar_border'),
  glassBarBg: $r('app.color.glass_bar_bg'),
  glassCardBg: $r('app.color.glass_card_bg'),
  glassSegmentBg: $r('app.color.glass_segment_bg'),
  glassSegmentBorder: $r('app.color.glass_segment_border'),
  glassPillFill: $r('app.color.glass_pill_fill'),
  glassPillRim: $r('app.color.glass_pill_rim'),
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
