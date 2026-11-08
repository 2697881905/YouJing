// 家族件：components.skeleton ｜ 对标有据：design/motion/Skeleton.ets:7-50 ｜ 状态：已落地未挂载 ｜ 契约锚点：3fcc3a62

/**
 * Skeleton —— 静态骨架条。
 *
 * 2026-11-09 按用户决定撤掉流光：原实现是 `linearGradient(base→highlight→base)`
 * + `.translate()` + `iterations:-1` 的循环扫光，视觉土味，整层已删。
 * 现在只保留契约 `components.skeleton` 的底色 / 圆角 / 尺寸三行：
 *   backgroundColor {colors.skeleton-base}、rounded {rounded.md}、镜像真实行高。
 * 不再引用 MotionTokens / MotionCurves，也不叠任何渐变或位移动画。
 *
 * 载体用 `Stack()` 而不是 `Column()`：tools/audit_layout_patterns.py 的 R2 把
 * 「只有尺寸+底色、无子节点」的空 Column/Row 判成死占位，Stack 不在判据内。
 *
 * 消费方：ohosTest/FamilyProbePage（编译图 emit 探针）。
 * 屏6 生成中的骨架仍是 GeneratingPage.ets 的局部 @Builder，本来就是静态灰块。
 */

import { ColorTokens } from '../design/ColorTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';

@Component
export struct Skeleton {
  /** 骨架条整体宽（默认铺满父容器） */
  @Prop skeletonWidth: Length = '100%';
  /** 骨架条整体高：契约 skeleton 行高 → SpaceTokens.base(16) */
  @Prop skeletonHeight: number = SpaceTokens.base;
  /** 圆角档：契约 skeleton rounded.md → RadiusTokens.reason */
  @Prop radius: number = RadiusTokens.reason;

  build() {
    Stack()
      .width(this.skeletonWidth)
      .height(this.skeletonHeight)
      .backgroundColor(ColorTokens.skeletonBase)
      .borderRadius(this.radius)
  }
}
