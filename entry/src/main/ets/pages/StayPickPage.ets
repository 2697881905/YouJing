/**
 * 屏5 住宿区域精选与通勤（帧 1cd06e03）。
 * §7 必改已落：badge padding 3→4、commute-col gap 2→0。
 * 底稿的地图卡与三列通勤数字未照搬：内置区域库只到城市质心、且无住宿库存与路径规划，
 * 详见 Docs/INIT_REPORT.md §4b-7/8。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { ShadowTokens } from '../design/ShadowTokens';
import { AreaPick } from '../mock/MockData';
import { Area, AreaGroup, AreaPriceTier } from '../model/Area';
import { PlanRepository } from '../data/PlanRepository';
import { PlanDraft } from '../data/PlanDraft';
import { common } from '@kit.AbilityKit';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';

@Component
export struct StayPickPage {
  private pathStack: NavPathStack = APP_NAV;
  @StorageProp('isDarkMode') isDark: boolean = false;
  @State private selectedId: string = '';
  @State private picks: AreaPick[] = [];

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const city: string = PlanDraft.get().basic.destination;
    PlanRepository.loadAreas(ctx, city).then((areas: Area[]) => {
      const list: AreaPick[] = [];
      const top: Area[] = areas.slice(0, 3);
      for (let i = 0; i < top.length; i++) {
        const a: Area = top[i];
        // 理由与三列只拼区域库里真有的字段：到首个景点耗时/日均通勤/房源数
        // 需要路径规划与住宿库存，本项目两者都没有，底稿那三项数字不再照抄
        const din: string = `周边餐饮${a.diningDensity}密度`;
        const pick: AreaPick = {
          area: a,
          badgeLabel: i === 0 ? '精选 1' : this.groupBadge(a.group),
          aiRank: i + 1,
          reason: a.suitableCrowds.length > 0 ? `适合${a.suitableCrowds.join('/')}，${din}` :
            `地铁${a.metroLines.join('/')}线直达，${din}`
        };
        list.push(pick);
      }
      this.picks = list;
      this.selectedId = list.length > 0 ? list[0].area.id : '';
    });
  }

  /** 角标只描述 Area.group 这一个真字段，不再按位次猜「交通枢纽」 */
  private groupBadge(group: AreaGroup): string {
    if (group === AreaGroup.CORE) {
      return '核心地段';
    }
    return group === AreaGroup.COMMERCIAL ? '商圈便利' : '交通枢纽';
  }

  private areaMeta(area: Area): string {
    const tier: string = area.priceTier === AreaPriceTier.ECONOMY ? '经济档'
      : (area.priceTier === AreaPriceTier.LUXURY ? '豪华档' : '舒适档');
    const lines: string = area.metroLines.length > 0 ? `地铁 ${area.metroLines.slice(0, 2).join('/')}` : '无直达地铁';
    // 锚定站只放第一个：两个站名会把这行顶到 maxLines(1) 的截断线
    const stations: string = area.anchorStations.length > 0 ? `锚定 ${area.anchorStations[0]}` : '';
    return stations.length > 0 ? `${tier} · ${lines} · ${stations}` : `${tier} · ${lines}`;
  }

  @Builder
  mapChip(pick: AreaPick) {
    Row({ space: 4 }) {
      Column()
        .width(6)
        .height(6)
        .borderRadius(RadiusTokens.pill)
        .backgroundColor(this.dotColor(pick.area.group))
      Text(pick.area.name)
        .fontSize(TypeTokens.caption.size)
        .fontWeight(450)
        .fontColor(ColorTokens.ink)
    }
    .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm, top: 4, bottom: 4 })
    .borderRadius(RadiusTokens.media)
    .backgroundColor(ColorTokens.surfaceElevated)
    .margin(4)
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
          Text(this.areaMeta(pick.area))
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
            .fontFeature("'tnum' on")
            // 全量种子这行最长 30 字（深圳 大鹏-较场尾「舒适档 · 地铁 E11接驳 · 锚定 大鹏中心(公交接驳)」），
            // 单行必截，故给两行
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
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
            .fontSize(22)
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
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        Column() {
          Row() {
            SymbolGlyph($r('sys.symbol.chevron_backward'))
              .fontSize(22)
              .fontColor([ColorTokens.ink])
              .onClick(() => {
                this.pathStack.pop();
              })
            Text('住哪一片')
              .fontSize(TypeTokens.body.size)
              .fontWeight(600)
              .fontColor(ColorTokens.ink)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
            Text('查看更多区域')
              .fontSize(TypeTokens.small.size)
              .fontColor(ColorTokens.primary)
              .width(96)
              .textAlign(TextAlign.End)
          }
          .height(LayoutTokens.titleBarHeight)
          .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })

          Scroll() {
            Column() {
              // 候选片区图例：底稿这格是手绘纸面动线地图，但内置区域库所有片区共用
              // 同一个城市质心坐标（DistrictCoords.lookup(city, city)），按经纬度布点
              // 就是编位置，故只保留 route-paper 底 + 芯片，不暗示相对方位
              Stack({ alignContent: Alignment.Center }) {
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
                    }, (pick: AreaPick): string => `chip-${pick.area.id}`)
                  }
                  .width('100%')
                  .margin({ left: SpaceTokens.md, right: SpaceTokens.md })
                  Text('按推荐顺序排列')
                    .fontSize(TypeTokens.caption.size)
                    .fontWeight(450)
                    .fontColor(ColorTokens.faint)
                }
                .padding({ left: SpaceTokens.md, right: SpaceTokens.md })
              }
              .width('100%')
              .height(LayoutTokens.mapHeightCompact)
              .borderRadius(RadiusTokens.card)
              .clip(true)
              .margin({ bottom: SpaceTokens.md })

              ForEach(this.picks, (pick: AreaPick) => {
                this.areaCard(pick)
              }, (pick: AreaPick): string => pick.area.id)
            }
            .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, bottom: 110 })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
        }
        .width('100%')
        .height('100%')

        Column() {
          Row({ space: SpaceTokens.md }) {
            YoujingButton({
              variant: YoujingButtonVariant.SECONDARY,
              label: '帮我选（推荐第一片）',
              buttonWidth: 200,
              onAction: (): void => {
                if (this.picks.length > 0) {
                  this.selectedId = this.picks[0].area.id;
                }
              }
            })
            YoujingButton({
              variant: YoujingButtonVariant.PRIMARY,
              label: '就住这里',
              onAction: (): void => {
                PlanDraft.get().selectedArea = { areaId: this.selectedId };
                this.pathStack.pushPath({ name: 'Generating' });
              }
            })
              .layoutWeight(1)
          }
        }
        .width('100%')
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, top: SpaceTokens.md, bottom: SpaceTokens.lg })
        .backgroundColor(ColorTokens.canvas)
      }
    }
    .hideTitleBar(true)
  }
}
