/**
 * HDS 官方顶栏的单点配置（对齐「有据」定稿：官方标题栏 + 沉浸渐变模糊，不再自绘标题 Row）。
 *
 * 三条来自有据真机实证的坑，改任何一条都会翻车：
 * 1. `content.menu` 的图标与标题文字默认都是**白色**（HDS 约定：透明栏压在 hero 媒体上）。
 *    有径静止态栏下是页面画布（浅色 #FFF），白图标/白标题等于看不见 → 必须显式给
 *    menuStyle/backIconStyle 的 iconColor 与 titleStyle 的 mainTitleColor/subTitleColor 用 token，
 *    深色模式才跟着翻白。（浅色真机量过：整条标题栏只有返回箭头在画，标题区一片 255。）
 * 2. `maskExtraHeight` 官方默认 32vp，即模糊区天生往栏底之下多伸 32vp，会把首屏内容顶边糊掉
 *    （用户看到的"顶栏一直糊"就是这条）→ 压到 0，磨砂正好停在栏底。
 * 3. `blurRadius` 只在 GRADIENT_BLUR / IMMERSIVE_GRADIENT_BLUR 两档下出图，COMMON_BLUR 会把
 *    整条栏画成平色；且实测只有挂在 originalStyle 上才生效。
 *
 * 类型一律 `import type`：这些接口运行时擦除，不会像 hdsMaterial 那样在低版本上"import 即崩"。
 */

import { LengthMetrics } from '@kit.ArkUI';
import { ScrollEffectType } from '@kit.UIDesignKit';
import type {
  HdsNavigationBackgroundStyle,
  HdsNavigationIconItemStyle,
  HdsNavigationIconOptions,
  HdsNavigationMenuContentOptions,
  HdsNavigationMenuItemOptions,
  HdsNavigationTitle,
  HdsNavigationTitleBarOptions,
  HdsNavigationTitleBarStyle,
  HdsNavigationTitleStyle,
  HdsTitleBarContentStyle,
  ScrollEffectOptions,
  TitleBarContentOptions,
  TitleBarStyleOptions
} from '@kit.UIDesignKit';
import { ColorTokens } from './ColorTokens';

/** 滚动后栏体磨砂半径（vp）：契约 layout.glass-blur = 24，四点位同一把尺 */
const BAR_BLUR_RADIUS: number = 24;
/** 模糊渐变终点：从 0 推到这段距离内完成"不糊→糊" */
const DEFAULT_BLUR_END_VP: number = 32;

export interface ChromeSpec {
  mainTitle: string;
  /** 副标题（如「3天2晚」「2026-07-01 – 07-03」），官方 small 档 */
  subTitle?: string;
  /** 右侧官方圆钮菜单（替代自绘 SymbolGlyph + onClick） */
  menu?: Array<HdsNavigationMenuItemOptions>;
  /** 栏内最多直出几枚图标，其余收进官方「更多」；不给即 3 */
  menuMaxCount?: number;
  /** 沉浸画布页（地图/全屏底图）：内容铺到状态栏下，栏体只作透明悬浮层 */
  fullBleed?: boolean;
  /** 页面滚动状态：驱动 blurRadius，静止时不给模糊（有据静止态白底白图标教训） */
  scrolled?: boolean;
  blurEndVp?: number;
}

export class HdsChrome {
  /** 官方标题栏菜单项：SymbolGlyph 资源 + 无障碍标签 + 动作 */
  static item(icon: Resource, label: string, action: () => void): HdsNavigationMenuItemOptions {
    const content: HdsNavigationIconOptions = {
      icon: icon,
      label: label,
      action: action
    };
    const item: HdsNavigationMenuItemOptions = { content: content };
    return item;
  }

  static bar(spec: ChromeSpec): HdsNavigationTitleBarOptions {
    const endVp: number = spec.blurEndVp === undefined ? DEFAULT_BLUR_END_VP : spec.blurEndVp;
    const scrollEffect: ScrollEffectOptions = {
      enableScrollEffect: true,
      scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR,
      blurEffectiveStartOffset: LengthMetrics.vp(0),
      blurEffectiveEndOffset: LengthMetrics.vp(endVp)
    };
    const backgroundStyle: HdsNavigationBackgroundStyle = {
      backgroundColor: Color.Transparent,
      blurRadius: spec.scrolled === true ? BAR_BLUR_RADIUS : 0,
      maskExtraHeight: 0
    };
    const iconStyle: HdsNavigationIconItemStyle = { iconColor: ColorTokens.ink };
    // 标题文字与图标同族：HDS 默认也是白的（透明栏压在 hero 媒体上的假设），
    // 浅色画布上等于整条栏只剩个返回箭头。真机量过：标题区整块 255,255,255。
    const titleStyle: HdsNavigationTitleStyle = {
      mainTitleColor: ColorTokens.ink,
      subTitleColor: ColorTokens.muted
    };
    const contentStyle: HdsTitleBarContentStyle = {
      titleStyle: titleStyle,
      menuStyle: iconStyle,
      backIconStyle: iconStyle
    };
    const originalStyle: HdsNavigationTitleBarStyle = {
      backgroundStyle: backgroundStyle,
      contentStyle: contentStyle
    };
    const style: TitleBarStyleOptions = {
      scrollEffectOpts: scrollEffect,
      originalStyle: originalStyle
    };
    const title: HdsNavigationTitle = {
      mainTitle: spec.mainTitle,
      subTitle: spec.subTitle
    };
    let menu: HdsNavigationMenuContentOptions | undefined = undefined;
    if (spec.menu !== undefined && spec.menu.length > 0) {
      const cap: number = spec.menuMaxCount === undefined ? 3 : spec.menuMaxCount;
      const built: HdsNavigationMenuContentOptions = { value: spec.menu, maxCount: cap };
      menu = built;
    }
    const content: TitleBarContentOptions = { title: title, menu: menu };
    const options: HdsNavigationTitleBarOptions = {
      content: content,
      style: style,
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: spec.fullBleed !== true
    };
    return options;
  }
}
