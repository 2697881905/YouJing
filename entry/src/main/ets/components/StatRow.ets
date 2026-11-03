// 家族件：components.stat-number ｜ 对标有据：design/components/StatRow.ets:13-87 ｜ 状态：已落地未挂载 ｜ 契约锚点：3fcc3a62

/**
 * StatRow —— 概览统计行（N 列并排的「数字 + 标签」）。
 *
 * 契约两档逐字映射（DESIGN.md:624-630）：
 *   stat-number: textColor {colors.ink} / typography {typography.hierarchy.headline}
 *                / fontFeature "tnum"
 *   stat-label:  textColor {colors.muted} / typography {typography.hierarchy.caption}
 * 排版口径（简报 §1）：**每列 72vp、左对齐、无分隔线**——72 就是家族具名值
 * `LayoutTokens.profileStatWidth`（LayoutTokens.ets:97「家族契约沿用具名值」一条），
 * 今天全仓零消费方，本件是它的第一个落点（挂载时才算真接上）。
 * tnum 是硬要求（契约 §typography「tnum for every numeral」)，漏了不会报错、
 * 只会让两列数字的冒号错开半格——`tools/audit_tnum.py` 钉这条。
 *
 * **与有据的形态分歧（必须写明，别读成「照搬」）**：有据那份 StatRow 是社交动作行
 * （点赞 + 评论数，props 为 `liked/likeCount/commentCount/showComment/compact/onLike`，
 * 还带 `CountRoll` 数字滚动与 `springBounce` 曲线）。有径**没有会话/点赞表面**，
 * 对应的真实表面是「概览三列」（行程数 / 花费 / 城市数这类统计），所以：
 * - props 语义按契约 stat-number/stat-label 设计（`items: StatItem[]`），不照搬点赞 API；
 * - 不移植 `CountRoll`（依赖契约 v2 未收的 successScale/springBounce 档，属 C4
 *   「无消费者不加」），也不移植 `Pressable`（这一行不是动作件）。
 * - 有据的 72vp 列宽概念在有径侧由 profileStatWidth 承载，档位同源、名字不同。
 *
 * 无分隔线这条不是漏做：契约 stat-number/stat-label 两档里没有任何线色，
 * 而家族今天正因为「12 处 6 种写法的线」要收成 Separator（见 `components/Separator.ets`
 * 文件头）——统计列之间再加线正好与那条决议相反。要加线得先改契约。
 *
 * 现存消费方：0（概览三列今天内联在页面里，接管属 T2/T4，逐屏复拍）。
 */

import { ColorTokens } from '../design/ColorTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { TypeTokens } from '../design/TypeTokens';

/** 一列 = 一个数 + 一个标签；`value` 由调用方格式化好（含单位/货币符），件内不做算术 */
export interface StatItem {
  key: string;
  value: string;
  label: string;
}

@Component
export struct StatRow {
  @Prop items: StatItem[] = [];

  build() {
    Row({ space: SpaceTokens.base }) {
      ForEach(this.items, (item: StatItem) => {
        Column({ space: SpaceTokens.xxs }) {
          Text(item.value)
            .fontSize(TypeTokens.headline.size)
            .fontWeight(TypeTokens.headline.weight)
            .fontFamily(TypeTokens.headline.family)
            .fontFeature("'tnum' on")
            .fontColor(ColorTokens.ink)
          Text(item.label)
            .fontSize(TypeTokens.caption.size)
            .fontWeight(TypeTokens.caption.weight)
            .fontFamily(TypeTokens.caption.family)
            .fontColor(ColorTokens.muted)
        }
        .width(LayoutTokens.profileStatWidth)
        .alignItems(HorizontalAlign.Start)
      }, (item: StatItem): string => item.key)
    }
    .alignItems(VerticalAlign.Top)
  }
}

