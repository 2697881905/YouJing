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

import { HOST_NAV } from '../common/constants/AppNav';
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
import { HdsNavDestination, HdsNavDestinationTitleMode, HideMode } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';
import { isMapArea } from '../utils/MapCityMapper';
import { isMapCity, seedCityListText } from '../common/constants/Cities';
import { requestSystemBarRefresh } from '../utils/systemBar';

const GROUP_ORDER: AreaGroup[] = [AreaGroup.CORE, AreaGroup.COMMERCIAL, AreaGroup.METRO];

@Component
export struct AreaMorePage {
  // 深浅档代 tick：翻档时 EntryAbility 自增，@StorageProp 变化带动本页 build 重跑，
  // 把新 tick 传进 HdsChrome.bar → 标题内容换新 ComponentContent 重挂载、按当前档重解色
  // （官方 HdsTitleBar 自绘内容不随配置切换重渲染，真机实证见 HdsChrome.themeTick）
  @StorageProp('chromeThemeTick') chromeThemeTick: number = 0;

  /** 断点（唯一来源 utils/breakpointCenter.ets）：宽屏下列表并成多栏，不再被整屏拉宽 */
  @StorageProp(KEY_CURRENT_BREAKPOINT) bp: string = 'sm';

  // 二级页全屏化（2026-11-11）：本页固定落宿主栈，pop 才弹得回
  private pathStack: NavPathStack = HOST_NAV;
  @Prop city: string = '';
  @State private areas: Area[] = [];
  @State private keyword: string = '';
  @State private loading: boolean = true;
  @State private loadFailed: boolean = false;
  private mapCity: boolean = false;
  /** 顶栏磨砂两态：由**绝对**滚动偏移驱动（每帧增量会被松手回弹的负帧打灭，契约 §Translucency） */
  @State private barScrolled: boolean = false;
  private barScroller: Scroller = new Scroller();
  // 穿底让位（含状态栏）：这一屏搜索行钉在 List 之外，所以让位加在外层 Column
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.mapCity = isMapCity(this.city);
    // 与屏5 同一取数口：京都演示城也要能走 mock 路由，不直连 DAO
    PlanRepository.loadAreas(ctx, this.city).then((rows: Area[]) => {
      this.areas = rows;
      this.loading = false;
    }).catch((err: Error) => {
      this.loading = false;
      this.loadFailed = true;
      Logger.error('Ui.AreaMore', `区域加载失败: ${err.message}`);
    });
  }

  private groupLabel(group: AreaGroup): string {
    if (this.mapCity) {
      return '地图服务区县';
    }
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
    // 吸顶组头没有底板就会与滚过来的行字压字（SpotPickPage 同族）；带高照有据钉成一条，
    // 不靠 padding 凑（PublishTagPanel.ets:83-86 `height(segmentedHeight)` + alignItems Center）。
    Row() {
      Text(label)
        .fontSize(TypeTokens.overline.size)
        .fontWeight(600)
        .fontColor(ColorTokens.muted)
    }
    .width('100%')
    .height(LayoutTokens.stickyHeaderHeight)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(ColorTokens.canvas)
  }

  @Builder
  areaRow(a: Area) {
    Row({ space: SpaceTokens.sm }) {
      Column() {
        Text(a.name)
          .fontSize(TypeTokens.body.size)
          .fontWeight(600)
          .fontColor(ColorTokens.ink)
        // 原来三件信息挤在一条 `maxLines(2)` 长句里，CJK 会在词中间断行——
        // 真机拍到「锚定 丽/泽商务区」「到火车站 10 分钟 ·/餐饮中密度」这种断法。
        // 改成每行只放一件语义完整的事，断行点由我们选，不交给排版引擎。
        // 三行的分工是**量出来的**（文本列右边界 749px）：
        //   档位+地铁 = 544~655px；锚定+餐饮密度 = 614~727px；机场+火车站 = 657~678px。
        // 中间试过把餐饮密度并到第一行，复拍发现那一行四张卡全部顶到 749px
        // ——也就是整条被省略号截掉，密度信息照样丢。**挪到有富余的锚定行才对。**
        Text(isMapArea(a) ? '舒适档（未校准） · 地图服务区县'
          : `${this.tierLabel(a.priceTier)} · ${a.metroLines.join('/')}`)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(isMapArea(a) ? '按景点所在区县聚合'
          : `锚定 ${a.anchorStations.join('/')} · 餐饮${a.diningDensity}密度`)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(isMapArea(a) ? '通勤与住宿供给未校准'
          : `到机场 ${a.airportMinutes} 分钟 · 到火车站 ${a.trainStationMinutes} 分钟`)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.body)
          .fontFeature("'tnum' on")
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 选这片：44vp 最小命中区 + button 档字号（16/600），不用 32vp 小热区
      Button('选这片')
        .fontSize(TypeTokens.body.size)
        .fontWeight(600)
        .height(LayoutTokens.minTouchTarget)
        .padding({ left: SpaceTokens.base, right: SpaceTokens.base })
        .type(ButtonType.Capsule)
        .buttonStyle(ButtonStyleMode.NORMAL)
        .onClick((): void => {
          this.pathStack.pop(a);
        })
    }
    .alignItems(VerticalAlign.Center)
    .width('100%')
    .padding(SpaceTokens.base)
    .borderRadius(RadiusTokens.card)
    .backgroundColor(ColorTokens.surfaceElevated)
  }

  /** 绝对滚动偏移 → 顶栏磨砂开关（>0 即开，静止归零） */
  private syncBarScroll(): void {
    const y: number = this.barScroller.currentOffset().yOffset;
    const on: boolean = y > 0;
    if (on !== this.barScrolled) {
      this.barScrolled = on;
      if (!on) {
        // 偏移回到 0：HDS 在这一帧回写系统栏内容色，补设通道连发四发压住它（utils/systemBar.ets）
        requestSystemBarRefresh();
      }
    }
  }

  /** 搜索行（迁进栏体做 bottomBuilder 行）：行内自撑满高，左右 base 内距由这里给。 */
  @Builder
  searchRow() {
    if (!this.loading && this.areas.length > 0) {
      Row() {
        Search({ value: this.keyword, placeholder: '搜索区域、站点或线路' })
          .onChange((v: string): void => {
            this.keyword = v;
          })
          .width('100%')
      }
      .width('100%')
      .height('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: SpaceTokens.base, right: SpaceTokens.base })
    }
  }

  build() {
    HdsNavDestination() {
      Column() {
        // 与屏12b 同一判据：没有可搜内容时不挂搜索框。
        // 这一屏在 loading 与「还没有这座城市的区域数据」两种状态下都不该摆输入框，
        // 否则用户会以为搜索框坏了（屏12b 实拍拍到同一形态后回这里查的）

        if (this.loading) {
          Column({ space: SpaceTokens.sm }) {
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
          // 空态（2026-11-07 全量对齐：44 展示档图标 + headline 18/600 serif + callout + 一个主按钮）
          Column({ space: SpaceTokens.sm }) {
            SymbolGlyph($r('sys.symbol.map'))
              .fontSize(IconSizes.display)
              .fontColor([ColorTokens.muted])
            Text(this.mapCity
              ? (this.loadFailed ? '地图服务没取到这座城市的住宿区' : '地图服务没有返回这座城市的住宿区')
              : '还没有这座城市的区域数据')
              .fontSize(TypeTokens.headline.size)
              .fontWeight(TypeTokens.headline.weight)
              .fontFamily(TypeTokens.title.family)
              .fontColor(ColorTokens.ink)
            Text(this.mapCity ? '检查网络后重试，或换一座城市'
              : `内置精选片区的城市：${seedCityListText()}；其他城市走地图服务实时取数`)
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
          .padding({ left: SpaceTokens.base, right: SpaceTokens.base })
        } else if (this.visible().length === 0) {
          Text(`没有匹配「${this.keyword}」的区域`)
            .fontSize(TypeTokens.small.size)
            .fontColor(ColorTokens.muted)
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: SpaceTokens.lg })
        } else {
          List({ space: SpaceTokens.xxs, scroller: this.barScroller }) {
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
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .sticky(StickyStyle.Header)
          .cachedCount(6)
          // 真机实拍（§5o）的 dock 净空已随 2026-11-11 二级页全屏化作废：本页落宿主栈、
          // 全屏无 dock，滚动内容直接贴到安全区底
          .padding({ left: SpaceTokens.base, right: SpaceTokens.base })
          // 穿底让位（2026-11-08 对标有据）：让位从 padding 移到 contentStartOffset，
          // 只挪首屏起点；滚动后内容才穿得到标题栏下被材质糊掉（padding 压的是视口）。
          .contentStartOffset(HdsChrome.contentTopInset(this.statusBarHeight, 56))
          .layoutWeight(1)
          .onDidScroll((): void => {
            this.syncBarScroll();
          })
        }
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(ColorTokens.canvas)
    }
    // HDS 深色档这层默认纯黑，透明栏会把它露成一条比画布暗一档的带（成因与实测见 Docs/INIT_REPORT.md §5ci 续 80）
    .backgroundColor(ColorTokens.canvas)
    .titleBar(HdsChrome.bar({ themeTick: this.chromeThemeTick,
      bottomBuilder: (): void => { this.searchRow(); },
      bottomRowHeight: 56,
      mainTitle: '全部区域',
      subTitle: this.areas.length > 0 ? `${this.city} · ${this.areas.length} 片` : this.city,
      scrolled: this.barScrolled
      
    }))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    // 收的是栏内搜索行，标题常驻（有据 HomeTab 同款）
    // 不收栏（2026-11-08）：NavDestination 内容区恒预留 56vp 栏位、收栏后不回收，收起只留一条 175px 白带
    .bindToScrollable([this.barScroller])
    .clip(false)
  }
}
