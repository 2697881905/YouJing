/**
 * 屏6 行程生成中（帧 35c7d3b4）——真管线版（阶段 7 接线）。
 * Generating 不再是假定时器：并行推进展示步骤 + 真实 LlmClient.generateTrip，
 * 成功 TripDao.saveTrip 后 replacePath 进屏8（带 tripId）；
 * 失败（重试耗尽）replacePath 进屏7 GenerateFailed（§4.1-5 降级链）。
 */

import { APP_NAV, FailInfo } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { PlanDraft } from '../data/PlanDraft';
import { PlanRepository } from '../data/PlanRepository';
import { TripDao } from '../data/TripDao';
import { WidgetSync } from '../widget/TodayCard';
import { LlmClient } from '../ai/LlmClient';
import { PlanParams } from '../model/PlanParams';
import { Spot } from '../model/Spot';
import { Area } from '../model/Area';
import { Trip } from '../model/Trip';
import { TripBasicInput } from '../model/PlanParams';
import { Logger } from '../common/logger/Logger';
import { AppError } from '../common/error/AppError';
import { common } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';

@Component
export struct GeneratingPage {
  @State private stage: number = 0;
  @State private progress: number = 0.25;
  @State private done: boolean = false;
  private stages: string[] = ['筛选景点', '排布每日动线', '校验开放时间与预约', '估算步行耗时'];
  private timer: number = -1;

  aboutToAppear(): void {
    this.timer = setInterval(() => {
      if (!this.done && this.stage < this.stages.length) {
        this.stage += 1;
        this.progress = (this.stage + 1) / (this.stages.length + 1);
      }
    }, 700);
    this.run();
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private async run(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const draft = PlanDraft.get();
    try {
      const spots: Spot[] = await PlanRepository.loadSpots(context, draft.basic.destination);
      const areas: Area[] = await PlanRepository.loadAreas(context, draft.basic.destination);
      const area: Area | undefined = areas.find((a: Area): boolean => a.id === draft.selectedArea.areaId);
      if (area === undefined) {
        throw new Error('住宿区域缺失');
      }
      const params: PlanParams = {
        basic: draft.basic, style: draft.style, stayTier: draft.stayTier,
        transit: draft.transit, paces: draft.paces,
        selectedSpots: draft.selectedSpots, selectedArea: draft.selectedArea
      };
      const trip: Trip = await LlmClient.generateTrip(params, spots, area);
      await TripDao.saveTrip(context, trip);
      this.done = true;
      this.stage = this.stages.length;
      this.progress = 1;
      Logger.info('Ui.Generating', `生成并落库 ${trip.id}`);
      WidgetSync.refreshAll(context).catch((err: Error) => {
        Logger.warn('Ui.Generating', `卡片刷新失败: ${err.message}`);
      });
      APP_NAV.replacePath({ name: 'Itinerary', param: trip.id });
    } catch (err) {
      const code: number = err instanceof AppError ? (err as AppError).code : 0;
      Logger.error('Ui.Generating', `生成失败 code=${code}: ${(err as Error).message}`);
      this.done = true;
      const info: FailInfo = { code: code, detail: (err as Error).message };
      APP_NAV.replacePath({ name: 'GenerateFailed', param: info });
    }
  }

  @Builder
  skeletonBlock(w: Length, h: number) {
    Column()
      .width(w)
      .height(h)
      .borderRadius(RadiusTokens.media)
      .backgroundColor(ColorTokens.skeletonBase)
      .opacity(0.6)
  }

  @Builder
  skeletonRow() {
    Row({ space: SpaceTokens.sm }) {
      this.skeletonBlock(40, 14)
      Column()
        .width(24)
        .height(24)
        .borderRadius(RadiusTokens.pill)
        .backgroundColor(ColorTokens.skeletonBase)
      Column({ space: SpaceTokens.xs }) {
        this.skeletonBlock('70%', 14)
        this.skeletonBlock('45%', 10)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
  }

  build() {
    HdsNavDestination() {
      Column() {

        Column() {
          Text(`正在为你规划 ${Math.max(1, this.daysCount())} 天行程`)
            .fontSize(TypeTokens.title.size)
            .fontWeight(700)
            .fontFamily(TypeTokens.title.family)
            .fontColor(ColorTokens.ink)
          Text(`已选好 ${PlanDraft.get().selectedSpots.length} 个景点 · 1 个住宿区域`)
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
            .fontFeature("'tnum' on")
            .margin({ top: SpaceTokens.xs, bottom: SpaceTokens.md })
          Progress({ value: Math.round(this.progress * 100), total: 100, type: ProgressType.Linear })
            .color(ColorTokens.primary)
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .margin({ top: SpaceTokens.xl })

        Column({ space: SpaceTokens.sm }) {
          ForEach(this.stages, (name: string, idx: number) => {
            Row({ space: SpaceTokens.sm }) {
              SymbolGlyph(idx < this.stage ? $r('sys.symbol.checkmark_circle_fill') :
                (idx === this.stage ? $r('sys.symbol.arrow_clockwise') : $r('sys.symbol.circle')))
                .fontSize(22)
                .fontColor([idx < this.stage ? ColorTokens.success :
                  (idx === this.stage ? ColorTokens.primary : ColorTokens.faint)])
              Text(name)
                .fontSize(TypeTokens.small.size)
                .fontWeight(idx === this.stage ? 600 : 400)
                .fontColor(idx <= this.stage ? ColorTokens.ink : ColorTokens.muted)
            }
          }, (name: string, idx: number): string => `stage-${idx}-${this.stage}`)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .margin({ top: SpaceTokens.xl })

        Column() {
          Column() {
            this.skeletonRow()
            this.skeletonRow()
            this.skeletonRow()
          }
          .padding(SpaceTokens.md)
          .borderRadius(RadiusTokens.card)
          .backgroundColor(ColorTokens.surfaceElevated)
          .width('100%')
          .margin({ bottom: SpaceTokens.md })

          Column() {
            this.skeletonRow()
            this.skeletonRow()
          }
          .padding(SpaceTokens.md)
          .borderRadius(RadiusTokens.card)
          .backgroundColor(ColorTokens.surfaceElevated)
          .width('100%')
        }
        .width('100%')
        .margin({ top: SpaceTokens.xl })
        .layoutWeight(1)

        Column({ space: SpaceTokens.sm }) {
          Text('全程在本机生成，无需等待网络')
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
          Text('取消')
            .fontSize(TypeTokens.body.size)
            .fontColor(ColorTokens.body)
            .width('100%')
            .height(LayoutTokens.minTouchTarget)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              APP_NAV.pop();
            })
        }
        .width('100%')
        .padding({ bottom: SpaceTokens.xl })
      }
      .width('100%')
      .height('100%')
      .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })
      .backgroundColor(ColorTokens.canvas)
    }
    .titleBar(HdsChrome.bar({ mainTitle: '生成行程' }))
    .titleMode(HdsNavDestinationTitleMode.MINI)
  }

  private daysCount(): number {
    const b: TripBasicInput = PlanDraft.get().basic;
    return Math.max(1, Math.round((Date.parse(b.endDate) - Date.parse(b.startDate)) / 86400000) + 1);
  }
}
