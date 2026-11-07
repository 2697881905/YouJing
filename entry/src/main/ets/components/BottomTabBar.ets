/**
 * 低 SDK 降级分支的悬浮玻璃药丸底栏 · 2026-11-07 按有据 `design/components/BottomTabBar.ets` 形态移植。
 *
 * 用途：官方 `HdsTabs.barFloatingStyle` 自 API 23 起才有。`pages/Index.ets` 用
 * `isImmersiveLightSenseSupported()` 分流：API 23+ 走官方 HdsTabs，API 20–22 走内置 Tabs + 本件。
 * 本工程 compatibleSdkVersion = 26.0.0 ⇒ **当前设备不可达**，只作预留兼容分支，
 * 未做真机 A/B（差异表 P-09）。不要把它当现行 dock 去调几何。
 *
 * 三条避让：① 材质生效时自绘 border/shadow/blur 归零；② 内容区 systemMaterial 不渲染，
 * 一律 backgroundBlurStyle + 实色兜底；③ API 门禁只住 utils/immersiveMaterial.ets。
 */

import { ColorTokens } from '../design/ColorTokens';
import { IconTokens, LayoutTokens } from '../design/LayoutTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { ShadowTokens } from '../design/ShadowTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { TypeTokens } from '../design/TypeTokens';
import { GlassBlurStyle } from '../utils/immersiveMaterial';
import { GlassTokens } from './GlassTokens';

@Component
export struct BottomTabBar {
  @Prop items: string[] = [];
  @Prop selectedIndex: number = 0;
  onSelect?: (index: number) => void = undefined;

  private itemColor(selected: boolean): Resource {
    return selected ? ColorTokens.onBrand : ColorTokens.icon;
  }

  build() {
    Row({ space: SpaceTokens.xs }) {
      ForEach(this.items, (label: string, index: number) => {
        Column({ space: SpaceTokens.xxs }) {
          SymbolGlyph($r('sys.symbol.info_circle'))
            .fontSize(IconTokens.tabBar)
            .fontColor([this.itemColor(this.selectedIndex === index)])
          Text(label)
            .fontSize(TypeTokens.navLabel.size)
            .fontWeight(TypeTokens.navLabel.weight)
            .fontFamily(TypeTokens.navLabel.family)
            .fontColor(this.itemColor(this.selectedIndex === index))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .height(LayoutTokens.tabItemHeight)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          if (this.onSelect !== undefined) {
            this.onSelect(index);
          }
        })
      }, (label: string, index: number): string => `${label}-${index}`)
    }
    .width(LayoutTokens.floatingDockWidth)
    .padding({ left: SpaceTokens.xs, right: SpaceTokens.xs })
    .backgroundBlurStyle(GlassBlurStyle.Floating)
    .backgroundColor(GlassTokens.BAR_BG)
    .border({
      width: LayoutTokens.glassBorderWidth,
      color: ColorTokens.glassBarBorder,
      style: BorderStyle.Solid
    })
    .borderRadius(RadiusTokens.dock)
    .shadow(ShadowTokens.floating)
    .clip(true)
  }
}
