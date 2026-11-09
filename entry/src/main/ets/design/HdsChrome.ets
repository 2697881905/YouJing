/**
 * HDS 官方顶栏的单点配置（对齐「有据」定稿：官方标题栏 + 沉浸渐变模糊，不再自绘标题 Row）。
 *
 * 三条来自有据真机实证的坑，改任何一条都会翻车：
 * 1. `content.menu` 的图标默认**白色**（HDS 约定：透明栏压在 hero 媒体上）。
 *    有径静止态栏下是页面画布（浅色 #FFF），白图标等于看不见 → 必须显式给
 *    menuStyle/backIconStyle 的 iconColor 用 token，深色模式才跟着翻白。
 *    （2026-11-09 起标题文字也脱离内置 mainTitle：改 stackBuilder 自绘衬线＋品牌蓝，
 *    titleStyle 两个色字段随之失效，只留 menu/backIcon 链还在用。）
 * 2. `maskExtraHeight` 官方默认 32vp，即模糊区天生往栏底之下多伸 32vp，会把首屏内容顶边糊掉
 *    （用户看到的"顶栏一直糊"就是这条）→ 压到 0，磨砂正好停在栏底。
 * 3. `blurRadius` 只在 GRADIENT_BLUR / IMMERSIVE_GRADIENT_BLUR 两档下出图，COMMON_BLUR 会把
 *    整条栏画成平色；且实测只有挂在 originalStyle 上才生效。
 *
 * 类型一律 `import type`：这些接口运行时擦除，不会像 hdsMaterial 那样在低版本上"import 即崩"。
 */

import { ComponentContent, LengthMetrics, UIContext } from '@kit.ArkUI';
import { ScrollEffectType } from '@kit.UIDesignKit';
import type {
  HdsNavigationBackgroundStyle,
  HdsNavigationIconItemStyle,
  HdsNavigationIconOptions,
  HdsNavigationMenuContentOptions,
  HdsNavigationMenuItemOptions,
  HdsNavigationTitleBarOptions,
  HdsNavigationTitleBarStyle,
  HdsNavigationTitleStyle,
  HdsTitleBarContentStyle,
  BottomBuilderParams,
  ScrollEffectOptions,
  SystemMaterialParams,
  TitleBarContentOptions,
  TitleBarStyleOptions
} from '@kit.UIDesignKit';
import { ColorTokens } from './ColorTokens';
import { FontFamilyNames, TypeTokens } from './TypeTokens';
import { SpaceTokens } from './SpaceTokens';
import { getSharedUiContext } from '../utils/longTake/cardRect';
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

/** 官方返回键的占位（vp）：40vp 圆钮实测占 16~56vp。stackBuilder 那行 width('100%')
 *  且 z 序在返回键之上，左内缩不留开会**吃掉返回键点击**（有据 ChatView 实测、
 *  DraftBoxPage/SearchResultPage 同值 64，防漂移 31）。 */
const BACK_SLOT_END_VP: number = 64;

export interface ChromeSpec {
  mainTitle: string;
  /** 副标题（如「3天2晚」「2026-07-01 – 07-03」），自绘 small/caption 档 */
  subTitle?: string;
  /**
   * 左上角是否有官方返回键：默认 true（子页/向导/详情都是推入页）；Tab 根页
   * hideBackButton(true) 的显式传 false，标题才从 base 起排而不是让出返回键位。
   */
  backSlot?: boolean;
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
   * 栏内底行（有据 HomeTab 的形状）：把页面里「钉在内容区顶部」的搜索/分段行迁进栏体。
   * 好处有两个：① 内容区从栏底起排后仍能在滚动时穿到栏下被材质采样
   * （钉在内容区的行会把这条路挡死，见续 257）；② 收起这类行改用 hideBottomBuilder，
   * 标题常驻、只收这一行，比收整块标题区更克制。
   */
  bottomBuilder?: CustomBuilder;
  /** 栏内底行高（vp）：要给足上下呼吸，行对内容双向裁切，投影铺不开会压出灰带 */
  bottomRowHeight?: number;
  // 穿底档已于 2026-11-07 铺满全部页面（对表第 19/20 行，用户裁决「做，风险我认」），
  // 迁移期开关 bleed 已删除：enableComponentSafeArea 恒 false，让位一律由
  // HdsChrome.contentTopInset(statusBarHeight) 承担。静态页（生成中/解锁）同样接了让位。
  /** 本页是否存在可滚容器；false 时关滚动特效，避免静止态空糊 */
  scrollable?: boolean;
  blurEndVp?: number;
  /**
   * 深浅档代 tick（EntryAbility.seedDarkMode 在档位**变化**时自增，AppStorage
   * `chromeThemeTick`）。页面把它从 `@StorageProp('chromeThemeTick')` 传进来。
   *
   * 为什么需要它：官方 HdsTitleBar 的自绘标题内容（stackBuilderComponent 的
   * ComponentContent）**不随配置切换重渲染**——真机实证（2026-11-10）：系统浅→深
   * 实时切换后，切档前挂载的页面标题仍按浅色档墨色渲染（#17171A 冻在 #121212 画布上，
   * 行程/规划两页可复现），build 重跑（滚动触发 barScrolled）也不重建内容。
   * 唯一可靠的刷新通道 = 换 tick 时换**新的 ComponentContent 实例**（titleContentOf
   * 缓存键带 tick）+ 页面因 @StorageProp 变化重跑 build，把新内容对象交给栏体重挂载。
   * 这与 ImmersiveSegmentBar `@Watch('rebuildOptions')` 重建官方件选项是同一族手法。
   */
  themeTick?: number;
}

/**
 * 栏标题自绘行（2026-11-09 对齐「有据」）：有据**所有**栏标题都是衬线＋正文字色
 * （`stackBuilder` 自绘：profileStackTitle / messageBrandRow / draftTitleRow——它的
 * `ColorTokens.primary` 实为 `ds_text_primary` 正文字色，浅色黑/深色白，**不是品牌蓝**；
 * 首版错搬成有径的 primary（品牌蓝），用户真机点名改黑）。HDS 内置 mainTitle 是
 * 系统默认 sans＋继承色——这就是最初用户看到的字体不一致。
 * 两档口径全抄有据：
 * · 根页（backSlot:false，无返回钮）：title 档 21/700/32，左内缩 base（16vp）
 * · 子页（默认，有返回钮）：headline 档 18/600/24 **显式衬线**（有据 headline 档本身
 *   不带族、draftTitleRow 显式给 serif），左内缩 64 让开返回键
 * 副标题沿官方 small 档语义：caption 12/450 muted。
 */
@Builder
function chromeTitleRow(spec: ChromeSpec) {
  Row() {
    Column() {
      Text(spec.mainTitle)
        .fontSize(spec.backSlot === false ? TypeTokens.title.size : TypeTokens.headline.size)
        .fontFamily(spec.backSlot === false ? TypeTokens.title.family : FontFamilyNames.serif)
        .fontWeight(spec.backSlot === false ? TypeTokens.title.weight : TypeTokens.headline.weight)
        .lineHeight(spec.backSlot === false ? TypeTokens.title.lineHeight : TypeTokens.headline.lineHeight)
        .fontColor(ColorTokens.ink)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (spec.subTitle !== undefined && spec.subTitle.length > 0) {
        Text(spec.subTitle)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(TypeTokens.caption.weight)
          .lineHeight(TypeTokens.caption.lineHeight)
          .fontColor(ColorTokens.muted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .alignItems(HorizontalAlign.Start)
  }
  .width('100%')
  .height('100%')
  .alignItems(VerticalAlign.Center)
  .padding({
    left: spec.backSlot === false ? SpaceTokens.base : BACK_SLOT_END_VP,
    right: SpaceTokens.base
  })
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
    if (isSystemMaterialActive()) {
      const material: SystemMaterialParams = {
        materialType: HDS_MATERIAL_TYPE_IMMERSIVE,
        materialLevel: HDS_MATERIAL_LEVEL_EXQUISITE
      };
      style.systemMaterialEffect = material;
    }
    let menu: HdsNavigationMenuContentOptions | undefined = undefined;
    if (spec.menu !== undefined && spec.menu.length > 0) {
      const cap: number = spec.menuMaxCount === undefined ? 3 : spec.menuMaxCount;
      const built: HdsNavigationMenuContentOptions = { value: spec.menu, maxCount: cap };
      menu = built;
    }
    // 标题自绘走两条通道（2026-11-09）：真机实证（dump：Text 直挂 HdsTitleBar = 内置管线）
    // 「静态类 lambda 直调全局 @Builder」在 API 26 运行时被**静默忽略**——全局 builder 没有
    // 组件实例可绑。主通道改 `stackBuilderComponent`（ComponentContent 显式绑共享 UIContext，
    // since 6.0.1(21)），wrapBuilder 包装同一个全局 builder；老 `stackBuilder` 通道保留给
    // API 20–24 云手机兜底（新版字段在旧运行时上无害地被忽略）。文档写明 Content 系优先。
    const content: TitleBarContentOptions = {
      stackBuilder: (): void => {
        chromeTitleRow(spec);
      },
      menu: menu
    };
    const ui: UIContext | null = getSharedUiContext();
    if (ui !== null) {
      content.stackBuilderComponent = HdsChrome.titleContentOf(ui, spec);
    }
    if (spec.bottomBuilder !== undefined) {
      const row: BottomBuilderParams = {
        builder: spec.bottomBuilder,
        height: spec.bottomRowHeight === undefined ? 48 : spec.bottomRowHeight
      };
      content.bottomBuilder = row;
    }
    const options: HdsNavigationTitleBarOptions = {
      content: content,
      style: style,
      // 栏体穿到状态栏下（带子与栏区同层）恒定 true。
      // 内容区原点恒 false＝从窗口原点起算，让位由页面的 contentTopInset 承担（有据同位写法）。
      // 注意这与已删的 `fullBleed` 不是一回事：那条翻的是栏内两行顺序，这条动的是内容原点。
      avoidLayoutSafeArea: true,
      // 恒 false：页面自己用 contentTopInset 让位（放进滚动容器、随内容滚走）。
      // 曾试过 true（组件安全区让位，有据 HomeTab 的写法）：静止能对，但**滚动到不了栏下**
      // （连滚三次 ListItem 顶边始终 ≥ 栏底），所以删掉这个开关、写死 false。
      enableComponentSafeArea: false
    };
    return options;
  }

  /** 已建 ComponentContent 缓存：key = 标题|副标题|档位。标题串不变就复用同一份，
   *  免得每次 build 重建内容造成标题闪动；行程页等动态标题变文案时会拿到新 key、建新份。 */
  private static readonly titleCache: Map<string, ComponentContent<Object>> = new Map();

  private static titleContentOf(ui: UIContext, spec: ChromeSpec): ComponentContent<Object> {
    // 键必须带深浅档 tick：档位切换时 tick 变化 → 旧缓存不再命中 → 建新 ComponentContent，
    // 栏体重挂载后按**当前档**重解 $r 色（见 ChromeSpec.themeTick 的真机实证说明）。
    const tick: number = spec.themeTick === undefined ? 0 : spec.themeTick;
    const key: string = `${spec.mainTitle}|${spec.subTitle ?? ''}|${spec.backSlot === false ? 'root' : 'back'}|${tick}`;
    const cached: ComponentContent<Object> | undefined = HdsChrome.titleCache.get(key);
    if (cached !== undefined) {
      return cached;
    }
    const made: ComponentContent<Object> = new ComponentContent(ui, wrapBuilder(chromeTitleRow), spec);
    // 标题串集合有界（每页一枚 + 行程名若干），不设淘汰也涨不到哪去
    HdsChrome.titleCache.set(key, made);
    return made;
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
  static contentTopInset(statusBarHeightVp: number, bottomRowVp: number = 0): number {
    return statusBarHeightVp + MINI_TITLE_BAR_VP + bottomRowVp;
  }
}
