/**
 * 字阶 tokens · 封闭九档（handoff §3），禁止插值。
 *
 * 允许字号只有 10/11/12/14/16/18/21/32；13/15/17/19/20 不存在。
 * 字距全局 0；所有数字 tabular（Text 上 `.fontFeature("'tnum' on")`）。
 * serif（NotoSerifSC，已打包 rawfile 并在 EntryAbility 注册）永不上控件、
 * 永不上站点名、永不上数字——唯一例外：金额 hero 用 display 档但走 sans。
 */

export interface TypeRoleSpec {
  family: string;
  size: number;
  weight: number;
  lineHeight: number;
}

export interface TypeTokensType {
  /** 页面大标题 32/700/44 serif；金额 hero 同档但 family 换 sans */
  display: TypeRoleSpec;
  /** 日标题、卡片目的地名 21/700/32 serif */
  title: TypeRoleSpec;
  /** 所有站点名 18/600/24 sans（绝不 serif） */
  headline: TypeRoleSpec;
  /** 正文 16/400/24 */
  body: TypeRoleSpec;
  /** 次级 14/400/20 */
  small: TypeRoleSpec;
  /** 辅助信息 12/450/16 */
  caption: TypeRoleSpec;
  /** 标签 11/600 */
  overline: TypeRoleSpec;
  /** dock 项标签 10/400/14：全 App 唯一允许的小于 11px 的字符串（DESIGN §2 nav-label） */
  navLabel: TypeRoleSpec;
  /** 桌面卡片辅助行 11/400/14（widget 最小字号档；契约 widget-min-text 11） */
  widgetMeta: TypeRoleSpec;
  /** 行程时间 12/600 tabular */
  time: TypeRoleSpec;
  /** 有据源码语义别名（值不变，避免 644 个调用点重命名）：callout = small */
  callout: TypeRoleSpec;
  /** 有据 title = 21/650/28 sans（控件上的标题字档）。
   * 有据的 titleSerif / displaySerif 在本仓就是现有的 title / display 两档（同为 serif），
   * 不另建别名——避免字族尺把同名新档误判为契约外 serif 槽。 */
  titleSans: TypeRoleSpec;
}

const FAMILY_SERIF: string = 'NotoSerifSC';
const FAMILY_SANS: string = 'HarmonyOS Sans';

export const FontFamilyNames: FontFamilyNamesType = {
  serif: FAMILY_SERIF,
  sans: FAMILY_SANS
};

export interface FontFamilyNamesType {
  serif: string;
  sans: string;
}

export const TypeTokens: TypeTokensType = {
  // ⚠ overline / time 两档的 lineHeight 写 0，含义是「这一档不设行高、走系统默认」，不是行高值。
  // 把它直接喂进 `.lineHeight(0)` 会把行盒压到字高以下（`tools/audit_type.py` 已钉住这条）；
  // 有据同位 overline 是 11/600/**14**，确实要行高时按 14 显式写。
  display: { family: FAMILY_SERIF, size: 32, weight: 700, lineHeight: 44 },
  title: { family: FAMILY_SERIF, size: 21, weight: 700, lineHeight: 32 },
  headline: { family: FAMILY_SANS, size: 18, weight: 600, lineHeight: 24 },
  body: { family: FAMILY_SANS, size: 16, weight: 400, lineHeight: 24 },
  small: { family: FAMILY_SANS, size: 14, weight: 400, lineHeight: 20 },
  caption: { family: FAMILY_SANS, size: 12, weight: 450, lineHeight: 16 },
  overline: { family: FAMILY_SANS, size: 11, weight: 600, lineHeight: 0 },
  navLabel: { family: FAMILY_SANS, size: 10, weight: 400, lineHeight: 14 },
  widgetMeta: { family: FAMILY_SANS, size: 11, weight: 400, lineHeight: 14 },
  time: { family: FAMILY_SANS, size: 12, weight: 600, lineHeight: 0 },
  callout: { family: FAMILY_SANS, size: 14, weight: 400, lineHeight: 20 },
  titleSans: { family: FAMILY_SANS, size: 21, weight: 650, lineHeight: 28 }
};

/** 允许字号封闭集，audit 用 */
export const ALLOWED_FONT_SIZES: number[] = [10, 11, 12, 14, 16, 18, 21, 32];
