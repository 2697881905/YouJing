// 家族件：components.empty-state ｜ 对标有据：design/components/EmptyState.ets:9-75 ｜ 2026-11-07 全量对齐

/**
 * EmptyState —— 空态（图标 / 主句 / 解释 / 出口）。
 *
 * 2026-11-07 按有据源码全量对齐（YU/design/components/EmptyState.ets:28-74）：
 * - 图形档 `IconTokens.empty` = 44（此前 48/title21 的 C8 裁决已推翻），`.fillColor(icon)`。
 * - 主句 `headline 18/600` serif（字族取 `TypeTokens.title.family`，即 NotoSerifSC）。
 * - 解释句 `callout 14` + `body` 字色；出口 `brandSolid` 实底 + `onBrand` 字。
 * - `accessibilityGroup(true)` 让整组读成一个空态。
 * - 件上不铺底色（canvas 是宿主屏的表面，不是件的颜色）。
 *
 * 出口仍走 `YoujingButton`（它是官方 Button 外壳 + 有据 DesignButton 配方的唯一入口），
 * 保证「一屏只许一个实心主按钮」与官方按压态/深色色板。
 */

import { ColorTokens } from '../design/ColorTokens';
import { IconTokens } from '../design/LayoutTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { TypeTokens } from '../design/TypeTokens';
import { YoujingButton, YoujingButtonVariant } from './YoujingButton';

@Component
export struct EmptyState {
  /** 官方符号资源；调用方按屏换（地图空态 map、行程空态 calendar…） */
  @Prop icon: Resource = $r('sys.symbol.info_circle');
  /** 主句：一句话说清「这里现在什么都没有」 */
  @Prop title: string = '';
  /** 解释句：可空；说了就排第二行 */
  @Prop message: string = '';
  /** 出口按钮文案；空串 = 不出按钮 */
  @Prop actionLabel: string = '';
  onAction: () => void = () => {
  };

  private safeTitle(): string {
    return this.title ?? '';
  }

  private safeMessage(): string {
    return this.message ?? '';
  }

  private safeActionLabel(): string {
    return this.actionLabel ?? '';
  }

  build() {
    Column({ space: SpaceTokens.sm }) {
      SymbolGlyph(this.icon)
        .fontSize(IconTokens.empty)
        .fontColor([ColorTokens.icon])

      Text(this.safeTitle())
        .fontSize(TypeTokens.headline.size)
        .fontWeight(TypeTokens.headline.weight)
        .fontFamily(TypeTokens.title.family)
        .fontColor(ColorTokens.ink)
        .textAlign(TextAlign.Center)

      if (this.safeMessage().length > 0) {
        Text(this.safeMessage())
          .fontSize(TypeTokens.callout.size)
          .fontWeight(TypeTokens.callout.weight)
          .fontFamily(TypeTokens.callout.family)
          .fontColor(ColorTokens.body)
          .textAlign(TextAlign.Center)
      }

      if (this.safeActionLabel().length > 0) {
        YoujingButton({
          variant: YoujingButtonVariant.PRIMARY,
          label: this.safeActionLabel(),
          onAction: () => {
            this.onAction();
          }
        })
      }
    }
    .width('100%')
    .padding({ left: SpaceTokens.xl, right: SpaceTokens.xl })
    .alignItems(HorizontalAlign.Center)
    .accessibilityGroup(true)
  }
}
