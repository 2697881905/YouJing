// 家族件：components.separator ｜ 对标有据：无同名件（契约 DESIGN.md:379-380；家族件按契约直建） ｜ 状态：已落地未挂载 ｜ 契约锚点：3fcc3a62

/**
 * Separator —— 家族唯一的分隔线件。
 *
 * 为什么要有这一件（命名理由，简报 §1 要求写在文件头）：有径现存 12 处分隔线是
 * **6 种写法 / 3 种线色**并存——
 *   ① `Divider()`（官方件，走自己的 color/strokeWidth 语义）
 *   ② `.divider({ strokeWidth, color })`（List 的列表线参数，如 ExpensePage.ets:857）
 *   ③ `Row()/Column()` 铺 `ColorTokens.hairline`
 *   ④ 铺 `ColorTokens.separator`
 *   ⑤ 铺 `ColorTokens.borderSubtle`（本意是「次按钮描边」，被借去当线色）
 *   ⑥ `.border({ width: 0.5, color: … })` 单边描边
 * 三种线色里只有 `separator` 是契约 `components.separator` 认的色（契约另一行只给
 * `height: {layout.hairline-width}`）。件收成一个之后，「这条线该多粗、什么色」
 * 在仓库里只剩一处答案；改线色时不再需要跨 12 个点找。
 *
 * 实现按简报 §1 的**唯一实现**：`height(LayoutTokens.hairlineWidth)` +
 * `backgroundColor(ColorTokens.separator)`，不加圆角、不加margin、不给线色档位——
 * 一有多种 props 就又会长成「各自版本的线」。
 *
 * 两处刻意选择，都记在报告里：
 * 1. **不用官方 `Divider()`**：契约给 separator 的是「一个高 0.5 的面」，`Divider`
 *    另有 direction/strokeWidth/color 三套语义，值等价但口径不同；本件按契约面实现。
 *    若 T2 挂载时改判为官方 Divider，需与契约锚点同批改（官方件优先是硬规矩，
 *    但这条属「契约已定形」的那一类，不在此轮单方面换）。
 * 2. **载体用 `Stack()` 而不是 `Column()/Row()`**：tools/audit_layout_patterns.py 的 R2
 *    把「只有尺寸+底色、无子节点」的空 `Column()/Row()` 判成永不填充的死占位（本轮
 *    未被 §4 授权改那把尺的 R2_WHITELIST，而骨架线/分隔线正是那条规则要豁免的形状）。
 *    `Stack()` 是同类容器、渲染等价，且不落进 R2 的 Component 名单，语义不损失。
 *    T2 若要把它写进白名单（有据那条路），必须同批改尺并写明理由。
 */

import { ColorTokens } from '../design/ColorTokens';
import { LayoutTokens } from '../design/LayoutTokens';

@Component
export struct Separator {
  build() {
    Stack()
      .width('100%')
      .height(LayoutTokens.hairlineWidth)
      .backgroundColor(ColorTokens.separator)
  }
}

