// 家族件：components.option-chip-pressed ｜ 对标有据：design/motion/Pressable.ets:5-53 ｜ 状态：已落地未挂载 ｜ 契约锚点：3fcc3a62

/**
 * Pressable —— 家族唯一的「按下反馈」封装件（scale 档）。
 *
 * 契约锚点：`components.option-chip-pressed` = `scale {motion.press-scale}` +
 * `duration {motion.press}`（DESIGN.md:443-445），曲线走 `curve-standard`。
 * 公共 props 名逐字照搬有据（`content/disabled/fillWidth/fullResponseRegion/
 * visualHeight/touchTargetHeight/action`），有 T2/P2 迁移时由各页接管，本轮零消费方。
 *
 * 与 R21 / C4 的关系（简报 §3 明令，必须写在这里）：有径 `MotionTokens` 只收批次一拍定的
 * 五档（press/control/container/shimmer/pressScale），契约里的 `press-opacity 0.92`
 * 属 C4「无消费者不加」清单——所以 **pressed 档只用 scale**，不许为了「对标完整」把 0.92
 * 提前写成死档。真挂载（T2/P2）时 pressOpacity 与消费点同批补。这条与有据不同：
 * 有据 pressed 档另带 `.opacity(pressOpacity)`（`motion/Pressable.ets:39`）。
 * 同向的第二条理由：DESIGN §8 禁令 10「不许用 opacity 表达状态」——禁用态在这里走
 * `.enabled(false)`，不压透明度。
 *
 * 顺序是硬约束：`.animation()` 必须在 `.stateStyles()` **之前**（有据实测：写在它之后的
 * 属性不生效，等于「按下没反馈而代码看着没错」；tools/audit_motion.py 的 [顺序] 判据
 * 按「上一条属性」钉这条，`.stateStyles().animation()` 必红）。
 */

import { LayoutTokens } from '../design/LayoutTokens';
import { MotionCurves, MotionTokens } from '../design/MotionTokens';

@Component
export struct Pressable {
  /** 被包裹的内容（家族里所有动作件的统一入口） */
  @BuilderParam content: () => void = this.emptyContent;
  @Prop disabled: boolean = false;
  /** 满宽：父容器给 100%，用于钉底/通栏动作 */
  @Prop fillWidth: boolean = false;
  /** 响应区吃满整块视觉高度（默认只吃 touchTargetHeight 那条带） */
  @Prop fullResponseRegion: boolean = false;
  /** 视觉高度；>0 时用它算响应区的纵向偏移，让 44vp 命中带居中包住矮控件 */
  @Prop visualHeight: number = 0;
  @Prop touchTargetHeight: number = LayoutTokens.minTouchTarget;
  action: () => void = () => {
  };

  @Builder
  emptyContent(): void {
  }

  /** 视觉高度小于命中带时，命中带要往内缩到居中，否则触点偏上半屏 */
  private touchOffset(): number {
    return this.visualHeight > 0 ? (this.visualHeight - this.touchTargetHeight) / 2 : 0;
  }

  build() {
    Column() {
      this.content()
    }
    .width(this.fillWidth ? '100%' : 'auto')
    .responseRegion({
      x: 0,
      y: this.touchOffset(),
      width: '100%',
      height: this.fullResponseRegion ? '100%' : this.touchTargetHeight
    })
    // ↓ 必须紧贴下面的 .stateStyles()，见文件头「顺序是硬约束」
    .animation({ duration: MotionTokens.press, curve: MotionCurves.standard })
    .stateStyles({
      normal: {
        .scale({ x: 1, y: 1 })
      },
      pressed: {
        .scale({
          x: this.disabled ? 1 : MotionTokens.pressScale,
          y: this.disabled ? 1 : MotionTokens.pressScale
        })
      }
    })
    .enabled(!this.disabled)
    .onClick(() => {
      if (!this.disabled) {
        this.action();
      }
    })
  }
}
