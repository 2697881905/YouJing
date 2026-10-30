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
 * - options 只在 aboutToAppear 与影响样式的入参变化时重建，逐帧重建打断内部状态。
 *   items 也在这个集合里（异步加载后条目数会从占位变成真值），所以宿主必须传 @State
 *   数组字段而不是 build 里的行内字面量——后者每次渲染都是新引用，等于逐帧重建。
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
  @Prop @Watch('rebuildOptions') items: SegmentedItem[] = [];
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
  /**
   * 深色档：契约 segmented-control.selectedItemSurface 是 dark-glass-selection-surface
   * `rgba(46,46,50,0.2)`，但这一档色值此前没进 color.json，选中面就落回官方 tab 默认——
   * 真机实测是一块浅灰药丸（#E5E5E5）配官方白字，几乎读不出（深色档逐屏走查查出）。
   * 这里只传官方 SegmentButtonOptions 的 selectedBackgroundColor 字段，不自绘表面层。
   */
  @StorageProp('isDarkMode') @Watch('rebuildOptions') isDark: boolean = false;
  /**
   * 无障碍组标签（帧的 aria-label 口径，如屏11「支出维度切换」）。
   * 非空时整条栏合成一个朗读元素，并把当前选中项一起念出来——
   * 官方 SegmentButton 的条目是 options 里的纯文本，没有逐条 accessibilityText 入口。
   */
  @Prop a11yLabel: string = '';
  onSelect?: (index: number) => void = undefined;
  @State private barOptions: SegmentButtonOptions | undefined = undefined;
  @State private indexes: number[] = [0];

  private a11yText(): string {
    if (this.a11yLabel.length === 0 || this.items.length === 0) {
      return '';
    }
    const idx: number = Math.min(Math.max(0, this.selectedIndex), this.items.length - 1);
    return `${this.a11yLabel}，当前 ${this.items[idx].label}`;
  }

  aboutToAppear(): void {
    this.indexes = [this.selectedIndex];
    this.barOptions = this.buildOptions();
  }

  private syncIndexes(): void {
    this.indexes = [this.selectedIndex];
  }

  private rebuildOptions(): void {
    this.barOptions = this.buildOptions();
    if (this.selectedIndex >= this.items.length) {
      // 条目变少（异步加载后从占位换成真值）时把越界索引收回来，@Link 回写会带动 indexes
      this.selectedIndex = 0;
    } else {
      this.indexes = [this.selectedIndex];
    }
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
    if (this.isDark && !this.lightContent) {
      opts.selectedBackgroundColor = $r('app.color.glass_selection_surface');
      // 深色档下光靠选中底色读不出选中态：glass_selection_surface 是 20% 不透明度
      // （#332E2E32），叠在 surface_elevated #1E1E1E 上实测只到 ≈#212124，差 3 级。
      // 所以这里补上文字级的选中区分（选中亮白、未选走降级白），
      // 不改任何 token 值——抬 alpha 属动设计定稿，留给用户定。
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
      // 只有一项时不渲染官方控件：它会在首帧改内部 buttonBorderRadius，
      // 触发「state changed during render」中断整棵子树（屏8 单日行程实测空白）
      if (this.barOptions !== undefined && this.items.length > 1) {
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
    .accessibilityGroup(this.a11yLabel.length > 0)
    .accessibilityText(this.a11yText())
  }
}
