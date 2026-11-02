// 家族件：components.skeleton ｜ 对标有据：design/motion/Skeleton.ets:7-50 ｜ 状态：已落地未挂载 ｜ 契约锚点：3fcc3a62

/**
 * Skeleton —— 骨架屏流光条（家族唯一实现方式，简报 §1 写死）。
 *
 * 契约 `components.skeleton`（DESIGN.md:391-395）四行：
 *   backgroundColor {colors.skeleton-base} / highlightColor {colors.skeleton-highlight}
 *   / rounded {rounded.md} / shimmerDuration {motion.shimmer}
 * 四行分别落在这里：外层 `backgroundColor(ColorTokens.skeletonBase)`
 * 、流光带中点 `ColorTokens.skeletonHighlight`
 * 、`radius` 默认 `RadiusTokens.reason`（有径 rounded.md 的具名档，与
 *   GeneratingPage.ets:136-143 现写骨架同一档）
 * 、`MotionTokens.shimmer`（1200ms，批次一 C4 五档之一）。
 *
 * 唯一实现方式（不许长成第二种）：
 *   `linearGradient(base→highlight→base)` + `.translate({x: travel})`
 *   + `.animation({duration, curve, iterations:-1})`；
 *   `travel` 初值 = **负高亮宽**（带子整条藏进左边界外），`onAppear` 置为
 *   `measuredWidth + 高亮宽`（跑到右边界外），`onAreaChange` 采样真实宽。
 *   外层 Stack 只负责圆角与 `.clip(true)`——流光必须被裁在骨架体内。
 * 不用 `.transition()`、不用 `keyframeAnimateTo`、不写裸毫秒：曲线必须是
 * `MotionCurves.linear`（循环流光不能有缓动，否则每圈都「呼吸」），
 * 时长必须走 token，否则 tools/audit_motion.py [裸时长] 报红。
 *
 * 深浅两档**不需要任何门控**：`skeleton_base` / `skeleton_highlight` 是
 * base/dark 成对资源（各 52 件同名同位），ColorMode 一翻自动换色——
 * 这正是简报 §0.3 要「成对资源」而不是显式 alpha 的原因。
 *
 * 载体用 `Stack()` 而不是 `Column()`：tools/audit_layout_patterns.py 的 R2 把
 * 「只有尺寸+底色、无子节点」的空 Column/Row 判成死占位（本件是骨架，按契约
 * 就永不填内容；GeneratingPage 那条现写骨架走的是文件级白名单，本轮未授权改尺）。
 *
 * 现存消费方：0（屏6 生成中的骨架今天长在 GeneratingPage.ets:136-156 的局部
 * @Builder `skeletonBlock()/skeletonRow()` 里，接管属 T2/T4——那是一次像素变化，
 * 必须逐屏复拍）。
 */

import { ColorTokens } from '../design/ColorTokens';
import { MotionCurves, MotionTokens } from '../design/MotionTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';

/**
 * 流光带宽度（有据 LayoutTokens.skeletonHighlightWidth = 56，space.ets:30）。
 * 有径 LayoutTokens 本轮不在改动清单（简报 §4），且这两个数是**件内实现常量**
 * 而不是契约尺寸（契约 skeleton 四行里没有它们），所以落在件里。
 */
const SKELETON_HIGHLIGHT_WIDTH: number = 56;
/** onAreaChange 还没采样到真实宽时的兜底宽度（有据 space.ets:29 = 160） */
const SKELETON_DEFAULT_WIDTH: number = 160;

@Component
export struct Skeleton {
  /** 骨架条整体宽（默认铺满父容器；屏6 现写骨架用 160/56/52 三档定宽） */
  @Prop skeletonWidth: Length = '100%';
  /** 骨架条整体高：有据默认 SpaceTokens.base(16) → 有径同值档 SpaceTokens.lg(16) */
  @Prop skeletonHeight: number = SpaceTokens.lg;
  /** 圆角档：契约 skeleton rounded.md → 有径 RadiusTokens.reason */
  @Prop radius: number = RadiusTokens.reason;
  /** 流光带的位移；负值 = 整条藏在左边外，第一帧不会「闪一下再走」 */
  @State travel: number = -SKELETON_HIGHLIGHT_WIDTH;
  /** 实测宽度（onAreaChange 采样），决定流光要跑多远 */
  @State measuredWidth: number = SKELETON_DEFAULT_WIDTH;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 流光带：三段渐变，中点是 highlight，两端回到 base —— 接缝不可见才能无限循环
      Stack()
        .width(SKELETON_HIGHLIGHT_WIDTH)
        .height('100%')
        .linearGradient({
          angle: 90,
          colors: [
            [ColorTokens.skeletonBase, 0],
            [ColorTokens.skeletonHighlight, 0.5],
            [ColorTokens.skeletonBase, 1]
          ]
        })
        .translate({ x: this.travel })
        // iterations:-1 无限循环；曲线必须 linear（契约没有 shimmer 专用曲线，
        // linear 是「匀速位移」唯一正确解，见文件头）
        .animation({ duration: MotionTokens.shimmer, curve: MotionCurves.linear, iterations: -1 })
    }
    .width(this.skeletonWidth)
    .height(this.skeletonHeight)
    .backgroundColor(ColorTokens.skeletonBase)
    .borderRadius(this.radius)
    .clip(true)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.measuredWidth = newValue.width as number;
    })
    .onAppear(() => {
      // 起帧时 measuredWidth 已由 onAreaChange 采样到，位移终点 = 实体宽 + 带宽
      this.travel = this.measuredWidth + SKELETON_HIGHLIGHT_WIDTH;
    })
  }
}

