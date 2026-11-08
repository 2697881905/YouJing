/**
 * 沉浸光感 / 系统玻璃材质统一入口（自「有据」线上定稿实现移植，2026-10-22）。
 *
 * 兼容性铁律（有据 AGC 审核实证）：hdsMaterial 命名空间与 HdsTabs.barFloatingStyle
 * 均 @since 6.1.0(23)。低版本设备运行时可能不存在 @hms.hds.hdsMaterial 模块——
 * 本文件绝不静态 import hdsMaterial，也不在模块顶层求值 hdsMaterial.*
 * （两者都会在缺失设备上加载即崩）。改用 deviceInfo.apiAvailable + canIUse 门禁。
 *
 * 有径落点（handoff §5/§9）：玻璃只四点位（顶栏/分段控件/浮动 dock/吸顶日标题），
 * 一律用本文件的材质档位，不翻 CSS 的 blur+rgba 数值；弹层不是玻璃，
 * 但 SheetOptions.systemMaterial 载体口径见 getSheetImmersiveMaterial 注释。
 *
 * 数值对照（SDK @hms.hds.hdsMaterial.d.ets）：
 *   MaterialType: NONE=0, ADAPTIVE=100, IMMERSIVE=101
 *   MaterialLevel: EXQUISITE=0, GENTLE=1, SMOOTH=2, ADAPTIVE=10
 * 使用处传数值字面量，避免为枚举值静态 import 缺失模块。
 */

import deviceInfo from '@ohos.deviceInfo';
import { uiMaterial } from '@kit.ArkUI';

// HDS 沉浸光感 API 的 @since 版本线
const HDS_IMMERSIVE_MIN_API: number = 23;
// canIUse 探测的 HMS 系统能力：HDS 组件核心（HdsTabs/HdsVisualComponent/hdsMaterial 同属此 syscap）。
const HDS_SYSCAP: string = 'SystemCapability.UIDesign.HDSComponent.Core';

let immersiveSupported: boolean | null = null;

/**
 * 探测当前设备是否支持 HDS 沉浸光感材质（同步、进程内缓存、异常返 false 不抛出）。
 * 条件：API ≥ 23 且设备声明 HDS syscap（模拟器/OpenHarmony 环境自动降级）。
 */
export function isImmersiveLightSenseSupported(): boolean {
  if (immersiveSupported === null) {
    try {
      immersiveSupported = deviceInfo.sdkApiVersion >= HDS_IMMERSIVE_MIN_API
        && canIUse(HDS_SYSCAP);
    } catch (e) {
      immersiveSupported = false;
    }
  }
  return immersiveSupported;
}

// 材质档位数值（与 SDK 枚举一致）。
// ⚠️ ADAPTIVE(10) 不等于「系统会挑最好」——有据真机实测它不出折射：
// 同一颗圆钮只差这一个字段，EXQUISITE 有玻璃珠折射环，ADAPTIVE 只是普通半透。
// 「要折射必须写 EXQUISITE」，取舍要显式做（handoff §9：材质档位不对，折射就没了）。
export const HDS_MATERIAL_LEVEL_ADAPTIVE: number = 10;
export const HDS_MATERIAL_LEVEL_EXQUISITE: number = 0;
export const HDS_MATERIAL_TYPE_IMMERSIVE: number = 101;

// —— 通用属性 systemMaterial（@since 26.0.0）：普通组件版沉浸光感 ——
// 载体：bindSheet 的 SheetOptions.systemMaterial、bindMenu 的 MenuOptions.systemMaterial，
// 以及 TopButtonMaterialModifier / FloatingTopButtonMaterialModifier（通用属性 systemMaterial）。
// 2026-11-07 全量对齐：按用户裁决恢复 #38 删掉的 GlassBlurStyle 与两个 AttributeModifier，
// 供 GlassPanel / GlowInput / SpringPanel / GlassPillButton / DesignButton / BottomTabBar 消费。
// 仍守兼容性铁律：新属性只放进 apiAvailable 门禁分支内调用，低版本加载即崩的形态绝不再出现。
//
// 档位规范（沉浸光感设计指南·场景规范，数值同 uiMaterial.ImmersiveStyle）：
//   顶部悬浮 → ULTRA_THIN；底部悬浮 → THIN；任意位置弹出 → THICK；半模态/弹框 → ULTRA_THICK。

let systemMaterialActive: boolean | null = null;

/** 材质是否实际生效；生效时使用处须撤掉自绘背景模糊与自绘阴影（会互相遮挡/叠加）。 */
export function isSystemMaterialActive(): boolean {
  if (systemMaterialActive === null) {
    try {
      systemMaterialActive = deviceInfo.apiAvailable('26.0.0');
    } catch (e) {
      systemMaterialActive = false;
    }
  }
  return systemMaterialActive;
}

let sheetImmersiveMaterial: uiMaterial.Material | null = null;

/**
 * 半模态（bindSheet）材质。载体纠正（有据「面板全透明」根因）：
 * systemMaterial 必须走 SheetOptions.systemMaterial 字段（@since 26.0.0），
 * 挂在 bindSheet builder 内的内容 Column 上属生效范围外、完全不渲染。
 * API < 26 返回 undefined，使用处按 isSystemMaterialActive() 回退实色 elevated 底。
 */
export function getSheetImmersiveMaterial(): uiMaterial.Material | undefined {
  if (!deviceInfo.apiAvailable('26.0.0')) {
    return undefined;
  }
  if (sheetImmersiveMaterial === null) {
    sheetImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
      // 场景规范：半模态/弹框 → ULTRA_THICK
      style: uiMaterial.ImmersiveStyle.ULTRA_THICK,
      interactive: false,
    });
  }
  return sheetImmersiveMaterial;
}

let menuImmersiveMaterial: uiMaterial.Material | null = null;

/**
 * 弹出菜单材质。载体：MenuOptions.systemMaterial（@since 26.0.0）——
 * 挂在菜单内容组件上属生效范围外，只能走 options 字段。
 * 场景规范：任意位置弹出 → THICK；API < 26 返 undefined 回退实色。
 */
export function getMenuImmersiveMaterial(): uiMaterial.Material | undefined {
  if (!deviceInfo.apiAvailable('26.0.0')) {
    return undefined;
  }
  if (menuImmersiveMaterial === null) {
    menuImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THICK,
      interactive: false,
    });
  }
  return menuImmersiveMaterial;
}

let segmentImmersiveMaterial: uiMaterial.Material | null = null;

/**
 * 官方 SegmentButton 材质。载体：options.backgroundSystemMaterial（@since 26.0.0）——
 * 挂在包裹它的 Row/Column 会被组件内部表面覆盖。
 * ULTRA_THIN 保留投影（宿主行需自带下方净空）；API < 26 返 undefined 落官方默认底色。
 */
export function getSegmentImmersiveMaterial(): uiMaterial.Material | undefined {
  if (!deviceInfo.apiAvailable('26.0.0')) {
    return undefined;
  }
  if (segmentImmersiveMaterial === null) {
    segmentImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      interactive: true,
      applyShadow: true,
    });
  }
  return segmentImmersiveMaterial;
}

/**
 * 系统玻璃档位（自绘件用 backgroundBlurStyle，不翻 CSS 的 blur+rgba 数值）。
 * 逐字对齐有据 `utils/immersiveMaterial.ets:72-81`：悬浮栏/底栏/弹层 = THICK，
 * 内容卡 = REGULAR，按压浅块 = THIN，高强调对话框 = THICK。
 * 2026-11-07 恢复（#38 曾按「官方件优先」删掉，本次按用户裁决全量对齐有据）。
 */
export class GlassBlurStyle {
  static readonly Floating: BlurStyle = BlurStyle.BACKGROUND_THICK;
  static readonly Card: BlurStyle = BlurStyle.BACKGROUND_REGULAR;
  static readonly Press: BlurStyle = BlurStyle.BACKGROUND_THIN;
  static readonly Dialog: BlurStyle = BlurStyle.BACKGROUND_THICK;
}

let topButtonMaterial: uiMaterial.Material | null = null;

function getTopButtonMaterial(): uiMaterial.Material {
  if (topButtonMaterial === null) {
    topButtonMaterial = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      interactive: true,
      applyShadow: false
    });
  }
  return topButtonMaterial;
}

/** 顶部常驻按钮的沉浸光感修饰器；HdsNavigation bottomBuilder 窄行用（关投影防硬边灰带）。 */
export class TopButtonMaterialModifier implements AttributeModifier<CommonAttribute> {
  applyNormalAttribute(instance: CommonAttribute): void {
    if (deviceInfo.apiAvailable('26.0.0')) {
      instance.systemMaterial(getTopButtonMaterial());
    }
  }
}

let floatingTopButtonMaterial: uiMaterial.Material | null = null;

function getFloatingTopButtonMaterial(): uiMaterial.Material {
  if (floatingTopButtonMaterial === null) {
    floatingTopButtonMaterial = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      interactive: true,
      applyShadow: true
    });
  }
  return floatingTopButtonMaterial;
}

/** 自带下方留白、不会被栏行裁切的标题栏按钮用（保留材质自带投影）。 */
export class FloatingTopButtonMaterialModifier implements AttributeModifier<CommonAttribute> {
  applyNormalAttribute(instance: CommonAttribute): void {
    if (deviceInfo.apiAvailable('26.0.0')) {
      instance.systemMaterial(getFloatingTopButtonMaterial());
    }
  }
}

/**
 * 栏级材质走**声明式字段**而不是 modifier：`TitleBarStyleOptions.systemMaterialEffect`
 * = `{ materialType: 101, materialLevel: 0 }`（照「有据」`HomeTab.ets:1048/1076` 同一入口）。
 * 这里原有的 `BarMaterialModifier` + `barMaterial()` 是另一条 attributeModifier 路线，
 * 全仓 0 消费方，两套机制并存只会让下一个人选错，故删除（2026-11-06 续 224）。
 * 真要接栏级材质时看任务 #31 的配方——**先做真机 A/B**，它与穿底是同一个改动。
 */
