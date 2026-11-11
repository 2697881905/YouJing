// 家族件：components.option-chip-pressed ｜ 对标有据：design/motion/Pressable.ets:5-53 ｜ 2026-11-07 全量对齐

/**
 * Pressable —— 家族唯一的「按下反馈」封装件。
 *
 * 2026-11-07 按有据源码全量对齐（YU/design/motion/Pressable.ets:32-45）：
 * - normal = `.opacity(1)` + `.scale(1,1)`；pressed = `.opacity(0.92)` + `.scale(0.97,0.97)`。
 *   此前「只用 scale、不许用 opacity 表达状态」的禁令已废止，pressOpacity 由 MotionTokens 单源给出。
 * - `.animation()` **必须紧贴 `.stateStyles()` 之前**（写在它之后属性不生效，
 *   tools/audit_motion.py 按「上一条属性」钉这条，`.stateStyles().animation()` 必红）。
 * - 禁用态仍走 `.enabled(!disabled)`，表面的 `.opacity(0.45)` 由 DesignButton / SoftChip 等
 *   具体控件自己承担（有据同款分工）。
 * - `responseRegion` 负责「看着 36、点着 44」：视觉高小于命中带时把 44vp 命中带居中包住矮控件。
 *
 * props 名逐字照搬有据：content/disabled/fillWidth/fullResponseRegion/
 * visualHeight/touchTargetHeight/action。
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
  /** 响应区吃满整块视觉高度（默认档已按视觉高度自动判断，见 build 里的 height 表达式） */
  @Prop fullResponseRegion: boolean = false;
  /** 视觉高度；>0 时用它算响应区的纵向偏移，让 44vp 命中带居中包住矮控件。
   *  不传 = 调用方是整卡/整行可点，响应区吃满自身高度（见下方 responseRegion 的注释）。 */
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
    // ⚠ 命中带必须跟着调用方走：传了 visualHeight（矮控件，如 36 高胶囊）才收成
    // 44vp 居中带；没传 visualHeight 的都是整卡/整行可点（行程卡、勋章行、候选项），
    // 这时还给 44vp 等于只剩卡片顶部一条能点——真机实测行程卡点标题/进度条全无反应，
    // 只有贴着卡片上沿 44vp 内才打开（2026-11-11 用户报「有时候点了没反应」）。
    .responseRegion({
      x: 0,
      y: this.touchOffset(),
      width: '100%',
      height: (this.fullResponseRegion || this.visualHeight <= 0) ? '100%' : this.touchTargetHeight
    })
    // ↓ 必须紧贴下面的 .stateStyles()，见文件头「顺序是硬约束」
    .animation({ duration: MotionTokens.press, curve: MotionCurves.standard })
    .stateStyles({
      normal: {
        .opacity(1)
        .scale({ x: 1, y: 1 })
      },
      pressed: {
        .opacity(this.disabled ? 1 : MotionTokens.pressOpacity)
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
