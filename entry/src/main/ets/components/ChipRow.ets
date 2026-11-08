// 家族件：components.tag-pill ｜ 对标有据：design/components/ChipRow.ets:17-103 ｜ 2026-11-07 全量对齐

/**
 * ChipRow —— 横滚胶囊选择条（家族唯一实现，外壳照搬有据的 `Pressable` 组合方式）。
 *
 * 2026-11-07 按有据源码全量对齐（YU/design/components/ChipRow.ets:63-89）：
 * - 选中 = `brandSolid` 实心底 + `onBrand` 字；未选 = `sunken` 底 + `primary` 字。
 *   此前「primaryTint + 1px primary 描边」的 C6 裁决已推翻。
 * - 字档 `callout 14` / `headline.weight 600`（选中）；未选 `caption.weight`。
 * - 圆角 `RadiusTokens.capsule`(10) 方片，不是 pill —— 方片读作「待选择」，pill 读作「已选标签」。
 * - 视觉高 `segmentedHeight 36`，命中带 44 由 `Pressable.responseRegion` 负责。
 * - 图标档按有据 `IconTokens.compact`(16)。
 *
 * props 名照搬有据：`items / selectedIndex(@Link) / showIcon / sidePadding /
 * itemGap / chipHeight / onSelect`。
 */

import { ColorTokens } from '../design/ColorTokens';
import { IconTokens, LayoutTokens } from '../design/LayoutTokens';
import { MotionCurves, MotionTokens } from '../design/MotionTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { TypeTokens } from '../design/TypeTokens';
import { Pressable } from './Pressable';

export interface ChipItem {
  key: string;
  label: string;
  /** 可选的官方符号；不传就不画图标位（与 showIcon 两个条件同时成立才画） */
  symbol?: Resource;
}

@Component
export struct ChipRow {
  @Prop items: ChipItem[] = [];
  @Link selectedIndex: number;
  @Prop showIcon: boolean = false;
  /** 左右内缩：有据 pageCompact(16) → 有径 LayoutTokens.pagePadding(16) */
  @Prop sidePadding: number = LayoutTokens.pagePadding;
  /** 胶囊间隙：有据 item(12) → 有径 LayoutTokens.itemGap(12) */
  @Prop itemGap: number = LayoutTokens.itemGap;
  /** 视觉高（命中带另由 Pressable 给 44） */
  @Prop chipHeight: number = LayoutTokens.segmentedHeight;
  onSelect?: (index: number) => void = undefined;

  private select(index: number): void {
    if (index < 0 || index >= this.items.length) {
      return;
    }
    if (this.selectedIndex !== index) {
      this.selectedIndex = index;
    }
    if (this.onSelect !== undefined) {
      this.onSelect(index);
    }
  }

  private itemColor(selected: boolean): Resource {
    return selected ? ColorTokens.onBrand : ColorTokens.primary;
  }

  private itemSurface(selected: boolean): Resource {
    return selected ? ColorTokens.brandSolid : ColorTokens.surfaceSunken;
  }

  build() {
    Scroll() {
      Row({ space: this.itemGap }) {
        ForEach(this.items, (item: ChipItem, index: number) => {
          Pressable({
            visualHeight: this.chipHeight,
            touchTargetHeight: LayoutTokens.minTouchTarget,
            action: () => {
              this.select(index);
            }
          }) {
            Row({ space: SpaceTokens.xs }) {
              if (this.showIcon && item.symbol !== undefined) {
                SymbolGlyph(item.symbol)
                  .fontSize(IconTokens.compact)
                  .fontColor([this.itemColor(this.selectedIndex === index)])
              }
              Text(item.label)
                .fontSize(TypeTokens.callout.size)
                .fontWeight(this.selectedIndex === index
                  ? TypeTokens.headline.weight : TypeTokens.caption.weight)
                .fontFamily(TypeTokens.callout.family)
                .fontColor(this.itemColor(this.selectedIndex === index))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .height(this.chipHeight)
            .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm })
            .backgroundColor(this.itemSurface(this.selectedIndex === index))
            .borderRadius(RadiusTokens.capsule)
            .alignItems(VerticalAlign.Center)
            .animation({ duration: MotionTokens.fast, curve: MotionCurves.standard })
          }
        }, (item: ChipItem): string => item.key)
      }
      .padding({ left: this.sidePadding, right: this.sidePadding })
    }
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .width('100%')
    .height(this.chipHeight)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
  }
}
