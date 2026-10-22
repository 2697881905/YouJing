/**
 * 官方分段栏（SegmentButton · tab 档）+ 沉浸光感系统材质。
 * 移植自有据线上定稿（handoff §9：官方默认表面、零自绘装饰）。
 *
 * 表面全部交回官方：选中面、文字颜色/字号/字重、圆角、内缩、投影一律不传，
 * 走官方默认（V1 tab 档这些字段 Default 均为 "auto"）。本文件不自绘任何表面层。
 *
 * 关键实测口径（有据真机）：
 * - ULTRA_THIN 轨道薄到几乎只透背板 → **overrideTrackMaterial 必须与 lightContent 同值**：
 *   轨道随身后内容转深时白标签才有对比，否则白字压白底。
 * - `selectedIndexes` 只接受整数数组，无连续/浮点索引入口 → 滑块不跟手逐帧位移，
 *   宿主把 Swiper onChange 落到 selectedIndex，切换动画由官方状态完成。
 * - options 是 @ObjectLink：只在 aboutToAppear 与影响样式的入参变化时重建，逐帧重建打断内部状态。
 */

import { ItemRestriction, SegmentButton, SegmentButtonOptions, SegmentButtonTextItem,
  TabSegmentButtonConstructionOptions, uiMaterial } from '@kit.ArkUI';
import { getSegmentImmersiveMaterial } from '../utils/immersiveMaterial';

/** 分段条目（label 直接用契约文案） */
export interface SegmentedItem {
  label: string;
}

@Component
export struct ImmersiveSegmentBar {
  @Prop items: SegmentedItem[] = [];
  @Link @Watch('syncIndexes') selectedIndex: number;
  // 每槽位宽度 vp：>0 时整栏按 items.length × 该值定宽（与按钮并排场景），0 = 撑满父容器
  @Prop itemWidth: number = 0;
  // 官方按内容自适应高（实测 ≈31.7vp），契约栏高 36 → 上下各补 (36-31.7)/2 ≈ 2.15；
  // 有据原值 9.5 对应其 40vp 参考栏高。有径按 segmentedControlHeight=36 传参，宿主可调。
  @Prop buttonVerticalPadding: number = 2.15;
  @Prop buttonHorizontalPadding: number = 8;
  // 浅色内容态：顶栏背板转深时标签切白（与 overrideTrackMaterial 必须同值）
  @Prop @Watch('rebuildOptions') lightContent: boolean = false;
  @Prop @Watch('rebuildOptions') overrideTrackMaterial: boolean = false;
  onSelect?: (index: number) => void = undefined;
  @State private barOptions: SegmentButtonOptions | undefined = undefined;
  @State private indexes: number[] = [0];

  aboutToAppear(): void {
    this.indexes = [this.selectedIndex];
    this.barOptions = this.buildOptions();
  }

  private syncIndexes(): void {
    this.indexes = [this.selectedIndex];
  }

  private rebuildOptions(): void {
    this.barOptions = this.buildOptions();
  }

  private buildOptions(): SegmentButtonOptions {
    const buttons: SegmentButtonTextItem[] = [];
    for (let i = 0; i < this.items.length; i++) {
      buttons.push({ text: this.items[i].label });
    }
    const opts: TabSegmentButtonConstructionOptions = {
      buttons: buttons as ItemRestriction<SegmentButtonTextItem>,
      buttonPadding: {
        top: this.buttonVerticalPadding,
        right: this.buttonHorizontalPadding,
        bottom: this.buttonVerticalPadding,
        left: this.buttonHorizontalPadding
      } as Padding
    };
    if (this.lightContent) {
      opts.fontColor = $r('app.color.on_dark_degraded');
      opts.selectedFontColor = $r('app.color.on_dark');
    }
    if (this.overrideTrackMaterial) {
      const material: uiMaterial.Material | undefined = getSegmentImmersiveMaterial();
      if (material !== undefined) {
        opts.backgroundSystemMaterial = material;
      }
    }
    return SegmentButtonOptions.tab(opts);
  }

  private barWidth(): Length {
    return this.itemWidth > 0 ? this.itemWidth * Math.max(1, this.items.length) : '100%';
  }

  build() {
    Row() {
      if (this.barOptions !== undefined) {
        SegmentButton({
          options: this.barOptions,
          selectedIndexes: $indexes,
          onItemClicked: (index: number): void => {
            if (this.selectedIndex !== index) {
              this.selectedIndex = index;
            }
            if (this.onSelect !== undefined) {
              this.onSelect(index);
            }
          }
        })
      }
    }
    .width(this.barWidth())
  }
}
