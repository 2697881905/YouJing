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

  build() {
    Row() {
      ForEach(ENTRIES, (item: DockEntry, idx: number) => {
        Column({ space: 2 }) {
          SymbolGlyph(item.symbol)
            .fontSize(IconSizes.control)
            .fontColor([idx === this.activeIndex ? ColorTokens.primary : ColorTokens.muted])
          Text(item.label)
            .fontSize(TypeTokens.overline.size)
            .fontWeight(idx === this.activeIndex ? 600 : 400)
            .fontColor(idx === this.activeIndex ? ColorTokens.primary : ColorTokens.muted)
        }
        .width(LayoutTokens.tabItemWidth)
        .height(LayoutTokens.tabItemHeight)
        .justifyContent(FlexAlign.Center)
        .onClick((): void => {
          this.go(idx);
        })
      }, (item: DockEntry): string => `dock-${item.label}-${this.activeIndex}`)
    }
    .width(LayoutTokens.floatingDockWidth)
    .height(LayoutTokens.tabBarHeight)
    .justifyContent(FlexAlign.SpaceEvenly)
    .borderRadius(RadiusTokens.dock)
    .attributeModifier(barMaterial(uiMaterial.ImmersiveStyle.THIN, true, this.glassOn && !this.isDark))
    .backgroundColor(this.glassOn && !this.isDark ? Color.Transparent : ColorTokens.surfaceElevated)
    .border({ width: 1, color: ColorTokens.borderSubtle, radius: RadiusTokens.dock })
    .shadow(this.glassOn && !this.isDark || this.isDark ? { radius: 0 } : ShadowTokens.floating)
    .margin({ bottom: LayoutTokens.floatingDockBottomMargin })
  }
}
