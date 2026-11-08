/**
 * 低 SDK 降级分支的悬浮玻璃药丸底栏 · 2026-11-08 按有据 `design/components/BottomTabBar.ets` 全量迁移。
 *
 * 用途：官方 `HdsTabs.barFloatingStyle` 自 API 23 起才有。`pages/Index.ets` 用
 * `isImmersiveLightSenseSupported()` 分流：API 23+ 走官方 HdsTabs，API 20–22 走内置 Tabs + 本件。
 * 本工程 compatibleSdkVersion = 26.0.0 ⇒ **当前设备不可达**，只作预留兼容分支，未做真机 A/B。
 *
 * 与上一版（70 行残缺移植）的差异，全部来自有据原件：
 * ① 选中指示块由 `SharedSlide` 承担（跟手/弹性/按压），不是裸色块；
 * ② 长按 180ms 进入「擦除」模式：按住横划实时预览选中的格，松手才切页（有据 dock 的核心手感）；
 * ③ 按压光斑：品牌蓝低透明径向光斑跟随手指，按压 0.55 / 擦除 0.92 两档不透明度；
 * ④ 整条栏按压缩放（x 0.994 / y 0.98）、未选中格 0.96 缩放，都由 `.animation()` 过渡；
 * ⑤ 图标改 `SymbolGlyph`（有径没有 nav_*.svg 资源，用户 2026-11-08 裁定保留系统符号）。
 *
 * 三条避让：① 材质生效时自绘 border/shadow/blur 归零；② 内容区 systemMaterial 不渲染，
 * 一律 backgroundBlurStyle + 实色兜底；③ API 门禁只住 utils/immersiveMaterial.ets。
 */

import { ColorTokens } from '../design/ColorTokens';
import { IconTokens, LayoutTokens } from '../design/LayoutTokens';
import { MotionCurves, MotionTokens } from '../design/MotionTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { ShadowTokens } from '../design/ShadowTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { TypeTokens } from '../design/TypeTokens';
import { GlassBlurStyle, isImmersiveLightSenseSupported } from '../utils/immersiveMaterial';
import { SharedSlide } from './SharedSlide';

/** 一格要渲染的东西。`key` 只用于 ForEach 复用，不参与布局 */
export interface BottomTabItem {
  key: string;
  title: string;
  /** 系统符号资源（有径全仓图标都是 SymbolGlyph，见文件头第 ⑤ 条） */
  symbol: Resource;
}

/** 按压光斑直径（有据 LayoutTokens.tabBarGlowSize 同值） */
const GLOW_SIZE: number = 180;
/** 长按多久进入「擦除」模式 */
const LONG_PRESS_MS: number = 180;
/** 擦除模式下手指移动多远才算真的在划 */
const MOVE_THRESHOLD: number = 6;
/** 擦除松手后抑制 click 的窗口，避免"划完又当成点了一下" */
const CLICK_SUPPRESS_MS: number = 250;
/** 栏体按压投影（有据原位硬编码值） */
const BAR_SHADOW_RADIUS: number = 18;
const BAR_SHADOW_OFFSET_Y: number = 8;

@Component
export struct BottomTabBar {
  @Prop items: BottomTabItem[] = [];
  @Link currentIndex: number;
  @Prop unreadCount: number = 0;
  /** 红点挂在第几格；-1 = 不挂（有径五格没有消息页，默认不挂） */
  @Prop badgeIndex: number = -1;
  onSelect?: (index: number) => void = undefined;

  @State scrubbing: boolean = false;
  @State glowX: number = 0;
  @State hoverIndex: number = -1;
  @State barPressed: boolean = false;
  @State barWidth: number = 0;
  private longPressTimer: number = 0;

  // 卸载时清掉在途的长按定时器：否则回调会在已销毁的组件上写状态
  aboutToDisappear(): void {
    if (this.longPressTimer !== 0) {
      clearTimeout(this.longPressTimer);
      this.longPressTimer = 0;
    }
  }

  private suppressClickUntil: number = 0;
  private pressArmed: boolean = false;
  private pressDownX: number = 0;

  private select(index: number): void {
    if (index < 0 || index >= this.items.length) {
      return;
    }
    if (this.onSelect !== undefined) {
      this.onSelect(index);
    } else if (this.currentIndex !== index) {
      this.currentIndex = index;
    }
  }

  private isActive(index: number): boolean {
    return this.scrubbing ? this.hoverIndex === index : this.currentIndex === index;
  }

  private selectedIndex(): number {
    return this.scrubbing && this.hoverIndex >= 0 ? this.hoverIndex : this.currentIndex;
  }

  private clampGlow(x: number): number {
    if (this.barWidth <= 0) {
      return x;
    }
    return Math.min(this.barWidth, Math.max(0, x));
  }

  private indexFromX(x: number): number {
    if (this.barWidth <= 0 || this.items.length === 0) {
      return this.currentIndex;
    }
    const w: number = this.barWidth / this.items.length;
    const idx: number = Math.floor(x / w);
    return Math.min(this.items.length - 1, Math.max(0, idx));
  }

  private onBarTouch(e: TouchEvent): void {
    if (e.type === TouchType.Down) {
      const t: TouchObject = e.touches[0];
      if (!t) {
        return;
      }
      const x: number = this.clampGlow(t.x);
      this.barPressed = true;
      this.pressArmed = false;
      this.scrubbing = false;
      this.hoverIndex = -1;
      this.pressDownX = x;
      this.glowX = x;
      if (this.longPressTimer !== 0) {
        clearTimeout(this.longPressTimer);
      }
      this.longPressTimer = setTimeout((): void => {
        this.pressArmed = true;
      }, LONG_PRESS_MS) as number;
    } else if (e.type === TouchType.Move) {
      const t: TouchObject = e.touches[0];
      if (!t) {
        return;
      }
      const x: number = this.clampGlow(t.x);
      this.glowX = x;
      if (this.pressArmed && !this.scrubbing && Math.abs(x - this.pressDownX) > MOVE_THRESHOLD) {
        this.scrubbing = true;
      }
      if (this.scrubbing) {
        this.hoverIndex = this.indexFromX(this.glowX);
      }
    } else {
      if (this.longPressTimer !== 0) {
        clearTimeout(this.longPressTimer);
        this.longPressTimer = 0;
      }
      if (this.scrubbing) {
        this.select(this.indexFromX(this.glowX));
        this.suppressClickUntil = Date.now() + CLICK_SUPPRESS_MS;
      }
      this.barPressed = false;
      this.pressArmed = false;
      this.scrubbing = false;
      this.hoverIndex = -1;
    }
  }

  @Builder
  tabIcon(item: BottomTabItem, index: number) {
    // 选中态：图标与文字同步品牌色；未选中态走常规图标色。
    // 有据这里用 Image + fillColor（SVG 内 fill="currentColor"）；有径没有对应 SVG，用系统符号。
    if (this.isActive(index)) {
      SymbolGlyph(item.symbol)
        .fontSize(IconTokens.tabBar)
        .fontColor([ColorTokens.primary])
        .scale({ x: 1.08, y: 1.08 })
    } else {
      SymbolGlyph(item.symbol)
        .fontSize(IconTokens.tabBar)
        .fontColor([ColorTokens.icon])
        .scale({ x: 1, y: 1 })
    }
  }

  @Builder
  tabInner(item: BottomTabItem, index: number): void {
    Column({ space: 3 }) {
      Column({ space: 3 }) {
        if (index === this.badgeIndex && this.unreadCount > 0) {
          Badge({
            count: this.unreadCount,
            position: BadgePosition.RightTop,
            style: { badgeColor: $r('app.color.danger'), color: ColorTokens.onPrimary, badgeSize: IconTokens.compact }
          }) {
            this.tabIcon(item, index)
          }
        } else {
          this.tabIcon(item, index)
        }
        Text(item.title)
          .fontSize(TypeTokens.navLabel.size)
          .fontFamily(TypeTokens.navLabel.family)
          .fontColor(this.isActive(index) ? ColorTokens.primary : ColorTokens.icon)
      }
      .width(LayoutTokens.tabItemWidth)
      .height(LayoutTokens.tabItemHeight)
      .justifyContent(FlexAlign.Center)
      .borderRadius(RadiusTokens.card)
      .backgroundColor(Color.Transparent)
      .scale({
        x: this.isActive(index) ? 1 : 0.96,
        y: this.isActive(index) ? 1 : 0.96
      })
      .animation({
        duration: MotionTokens.base,
        curve: MotionCurves.standard
      })
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick((): void => {
      if (Date.now() < this.suppressClickUntil) {
        return;
      }
      this.select(index);
    })
  }

  @Builder
  glowOverlay(): void {
    Column()
      .width(GLOW_SIZE)
      .height(LayoutTokens.tabBarHeight)
      .radialGradient({
        center: [GLOW_SIZE / 2, LayoutTokens.tabBarHeight / 2],
        radius: GLOW_SIZE / 2,
        colors: [
          [ColorTokens.primaryTint, 0.0],
          [ColorTokens.primaryTint, 0.35],
          [Color.Transparent, 1.0]
        ]
      })
      // 白底迁移：SCREEN 混合在纯白底上数学不可见（白+任何值=白），
      // 改 normal 混合 + 品牌蓝低透明光斑
      .position({ x: this.glowX - GLOW_SIZE / 2, y: 0 })
      .opacity(this.barPressed ? (this.scrubbing ? 0.92 : 0.55) : 0)
      .hitTestBehavior(HitTestMode.None)
      .animation({
        duration: MotionTokens.instant,
        curve: MotionCurves.standard
      })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Row() {
        SharedSlide({
          selectedIndex: this.selectedIndex(),
          itemCount: this.items.length,
          controlHeight: LayoutTokens.tabItemHeight,
          inset: 0,
          itemWidth: LayoutTokens.tabItemWidth,
          radius: RadiusTokens.card,
          // 选中项是一层轻薄的纸面高亮，保留背景内容的透光感
          fill: $r('app.color.glass_selection_surface')
        })
      }
      .width('100%')
      .height('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        ForEach(this.items, (item: BottomTabItem, index: number) => {
          this.tabInner(item, index);
        }, (item: BottomTabItem): string => item.key)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
      .alignItems(VerticalAlign.Center)

      this.glowOverlay()
    }
    .width('100%')
    .height(LayoutTokens.tabBarHeight)
    .borderRadius(RadiusTokens.dock)
    // 沉浸光感材质：真机由系统材质提供弹性反馈/点光源/流光；
    // 模拟器/低端机自动降级为系统 backgroundBlurStyle，仍保留通透玻璃感与文字可读性。
    .backgroundBlurStyle(GlassBlurStyle.Card)
    .backgroundColor(isImmersiveLightSenseSupported() ? Color.Transparent : ColorTokens.glassBarSurface)
    .border({
      width: LayoutTokens.glassBorderWidth,
      color: ColorTokens.glassBarBorder,
      style: BorderStyle.Solid
    })
    .shadow({ radius: BAR_SHADOW_RADIUS, color: ColorTokens.barShadow, offsetY: BAR_SHADOW_OFFSET_Y })
    .clip(true)
    .scale({
      x: this.barPressed ? 0.994 : 1,
      y: this.barPressed ? 0.98 : 1
    })
    .animation({
      duration: MotionTokens.fast,
      curve: MotionCurves.standard
    })
    .onAreaChange((_old: Area, area: Area): void => {
      this.barWidth = area.width as number;
    })
    .onTouch((e: TouchEvent): void => {
      this.onBarTouch(e);
    })
  }
}
