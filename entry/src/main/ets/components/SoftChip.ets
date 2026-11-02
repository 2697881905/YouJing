// 家族件：components.tag-pill ｜ 对标有据：design/components/SoftChip.ets:19-76 ｜ 状态：已落地未挂载 ｜ 契约锚点：3fcc3a62

/**
 * SoftChip —— 小型实色动作胶囊（家族唯一样式源，「重试 / 加一块」这类）。
 *
 * 契约 `components.tag-pill`（DESIGN.md:615-619）四行映射：
 *   backgroundColor {colors.primary-tint} → 选中/品牌档的底由 tone 决定（见下）
 *   textColor {colors.primary}            → 同上
 *   typography {typography.hierarchy.caption} → `TypeTokens.caption`（12/450/16）
 *   rounded {rounded.pill}                → `RadiusTokens.pill`
 *   padding "4px 10px"                    → 纵向 `SpaceTokens.xs`(4)；横向 10 **离表**
 *     （有径间距阶梯封闭为 0/4/8/12/16/18/20/24/28/32/48/94，无 10），按 handoff §7
 *     「实现期一律并到本阶梯」并到 `SpaceTokens.sm`(8)，与 TripsPage.ets:227 现写
 *     标签胶囊同一档；不为了「对标完整」把 10 写成离表字面量（audit_geometry 必红）。
 *
 * 组合方式照搬有据：**外壳是 `Pressable`**（`SoftChip.ets:51`），按下反馈只有一处实现。
 *
 * tone 只有两档，有据的第三档 **danger 本轮不建**，理由写在这里：
 * 有据 danger 档 = `dangerTint` 底 + `danger` 字（`SoftChip.ets:31-45`）。有径色板里
 * **没有 danger_tint**（base/dark 各 52 件成对，简报 §0.3 收在 52），而 §8 禁令 10
 * 不许用 opacity 把 danger 压成 tint；契约 v2 也没命名过第 53 件。⇒ 等真出现
 * 「取消拉黑」这类危险动作时，与契约同批加 `danger_tint` 成对资源 + 第三档，
 * 本轮不加死档。
 *
 * 禁用态不用 opacity：有据 `SoftChip.ets:73` 的 `.opacity(this.disabled ? 0.45 : 1)`
 * **不移植**——禁令 10 + 本仓 `YoujingButton.ets:36-43` 已裁定过一次（0.4 把白字压到
 * 1.26:1，浅色档真机实测读不出文案）。这里禁用态换 `ColorTokens.muted` 字色 +
 * `Pressable.disabled`（内部 `.enabled(false)`），色板与可用性都由 token 说话。
 *
 * 现存消费方：0（屏11 分类、屏5 候选今天的胶囊都是各页自写；接管属 T2/T4）。
 */

import { ColorTokens } from '../design/ColorTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { TypeTokens } from '../design/TypeTokens';
import { Pressable } from './Pressable';

/**
 * 两档表面。有径侧 §8「语义色五个封闭」，字面量联合类型在本仓不用
 * （全仓零 `export type` 先例），按 YoujingButtonVariant 的既有写法收成 enum。
 */
export enum SoftChipTone {
  NEUTRAL = 'neutral',
  BRAND = 'brand'
}

@Component
export struct SoftChip {
  @Prop label: string = '';
  @Prop tone: SoftChipTone = SoftChipTone.NEUTRAL;
  /** 视觉高；命中带仍是 44（由 Pressable 的 touchTargetHeight 负责） */
  @Prop visualHeight: number = LayoutTokens.segmentedControlHeight;
  @Prop disabled: boolean = false;
  action: () => void = () => {
  };

  private bg(): ResourceColor {
    return this.tone === SoftChipTone.BRAND ? ColorTokens.primary : ColorTokens.surfaceSubtle;
  }

  /** 禁令 10：禁用态是换色，不是压透明度 */
  private fg(): ResourceColor {
    if (this.disabled) {
      return ColorTokens.muted;
    }
    return this.tone === SoftChipTone.BRAND ? ColorTokens.onPrimary : ColorTokens.primary;
  }

  private safeLabel(): string {
    return this.label ?? '';
  }

  /**
   * 描边宽度。名字**不能**叫 `borderWidth`：ArkTS 里 `CustomComponent` 已有同名成员
   * （通用属性 `CommonAttribute`），方法名撞它会报 10505001
   * 「Property 'borderWidth' ... is not assignable to the same property in base type」。
   */
  private edgeWidth(): number {
    // neutral 走发丝描边（契约「次按钮描边」border_subtle）；brand 实色不需要边
    return this.tone === SoftChipTone.NEUTRAL ? LayoutTokens.hairlineWidth : 0;
  }

  build() {
    Pressable({
      disabled: this.disabled,
      visualHeight: this.visualHeight,
      touchTargetHeight: LayoutTokens.minTouchTarget,
      action: this.action
    }) {
      Text(this.safeLabel())
        .fontSize(TypeTokens.caption.size)
        .fontWeight(TypeTokens.caption.weight)
        .fontFamily(TypeTokens.caption.family)
        .fontColor(this.fg())
        .textAlign(TextAlign.Center)
        .height(this.visualHeight)
        .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm })
        .backgroundColor(this.bg())
        .border({
          width: this.edgeWidth(),
          color: ColorTokens.borderSubtle,
          style: BorderStyle.Solid
        })
        .borderRadius(RadiusTokens.pill)
    }
  }
}
