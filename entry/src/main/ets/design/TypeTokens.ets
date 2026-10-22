/**
 * 字阶 tokens · 封闭八档（handoff §3），禁止插值。
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
  /** 行程时间 12/600 tabular */
  time: TypeRoleSpec;
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
  display: { family: FAMILY_SERIF, size: 32, weight: 700, lineHeight: 44 },
  title: { family: FAMILY_SERIF, size: 21, weight: 700, lineHeight: 32 },
  headline: { family: FAMILY_SANS, size: 18, weight: 600, lineHeight: 24 },
  body: { family: FAMILY_SANS, size: 16, weight: 400, lineHeight: 24 },
  small: { family: FAMILY_SANS, size: 14, weight: 400, lineHeight: 20 },
  caption: { family: FAMILY_SANS, size: 12, weight: 450, lineHeight: 16 },
  overline: { family: FAMILY_SANS, size: 11, weight: 600, lineHeight: 0 },
  time: { family: FAMILY_SANS, size: 12, weight: 600, lineHeight: 0 }
};

/** 允许字号封闭集，audit 用 */
export const ALLOWED_FONT_SIZES: number[] = [10, 11, 12, 14, 16, 18, 21, 32];
