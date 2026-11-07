// 家族件：components.tag-pill ｜ 对标有据：design/components/SoftChip.ets:19-76 ｜ 2026-11-07 全量对齐

/**
 * SoftChip —— 小型实色动作胶囊（「重试 / 加一块」这类）。
 *
 * 2026-11-07 按有据源码全量对齐：
 * - 三档 neutral / brand / **danger**（YU SoftChip.ets:16 的第三档；danger = dangerTint 底 + danger 字）。
 *   danger_tint 已在 resources/{base,dark}/element/color.json 成对新增，契约 ledger 同步。
 * - 禁用态改为 `.opacity(this.disabled ? 0.45 : 1)`（YU SoftChip.ets:73）；
 *   此前「禁用换 muted 字色、不用 opacity」的禁令已废止。
 * - 组合方式照搬有据：外壳是 `Pressable`，按下反馈只有一处实现。
 * - 间距：纵向 xxs(4)、横向 xs(8)（10 离表，按 handoff §7 并到本阶梯）。
 */

import { ColorTokens } from '../design/ColorTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { TypeTokens } from '../design/TypeTokens';
import { Pressable } from './Pressable';

export enum SoftChipTone {
  NEUTRAL = 'neutral',
  BRAND = 'brand',
  DANGER = 'danger'
}

@Component
export struct SoftChip {
  @Prop label: string = '';
  @Prop tone: SoftChipTone = SoftChipTone.NEUTRAL;
  /** 视觉高；命中带仍是 44（由 Pressable 的 touchTargetHeight 负责） */
  @Prop visualHeight: number = LayoutTokens.segmentedHeight;
  @Prop disabled: boolean = false;
  action: () => void = () => {
  };

  private bg(): ResourceColor {
    if (this.tone === SoftChipTone.BRAND) {
      return ColorTokens.brandSolid;
    }
    if (this.tone === SoftChipTone.DANGER) {
      return ColorTokens.dangerTint;
    }
    return ColorTokens.surfaceSubtle;
  }

  private fg(): ResourceColor {
    if (this.tone === SoftChipTone.BRAND) {
      return ColorTokens.onBrand;
    }
    if (this.tone === SoftChipTone.DANGER) {
      return ColorTokens.danger;
    }
    return ColorTokens.primary;
  }

  private safeLabel(): string {
    return this.label ?? '';
  }

  /**
   * 描边宽度。名字不能叫 `borderWidth`：ArkTS 里 `CustomComponent` 已有同名成员，
   * 撞它会报 10505001。
   */
  private edgeWidth(): number {
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
        .padding({ left: SpaceTokens.xs, right: SpaceTokens.xs })
        .backgroundColor(this.bg())
        .border({
          width: this.edgeWidth(),
          color: ColorTokens.borderSubtle,
          style: BorderStyle.Solid
        })
        .borderRadius(RadiusTokens.pill)
        .opacity(this.disabled ? 0.45 : 1)
    }
  }
}
