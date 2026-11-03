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
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
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
import { DateUtils } from '../utils/DateUtils';
import { Logger } from '../common/logger/Logger';
import { AppError } from '../common/error/AppError';
import { ErrorCode } from '../common/error/ErrorCode';
import { isMapCity } from '../common/constants/Cities';
import { EntitlementStore } from '../data/EntitlementStore';
import { GenerationChannel } from '../utils/GenerationChannel';
import { common } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';

@Component
export struct GeneratingPage {
  @State private stage: number = 0;
  @State private progress: number = 0.25;
  @State private done: boolean = false;
  private stages: string[] = ['筛选景点', '排布每日动线', '校验开放时间与预约', '估算步行耗时'];
  private timer: number = -1;
  /**
   * 取消竞态：页面离开（取消钮或系统返回）后 in-flight 的 run() 必须停止导航，
   * 否则生成完成后会把用户强行拽到 Itinerary/GenerateFailed。
   * Mock 传输微秒级返回时窗口极小，切 HttpLlmTransport 后会拉长到秒级。
   */
  private cancelled: boolean = false;
  /** 本次生成的本地行程标识（通行证绑定的 key） */
  private localTripId: string = `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;

  aboutToAppear(): void {
    this.cancelled = false;
    this.timer = setInterval(() => {
      if (!this.done && this.stage < this.stages.length) {
        this.stage += 1;
        this.progress = (this.stage + 1) / (this.stages.length + 1);
      }
    }, 700);
    this.run();
  }

  aboutToDisappear(): void {
    this.cancelled = true;
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
      if (this.cancelled) {
        return;
      }
      if (spots.length === 0 && isMapCity(draft.basic.destination)) {
        throw new AppError(ErrorCode.MAP_CITY_DATA_FAILED, '地图服务没有返回景点');
      }
      const areas: Area[] = await PlanRepository.loadAreas(context, draft.basic.destination);
      if (this.cancelled) {
        return;
      }
      const area: Area | undefined = areas.find((a: Area): boolean => a.id === draft.selectedArea.areaId);
      if (area === undefined) {
        if (isMapCity(draft.basic.destination)) {
          throw new AppError(ErrorCode.MAP_CITY_DATA_FAILED, '地图服务没有返回住宿区');
        }
        // 裸 Error 上抛会落进屏7 的兜底标题（「生成没能完成」），而这条明明有对应码值：
        // 4003 → 标题「还没选住宿区域」、副标题给出口。md 档实测过一次，就是这里漏的。
        throw new AppError(ErrorCode.TRIP_NO_AREA_SELECTED, '住宿区域缺失');
      }
      const params: PlanParams = {
        basic: draft.basic, style: draft.style, stayTier: draft.stayTier,
        transit: draft.transit, paces: draft.paces,
        selectedSpots: draft.selectedSpots, selectedArea: draft.selectedArea
      };
      // 端侧规则引擎合成（免费档）不依赖 BFF 权益，不该被额度拦；只有真要打 BFF 才问额度。
      // 判据与 ai/LlmClient 的传输选择同源于 utils/GenerationChannel。
      if (GenerationChannel.needsEntitlement() && !EntitlementStore.canGenerate()) {
        throw new AppError(ErrorCode.CLOUD_QUOTA_EXHAUSTED, '生成额度已用完');
      }
      const trip: Trip = await LlmClient.generateTrip(params, spots, area, undefined, context, this.localTripId);
      if (this.cancelled) {
        return;
      }
      trip.passId = this.localTripId;
      await TripDao.saveTrip(context, trip);
      if (this.cancelled) {
        return;
      }
      // 选中的站不一定都排得进这几天（种子库停留 4h/5h，加上 20:00 起排上限，
      // 3 天最多容纳约 3 站/天）。**少掉的必须说出来**——静默丢失用户的选择比超载更糟。
      let placed: number = 0;
      for (const day of trip.days) {
        placed += day.activities.length;
      }
      const shortfall: number = params.selectedSpots.length - placed;
      if (shortfall > 0) {
        Logger.info('Ui.Generating', `排不下 ${shortfall} 站：选中 ${params.selectedSpots.length} 实排 ${placed}`);
        this.getUIContext().getPromptAction().showToast({
          message: `这几天排不下 ${shortfall} 个景点，可在「编辑行程」里调整或减少`,
          duration: 2600
        });
      }
      this.done = true;
      this.stage = this.stages.length;
      this.progress = 1;
      Logger.info('Ui.Generating', `生成并落库 ${trip.id}`);
      WidgetSync.refreshAll(context).catch((err: Error) => {
        Logger.warn('Ui.Generating', `卡片刷新失败: ${err.message}`);
      });
      APP_NAV.replacePath({ name: 'Itinerary', param: trip.id });
    } catch (err) {
      if (this.cancelled) {
        return;
      }
      const code: number = err instanceof AppError ? (err as AppError).code : 0;
      Logger.error('Ui.Generating', `生成失败 code=${code}: ${(err as Error).message}`);
      this.done = true;
      if (code === ErrorCode.CLOUD_QUOTA_EXHAUSTED) {
        APP_NAV.replacePath({ name: 'Pricing', param: this.localTripId });
        return;
      }
      const info: FailInfo = { code: code, detail: (err as Error).message };
      APP_NAV.replacePath({ name: 'GenerateFailed', param: info });
    }
  }

  @Builder
  skeletonBlock(w: Length, h: number) {
    Column()
      .width(w)
      .height(h)
      // 契约 skeleton：md 圆角、镜像真实行程行（52px 时间块 / 76px 行 / 160px 默认宽）
      .borderRadius(RadiusTokens.reason)
      .backgroundColor(ColorTokens.skeletonBase)
      .opacity(0.6)
  }

  @Builder
  skeletonRow() {
    Row({ space: SpaceTokens.sm }) {
      this.skeletonBlock(LayoutTokens.itineraryTimeGutter, 14)
      Circle()
        .width(LayoutTokens.itineraryNodeSize)
        .height(LayoutTokens.itineraryNodeSize)
        .fill(ColorTokens.skeletonBase)
      Column({ space: SpaceTokens.xs }) {
        this.skeletonBlock(160, 14)
        this.skeletonBlock(56, 10)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .constraintSize({ minHeight: LayoutTokens.itineraryRowMinHeight })
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
          Text(`已选好 ${PlanDraft.get().selectedSpots.length} 个景点 · ${this.areaCount()} 个住宿区域`)
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
            .fontFeature("'tnum' on")
            .margin({ top: SpaceTokens.xs, bottom: SpaceTokens.md })
          Progress({ value: Math.round(this.progress * 100), total: 100, type: ProgressType.Linear })
            .color(ColorTokens.primary)
            .backgroundColor(ColorTokens.surfaceSunken)
            .width('100%')
            .accessibilityText(`生成进度 ${Math.round(this.progress * 100)}%`)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .margin({ top: SpaceTokens.xl })

        Column({ space: SpaceTokens.sm }) {
          ForEach(this.stages, (name: string, idx: number) => {
            Row({ space: SpaceTokens.sm }) {
              SymbolGlyph(idx < this.stage ? $r('sys.symbol.checkmark_circle_fill') :
                (idx === this.stage ? $r('sys.symbol.arrow_clockwise') : $r('sys.symbol.circle')))
                .fontSize(IconSizes.control)
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
          // 文案不绑定传输实现：离线合成与直连 LLM 两种模式下都为真
          Text('正在按你的偏好逐项核对')
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
          // 底稿帧把取消画成 44 高胶囊 + hairline 描边（.btn-cancel），
          // 原来是一条裸 Text 当按钮：既没有钮面也不进命中树的一致行为
          YoujingButton({
            variant: YoujingButtonVariant.SECONDARY,
            label: '取消',
            fullWidth: true,
            onAction: (): void => {
              APP_NAV.pop();
            }
          })
        }
        .width('100%')
        // 与屏7 同一处漏网：钉底的「取消」只留 xl(24)，这一屏也挂在悬浮 dock 上
        .padding({ bottom: LayoutTokens.floatingDockClearance })
      }
      .width('100%')
      .height('100%')
      .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })
      .backgroundColor(ColorTokens.canvas)
    }
    // HDS 深色档这层默认纯黑，透明栏会把它露成一条比画布暗一档的带（成因与实测见 Docs/INIT_REPORT.md §5ci 续 80）
    .backgroundColor(ColorTokens.canvas)
    // 本页只有骨架屏、没有纵向滚动容器 ⇒ 关滚动特效，避免静止态空糊
    .titleBar(HdsChrome.bar({ mainTitle: '生成行程', scrollable: false }))
    .titleMode(HdsNavDestinationTitleMode.MINI)
  }

  private daysCount(): number {
    const b: TripBasicInput = PlanDraft.get().basic;
    return DateUtils.spanDays(b.startDate, b.endDate);
  }

  /**
   * 住宿区域个数取草稿真值。原来这里写死「1 个住宿区域」（帧的 mock 是 2 个），
   * 深链直启或用户没走完屏5 时会报出一个不存在的已选区域。
   * 模型里 selectedArea 是单个（不是多选），所以这个数最多是 1。
   */
  private areaCount(): number {
    return PlanDraft.get().selectedArea.areaId.length > 0 ? 1 : 0;
  }
}
