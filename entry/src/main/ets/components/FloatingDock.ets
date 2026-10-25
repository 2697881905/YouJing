/**
 * 浮动 dock（底稿 dock-item 四件套：行程 / 地图 / 费用 / 我的）。
 * 帧归属按底稿实测：屏8 与屏15 高亮「行程」、屏11 高亮「费用」、屏12 高亮「我的」；
 * 其余帧没有 dock，不要往别的页面上贴。
 *
 * 材质与屏8 早前定案一致：浅色挂系统材质（底部悬浮 THIN，带投影）并撤自绘背景与阴影，
 * 深色近黑底上模糊≈透明会让滚动内容穿透，回退实色 + 1px 描边（深色零阴影契约不变）。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { ShadowTokens } from '../design/ShadowTokens';
import { barMaterial, isSystemMaterialActive } from '../utils/immersiveMaterial';
import { uiMaterial } from '@kit.ArkUI';

interface DockEntry {
  symbol: Resource;
  label: string;
}

const ENTRIES: DockEntry[] = [
  { symbol: $r('sys.symbol.calendar'), label: '行程' },
  { symbol: $r('sys.symbol.map'), label: '地图' },
  { symbol: $r('sys.symbol.wallet'), label: '费用' },
  { symbol: $r('sys.symbol.person'), label: '我的' }
];

@Component
export struct FloatingDock {
  private pathStack: NavPathStack = APP_NAV;
  @StorageProp('isDarkMode') isDark: boolean = false;
  /** 当前页对应的 tab，点自己不跳 */
  @Prop activeIndex: number = 0;
  /** 行程/费用两页需要 tripId 才能直达；为空时退回到列表页 */
  @Prop tripId: string = '';
  private glassOn: boolean = isSystemMaterialActive();

  private go(index: number): void {
    if (index === this.activeIndex) {
      return;
    }
    if (index === 0) {
      // 行程：栈里已有 Itinerary 就退回去，避免同一 tab 叠两层
      if (this.tripId.length > 0 && this.pathStack.popToName('Itinerary') < 0) {
        this.pathStack.pushPath({ name: 'Itinerary', param: this.tripId });
      } else if (this.tripId.length === 0) {
        this.pathStack.pushPath({ name: 'Trips' });
      }
      return;
    }
    if (index === 1) {
      // 地图页要有行程才有动线可画，没有就直接回列表，不给一张空底图
      if (this.tripId.length === 0) {
        this.pathStack.replacePath({ name: 'Trips' });
      } else {
        this.pathStack.replacePath({ name: 'Map', param: this.tripId });
      }
      return;
    }
    if (index === 2) {
      this.pathStack.replacePath({ name: 'Expense', param: this.tripId });
      return;
    }
    this.pathStack.replacePath({ name: 'Trips' });
  }

  /**
   * 底稿 dock-glow（屏8/11/12/15 及其 dark 共 10 帧声明）：一团品牌蓝径向光，
   * 只跟在选中项后面。三档色停（tint 0 → tint 0.35 → 同色相 alpha 0）沿用有据
   * BottomTabBar.glowOverlay 的写法；外缘用 alpha 0 但保留蓝相，避免渐变往灰里褪。
   * 帧自身两档尺寸不一致（按格 68×56 vs 氛围大光 180×180 / 140×140），
   * 这里取按格档并限制在本格热区内，大光等待设计方定点（任务 #28）。
   */
  @Builder
  glowLayer() {
    Column()
      .width(LayoutTokens.tabItemWidth)
      .height(LayoutTokens.tabItemHeight)
      .radialGradient({
        center: [LayoutTokens.tabItemWidth / 2, LayoutTokens.tabItemHeight / 2],
        radius: LayoutTokens.tabItemWidth / 2,
        colors: [
          [ColorTokens.primaryTint, 0.0],
          [ColorTokens.primaryTint, 0.35],
          [ColorTokens.primaryGlowEdge, 1.0]
        ]
      })
      .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Row() {
      ForEach(ENTRIES, (item: DockEntry, idx: number) => {
        // 官方 Button（TEXTUAL 档）承载 tab 项：按压态、焦点与无障碍由系统给，
        // 原来是裸 Column + onClick，既没有按压反馈也不是可聚焦控件。
        Button() {
          Stack() {
            if (idx === this.activeIndex) {
              this.glowLayer()
            }
            Column() {
              SymbolGlyph(item.symbol)
                .fontSize(IconSizes.control)
                .fontColor([idx === this.activeIndex ? ColorTokens.primary : ColorTokens.muted])
              Text(item.label)
                .fontSize(TypeTokens.navLabel.size)
                .fontWeight(idx === this.activeIndex ? 500 : TypeTokens.navLabel.weight)
                .lineHeight(TypeTokens.navLabel.lineHeight)
                .fontColor(idx === this.activeIndex ? ColorTokens.primary : ColorTokens.muted)
            }
          }
        }
        .type(ButtonType.Circle)
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .width(LayoutTokens.tabItemWidth)
        .height(LayoutTokens.tabItemHeight)
        .onClick((): void => {
          this.go(idx);
        })
      }, (item: DockEntry): string => `dock-${item.label}`)
    }
    .width(LayoutTokens.floatingDockWidth)
    .height(LayoutTokens.tabBarHeight)
    .justifyContent(FlexAlign.SpaceEvenly)
    .borderRadius(RadiusTokens.dock)
    .attributeModifier(barMaterial(uiMaterial.ImmersiveStyle.THIN, true, this.glassOn && !this.isDark))
    .backgroundColor(this.glassOn && !this.isDark ? Color.Transparent : ColorTokens.surfaceElevated)
    // 材质生效时描边也要撤（DESIGN Elevation：background/border/shadow 三项一起 zero out），
    // 否则系统材质外沿再套一道自绘线 = 双环
    .border({
      width: this.glassOn && !this.isDark ? 0 : LayoutTokens.glassBorderWidth,
      color: ColorTokens.borderSubtle,
      radius: RadiusTokens.dock
    })
    .shadow(this.glassOn && !this.isDark || this.isDark ? { radius: 0 } : ShadowTokens.floating)
    .margin({ bottom: LayoutTokens.floatingDockBottomMargin })
  }
}
