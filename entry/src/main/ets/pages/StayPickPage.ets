/**
 * 屏5 住宿区域精选与通勤（帧 1cd06e03）。
 * §7 必改已落：badge padding 3→4、commute-col gap 2→0。
 * 地图卡为 route-paper 渐变占位（Map Kit 真实地图在系统能力批次接入）。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { ShadowTokens } from '../design/ShadowTokens';
import { AreaPick } from '../mock/MockData';
import { Area } from '../model/Area';
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
        const pick: AreaPick = {
          area: a,
          badgeLabel: i === 0 ? 'AI 精选 1' : (a.group === 'commercial' ? '商圈便利' : '交通枢纽'),
          aiRank: i + 1,
          reason: a.suitableCrowds.length > 0 ?
            `适合${a.suitableCrowds.join('/')}，${a.diningDensity === '高' ? '周边餐饮密集' : '环境安静'}` :
            `${a.metroLines.join('/')}直达，通勤友好`,
          firstSpot: `地铁 ${8 + i * 4}分钟`,
          dailyCommuteMin: 30 + i * 6,
          stayCount: 9 + i * 7
        };
        list.push(pick);
      }
      this.picks = list;
      this.selectedId = list.length > 0 ? list[0].area.id : '';
    });
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

      // 通勤三列
      Row() {
        this.commuteCol(pick.firstSpot, '到首个景点')
        this.commuteCol(`${pick.dailyCommuteMin}分钟`, '日均通勤')
        this.commuteCol(`${pick.stayCount} 家`, '舒适型房源')
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
              // 地图占位卡：route-paper 渐变 + 区域点位芯片
              Stack({ alignContent: Alignment.TopStart }) {
                Column()
                  .width('100%')
                  .height('100%')
                  .linearGradient({
                    angle: 180,
                    colors: [[ColorTokens.routeBgTop, 0], [ColorTokens.routeBgBottom, 1]]
                  })
                Text('动线地图 · Map Kit 批次接入')
                  .fontSize(TypeTokens.caption.size)
                  .fontColor(ColorTokens.faint)
                  .margin(8)
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
              label: '帮我选（按通勤最短）',
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
