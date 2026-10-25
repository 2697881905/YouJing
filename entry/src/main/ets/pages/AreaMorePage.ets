/**
 * 屏5b 全部区域（屏5「查看更多区域」的落点）。
 *
 * 屏5 只摊三片候选，但内置区域库每城 36 片——原来那行「查看更多区域」是纯文字死控件。
 * 这页按 Area.group 真字段分组浏览（核心地段 / 商圈便利 / 交通枢纽），
 * 搜索命中名称、锚定站名与途经线路；「选这片」带 Area 出栈，屏5 把它插成首位候选。
 *
 * 三列数字与屏5 同口径：只取库里真有的字段（到机场 / 到火车站 / 餐饮密度），
 * 不编「到首个景点」「日均通勤」「房源数」——本项目没有路径规划与住宿库存。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { PlanRepository } from '../data/PlanRepository';
import { Area, AreaGroup, AreaPriceTier } from '../model/Area';
import { Logger } from '../common/logger/Logger';
import { KEY_CURRENT_BREAKPOINT } from '../utils/breakpointCenter';
import { listLanesForBreakpoint } from '../utils/responsive';
import { common } from '@kit.AbilityKit';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';

const GROUP_ORDER: AreaGroup[] = [AreaGroup.CORE, AreaGroup.COMMERCIAL, AreaGroup.METRO];

@Component
export struct AreaMorePage {
  /** 断点（唯一来源 utils/breakpointCenter.ets）：宽屏下列表并成多栏，不再被整屏拉宽 */
  @StorageProp(KEY_CURRENT_BREAKPOINT) bp: string = 'sm';

  private pathStack: NavPathStack = APP_NAV;
  @Prop city: string = '';
  @State private areas: Area[] = [];
  @State private keyword: string = '';
  @State private loading: boolean = true;

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    // 与屏5 同一取数口：京都演示城也要能走 mock 路由，不直连 DAO
    PlanRepository.loadAreas(ctx, this.city).then((rows: Area[]) => {
      this.areas = rows;
      this.loading = false;
    }).catch((err: Error) => {
      this.loading = false;
      Logger.error('Ui.AreaMore', `区域加载失败: ${err.message}`);
    });
  }

  private groupLabel(group: AreaGroup): string {
    if (group === AreaGroup.CORE) {
      return '核心地段';
    }
    return group === AreaGroup.COMMERCIAL ? '商圈便利' : '交通枢纽';
  }

  private tierLabel(tier: AreaPriceTier): string {
    if (tier === AreaPriceTier.ECONOMY) {
      return '经济档';
    }
    return tier === AreaPriceTier.LUXURY ? '豪华档' : '舒适档';
  }

  private visible(): Area[] {
    const k: string = this.keyword.trim();
    if (k.length === 0) {
      return this.areas;
    }
    return this.areas.filter((a: Area): boolean =>
      a.name.includes(k) || a.anchorStations.some((s: string): boolean => s.includes(k)) ||
      a.metroLines.some((s: string): boolean => s.includes(k)));
  }

  private inGroup(group: AreaGroup): Area[] {
    return this.visible().filter((a: Area): boolean => a.group === group);
  }

  @Builder
  groupHeader(label: string) {
    Text(label)
      .fontSize(TypeTokens.overline.size)
      .fontWeight(600)
      .fontColor(ColorTokens.muted)
      .width('100%')
      .padding({ top: SpaceTokens.md, bottom: SpaceTokens.xs })
  }

  @Builder
  areaRow(a: Area) {
    Row({ space: SpaceTokens.md }) {
      Column() {
        Text(a.name)
          .fontSize(TypeTokens.body.size)
          .fontWeight(600)
          .fontColor(ColorTokens.ink)
        Text(`${this.tierLabel(a.priceTier)} · 地铁 ${a.metroLines.join('/')} · 锚定 ${a.anchorStations.join('/')}`)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`到机场 ${a.airportMinutes} 分钟 · 到火车站 ${a.trainStationMinutes} 分钟 · 餐饮${a.diningDensity}密度`)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.body)
          .fontFeature("'tnum' on")
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 选这片：44vp 最小命中区 + button 档字号（16/600），不用 32vp 小热区
      Button('选这片')
        .fontSize(TypeTokens.body.size)
        .fontWeight(600)
        .height(LayoutTokens.minTouchTarget)
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })
        .type(ButtonType.Capsule)
        .buttonStyle(ButtonStyleMode.NORMAL)
        .onClick((): void => {
          this.pathStack.pop(a);
        })
    }
    .alignItems(VerticalAlign.Center)
    .width('100%')
    .padding(SpaceTokens.lg)
    .borderRadius(RadiusTokens.card)
    .backgroundColor(ColorTokens.surfaceElevated)
  }

  build() {
    HdsNavDestination() {
      Column() {
        Search({ value: this.keyword, placeholder: '搜索区域、站点或地铁线' })
          .onChange((v: string): void => {
            this.keyword = v;
          })
          .margin({ left: SpaceTokens.lg, right: SpaceTokens.lg, top: SpaceTokens.sm })

        if (this.loading) {
          Column({ space: SpaceTokens.md }) {
            LoadingProgress()
              .width(IconSizes.display)
              .height(IconSizes.display)
              .color(ColorTokens.primary)
            Text('读取区域库…')
              .fontSize(TypeTokens.small.size)
              .fontColor(ColorTokens.muted)
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.areas.length === 0) {
          // 空态（契约 empty-state 规格：48px 展示档图标 + title + callout + 一个主按钮）
          Column({ space: SpaceTokens.md }) {
            SymbolGlyph($r('sys.symbol.map'))
              .fontSize(IconSizes.display)
              .fontColor([ColorTokens.muted])
            Text('还没有这座城市的区域数据')
              .fontSize(TypeTokens.title.size)
              .fontWeight(700)
              .fontFamily(TypeTokens.title.family)
              .fontColor(ColorTokens.ink)
            Text('首批支持北京、上海、广州、深圳，换一座城市试试')
              .fontSize(TypeTokens.small.size)
              .fontColor(ColorTokens.muted)
              .textAlign(TextAlign.Center)
            YoujingButton({
              variant: YoujingButtonVariant.PRIMARY,
              label: '返回',
              buttonWidth: 160,
              onAction: (): void => {
                this.pathStack.pop();
              }
            })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })
        } else if (this.visible().length === 0) {
          Text(`没有匹配「${this.keyword}」的区域`)
            .fontSize(TypeTokens.small.size)
            .fontColor(ColorTokens.muted)
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: SpaceTokens.xl })
        } else {
          List({ space: SpaceTokens.xs }) {
            ForEach(GROUP_ORDER, (g: AreaGroup) => {
              if (this.inGroup(g).length > 0) {
                ListItemGroup({ header: this.groupHeader(this.groupLabel(g)) }) {
                  ForEach(this.inGroup(g), (a: Area) => {
                    ListItem() {
                      this.areaRow(a)
                    }
                  }, (a: Area): string => `areamore-${a.id}`)
                }
              }
            }, (g: AreaGroup): string => `areamore-group-${g}`)
          }
          .lanes(listLanesForBreakpoint(this.bp))
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .sticky(StickyStyle.Header)
          .cachedCount(6)
          .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(ColorTokens.canvas)
    }
    .titleBar(HdsChrome.bar({
      mainTitle: '全部区域',
      subTitle: this.areas.length > 0 ? `${this.city} · ${this.areas.length} 片` : this.city
    }))
    .titleMode(HdsNavDestinationTitleMode.MINI)
  }
}
