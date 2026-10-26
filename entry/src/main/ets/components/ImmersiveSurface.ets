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
 *
 * 与有据的一处**有意差异**（别照抄回去）：有据 TagNav 那层在流光生效时把表面换成
 * `backgroundBlurStyle` + 透明底（悬浮条要透背）。有径的玻璃点位由底稿锁死在四处
 * （顶栏/分段控件/浮动 dock/吸顶日标题），内容卡不在其列，所以被包层的表面**保持实色**，
 * 只让流光走边。新增点位要先改 handoff 的玻璃点位表，不要在这里就地加模糊。
 */

import { HdsSceneController, HdsSceneType, HdsVisualComponent } from '@kit.UIDesignKit';
import { isImmersiveLightSenseSupported } from '../utils/immersiveMaterial';

/**
 * 浅色档的流光配色。默认那几档是从有据带过来的深色值（白 77% + 紫蓝 56%），
 * 压在白卡上会在两个上角结成一坨品红（真机浅色拍到过）——浅色底要收力度并换成品牌蓝。
 *
 * 色值说明（HDS scene 参数只吃 ResourceColor 字符串，$r 引用不进这里，
 * 故这八件无法进 color.json 被 audit_colors.py 机核；全部从 DESIGN.md 契约色派生，
 * 变更须与契约对照后手动登记）：
 * - LIGHT_* 四件 = primary #0066CC 的 4%/8%/50% 与 star-night-badge #4D9FFF 的 40%；
 * - maskColors / edgeColor 深色档 = 白与 primary 的契约内 alpha 档；
 * - edgeColor2 深色档 2026-10-25 由 #8F5FA8FF 改为 #664D9FFF：#5FA8FF 不在契约任何色表
 *   （§0.1「表外色相即缺陷」），#4D9FFF 是契约 star-night-badge 同色相。
 */
const LIGHT_MASK_TOP: string = '#0A0066CC';
const LIGHT_MASK_BOTTOM: string = '#140066CC';
const LIGHT_EDGE_1: string = '#800066CC';
const LIGHT_EDGE_2: string = '#664D9FFF';

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
  @Prop edgeColor2: ResourceColor = '#664D9FFF';
  /** 弹性布局（layoutWeight 拉伸）下测量不可靠时显式给真实宽高，避免流光按未拉伸尺寸绘制 */
  @Prop explicitWidth: number = 0;
  @Prop explicitHeight: number = 0;
  // 与其余组件一致：默认浅色，StorageProp 就位后按真主题重设 scene
  @StorageProp('isDarkMode') @Watch('applyScene') isDark: boolean = false;
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

  /** 场景参数要能跟着深浅档重设：只在 aboutToAppear 设一次的话，运行中切系统主题就留旧配色 */
  applyScene(): void {
    if (!isImmersiveLightSenseSupported()) {
      return;
    }
    const mask: Array<ResourceColor> = this.isDark ? this.maskColors : [LIGHT_MASK_TOP, LIGHT_MASK_BOTTOM];
    const e1: ResourceColor = this.isDark ? this.edgeColor : LIGHT_EDGE_1;
    const e2: ResourceColor = this.isDark ? this.edgeColor2 : LIGHT_EDGE_2;
    this.getSceneController().setSceneParams({
      backgroundMaskColors: mask,
      firstEdgeFlowLight: { startPos: 0, endPos: 0.5, color: e1 },
      secondEdgeFlowLight: { startPos: 0, endPos: -0.5, color: e2 }
    });
  }

  aboutToAppear(): void {
    this.applyScene();
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
    // 容器自己也要按表面几何裁切：只 clip 流光层不够，实测屏15 的边光会画到
    // 卡片上沿之外、悬在页面黑底上（真机 23:18 实拍）。流光层的圆角半径与
    // 内容卡不一致时（hero 28 vs card 20）偏差就露出来，所以外层再兜一道
    .borderRadius(this.radius)
    .clip(true)
    .onAreaChange((oldValue: Area, newValue: Area): void => {
      // Length 可能是 number/string/Resource：只认 number，其余按 0 让流光层不画
      const w: number = typeof newValue.width === 'number' ? newValue.width : 0;
      const h: number = typeof newValue.height === 'number' ? newValue.height : 0;
      if (w > 0 && h > 0 && (w !== this.glowWidth || h !== this.glowHeight)) {
        this.glowWidth = w;
        this.glowHeight = h;
      }
    })
  }
}
