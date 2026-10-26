/**
 * 屏5 住宿区域精选与通勤（帧 1cd06e03）。
 * §7 必改已落：badge padding 3→4、commute-col gap 2→0。
 * 顶部地图卡：v2 起区域库有逐片坐标，上真实底图（三片互斥、不连线）；
 * 三列通勤取 Area 真字段（到机场/到火车站/餐饮密度），底稿的「到首个景点/日均通勤/房源数」
 * 要的是路径规划与住宿库存，本项目两者都没有。详见 Docs/INIT_REPORT.md §4b-7/8。
 * 候选收敛（§3.3 住宿区域同理）：App 端先按与屏4 所选景点的平均直线距离排序，
 * 取前 12 片做候选，再展示前 3 片；没有可用坐标时退回种子库顺序，不谎报距离。
 * 「帮我选」：底稿写「按通勤最短」，无路径规划时能算的最近似是与屏4 所选景点的平均
 * 直线距离（utils/Geo），按钮按这个口径写成「离景点最近」，不谎报成导航里程。
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
import { KEY_CURRENT_BREAKPOINT } from '../utils/breakpointCenter';
import { listLanesForBreakpoint } from '../utils/responsive';

/** §3.3：App 端距离筛选后的候选片区上限 */
const AREA_CANDIDATES: number = 12;
/** 展示给用户的候选卡片数（AI 精选 2-3 个的呈现档；LLM 通道就绪前按距离取前 3） */
const AREA_PICKS: number = 3;

/** 片区与到所选景点集合的平均直线距离（km） */
interface AreaDistance {
  area: Area;
  dist: number;
}

@Component
export struct StayPickPage {
  /** 断点（唯一来源 utils/breakpointCenter.ets）：宽屏下列表并成多栏，不再被整屏拉宽 */
  @StorageProp(KEY_CURRENT_BREAKPOINT) bp: string = 'sm';

  private pathStack: NavPathStack = APP_NAV;
  @StorageProp('isDarkMode') isDark: boolean = false;
  @State private selectedId: string = '';
  @State private picks: AreaPick[] = [];
  /** 候选片区落点：坐标可用时才上真实底图，否则保留图例 */
  @State private areaStops: MapStop[] = [];
  @State private areaSig: string = '';
  /** 屏4 已选景点的坐标，「帮我选」按到这些点的平均距离取最小 */
  private spotPoints: GeoPoint[] = [];

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const city: string = PlanDraft.get().basic.destination;
    // 先取景点坐标、再排区域候选：两条 Promise 链式衔接，不用「谁先回来算谁」
    this.loadSpotPoints(ctx, city).then((): Promise<Area[]> => {
      return PlanRepository.loadAreas(ctx, city);
    }).then((areas: Area[]) => {
      const ranked: Area[] = StayPickPage.rankByDistance(areas, this.spotPoints);
      const top: Area[] = ranked.slice(0, AREA_PICKS);
      const list: AreaPick[] = [];
      for (let i = 0; i < top.length; i++) {
        list.push(this.makePick(top[i], i));
      }
      this.picks = list;
      // 回退到这一屏时保住上次选的那一片：原来无条件重置成 list[0]，
      // 用户从后面几步回来换住宿，选中态会跳回第一个候选
      const remembered: string = PlanDraft.get().selectedArea.areaId;
      const keep: AreaPick | undefined =
        list.find((p: AreaPick): boolean => p.area.id === remembered);
      this.selectedId = keep !== undefined ? keep.area.id : (list.length > 0 ? list[0].area.id : '');
      this.applyStops(top);
      Logger.info('Ui.StayPick',
        `候选片区 ${areas.length} → 距离排序取前 ${AREA_CANDIDATES} → 展示 ${list.length}`);
    }).catch((err: Error) => {
      Logger.error('Ui.StayPick', `区域库加载失败: ${err.message}`);
    });
  }

  /**
   * §3.3 住宿候选收敛：按与所选景点的平均直线距离升序；
   * 景点/片区任一侧缺坐标的行排最后（保持种子库顺序），不把没坐标的片区当最近。
   */
  private static rankByDistance(areas: Area[], spotPoints: GeoPoint[]): Area[] {
    if (spotPoints.length === 0) {
      return areas;
    }
    const withDist: AreaDistance[] = [];
    const noGeo: Area[] = [];
    for (const a of areas) {
      if (Geo.usable(a.latitude, a.longitude)) {
        const g: GeoPoint = { latitude: a.latitude, longitude: a.longitude };
        withDist.push({ area: a, dist: Geo.meanDistanceKm(g, spotPoints) });
      } else {
        noGeo.push(a);
      }
    }
    withDist.sort((x: AreaDistance, y: AreaDistance): number => x.dist - y.dist);
    return withDist.slice(0, AREA_CANDIDATES).map((x: AreaDistance): Area => x.area)
      .concat(noGeo);
  }

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
   * 底稿屏5 的「帮我选（按通勤最短）」：本项目没有路径规划，能算的最近似是与所选景点的
   * 平均直线距离，所以按钮文案按这个口径写，不谎报成导航里程。
   */
  private autoPickArea(): void {
    if (this.picks.length === 0) {
      return;
    }
    const targets: GeoPoint[] = this.spotPoints;
    const usableIdx: number[] = [];
    const areaPoints: GeoPoint[] = [];
    for (let i = 0; i < this.picks.length; i++) {
      const a: Area = this.picks[i].area;
      if (Geo.usable(a.latitude, a.longitude)) {
        usableIdx.push(i);
        const g: GeoPoint = { latitude: a.latitude, longitude: a.longitude };
        areaPoints.push(g);
      }
    }
    const at: number = targets.length === 0 ? -1 : Geo.argminMean(areaPoints, targets);
    if (at < 0) {
      this.selectedId = this.picks[0].area.id;
      Logger.warn('Ui.StayPick',
        `帮我选退回推荐顺序 targets=${targets.length} usableAreas=${areaPoints.length}`);
      this.toast(targets.length === 0 ? '暂时算不出距离，先按推荐顺序选了一片' :
        '候选片区都缺位置信息，先按推荐顺序选了一片');
      return;
    }
    const pick: AreaPick = this.picks[usableIdx[at]];
    this.selectedId = pick.area.id;
    const km: number = Geo.meanDistanceKm(areaPoints[at], targets);
    Logger.info('Ui.StayPick', `帮我选 ${pick.area.name} 平均 ${km.toFixed(2)}km targets=${targets.length}`);
    this.toast(`${pick.area.name} · 到 ${targets.length} 个所选景点平均约 ${km.toFixed(1)} km`);
  }

  /** 理由与三列只拼区域库里真有的字段：到首个景点耗时/日均通勤/房源数
   *  需要路径规划与住宿库存，本项目两者都没有，底稿那三项数字不再照抄 */
  private makePick(a: Area, rank: number): AreaPick {
    const din: string = `周边餐饮${a.diningDensity}密度`;
    const pick: AreaPick = {
      area: a,
      badgeLabel: rank === 0 ? '精选 1' : this.groupBadge(a.group),
      aiRank: rank + 1,
      reason: a.suitableCrowds.length > 0 ? `适合${a.suitableCrowds.join('/')}，${din}` :
        `地铁${a.metroLines.join('/')}线直达，${din}`
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
    return HdsChrome.bar({ mainTitle: '住哪一片', menu: items });
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
    const tier: string = area.priceTier === AreaPriceTier.ECONOMY ? '经济档'
      : (area.priceTier === AreaPriceTier.LUXURY ? '豪华档' : '舒适档');
    const lines: string = area.metroLines.length > 0 ? `地铁 ${area.metroLines.slice(0, 2).join('/')}` : '无直达地铁';
    return `${tier} · ${lines}`;
  }

  private areaMetaAnchor(area: Area): string {
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
      // 内置库没有；换成区域库真有的三个字段，版式不变）
      Row() {
        this.commuteCol(`${pick.area.airportMinutes}分钟`, '到机场')
        this.commuteCol(`${pick.area.trainStationMinutes}分钟`, '到火车站')
        this.commuteCol(pick.area.diningDensity, '餐饮密度')
      }
      .width('100%')
      .margin({ top: SpaceTokens.md })
    }
    .width('100%')
    .padding(SpaceTokens.lg)
    .borderRadius(RadiusTokens.card)
    .backgroundColor(ColorTokens.canvas)
    .shadow(this.isDark ? { radius: 0 } : ShadowTokens.card)
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

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        Column() {
          // 主链进度
          Column() {
            FlowSteps({ step: FLOW_STEP_STAY_PICK })
          }
          .width('100%')
          .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, top: SpaceTokens.md })

          // 官方 List：地图面板一个 ListItem，三张候选卡各成一个 ListItem（卡间距在卡片自己身上）
          List() {
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
                    .width('100%')
                    .margin({ left: SpaceTokens.md, right: SpaceTokens.md })
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
        }
        .width('100%')
        .height('100%')

        Column() {
          Row({ space: SpaceTokens.md }) {
            YoujingButton({
              variant: YoujingButtonVariant.SECONDARY,
              label: '帮我选（离景点最近）',
              buttonWidth: 200,
              onAction: (): void => {
                this.autoPickArea();
              }
            })
            YoujingButton({
              variant: YoujingButtonVariant.PRIMARY,
              label: '就住这里',
              onAction: (): void => {
                PlanDraft.get().selectedArea = { areaId: this.selectedId };
                markDraftDirty(true);
                this.pathStack.pushPath({ name: 'Generating' });
              }
            })
              .layoutWeight(1)
          }
        }
        .width('100%')
        // 吸底 CTA 条让位实测 dock 净空（原来只有 lg=16）
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, top: SpaceTokens.md,
          bottom: LayoutTokens.floatingDockClearance })
        .backgroundColor(ColorTokens.canvas)
      }
    }
    .titleBar(this.titleBarOptions())
    .titleMode(HdsNavDestinationTitleMode.MINI)
  }
}
