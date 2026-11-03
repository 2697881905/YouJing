// 家族件：components.tag-pill ｜ 对标有据：design/components/ChipRow.ets:17-103 ｜ 状态：已落地未挂载 ｜ 契约锚点：3fcc3a62

/**
 * ChipRow —— 横滚胶囊选择条（家族唯一实现，外壳照搬有据的 `Pressable` 组合方式）。
 *
 * 契约 `components.tag-pill`（DESIGN.md:615-619）在本件里的落点：
 *   选中态 = `primaryTint` 底 + `primary` 字（契约那两行），
 *   未选中 = `surfaceSubtle` 底 + `body` 字（契约没给未选中档，取 TripsPage.ets:229-230
 *   现写标签的家族语言，不新造第三块底），
 *   `typography caption` / `rounded.pill` 两行逐字落。
 *
 * props 名照搬有据：`items / selectedIndex(@Link) / showIcon / sidePadding /
 * itemGap / chipHeight / onSelect`。有据侧另有的两档本轮**不移植**，理由写在这里：
 * - `glass`：有径 §1062/§1156 把书面 blur 只许在三处栏面（顶栏 / dock / 吸顶日标题），
 *   胶囊**不是玻璃面**；照抄那一档就是往 §1150 的「材质上叠自绘层」那条错法里走，
 *   `tools/audit_material.py` 也会盯着自绘背景/描边。真要做玻璃胶囊得先改契约。
 * - `compact`：有据的 compact 是「透明底 + 1px 分隔线 + pill」的紧凑标签档
 *   （`ChipRow.ets:82-87`）。有径今天没有第二种胶囊形态要落，按 C4「无消费者不加」
 *   等真出现再开档，不在本轮先立一个零消费方的形态。
 *
 * 图标：有径没有 `TagIcon` 那层名字映射（自家 `utils/` 里也没有 ACTION_ICONS），
 * 直接把 `symbol?: Resource` 放进 `ChipItem`——官方 `SymbolGlyph` 直收资源，
 * 尺寸走封闭两档 `IconSizes.control`（§8 禁令 7：图标只有 22/48，有据的 16 档不移植）。
 *
 * 触控：视觉高 36（`LayoutTokens.segmentedControlHeight`，有据 segmentedHeight 同值），
 * 命中带 44（`LayoutTokens.minTouchTarget`）由 `Pressable.responseRegion` 负责——
 * 「看着 36、点着 44」是家族件的一条硬口径，页面里再写 `.height(36).onClick` 就漏了命中带。
 *
 * 现存消费方：0（屏11 分类、屏5 候选的胶囊今天各页自写；接管属 T2/T4，逐屏复拍）。
 */

import { ColorTokens } from '../design/ColorTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
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
  @Prop chipHeight: number = LayoutTokens.segmentedControlHeight;
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
            Row({ space: SpaceTokens.xxs }) {
              if (this.showIcon && item.symbol !== undefined) {
                SymbolGlyph(item.symbol)
                  .fontSize(IconSizes.control)
                  .fontColor([this.selectedIndex === index
                    ? ColorTokens.primary : ColorTokens.icon])
              }
              Text(item.label)
                .fontSize(TypeTokens.caption.size)
                .fontWeight(this.selectedIndex === index
                  ? TypeTokens.headline.weight : TypeTokens.caption.weight)
                .fontFamily(TypeTokens.caption.family)
                .fontColor(this.selectedIndex === index
                  ? ColorTokens.primary : ColorTokens.body)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .height(this.chipHeight)
            .padding({ left: SpaceTokens.xs, right: SpaceTokens.xs })
            .backgroundColor(this.selectedIndex === index
              ? ColorTokens.primaryTint : ColorTokens.surfaceSubtle)
            .borderRadius(RadiusTokens.pill)
            .alignItems(VerticalAlign.Center)
            // 选中态换色是控件级过渡（契约 motion.control 220ms），
            // 曲线走契约 curve-standard；.animation() 在这条链的末位，不接 .stateStyles()
            .animation({ duration: MotionTokens.control, curve: MotionCurves.standard })
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

