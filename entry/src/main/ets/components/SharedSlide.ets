/**
 * 共享滑块 · 2026-11-08 按有据 `design/motion/SharedSlide.ets` 移植（逐字同构，只换 token 名）。
 *
 * 消费方：低 SDK 降级分支的 `BottomTabBar`（悬浮玻璃药丸里的选中指示块）。
 * API 23+ 走官方 HdsTabs，选中态由 `Index.dockSelectionPill` 的玻璃珠负责，与这里互斥。
 *
 * 三条不能改的地方（有据真机踩出来的）：
 * ① 跟手分支必须用 duration 可控的线性曲线：springMotion 是物理弹簧，时长由 response
 *    与初速度决定、忽略 duration，逐帧喂入会变成弹簧逐帧追赶，滑块滞后于手指；
 * ② 尺寸/圆角声明必须放在 `.animation()` **之后**：显式动画吃掉的是它之前声明的可动画属性，
 *    宽度入域那一帧会把滑块弹成小圆块；
 * ③ 容器宽度只接受「有效且确有变化」的值（0 / 抖动值会把滑块算成 0）。
 */

import { ColorTokens } from '../design/ColorTokens';
import { MotionCurves, MotionTokens } from '../design/MotionTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { ShadowTokens } from '../design/ShadowTokens';
import { SpaceTokens } from '../design/SpaceTokens';

/** 分段栏基准高（有据 LayoutTokens.segmentedHeight 同值）；调用方一般显式传 controlHeight */
const DEFAULT_CONTROL_HEIGHT: number = 36;

@Component
export struct SharedSlide {
  @Prop selectedIndex: number = 0;
  @Prop itemCount: number = 1;
  @Prop controlHeight: number = DEFAULT_CONTROL_HEIGHT;
  @Prop inset: number = SpaceTokens.xs;
  @Prop itemWidth: number = 0;
  @Prop radius: number = RadiusTokens.capsule;
  @Prop fill: ResourceColor = ColorTokens.surfaceElevated;
  /** 滑块投影：默认极轻接触阴影；需要更柔和的悬浮投影时由调用方传入 */
  @Prop slideShadow: ShadowOptions = ShadowTokens.cardContact;
  /** 按压态：滑块缩小的弹性形变，松手后 spring 回弹 */
  @Prop pressed: boolean = false;
  @State containerWidth: number = 0;

  private safeCount(): number {
    return Math.max(1, this.itemCount);
  }

  private slotWidth(): number {
    return Math.max(0, (this.containerWidth - this.inset * 2) / this.safeCount());
  }

  private pillWidth(): number {
    const slot: number = this.slotWidth();
    return this.itemWidth > 0 ? Math.min(this.itemWidth, slot) : slot;
  }

  private selectedOffset(): number {
    const safeIndex: number = Math.max(0, Math.min(this.safeCount() - 1, this.selectedIndex));
    return safeIndex * this.slotWidth() + (this.slotWidth() - this.pillWidth()) / 2;
  }

  // 逐帧跟手：浮点索引（滑动/吸附过程中的连续位置）不做补间，逐帧即时贴合手势；
  // 整数索引（点击切换）保留弹性动画（springInteract 过冲回弹）
  private isTracking(): boolean {
    return Math.abs(this.selectedIndex - Math.round(this.selectedIndex)) > 0.001;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .position({ x: this.inset, y: this.inset })
        .translate({ x: this.selectedOffset() })
        .backgroundColor(this.fill)
        .shadow(this.slideShadow)
        // 按下滑块轻微缩小，松手 spring 过冲回弹
        .scale({
          x: this.pressed ? MotionTokens.pressSlideScale : 1,
          y: this.pressed ? MotionTokens.pressSlideScale : 1
        })
        // 跟手分支必须用 duration 可控的线性曲线（springMotion 是物理弹簧，忽略 duration）
        .animation({
          duration: this.isTracking() ? MotionTokens.none : MotionTokens.base,
          curve: this.isTracking() ? Curve.Linear : MotionCurves.springInteract
        })
        // ⚠ 尺寸/圆角声明在 animation 之后：显式动画吃掉的是它之前声明的可动画属性
        .width(this.pillWidth())
        .height(Math.max(0, this.controlHeight - this.inset * 2))
        .borderRadius(this.radius)
    }
    .width('100%')
    .height(this.controlHeight)
    .hitTestBehavior(HitTestMode.BLOCK_DESCENDANTS)
    .onAreaChange((_old: Area, next: Area): void => {
      // 只接受有效且确有变化的宽度：0/抖动值会把滑块宽度算成 0，再被上面的动画补间出来
      const w: number = next.width as number;
      if (w > 0 && Math.abs(w - this.containerWidth) > 0.5) {
        this.containerWidth = w;
      }
    })
  }
}
