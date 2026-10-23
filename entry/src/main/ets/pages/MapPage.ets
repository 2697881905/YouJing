/**
 * dock「地图」落点页（底稿 dock 四项之一，39 帧里没有对应地图帧，v1 按现有设计语言出）。
 *
 * 与屏8 的分工：屏8 面板只看当天，这一页看全程——所以顶部给了「全程 / Day N」切换，
 * 底部给站点条。全程视图按天分段连线（跨天不连，见 MapStops.runs）。
 * 底图铺满、浮层透明穿透（hitTestBehavior Transparent），不遮地图手势。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { TripDao } from '../data/TripDao';
import { Trip, TripDay } from '../model/Trip';
import { MapStop, MapStops } from '../utils/MapStops';
import { TripMapView } from '../components/TripMapView';
import { FloatingDock } from '../components/FloatingDock';
import { Logger } from '../common/logger/Logger';
import { common } from '@kit.AbilityKit';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { ShadowTokens } from '../design/ShadowTokens';
import { barMaterial, isSystemMaterialActive } from '../utils/immersiveMaterial';
import { uiMaterial } from '@kit.ArkUI';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import type { HdsNavigationMenuItemOptions, HdsNavigationTitleBarOptions } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';

const ALL_DAYS: number = -1;

@Component
export struct MapPage {
  private pathStack: NavPathStack = APP_NAV;
  @Prop tripId: string = '';
  @StorageProp('isDarkMode') isDark: boolean = false;
  @State private days: TripDay[] = [];
  /** -1 = 全程 */
  @State private daySel: number = ALL_DAYS;
  @State private stops: MapStop[] = [];
  @State private signature: string = '';
  @State private request: string = '';
  @State private titleText: string = '地图';
  @State private loaded: boolean = false;
  private seq: number = 0;
  private glassOn: boolean = isSystemMaterialActive();

  /** 编辑页/屏8 返回后要吃到回写的库数据，统一挂 onShown（首帧也会触发） */
  /** 官方标题栏：行程名 + 副标题步数，「全览」走 content.menu 圆钮 */
  private titleBarOptions(): HdsNavigationTitleBarOptions {
    const items: Array<HdsNavigationMenuItemOptions> = [HdsChrome.item(
      $r('sys.symbol.arrow_2_circlepath'), '全览', (): void => {
        this.fitAll();
      })];
    const sub: string = this.stops.length > 0 ? `${this.stops.length} 站` : '';
    return HdsChrome.bar({ mainTitle: this.titleText, subTitle: sub, menu: items });
  }

  private reload(): void {    if (this.tripId.length === 0) {
      this.loaded = true;
      return;
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    TripDao.loadTrip(ctx, this.tripId).then((trip: Trip | null) => {
      this.loaded = true;
      if (trip === null) {
        return;
      }
      this.days = trip.days;
      const nights: number = trip.days.length - 1;
      this.titleText = `${trip.destination} · ${trip.days.length}天${nights}晚`;
      this.applySel(this.daySel);
    }).catch((err: Error) => {
      this.loaded = true;
      Logger.error('Ui.MapPage', `加载行程失败: ${err.message}`);
    });
  }

  private applySel(sel: number): void {
    this.daySel = sel;
    const next: MapStop[] = sel === ALL_DAYS ? MapStops.fromDays(this.days) :
      (this.days.length > 0 ? MapStops.fromDay(this.days[Math.min(sel, this.days.length - 1)]) : []);
    this.stops = next;
    this.signature = MapStops.signature(next);
    this.fitAll();
  }

  private fitAll(): void {
    this.seq += 1;
    this.request = `fit:${this.seq}`;
  }

  private chips(): string[] {
    const out: string[] = ['全程'];
    for (const d of this.days) {
      out.push(`Day ${d.dayIndex}`);
    }
    return out;
  }

  private focusStop(index: number): void {
    this.seq += 1;
    this.request = `focus:${index}:${this.seq}`;
  }

  @Builder
  chipRow(label: string, idx: number) {
    Button(label)
      .fontSize(TypeTokens.caption.size)
      .fontWeight(idx === this.daySel + 1 ? 600 : 450)
      .height(32)
      .type(ButtonType.Capsule)
      .buttonStyle(idx === this.daySel + 1 ? ButtonStyleMode.EMPHASIZED : ButtonStyleMode.NORMAL)
      .margin({ right: SpaceTokens.sm })
      .onClick((): void => {
        this.applySel(idx === 0 ? ALL_DAYS : idx - 1);
      })
  }

  @Builder
  stopChip(stop: MapStop) {
    Button() {
      Column({ space: 2 }) {
        Row({ space: SpaceTokens.xs }) {
          Text(`${stop.index}`)
            .fontSize(TypeTokens.overline.size)
            .fontWeight(600)
            .fontColor(ColorTokens.primary)
          Text(stop.subtitle)
            .fontSize(TypeTokens.overline.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
            .fontFeature("'tnum' on")
        }
        Text(stop.title)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(500)
          .fontColor(ColorTokens.ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
    }
    .width(132)
    .height(56)
    .padding({ left: SpaceTokens.md, right: SpaceTokens.md })
    .type(ButtonType.Normal)
    .borderRadius(RadiusTokens.capsule)
    .buttonStyle(ButtonStyleMode.NORMAL)
    .margin({ right: SpaceTokens.sm })
    .onClick((): void => {
      this.focusStop(stop.index);
    })
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        if (this.stops.length > 0) {
          TripMapView({
            stops: this.stops,
            signature: this.signature,
            request: this.request,
            onStopClick: (index: number): void => {
              this.focusStop(index);
            }
          })
            .width('100%')
            .height('100%')
        }

        Column() {
          if (this.days.length > 0) {
            Scroll() {
              Row() {
                ForEach(this.chips(), (label: string, idx: number) => {
                  this.chipRow(label, idx)
                }, (label: string): string => `mapchip-${label}-${this.daySel}`)
              }
              .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
          }

          Blank()

          if (this.stops.length > 0) {
            Column() {
              Scroll() {
                Row() {
                  ForEach(this.stops, (stop: MapStop) => {
                    this.stopChip(stop)
                  }, (stop: MapStop): string => `mapstop-${this.signature}-${stop.index}`)
                }
                .padding({ left: SpaceTokens.md, right: SpaceTokens.md })
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')
              .height(64)
            }
            .width('100%')
            .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
            .borderRadius({ topLeft: RadiusTokens.hero, topRight: RadiusTokens.hero })
            .attributeModifier(barMaterial(uiMaterial.ImmersiveStyle.THIN, true, this.glassOn && !this.isDark))
            .backgroundColor(this.glassOn && !this.isDark ? Color.Transparent : ColorTokens.surfaceElevated)
            .border({ width: 1, color: ColorTokens.borderSubtle })
            .shadow(this.glassOn && !this.isDark || this.isDark ? { radius: 0 } : ShadowTokens.floating)
          } else if (this.loaded) {
            Text(this.tripId.length === 0 ? '先从「我的行程」选一条行程' : '这条行程里没有可显示的坐标')
              .fontSize(TypeTokens.caption.size)
              .fontColor(ColorTokens.muted)
              .height(36)
              .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })
              .borderRadius(RadiusTokens.pill)
              .backgroundColor(ColorTokens.surfaceElevated)
          }

          Row() {
            FloatingDock({ activeIndex: 1, tripId: this.tripId })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.stops.length > 0 ? Color.Transparent : ColorTokens.canvas)
    }
    .titleBar(this.titleBarOptions())
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .onShown((): void => {
      this.reload();
    })
  }
}
