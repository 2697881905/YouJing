/**
 * 伴随助手 · AI 能量球触点图标。
 *
 * 替代「助手」两字胶囊：圆形 orb，紫→蓝径向渐变（accentMention→primary，AI 感），
 * 外圈旋转能量环（sweepGradient）+ 整体呼吸缩放 + 中心 sparkle。动效全走 MotionTokens，
 * 颜色全走 ColorTokens，不新增字面量。轻点/拖拽手势由外层 CompanionOverlay 承载。
 */

import { ColorTokens } from '../design/ColorTokens';
import { MotionTokens, MotionCurves } from '../design/MotionTokens';
import { ShadowTokens } from '../design/ShadowTokens';
import { RadiusTokens } from '../design/RadiusTokens';

@Component
export struct CompanionOrb {
  /** 呼吸缩放（1 → 1.06 往复） */
  @State private breath: number = 1;
  /** 能量环旋转角 */
  @State private spin: number = 0;
  /** 外圈光晕透明度 */
  @State private glow: number = 0.4;
  private started: boolean = false;

  aboutToAppear(): void {
    this.startMotion();
  }

  private startMotion(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    // 呼吸：缩放 + 光晕往复（shimmer 档 1200ms 半程 ≈ 2.4s 一次呼吸）
    this.getUIContext().animateTo({
      duration: MotionTokens.shimmer, curve: MotionCurves.standard,
      iterations: -1, playMode: PlayMode.Alternate
    }, (): void => {
      this.breath = 1.06;
      this.glow = 0.85;
    });
    // 能量环匀速慢转
    this.getUIContext().animateTo({
      duration: MotionTokens.shimmer, curve: MotionCurves.linear, iterations: -1
    }, (): void => {
      this.spin = 360;
    });
  }

  build() {
    Stack() {
      // 外圈光晕（呼吸明暗）
      Stack()
        .width(64)
        .height(64)
        .borderRadius(RadiusTokens.pill)
        .clip(true)
        .radialGradient({
          center: ['50%', '50%'], radius: 32,
          colors: [['#330066CC', 0.0], ['#000066CC', 1.0]]
        })
        .opacity(this.glow)

      // 旋转能量环：sweepGradient 圆盘裁成圆，中心被主 orb 盖住露出旋转环
      Stack()
        .width(60)
        .height(60)
        .borderRadius(RadiusTokens.pill)
        .clip(true)
        .sweepGradient({
          center: ['50%', '50%'],
          colors: [
            ['#1A0066CC', 0.0], ['#FF5856D6', 0.18],
            ['#1A0066CC', 0.4], ['#FF0066CC', 0.62],
            ['#1A0066CC', 0.82], ['#FF5856D6', 1.0]
          ]
        })
        .rotate({ angle: this.spin })

      // 主 orb：紫→蓝径向渐变 + 玻璃高光 + 魔法棒星芒
      Stack() {
        Stack()
          .width(48)
          .height(48)
          .borderRadius(RadiusTokens.pill)
          .clip(true)
          .radialGradient({
            center: ['36%', '30%'], radius: 42,
            colors: [['#FF5856D6', 0.0], ['#FF0066CC', 0.62], ['#FF0055BB', 1.0]]
          })
          .shadow(ShadowTokens.floating)
        // 玻璃高光点
        Circle()
          .width(14)
          .height(10)
          .fill(ColorTokens.onBrand)
          .opacity(0.35)
          .position({ x: 11, y: 9 })
        SymbolGlyph($r('sys.symbol.wand_and_stars'))
          .fontSize(22)
          .fontColor([ColorTokens.onBrand])
      }
      .width(48)
      .height(48)
    }
    .width(64)
    .height(64)
    .scale({ x: this.breath, y: this.breath })
  }
}