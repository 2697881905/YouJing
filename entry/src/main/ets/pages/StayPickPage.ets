/**
 * 屏5 住宿区域精选与通勤（帧 1cd06e03）。
 * §7 必改已落：badge padding 3→4、commute-col gap 2→0。
 * 顶部地图卡：v2 起区域库有逐片坐标，上真实底图（三片互斥、不连线）；
 * 三列通勤取 Area 真字段（到机场/到火车站/餐饮密度），底稿的「到首个景点/日均通勤/房源数」
 * 要的是路径规划与住宿库存，本项目两者都没有。详见 Docs/INIT_REPORT.md §4b-7/8。
 * 候选收敛（§3.3 住宿区域同理）：排序统一走 `PlanAutoPick.rankAreas`——
 * 地图区县按酒店供给（`buildAreas` 的入参顺序）、种子片区按与屏4 所选景点的平均
 * 直线距离，取前 12 片做候选再展示前 3 片；没有可用坐标时退回原顺序，不谎报距离。
 * 「帮我选」：底稿写「按通勤最短」，本项目没有路径规划，按钮文案按各自的真实判据写
 * （住得最方便 / 离景点最近），toast 报平均直线距离，不谎报成导航里程。
 */

import { APP_NAV, markDraftDirty } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { FlowSteps, FLOW_STEP_STAY_PICK } from '../components/FlowSteps';
import { ShadowTokens } from '../design/ShadowTokens';
import { AreaPick } from '../model/PlanParams';
import { Area, AreaGroup, AreaPriceTier } from '../model/Area';
import { Spot } from '../model/Spot';
import { SelectedSpot } from '../model/PlanParams';
import { Geo, GeoPoint } from '../utils/Geo';
import { PlanAutoPick } from '../utils/PlanAutoPick';
import { MapStop, MapStops } from '../utils/MapStops';
import { TripMapView } from '../components/TripMapView';
import { PlanRepository } from '../data/PlanRepository';
import { PlanDraft } from '../data/PlanDraft';
import { common } from '@kit.AbilityKit';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import type { HdsNavigationMenuItemOptions, HdsNavigationTitleBarOptions } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';
import { Logger } from '../common/logger/Logger';
import { isMapCity } from '../common/constants/Cities';
import { isMapArea } from '../utils/MapCityMapper';
import { KEY_CURRENT_BREAKPOINT } from '../utils/breakpointCenter';
import { listLanesForBreakpoint } from '../utils/responsive';

/** §3.3：App 端距离筛选后的候选片区上限 */
const AREA_CANDIDATES: number = 12;
/** 展示给用户的候选卡片数（AI 精选 2-3 个的呈现档；LLM 通道就绪前按距离取前 3） */
const AREA_PICKS: number = 3;

@Component
export struct StayPickPage {
  /** 断点（唯一来源 utils/breakpointCenter.ets）：宽屏下列表并成多栏，不再被整屏拉宽 */
  @StorageProp(KEY_CURRENT_BREAKPOINT) bp: string = 'sm';

  private pathStack: NavPathStack = APP_NAV;
  /** 顶栏磨砂两态：由**绝对**滚动偏移驱动（每帧增量会被松手回弹的负帧打灭，契约 §Translucency） */
  @State private barScrolled: boolean = false;
  private barScroller: Scroller = new Scroller();
  @State private selectedId: string = '';
  @State private picks: AreaPick[] = [];
  /** 候选片区落点：坐标可用时才上真实底图，否则保留图例 */
  @State private areaStops: MapStop[] = [];
  @State private areaSig: string = '';
  /** 屏4 已选景点的坐标，供 rankAreas 排序与「帮我选」使用 */
  private spotPoints: GeoPoint[] = [];
  /** 任意城市：住宿区按区县聚合，档位/通勤未校准 */
  private mapCity: boolean = false;

  @State private loaded: boolean = false;

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const city: string = PlanDraft.get().basic.destination;
    this.mapCity = isMapCity(city);
    this.loaded = false;
    this.loadSpotPoints(ctx, city).then((): Promise<Area[]> => {
      return PlanRepository.loadAreas(ctx, city);
    }).then((areas: Area[]) => {
      const ranked: Area[] =
        PlanAutoPick.rankAreas(areas, this.spotPoints).slice(0, AREA_CANDIDATES);
      const top: Area[] = ranked.slice(0, AREA_PICKS);
      const list: AreaPick[] = [];
      for (let i = 0; i < top.length; i++) {
        list.push(this.makePick(top[i], i));
      }
      this.picks = list;
      const remembered: string = PlanDraft.get().selectedArea.areaId;
      const keep: AreaPick | undefined =
        list.find((p: AreaPick): boolean => p.area.id === remembered);
      this.selectedId = keep !== undefined ? keep.area.id : (list.length > 0 ? list[0].area.id : '');
      this.applyStops(top);
      this.loaded = true;
      Logger.info('Ui.StayPick',
        `候选片区 ${areas.length} → 统一排序取前 ${AREA_CANDIDATES} → 展示 ${list.length}`);
    }).catch((err: Error) => {
      this.loaded = true;
      Logger.error('Ui.StayPick', `区域库加载失败: ${err.message}`);
    });
  }

  /**
   * §3.3 住宿候选收敛已并入 `PlanAutoPick.rankAreas`：
   * 列表顺序与屏2 预选必须同源，否则「首屏推荐」和「自动帮你选」会各说一套
   * （2026-10-31 丽江实测：按平均距离重排把玉龙县城顶到了古城区前面）。
   */

  private loadSpotPoints(ctx: common.UIAbilityContext, city: string): Promise<void> {
    const chosen: string[] = PlanDraft.get().selectedSpots.map((s: SelectedSpot): string => s.spotId);
    if (chosen.length === 0) {
      return Promise.resolve();
    }
    return PlanRepository.loadSpots(ctx, city).then((spots: Spot[]): void => {
      const pts: GeoPoint[] = [];
      for (const s of spots) {
        if (chosen.indexOf(s.id) >= 0 && Geo.usable(s.latitude, s.longitude)) {
          const p: GeoPoint = { latitude: s.latitude, longitude: s.longitude };
          pts.push(p);
        }
      }
      this.spotPoints = pts;
      Logger.info('Ui.StayPick', `所选景点可用坐标 ${pts.length}/${chosen.length}`);
    });
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1800 });
  }

  /**
   * 底稿屏5 的「帮我选（按通勤最短）」：本项目没有路径规划，规则按数据源分——
   * 地图区县按酒店供给（住宿最集中）、种子片区按到所选景点的平均直线距离，
   * 与屏2 预选共用 `PlanAutoPick.rankAreas`。toast 报的是平均直线距离，不谎报成导航里程。
   */
  private autoPickArea(): void {
    if (this.picks.length === 0) {
      return;
    }
    const targets: GeoPoint[] = this.spotPoints;
    const areas: Area[] = this.picks.map((p: AreaPick): Area => p.area);
    // 与屏2 一句话「直接生成」共用同一条排序（utils/PlanAutoPick），
    // 免得手工走屏5 与自动生成得到两套不同的住宿区
    const pick: Area | null = PlanAutoPick.nearestArea(areas, targets);
    if (pick === null) {
      this.selectedId = this.picks[0].area.id;
      Logger.warn('Ui.StayPick', `帮我选退回推荐顺序 targets=${targets.length}`);
      this.toast(targets.length === 0 ? '暂时算不出距离，先按推荐顺序选了一片' :
        '候选片区都缺位置信息，先按推荐顺序选了一片');
      return;
    }
    this.selectedId = pick.id;
    const g: GeoPoint = { latitude: pick.latitude, longitude: pick.longitude };
    const km: number = Geo.meanDistanceKm(g, targets);
    Logger.info('Ui.StayPick', `帮我选 ${pick.name} 平均 ${km.toFixed(2)}km targets=${targets.length}`);
    const lead: string = this.mapCity ? '住宿最集中的片区' : '离所选景点最近';
    this.toast(`${pick.name} · ${lead}；到 ${targets.length} 个所选景点平均约 ${km.toFixed(1)} km`);
  }

  /** 理由与三列只拼区域库里真有的字段：到首个景点耗时/日均通勤/房源数
   *  需要路径规划与住宿库存，本项目两者都没有，底稿那三项数字不再照抄 */
  private makePick(a: Area, rank: number): AreaPick {
    if (isMapArea(a)) {
      const mapPick: AreaPick = {
        area: a,
        badgeLabel: rank === 0 ? '精选 1' : '地图区县',
        aiRank: rank + 1,
        reason: '按酒店供给多少排序；住宿档与通勤未校准'
      };
      return mapPick;
    }
    const din: string = `周边餐饮${a.diningDensity}密度`;
    const pick: AreaPick = {
      area: a,
      badgeLabel: rank === 0 ? '精选 1' : this.groupBadge(a.group),
      aiRank: rank + 1,
      reason: a.suitableCrowds.length > 0 ? `适合${a.suitableCrowds.join('/')}，${din}` :
        `${a.metroLines.join('/')}直达，${din}`
    };
    return pick;
  }

  private applyStops(areas: Area[]): void {
    const stops: MapStop[] = MapStops.fromAreas(areas);
    this.areaStops = stops;
    this.areaSig = MapStops.signature(stops);
  }

  /** 屏5b 全部区域：带 Area 出栈后插成首位候选并选中（原来那行字是个没有动作的死控件） */
  private openAreaMore(): void {
    const city: string = PlanDraft.get().basic.destination;
    this.pathStack.pushPath({
      name: 'AreaMore',
      param: city,
      onPop: (info: PopInfo): void => {
        if (typeof info.result !== 'object' || info.result === null) {
          return;
        }
        const chosen: Area = info.result as Area;
        if (chosen.id.length === 0) {
          return;
        }
        const rest: Area[] = this.picks.map((p: AreaPick): Area => p.area)
          .filter((a: Area): boolean => a.id !== chosen.id).slice(0, 2);
        const merged: Area[] = [chosen].concat(rest);
        const list: AreaPick[] = merged.map((a: Area, i: number): AreaPick => this.makePick(a, i));
        this.picks = list;
        this.selectedId = chosen.id;
        this.applyStops(merged);
      }
    });
  }

  private titleBarOptions(): HdsNavigationTitleBarOptions {
    const items: Array<HdsNavigationMenuItemOptions> = [HdsChrome.item(
      $r('sys.symbol.ellipsis_circle'), '查看更多区域', (): void => {
        this.openAreaMore();
      })];
    return HdsChrome.bar({ mainTitle: '住哪一片', menu: items, scrolled: this.barScrolled });
  }

  /** 角标只描述 Area.group 这一个真字段，不再按位次猜「交通枢纽」 */
  private groupBadge(group: AreaGroup): string {
    if (group === AreaGroup.CORE) {
      return '核心地段';
    }
    return group === AreaGroup.COMMERCIAL ? '商圈便利' : '交通枢纽';
  }

  /**
   * 元信息拆成两行，每行只讲一件事。
   * 原来是一条 `maxLines(2)` 长句，CJK 会在词中间换行——真机屏5 实拍到
   * 「锚定 南锣鼓/巷」这种把站名劈成两半的断法（屏11 同一族缺陷，见 INIT_REPORT §5o）。
   */
  private areaMetaTop(area: Area): string {
    if (isMapArea(area)) {
      return '舒适档（未校准） · 地图服务区县';
    }
    const tier: string = area.priceTier === AreaPriceTier.ECONOMY ? '经济档'
      : (area.priceTier === AreaPriceTier.LUXURY ? '豪华档' : '舒适档');
    const lines: string = area.metroLines.length > 0 ? area.metroLines.slice(0, 2).join('/') : '无直达线路';
    return `${tier} · ${lines}`;
  }

  private areaMetaAnchor(area: Area): string {
    if (isMapArea(area)) {
      return '';
    }
    return area.anchorStations.length > 0 ? `锚定 ${area.anchorStations[0]}` : '';
  }

  @Builder
  mapChip(pick: AreaPick) {
    Row({ space: SpaceTokens.xs }) {
      Circle()
        .width(6)
        .height(6)
        .fill(this.dotColor(pick.area.group))
      Text(pick.area.name)
        .fontSize(TypeTokens.caption.size)
        .fontWeight(450)
        .fontColor(ColorTokens.ink)
    }
    .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm, top: SpaceTokens.xs, bottom: SpaceTokens.xs })
    .borderRadius(RadiusTokens.media)
    .backgroundColor(ColorTokens.surfaceElevated)
    .margin(SpaceTokens.xs)
  }

  private dotColor(group: AreaGroup): Resource {
    if (group === AreaGroup.CORE) {
      return ColorTokens.primary;
    }
    return group === AreaGroup.COMMERCIAL ? ColorTokens.accentMention : ColorTokens.muted;
  }

  @Builder
  areaCard(pick: AreaPick) {
    Column() {
      Row() {
        Column({ space: SpaceTokens.xs }) {
          Text(pick.area.name)
            .fontSize(TypeTokens.headline.size)
            .fontWeight(600)
            .fontColor(ColorTokens.ink)
          // 档位/线路/通勤都是区域库真字段（价位段数据未采集，故不显示价格）
          Text(this.areaMetaTop(pick.area))
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
            .fontFeature("'tnum' on")
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          // 站名单独一行：最长的一条是「锚定 大鹏中心(公交接驳)」，一行放得下
          if (this.areaMetaAnchor(pick.area).length > 0) {
            Text(this.areaMetaAnchor(pick.area))
              .fontSize(TypeTokens.caption.size)
              .fontWeight(450)
              .fontColor(ColorTokens.muted)
              .fontFeature("'tnum' on")
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(pick.badgeLabel)
          .fontSize(TypeTokens.overline.size)
          .fontWeight(600)
          .fontColor(pick.aiRank === 1 ? ColorTokens.onPrimary : ColorTokens.body)
          .height(22)
          .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm })
          .borderRadius(RadiusTokens.pill)
          .backgroundColor(pick.aiRank === 1 ? ColorTokens.primary : ColorTokens.surfaceSubtle)
          .margin({ right: SpaceTokens.sm })

        if (this.selectedId === pick.area.id) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(IconSizes.control)
            .fontColor([ColorTokens.primary])
        }
      }
      .width('100%')

      // 理由件：border-left 2px primary（契约组件规格）
      Column() {
        Text('为什么是这里')
          .fontSize(TypeTokens.overline.size)
          .fontWeight(600)
          .fontColor(ColorTokens.muted)
        Text(pick.reason)
          .fontSize(TypeTokens.small.size)
          .fontColor(ColorTokens.ink)
          .margin({ top: SpaceTokens.xs })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(SpaceTokens.md)
      .borderRadius(RadiusTokens.reason)
      .backgroundColor(ColorTokens.surfacePanel)
      .border({ width: { left: 2 }, color: ColorTokens.primary })
      .margin({ top: SpaceTokens.md })

      // 通勤三列（底稿为 到首个景点/日均通勤/舒适型房源，三项均需路径规划与住宿库存，
      // 内置库没有；换成区域库真有的三个字段，版式不变）。
      // 地图服务区县没有这些字段，不拿 0 分钟冒充事实，改为一句未校准说明。
      if (isMapArea(pick.area)) {
        Text('住宿区按景点所在区县聚合；通勤与餐饮未校准')
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .width('100%')
          .margin({ top: SpaceTokens.md })
      } else {
        Row() {
          this.commuteCol(`${pick.area.airportMinutes}分钟`, '到机场')
          this.commuteCol(`${pick.area.trainStationMinutes}分钟`, '到火车站')
          this.commuteCol(pick.area.diningDensity, '餐饮密度')
        }
        .width('100%')
        .margin({ top: SpaceTokens.md })
      }
    }
    .width('100%')
    .padding(SpaceTokens.lg)
    .borderRadius(RadiusTokens.card)
    .backgroundColor(ColorTokens.canvas)
    .shadow(ShadowTokens.cardAmbient)
    .border({
      width: this.selectedId === pick.area.id ? 1 : 0,
      color: ColorTokens.primary,
      radius: RadiusTokens.card
    })
    .margin({ bottom: SpaceTokens.md })
    .onClick(() => {
      this.selectedId = pick.area.id;
    })
  }

  @Builder
  commuteCol(value: string, label: string) {
    Column() {
      Text(value)
        .fontSize(TypeTokens.small.size)
        .fontWeight(600)
        .fontColor(ColorTokens.ink)
        .fontFeature("'tnum' on")
      Text(label)
        .fontSize(TypeTokens.caption.size)
        .fontWeight(450)
        .fontColor(ColorTokens.muted)
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  @Builder
  mapSourceNotice() {
    Column({ space: SpaceTokens.xs }) {
      Text('住宿区来自地图服务')
        .fontSize(TypeTokens.overline.size)
        .fontWeight(600)
        .fontColor(ColorTokens.muted)
      Text('按景点所在区县聚合；住宿档、通勤与餐饮未校准')
        .fontSize(TypeTokens.caption.size)
        .fontWeight(450)
        .fontColor(ColorTokens.body)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(SpaceTokens.md)
    .borderRadius(RadiusTokens.reason)
    .backgroundColor(ColorTokens.surfacePanel)
    .margin({ bottom: SpaceTokens.md })
  }

  /** 绝对滚动偏移 → 顶栏磨砂开关（>0 即开，静止归零） */
  private syncBarScroll(): void {
    const y: number = this.barScroller.currentOffset().yOffset;
    const on: boolean = y > 0;
    if (on !== this.barScrolled) {
      this.barScrolled = on;
    }
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        Column() {
          if (!this.loaded) {
            Column() {
              LoadingProgress()
                .width(48)
                .height(48)
                .color(ColorTokens.primary)
              Text('正在加载住宿区域…')
                .fontSize(TypeTokens.caption.size)
                .fontColor(ColorTokens.muted)
                .margin({ top: SpaceTokens.md })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            // 主链进度
            Column() {
              FlowSteps({ step: FLOW_STEP_STAY_PICK })
            }
            .width('100%')
            .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, top: SpaceTokens.md })

            // 官方 List：地图面板一个 ListItem，三张候选卡各成一个 ListItem（卡间距在卡片自己身上）
            List({ scroller: this.barScroller }) {
            if (this.mapCity) {
              ListItem() {
                this.mapSourceNotice()
              }
            }
            ListItem() {
              // 候选片区地图：区域库有逐片坐标时上真实底图（三片是互斥选项，不连线），
              // 坐标缺失才退回 route-paper 图例——不拿城市质心假装位置
              Stack({ alignContent: Alignment.BottomStart }) {
                if (this.areaStops.length > 0) {
                  TripMapView({
                    stops: this.areaStops,
                    signature: this.areaSig,
                    route: false
                  })
                    .width('100%')
                    .height('100%')
                  Text('本次候选的三片 · 按推荐顺序')
                    .fontSize(TypeTokens.caption.size)
                    .fontWeight(450)
                    .fontColor(ColorTokens.ink)
                    .height(28)
                    .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm })
                    .borderRadius(RadiusTokens.pill)
                    .backgroundColor(ColorTokens.canvas)
                    .margin(LayoutTokens.mapOverlayInset - 8)
                } else {
                  Column()
                    .width('100%')
                    .height('100%')
                    .linearGradient({
                      angle: 180,
                      colors: [[ColorTokens.routeBgTop, 0], [ColorTokens.routeBgBottom, 1]]
                    })
                  Column({ space: SpaceTokens.sm }) {
                    Text('本次候选的三片')
                      .fontSize(TypeTokens.overline.size)
                      .fontWeight(600)
                      .fontColor(ColorTokens.muted)
                    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
                      ForEach(this.picks, (pick: AreaPick) => {
                        this.mapChip(pick)
                      }, (pick: AreaPick): string => `chip-${pick.area.id}-${pick.aiRank}`)
                    }
                    // 外层 Column 已经给了左右 md 的 padding；这里再叠一道横向 margin
                    // 就是 100% 宽 + 32 边距，必然往两边溢出（父级让位用 padding，不用 margin）
                    .width('100%')
                    Text('该城市暂未提供位置信息，按推荐顺序列出')
                      .fontSize(TypeTokens.caption.size)
                      .fontWeight(450)
                      .fontColor(ColorTokens.muted)
                  }
                  .width('100%')
                  .height('100%')
                  .justifyContent(FlexAlign.Center)
                  .padding({ left: SpaceTokens.md, right: SpaceTokens.md })
                }
              }
              .width('100%')
              .height(LayoutTokens.mapHeightCompact)
              .borderRadius(RadiusTokens.card)
              .clip(true)
              .margin({ bottom: SpaceTokens.md })
            }

            ForEach(this.picks, (pick: AreaPick) => {
              ListItem() {
                this.areaCard(pick)
              }
            }, (pick: AreaPick): string => `card-${pick.area.id}`)
          }
          .lanes(listLanesForBreakpoint(this.bp))
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .cachedCount(4)
          .alignListItem(ListItemAlign.Start)
          // 滚动预留跟着钉底条抬高的一档补回来
          .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg,
            bottom: LayoutTokens.stickyBarScrollReserve + LayoutTokens.floatingDockClearance })
          .onDidScroll((): void => {
            this.syncBarScroll();
          })
          }
        }
        .width('100%')
        .height('100%')

        if (this.loaded) {
          Column() {
            Row({ space: SpaceTokens.md }) {
              YoujingButton({
                variant: YoujingButtonVariant.SECONDARY,
                label: this.mapCity ? '帮我选（住得最方便）' : '帮我选（离景点最近）',
                buttonWidth: 200,
                onAction: (): void => {
                  this.autoPickArea();
                }
              })
              Column() {
                YoujingButton({
                  variant: YoujingButtonVariant.PRIMARY,
                  label: '就住这里',
                  fullWidth: true,
                  disabled: this.selectedId.length === 0,
                  onAction: (): void => {
                    if (this.selectedId.length === 0) {
                      this.toast('请先选择一个住宿区域');
                      return;
                    }
                    PlanDraft.get().selectedArea = { areaId: this.selectedId };
                    markDraftDirty(true);
                    this.pathStack.pushPath({ name: 'Generating' });
                  }
                })
              }
              .layoutWeight(1)
            }
          }
          .width('100%')
          .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, top: SpaceTokens.md,
            bottom: LayoutTokens.floatingDockClearance })
          .backgroundColor(ColorTokens.canvas)
        }
      }
    }
    // HDS 深色档这层默认纯黑，透明栏会把它露成一条比画布暗一档的带（成因与实测见 Docs/INIT_REPORT.md §5ci 续 80）
    .backgroundColor(ColorTokens.canvas)
    .titleBar(this.titleBarOptions())
    .titleMode(HdsNavDestinationTitleMode.MINI)
  }
}
