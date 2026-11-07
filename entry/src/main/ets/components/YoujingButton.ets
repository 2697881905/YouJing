/**
 * 按钮适配层 · 2026-11-07 全量对齐「有据」组件体系。
 *
 * 组件实现已换到 `DesignButton`（有据 `design/components/DesignButton.ets` 配方：
 * 四变体 / callout 14 / brandSolid+onBrand / 禁用 opacity 0.45 / Pressable 按下反馈）。
 * 本文件只保留 55 个既有调用点的 props 名，避免逐屏改调用签名；业务语义零变化。
 * 不做 hover（有据源码 0 处 onHover/hoverEffect）。
 */

import { DesignButton, DesignButtonVariant } from './DesignButton';

export enum YoujingButtonVariant {
  PRIMARY = 'primary',
  SECONDARY = 'secondary',
  TEXT = 'text',
  GLASS = 'glass'
}

@Component
export struct YoujingButton {
  @Prop variant: YoujingButtonVariant = YoujingButtonVariant.PRIMARY;
  @Prop label: string = '';
  @Prop fullWidth: boolean = false;
  /** 非满宽时的按钮宽度（屏3 上一题/下一题 ≈150vp） */
  @Prop buttonWidth: Length = 150;
  @Prop leadingSymbol: Resource | undefined = undefined;
  @Prop trailingSymbol: Resource | undefined = undefined;
  @Prop disabled: boolean = false;
  onAction?: () => void = undefined;

  private toDesignVariant(): DesignButtonVariant {
    if (this.variant === YoujingButtonVariant.SECONDARY) {
      return DesignButtonVariant.OUTLINED;
    }
    if (this.variant === YoujingButtonVariant.TEXT) {
      return DesignButtonVariant.GHOST;
    }
    if (this.variant === YoujingButtonVariant.GLASS) {
      return DesignButtonVariant.GLASS;
    }
    return DesignButtonVariant.PRIMARY;
  }

  build() {
    DesignButton({
      label: this.label,
      variant: this.toDesignVariant(),
      disabled: this.disabled,
      fillWidth: this.fullWidth,
      visualWidth: this.buttonWidth,
      leadingSymbol: this.leadingSymbol,
      trailingSymbol: this.trailingSymbol,
      onAction: () => {
        if (this.onAction !== undefined) {
          this.onAction();
        }
      }
    })
  }
}
