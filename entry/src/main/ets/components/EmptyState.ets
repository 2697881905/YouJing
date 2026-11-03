// 家族件：components.empty-state ｜ 对标有据：design/components/EmptyState.ets:9-75 ｜ 状态：已落地未挂载 ｜ 契约锚点：3fcc3a62

/**
 * EmptyState —— 空态（家族唯一排布：图标 / 主句 / 解释 / 出口）。
 *
 * 契约 `components.empty-state`（DESIGN.md:396-400）四行逐字映射：
 *   backgroundColor {colors.canvas}          → **件上不铺底**（见下面第 3 条）
 *   textColor {colors.muted}                 → 解释句 `ColorTokens.muted`
 *   typography {typography.hierarchy.callout} → 契约 callout = 14/400/20，有径同值档
 *                                              `TypeTokens.small`（简报 §1 就写「文案 small/14」）
 *   iconColor {colors.muted}                 → 图标 `ColorTokens.muted`（**采散文，见下方冲突留痕**）
 * 主句档位：契约散文 §1109「Empty state. Centered: … `title` line」+ §913 档位表
 * （`title` = serif 21/700/32）+ §937「hero empty-state line」归 serif ⇒ 标题走
 * **serif `TypeTokens.title`**，并按 §3.1 既有纪律同链带 `.fontFamily(TypeTokens.title.family)`
 * （ArkUI 的 fontFamily 不随字号档自动带上，漏写就还是黑体，`audit_fontfamily.py` [漏字族] 会咬）。
 *
 * **冲突留痕（评审 R28 裁定：契约散文赢）**：YAML `components.empty-state.iconColor`
 * 现为 `{colors.faint}`（DESIGN.md:400），与散文 DESIGN.md:1109 互斥——散文原文
 * 「`muted` `#69696E` icon at 48px … `faint` is barred here by §8：它在 canvas 上 2.67:1，
 * 连 3:1 图形底线都不过」。本轮按 R28 采散文落 `ColorTokens.muted`；
 * YAML 那一行的校正**随 T2 契约批同改**（本轮不动契约文件），届时删掉这段留痕。
 *
 * props 名逐字照搬有据：`icon / title / message / actionLabel / onAction`，
 * 三个字符串都过一层 `safe*()`——`@Prop` 从父级拿到 undefined 时
 * `.length` 会直接把整屏炸掉（有据同款防护，`EmptyState.ets:16-26`）。
 *
 * 三处有据 → 有径的口径差，都在文件头交代清楚：
 * 1. **图标尺寸**：有据 `IconTokens.empty` = 44（icon.ets:13）。有径 §8 禁令 7 把图标
 *    收成**封闭两档** 22/48（`IconSizes`），44 在 有径 不是合法图形档（44 是命中盒，
 *    不是图形）→ 取展示档 `IconSizes.display`（48），与 TripsPage.ets:430-432 现写空态同档。
 * 2. **图标资源**：有据默认 `$r('app.media.empty_search')`（自有位图）。有径 media/ 里
 *    只有 startIcon/background/foreground 四件，空态一律走**官方 SymbolGlyph**
 *    （`sys.symbol.*`），默认档取仓里已在用的 `info_circle`，不新造位图资源。
 * 3. **出口键**：有据在件内自绘 `Pressable + Row + Text + backgroundColor(brandSolid)`
 *    （`EmptyState.ets:54-67`）。有径侧实心主按钮的**唯一出口是官方 Button 的包**
 *    `YoujingButton`（`components/YoujingButton.ets:4` 那次「去自绘」就是这个道理：
 *    官方 stateEffect/深色色板自己管，手抄那份在深色下会偏）——**用官方件，不造自绘替代品**
 *    是用户硬规矩，所以这里直接引用 `YoujingButton`，件内不写第二颗按钮。
 *    禁令 1（一屏只许一个实心主按钮）由调用方负责：空态出口通常就是那一屏唯一的主按钮。
 * 4. **底色**：契约 `canvas` 是这一屏的**表面**而不是件的颜色。件铺满 100% canvas 的话，
 *    装进卡（surface-elevated）里就会多出一块色板边界——与 §1150 那类「材质上叠自绘层」
 *    同族的错法。铺底由宿主页负责，有据同样不铺（`EmptyState.ets:28-74` 无 backgroundColor）。
 *
 * 现存消费方：0。有径 13 个文件里今天各写各的空态（如 ExpensePage.ets:843-848、
 * TripsPage.ets:429-445），逐个接管属 T2/T4（每次接管都是像素变化，必须复拍）。
 */

import { ColorTokens } from '../design/ColorTokens';
import { IconSizes } from '../design/LayoutTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { TypeTokens } from '../design/TypeTokens';
import { YoujingButton, YoujingButtonVariant } from './YoujingButton';

@Component
export struct EmptyState {
  /** 官方符号资源；调用方按屏换（地图空态 map、行程空态 calendar…） */
  @Prop icon: Resource = $r('sys.symbol.info_circle');
  /** 主句：一句话说清「这里现在什么都没有」 */
  @Prop title: string = '';
  /** 解释句：可空；说了就排第二行（契约 callout→small / muted） */
  @Prop message: string = '';
  /** 出口按钮文案；空串 = 不出按钮（只读的屏没有出口） */
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
        .fontSize(IconSizes.display)
        .fontColor([ColorTokens.muted])

      Text(this.safeTitle())
        .fontSize(TypeTokens.title.size)
        .fontWeight(TypeTokens.title.weight)
        .fontFamily(TypeTokens.title.family)
        .fontColor(ColorTokens.ink)
        .textAlign(TextAlign.Center)

      if (this.safeMessage().length > 0) {
        Text(this.safeMessage())
          .fontSize(TypeTokens.small.size)
          .fontWeight(TypeTokens.small.weight)
          .fontFamily(TypeTokens.small.family)
          .fontColor(ColorTokens.muted)
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
    // 有据 SpaceTokens.lg = 24 → 有径同名值档 SpaceTokens.lg
    .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })
    .alignItems(HorizontalAlign.Center)
    // 整组读成一个「空态」而不是三段散装文字
    .accessibilityGroup(true)
  }
}

