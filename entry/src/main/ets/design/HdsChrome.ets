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
  SystemMaterialParams,
  TitleBarContentOptions,
  TitleBarStyleOptions
} from '@kit.UIDesignKit';
import { ColorTokens } from './ColorTokens';
import { HDS_MATERIAL_LEVEL_EXQUISITE, HDS_MATERIAL_TYPE_IMMERSIVE,
  isSystemMaterialActive } from '../utils/immersiveMaterial';

/** MINI 档标题栏高（vp）：SDK `HdsNavDestinationTitleMode.MINI` 注释写明固定 56vp，
 *  穿底让位要用它而不是契约里那条 60vp 的沉浸顶栏（两者不是同一个栏）。 */
const MINI_TITLE_BAR_VP: number = 56;

/** 滚动后栏体磨砂半径（vp）：契约 layout.glass-blur = 50，三处栏面同一把尺
 *  （分段控件是 `components.segmented-control.blur: 20` 的组件内成文例外，不走这条路径） */
const BAR_BLUR_RADIUS: number = 50;
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
  // 这里原有过一项 `fullBleed`（内容铺到状态栏下、栏体只作透明悬浮层）：全仓零调用点，
  // 且真机实测它会把栏内两行翻转成分段在上、标题在下（契约 §1055 是标题在上）——已删。
  // 2026-11-05 还试过用它的位置加 `barBackground`（把顶边基色交给栏体），也不成立：
  // 栏体涂不出那层不透明底，撤掉壳层涂色后地图格顶边从「平 L=55/56」变成「透底图渐变」
  // （同一机位复拍，见 Docs/INIT_REPORT.md §5ci 续 198）。底图基色仍由壳层 + TopStrip 单点涂。
  /** 页面滚动状态：驱动 blurRadius，静止时不给模糊（有据静止态白底白图标教训） */
  scrolled?: boolean;
  /**
   * 穿底档（对表第 19/20 行，2026-11-07 用户裁决「做，风险我认」）：
   * true → `enableComponentSafeArea:false`（内容区从窗口原点起算，能画到栏体底下被材质采样）
   *        ＋ 栏级 `systemMaterialEffect`（IMMERSIVE=101 / EXQUISITE=0，API<26 门禁不过就不设）。
   * 开了它，页面**必须**自己给内容让位：`HdsChrome.contentTopInset(this.statusBarHeight)`
   * 加进滚动容器的 top padding（这段留白随内容滚走，才是有据「帖子穿到栏底下」的形状）。
   * 这是迁移期开关：18 页全部接完后删掉它、把 false 写死（任务 #31）。
   */
  bleed?: boolean;
  /** 本页是否存在可滚容器；false 时关滚动特效，避免静止态空糊 */
  scrollable?: boolean;
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
      enableScrollEffect: spec.scrollable !== false,
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
      originalStyle: originalStyle,
      // 两态：originalStyle = 静止态，scrollEffectStyle = 滚动到位后的终态（契约 §1062 的
      // 「三处栏面 blur 50」靠这条切换；只写 originalStyle 等于没有终态，模糊推不出来）。
      scrollEffectStyle: { contentStyle: contentStyle }
    };
    // 栏级沉浸材质（对表第 19 行）：只有穿底档才给——栏体下面没有内容时材质是白压白，
    // 这也是它此前在模拟器上 A/B 无差别、被回退的原因（续 222）。数值字面量避免静态
    // import hdsMaterial（低版本设备 import 即崩，见 immersiveMaterial.ets 兼容性铁律）。
    if (spec.bleed === true && isSystemMaterialActive()) {
      const material: SystemMaterialParams = {
        materialType: HDS_MATERIAL_TYPE_IMMERSIVE,
        materialLevel: HDS_MATERIAL_LEVEL_EXQUISITE
      };
      style.systemMaterialEffect = material;
    }
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
      // 栏体穿到状态栏下（带子与栏区同层）恒定 true。
      // 内容区原点则按档切：默认 true＝内容被顶到栏体之下（穿不过去）；
      // 穿底档 false＝内容从窗口原点起算，让位改由页面的 contentTopInset 承担（有据同位写法）。
      // 注意这与已删的 `fullBleed` 不是一回事：那条翻的是栏内两行顺序，这条动的是内容原点。
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: spec.bleed !== true
    };
    return options;
  }

  /**
   * 穿底档的内容让位（vp）＝状态栏高 ＋ MINI 标题栏高（与有据 `profileListInset()` 同式）。
   *
   * 必须含状态栏：`enableComponentSafeArea:false` 下滚动容器的布局原点回到**窗口 0**。
   * 真机实证（2026-11-07，装机成功字样确认后）：List 原点 y=0，只给 56vp 让位时首个
   * ListItem 落在 175px＝56vp，而栏带占 106..281px ⇒ 首行被栏盖住 33.9vp。
   * 补上状态栏后 ListItem 顶边应 == HdsTitleBar 底边（281px），这条就是验收判据。
   * ⚠ 曾据一次**旧包**读数（install 只回 AppMod finish、未确认成功）误判成"原点已在状态栏之下"
   * 而删掉状态栏项——装机必须看到 `install bundle successfully` 才算换了包。
   * statusBarHeightVp 由页面 `@StorageProp('statusBarHeight')` 传入，冷启晚到也能重排。
   */
  static contentTopInset(statusBarHeightVp: number): number {
    return statusBarHeightVp + MINI_TITLE_BAR_VP;
  }
}
