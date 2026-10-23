/**
 * 沉浸光感表面容器（自「有据」线上定稿移植，2026-10-24）。
 *
 * 在子内容上方叠一层 HDS 双边流光（HdsVisualComponent +
 * DUAL_EDGE_FLOW_LIGHT_WITH_BACKGROUND_MASK），配合系统玻璃呈现 HarmonyOS 6 沉浸光感。
 *
 * 降级：只有 isImmersiveLightSenseSupported()（API≥23 且设备声明 HDS syscap）才渲染流光，
 * 模拟器/低版本自动跳过，视觉退回原玻璃/实色，绝不白屏。
 * HdsSceneController 与 new 都惰性放在门禁分支里（@since 22，低版本该类不存在，字段初始化即崩）。
 *
 * 用法：把原本挂在自绘面板上的玻璃/圆角/描边保持不变，外层包一层本容器即可。
 */

import { HdsSceneController, HdsSceneType, HdsVisualComponent } from '@kit.UIDesignKit';
import { isImmersiveLightSenseSupported } from '../utils/immersiveMaterial';

@Component
export struct ImmersiveSurface {
  @BuilderParam content: () => void = this.emptyContent;
  /** 流光层圆角：需与表面内容 borderRadius 一致，流光才贴边 */
  @Prop radius: number = 20;
  @Prop surfaceWidth: Length = 'auto';
  @Prop surfaceHeight: Length = 'auto';
  /** 背景蒙层色（渐变起止）：透明度宜克制（10%~14%），别盖过页面主色 */
  @Prop maskColors: Array<ResourceColor> = ['#1EFFFFFF', '#260066CC'];
  @Prop edgeColor: ResourceColor = '#C4FFFFFF';
  @Prop edgeColor2: ResourceColor = '#8F5FA8FF';
  /** 弹性布局（layoutWeight 拉伸）下测量不可靠时显式给真实宽高，避免流光按未拉伸尺寸绘制 */
  @Prop explicitWidth: number = 0;
  @Prop explicitHeight: number = 0;
  private sceneController: HdsSceneController | null = null;
  @State private glowWidth: number = 0;
  @State private glowHeight: number = 0;

  @Builder
  emptyContent(): void {
  }

  private glowW(): number {
    return this.explicitWidth > 0 ? this.explicitWidth : this.glowWidth;
  }

  private glowH(): number {
    return this.explicitHeight > 0 ? this.explicitHeight : this.glowHeight;
  }

  private getSceneController(): HdsSceneController {
    if (this.sceneController === null) {
      this.sceneController = new HdsSceneController();
    }
    return this.sceneController;
  }

  aboutToAppear(): void {
    if (isImmersiveLightSenseSupported()) {
      this.getSceneController().setSceneParams({
        backgroundMaskColors: this.maskColors,
        firstEdgeFlowLight: { startPos: 0, endPos: 0.5, color: this.edgeColor },
        secondEdgeFlowLight: { startPos: 0, endPos: -0.5, color: this.edgeColor2 }
      });
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        this.content()
      }

      // 流光层置于最上层：部分真机 backgroundBlurStyle 渲染成不透明面板，放底层会被完全遮住。
      // 尺寸只由 explicit/实测驱动，绝不写 100%（百分比在自动尺寸 Stack 里按父约束解析，
      // 对话框场景会撑满整屏）。触摸透传，不抢表面交互。
      if (isImmersiveLightSenseSupported() && this.glowW() > 0 && this.glowH() > 0) {
        HdsVisualComponent()
          .scene(HdsSceneType.DUAL_EDGE_FLOW_LIGHT_WITH_BACKGROUND_MASK, this.getSceneController())
          .width(this.glowW())
          .height(this.glowH())
          .borderRadius(this.radius)
          .clip(true)
          .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width(this.explicitWidth > 0 ? this.explicitWidth : this.surfaceWidth)
    .height(this.explicitHeight > 0 ? this.explicitHeight : this.surfaceHeight)
    .onAreaChange((oldValue: Area, newValue: Area): void => {
      const w: number = parseFloat(String(newValue.width));
      const h: number = parseFloat(String(newValue.height));
      if (w > 0 && h > 0 && (w !== this.glowWidth || h !== this.glowHeight)) {
        this.glowWidth = w;
        this.glowHeight = h;
      }
    })
  }
}
