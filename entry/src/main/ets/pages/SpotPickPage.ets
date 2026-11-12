/**
 * 屏4 景点挑选与优先级（帧 7d6e58d6）——真数据版（阶段 7）。
 * 数据源 PlanRepository（USE_MOCK_DATA 路由，京都走 mock 演示、四城走 RDB 种子）。
 * 交互：点行循环 未选→必去→想去→可选→未选；「推荐更多」按热度补拉；
 * 容量提示：已选 > 天数×4 显示时间偏紧 advisory（§4.1-3）。
 * §3.3 第一层（App 端规则筛选）：每个标签组按热度取前 revealCap 个，
 * 「推荐更多」同时放宽展示上限并补选；不把 32 个景点一次全摊给用户。
 * §10 必改保持：底栏实色悬浮、CTA 距底 ≥16、状态栏无玻璃。
 */

import { HOST_NAV, markDraftDirty } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { FlowSteps, FLOW_STEP_SPOT_PICK } from '../components/FlowSteps';
import { Spot, SpotTag } from '../model/Spot';
import { PlanRepository } from '../data/PlanRepository';
import { PlanDraft } from '../data/PlanDraft';
import { SelectedSpot, SpotPriority, TripBasicInput } from '../model/PlanParams';
import { PlanAutoPick } from '../utils/PlanAutoPick';
import { PickClient } from '../ai/PickClient';
import { PickCandidate, PickRankItem, PickResult } from '../model/Pick';
import { DateUtils } from '../utils/DateUtils';
import { Logger } from '../common/logger/Logger';
import { KEY_CURRENT_BREAKPOINT } from '../utils/breakpointCenter';
import { listLanesForBreakpoint } from '../utils/responsive';
import { getMenuImmersiveMaterial } from '../utils/immersiveMaterial';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { common } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode, HideMode } from '@kit.UIDesignKit';
import type { HdsNavigationMenuItemOptions, HdsNavigationTitleBarOptions } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';
import { isMapCity, seedCityListText } from '../common/constants/Cities';
import { DurationCn } from '../utils/DurationCn';
import { requestSystemBarRefresh } from '../utils/systemBar';

interface SpotGroup {
  label: string;
  spots: Spot[];
  /** 该标签在库中的总数（截断展示时 header 显示 shown/total） */
  total: number;
}

const TAG_LABELS: string[] = ['必去', '经典', '小众', '亲子', '其他'];
const KNOWN_TAGS: SpotTag[] = [SpotTag.MUST_SEE, SpotTag.CLASSIC, SpotTag.NICHE, SpotTag.FAMILY];
/** 每组默认展示个数（§3.3 第一层：每组取热度最高的 N 个） */
const REVEAL_CAP: number = 8;
/** 「推荐更多」每次放宽的展示个数 */
const REVEAL_STEP: number = 4;

@Component
export struct SpotPickPage {
  // 深浅档代 tick：翻档时 EntryAbility 自增，@StorageProp 变化带动本页 build 重跑，
  // 把新 tick 传进 HdsChrome.bar → 标题内容换新 ComponentContent 重挂载、按当前档重解色
  // （官方 HdsTitleBar 自绘内容不随配置切换重渲染，真机实证见 HdsChrome.themeTick）
  @StorageProp('chromeThemeTick') chromeThemeTick: number = 0;

  /** 断点（唯一来源 utils/breakpointCenter.ets）：宽屏下列表并成多栏，不再被整屏拉宽 */
  @StorageProp(KEY_CURRENT_BREAKPOINT) bp: string = 'sm';

  // 二级页全屏化（2026-11-11）：本页固定落宿主栈，push StayPick 同栈
  private pathStack: NavPathStack = HOST_NAV;
  @State private groups: SpotGroup[] = [];
  @State private all: Spot[] = [];
  @State private priorities: SelectedSpot[] = [];
  @State private revealCap: number = REVEAL_CAP;
  @State private loaded: boolean = false;
  /** Map Kit 城市：空态/重试/来源提示与种子城市分开说 */
  @State private mapCity: boolean = false;
  @State private loadFailed: boolean = false;
  /** 顶栏磨砂两态：由**绝对**滚动偏移驱动（每帧增量会被松手回弹的负帧打灭，契约 §Translucency） */
  @State private barScrolled: boolean = false;
  private barScroller: Scroller = new Scroller();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  private destination: string = '';
  private days: number = 3;
  /**
   * 建议上限 = 天数 × 节奏档每日上限。四处提示（计数行 / 进度环 / 无障碍名 / 超量 advisory）
   * 原来各写一遍 `days * 4`，**完全忽略用户选的节奏**：轻松档每天 3 站却被劝到 4，
   * 紧凑档每天 6 站却被当成超量。口径取 `PaceRule.dailyCap`（与预选、生成器同一处）。
   */
  private capacity: number = 0;
  /** AI 精选结果：id → 排名；请求失败时保持空，列表仍按热度确定性排序 */
  private pickRank: Map<string, number> = new Map();
  @State private reasons: Record<string, string> = {};
  @State private aiNote: string = '';

  aboutToAppear(): void {
    this.load();
  }

  private load(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const b: TripBasicInput = PlanDraft.get().basic;
    // 空日期按屏2 的默认档算，不能让 spanDays('','') 把 3 天行程读成 1 天（§5ci 续 189）
    this.days = PlanDraft.days(b);
    this.capacity = PlanAutoPick.capacityOf(this.days, PlanDraft.get().paces);
    this.destination = b.destination;
    this.mapCity = isMapCity(b.destination);
    this.loaded = false;
    this.loadFailed = false;
    PlanRepository.loadSpots(ctx, b.destination).then((spots: Spot[]) => {
      this.all = spots;
      // 回退到这一屏时保住已标的景点：`confirm()`(:181) 把选择写进了草稿，
      // 但这里原来不读回来——去屏5 再退回来，圆环全空、底部计数归 0
      const kept: SelectedSpot[] = PlanDraft.get().selectedSpots.filter((p: SelectedSpot): boolean =>
        spots.some((s: Spot): boolean => s.id === p.spotId));
      this.priorities = kept;
      this.rebuildGroups(spots);
      this.loaded = true;
      this.requestPick(spots);
    }).catch((err: Error) => {
      this.loaded = true;
      this.loadFailed = true;
      Logger.error('Ui.SpotPick', `景点库加载失败: ${err.message}`);
    });
  }

  /** 每组按热度降序取前 revealCap 个（§3.3 第一层精简列表） */
  private rebuildGroups(spots: Spot[]): void {
    // AI 精选有排名就按排名；没有排名（请求中/失败）才退回热度——两条路都不空屏
    const byPop: Spot[] = spots.slice().sort((a: Spot, b: Spot): number => {
      const ra: number | undefined = this.pickRank.get(a.id);
      const rb: number | undefined = this.pickRank.get(b.id);
      if (ra !== undefined && rb !== undefined) {
        return ra - rb;
      }
      if (ra !== undefined) {
        return -1;
      }
      if (rb !== undefined) {
        return 1;
      }
      return b.popularity - a.popularity;
    });
    const out: SpotGroup[] = [];
    for (let i = 0; i < TAG_LABELS.length; i++) {
      let inTag: Spot[];
      if (i < KNOWN_TAGS.length) {
        const tag: SpotTag = KNOWN_TAGS[i];
        inTag = byPop.filter((s: Spot): boolean => s.tags.indexOf(tag) >= 0);
      } else {
        // Map Kit 的 POI 类型映射不到四值时进「其他」，不能被分组吞掉
        inTag = byPop.filter((s: Spot): boolean => !this.hasKnownTag(s));
      }
      if (inTag.length > 0) {
        const g: SpotGroup = {
          label: TAG_LABELS[i],
          spots: inTag.slice(0, this.revealCap),
          total: inTag.length
        };
        out.push(g);
      }
    }
    this.groups = out;
  }

  /** AI 精选异步请求：不挡首屏，失败就保留热度排序 */
  private requestPick(spots: Spot[]): void {
    const draft: PlanDraft = PlanDraft.get();
    const candidates: PickCandidate[] = spots.map((s: Spot): PickCandidate => {
      const item: PickCandidate = {
        id: s.id, name: s.name, tag: this.tagTextOf(s), brief: s.brief,
        district: s.district, popularity: s.popularity,
        suggestedDuration: s.suggestedDuration, requiresBooking: s.booking.requiresBooking
      };
      return item;
    });
    const interests: string = `${draft.style}/${draft.paces.join('/')}`;
    PickClient.pickSpots(draft.basic.destination, this.days, draft.paces.join('/'), interests, candidates)
      .then((result: PickResult | null): void => {
        if (result === null) {
          return;
        }
        this.applyPick(result, spots);
      }).catch((err: Error): void => {
        Logger.warn('Ui.SpotPick', `AI 精选失败，保留确定性规则: ${err.message}`);
      });
  }

  private applyPick(result: PickResult, spots: Spot[]): void {
    const rank: Map<string, number> = new Map();
    const reasons: Record<string, string> = {};
    for (let i = 0; i < result.ranked.length; i++) {
      const item: PickRankItem = result.ranked[i];
      rank.set(item.id, i);
      if (item.reason.length > 0) {
        reasons[item.id] = item.reason;
      }
    }
    this.pickRank = rank;
    this.reasons = reasons;
    this.aiNote = result.note;
    this.rebuildGroups(spots);
    Logger.info('Ui.SpotPick', `AI 精选已应用 rank=${rank.size} reasons=${Object.keys(reasons).length}`);
  }

  private tagTextOf(spot: Spot): string {
    const labels: string[] = [];
    for (let i = 0; i < KNOWN_TAGS.length; i++) {
      if (spot.tags.indexOf(KNOWN_TAGS[i]) >= 0) {
        labels.push(TAG_LABELS[i]);
      }
    }
    return labels.length > 0 ? labels.join('/') : '其他';
  }

  private hasKnownTag(sp: Spot): boolean {
    for (const tag of KNOWN_TAGS) {
      if (sp.tags.indexOf(tag) >= 0) {
        return true;
      }
    }
    return false;
  }

  private priorityOf(id: string): SpotPriority | undefined {
    const hit: SelectedSpot | undefined = this.priorities.find((p: SelectedSpot): boolean => p.spotId === id);
    return hit === undefined ? undefined : hit.priority;
  }

  private priorityMenu(id: string): MenuElement[] {
    const mk = (label: string, p: SpotPriority | undefined): MenuElement => ({
      value: label,
      action: (): void => {
        this.setPriority(id, p);
      }
    });
    return [
      // 菜单项一律带动词前缀：分组头的「必去 · 7」是**景点库的 SpotTag 分类**
      // （库里 7 个标了必去），而这里是**用户要做的标记动作**——
      // 同一个词在一屏里指两件事，实拍读起来就是「必去·7 却已选 0」的矛盾。
      // 底稿帧本来写的就是 aria-label="设为必去"，实现时把「设为」丢了，补回来
      mk('设为必去', SpotPriority.MUST),
      mk('设为想去', SpotPriority.WANT),
      mk('设为可去', SpotPriority.OPTIONAL),
      mk('取消标记', undefined)
    ];
  }

  private priorityName(id: string): string {
    const p: SpotPriority | undefined = this.priorityOf(id);
    if (p === SpotPriority.MUST) {
      return '必去';
    }
    if (p === SpotPriority.WANT) {
      return '想去';
    }
    if (p === SpotPriority.OPTIONAL) {
      return '可去';
    }
    return '未标记';
  }

  private setPriority(id: string, want: SpotPriority | undefined): void {
    const next: SelectedSpot[] = this.priorities.slice();
    const idx: number = next.findIndex((row: SelectedSpot): boolean => row.spotId === id);
    if (want === undefined) {
      if (idx >= 0) {
        next.splice(idx, 1);
      }
    } else if (idx < 0) {
      next.push({ spotId: id, priority: want });
    } else {
      next.splice(idx, 1, { spotId: id, priority: want } as SelectedSpot);
    }
    this.priorities = next;
  }

  /**
   * 「推荐更多」：既放宽每组展示上限（让新推荐的景点看得见），
   * 也按热度补选 4 个未选景点（§4.1-3「AI 从内置库挖掘符合偏好的景点」的规则版替身；
   * LLM 通道就绪前不谎报是 AI 选的）。
   */
  private markMore(): void {
    this.revealCap += REVEAL_STEP;
    this.rebuildGroups(this.all);
    const next: SelectedSpot[] = this.priorities.slice();
    let added: number = 0;
    for (const s of this.all) {
      if (added >= 4) {
        break;
      }
      if (this.priorityOf(s.id) === undefined) {
        const sel: SelectedSpot = { spotId: s.id, priority: SpotPriority.WANT };
        next.push(sel);
        added += 1;
      }
    }
    this.priorities = next;
    if (added === 0) {
      this.getUIContext().getPromptAction().showToast({
        message: '库里的景点都已推荐过了', duration: 1800
      });
    }
  }

  private confirm(): void {
    let final: SelectedSpot[] = this.priorities;
    if (final.length === 0) {
      this.getUIContext().getPromptAction().showToast({
        message: '已为你自动选了前 8 个热门景点', duration: 1800
      });
      final = this.all.slice(0, 8).map((s: Spot, i: number): SelectedSpot => {
        const sel: SelectedSpot = { spotId: s.id, priority: i < 3 ? SpotPriority.MUST : SpotPriority.WANT };
        return sel;
      });
    }
    PlanDraft.get().selectedSpots = final;
    markDraftDirty(true);
    PlanDraft.flush();
    this.pathStack.pushPath({ name: 'StayPick' });
  }

  @Builder
  selectionSummary() {
    Column({ space: SpaceTokens.xs }) {
      Row({ space: SpaceTokens.xxs }) {
        Text('已选')
          .fontSize(TypeTokens.caption.size)
          .fontColor(ColorTokens.muted)
        Text(`${this.priorities.length}`)
          .fontSize(TypeTokens.title.size)
          .fontWeight(TypeTokens.title.weight)
          .fontFamily(TypeTokens.title.family)
          .fontColor(ColorTokens.primary)
          .fontFeature("'tnum' on")
        Text(`/ ${this.capacity}`)
          .fontSize(TypeTokens.caption.size)
          .fontColor(ColorTokens.muted)
          .fontFeature("'tnum' on")
        Blank()
        Text(`可用 ${this.days} 天`)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.body)
          .padding({ left: SpaceTokens.xs, right: SpaceTokens.xs,
            top: SpaceTokens.xxs, bottom: SpaceTokens.xxs })
          .backgroundColor(ColorTokens.surfaceSubtle)
          .borderRadius(RadiusTokens.pill)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Progress({
        value: Math.round(this.priorities.length * 100 / Math.max(1, this.capacity)),
        total: 100,
        type: ProgressType.Linear
      })
        .color(ColorTokens.primary)
        .backgroundColor(ColorTokens.surfaceSunken)
        .width('100%')
        .accessibilityText(`已选 ${this.priorities.length} 个景点，` +
          `按 ${this.days} 天建议上限 ${this.capacity} 个`)
      if (this.priorities.length === 0) {
        Text('点每行右侧的圆环，标记必去 / 想去 / 可去')
          .fontSize(TypeTokens.overline.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(SpaceTokens.base)
    .backgroundColor(ColorTokens.surfaceElevated)
    .borderRadius(RadiusTokens.card)
    .border({ width: LayoutTokens.hairlineWidth, color: ColorTokens.primaryGlowEdge })
  }

  @Builder
  groupHeader(group: SpotGroup) {
    // 吸顶组头必须有**不透明底板**：sticky(StickyStyle.Header) 的组头压在滚动内容上，裸 Text 没底板
    // 时行文字会从组头底下透出来叠成两行。带高不靠 padding 凑，照有据钉成一条
    // （PublishTagPanel.ets:83-86 `height(segmentedHeight)` + alignItems Center），本仓同值 36。
    Row() {
      Text(group.spots.length < group.total
        ? `${group.label} · ${group.spots.length}/${group.total}`
        : `${group.label} · ${group.total}`)
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
  spotRow(sp: Spot) {
    Row({ space: SpaceTokens.sm }) {
      // 原来行首挂着一块 36×48 的 surfaceSunken 缩略位，但这一屏从头到尾
      // 没有任何 Image() ——`Spot` 契约里没有图片字段，它永远是空的灰块，
      // 实拍就是每行左边一条对不上内容的深色矩形。
      // 与屏8 行内、屏10 面板、屏16 行程纸同一判据：装饰件永远没有内容就删
      Column() {
        Row({ space: SpaceTokens.xs }) {
          Text(sp.name)
            .fontSize(TypeTokens.body.size)
            .fontWeight(600)
            .fontColor(ColorTokens.ink)
          if (sp.booking.requiresBooking) {
            Text('需预约')
              .fontSize(TypeTokens.caption.size)
              .fontWeight(600)
              .fontColor(ColorTokens.onPrimary)
              .height(22)
              .padding({ left: SpaceTokens.xs, right: SpaceTokens.xs })
              .borderRadius(RadiusTokens.pill)
              .backgroundColor(ColorTokens.warning)
          }
        }
        Text(`${sp.district} · 建议停留 ${sp.suggestedDuration > 0 ? DurationCn.text(sp.suggestedDuration) : '—'}`)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .fontFeature("'tnum' on")
          .margin({ top: SpaceTokens.xxs })
        if (this.reasons[sp.id] !== undefined) {
          Text(`推荐：${this.reasons[sp.id]}`)
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.primary)
            .margin({ top: SpaceTokens.xs })
            .padding({ left: SpaceTokens.xs, right: SpaceTokens.xs,
              top: SpaceTokens.xxs, bottom: SpaceTokens.xxs })
            .backgroundColor(ColorTokens.primaryTint)
            .borderRadius(RadiusTokens.reason)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (sp.openingHours !== undefined && sp.openingHours.length > 0) {
          // 只展示各天一致的时段；不一致/闭馆/没有数据时这里不出现，统一以官方为准
          Text(sp.openingHours === '全天开放' ? '全天开放 · 地图服务'
            : `开放 ${sp.openingHours} · 地图服务`)
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.body)
            .fontFeature("'tnum' on")
            .margin({ top: SpaceTokens.xxs })
        }
        // 预约硬信息口径（§3.2/§7）：标注「以官方为准」，不放任用户当成实时准确
        if (sp.booking.requiresBooking) {
          Text('预约规则以官方为准')
            .fontSize(TypeTokens.overline.size)
            .fontWeight(400)
            .fontColor(ColorTokens.muted)
            .margin({ top: SpaceTokens.xxs })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 底稿这格是 `<button class="priority-action" aria-label="设为必去">`：
      // 一个带无障碍动作名的按钮，不是「整行可点」（整行可点会误触，点名字就改了优先级）。
      // 热区收在指示器本身，点开官方 bindMenu 选档。
      Button() {
        Column() {
          if (this.priorityOf(sp.id) === SpotPriority.MUST) {
            Text('必').fontSize(TypeTokens.caption.size).fontWeight(600).fontColor(ColorTokens.onPrimary)
          } else if (this.priorityOf(sp.id) === SpotPriority.WANT) {
            Text('想').fontSize(TypeTokens.caption.size).fontWeight(600).fontColor(ColorTokens.primary)
          } else if (this.priorityOf(sp.id) === SpotPriority.OPTIONAL) {
            Text('可').fontSize(TypeTokens.caption.size).fontWeight(600).fontColor(ColorTokens.muted)
          }
        }
        .width(24)
        .height(24)
        .justifyContent(FlexAlign.Center)
        .borderRadius(RadiusTokens.pill)
        .backgroundColor(this.priorityOf(sp.id) === SpotPriority.MUST ? ColorTokens.bookmark : ColorTokens.canvas)
        .border({
          width: 1,
          color: this.priorityOf(sp.id) === SpotPriority.WANT ? ColorTokens.primary :
            (this.priorityOf(sp.id) === SpotPriority.MUST ? ColorTokens.bookmark : ColorTokens.hairlineStrong),
          radius: RadiusTokens.pill
        })
      }
      .type(ButtonType.Circle)
      .buttonStyle(ButtonStyleMode.TEXTUAL)
      .padding(0)
      .width(LayoutTokens.minTouchTarget)
      .height(LayoutTokens.minTouchTarget)
      .accessibilityText(`选择优先级，当前${this.priorityName(sp.id)}`)
      // 官方下拉菜单：四档一次摊开（原来是"点一下循环一档"，看不见其余选项）。
      // 材质走 MenuOptions.systemMaterial——挂在菜单内容组件上属生效范围外。
      .bindMenu(this.priorityMenu(sp.id), {
        placement: Placement.BottomRight,
        systemMaterial: getMenuImmersiveMaterial()
      } as MenuOptions)
    }
    .width('100%')
    // 行即卡片：elevated 面 + card 圆角 + base 内缩，列表读作可扫读的卡片而非散行
    .padding(SpaceTokens.base)
    .backgroundColor(ColorTokens.surfaceElevated)
    .borderRadius(RadiusTokens.card)
    // List 的 space 不作用于 ListItemGroup 内部，组内卡片需自带下间距，否则紧贴
    .margin({ bottom: SpaceTokens.sm })
  }

  private backToInput(): void {
    this.pathStack.pop();
  }

  @Builder
  mapSourceNotice() {
    Column({ space: SpaceTokens.xxs }) {
      Text('景点来自地图服务')
        .fontSize(TypeTokens.overline.size)
        .fontWeight(600)
        .fontColor(ColorTokens.muted)
      Text('停留时长为估算，预约与开放时间以官方为准')
        .fontSize(TypeTokens.caption.size)
        .fontWeight(450)
        .fontColor(ColorTokens.body)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(SpaceTokens.sm)
    .borderRadius(RadiusTokens.reason)
    .backgroundColor(ColorTokens.surfacePanel)
    .margin({ top: SpaceTokens.xs })
  }

  @Builder
  emptyState() {
    Column({ space: SpaceTokens.sm }) {
      SymbolGlyph($r('sys.symbol.map'))
        .fontSize(IconSizes.display)
        .fontColor([ColorTokens.muted])
      Text(this.mapCity
        ? (this.loadFailed ? `地图服务没取到${this.destination}的景点` :
          `地图服务没有返回${this.destination}的景点`)
        : '还没有这座城市的景点数据')
        .fontSize(TypeTokens.title.size)
        .fontWeight(700)
        .fontFamily(TypeTokens.title.family)
        .fontColor(ColorTokens.ink)
        .textAlign(TextAlign.Center)
      Text(this.mapCity ? '检查网络后重试，或换一座城市'
        : `内置精选景点的城市：${seedCityListText()}；其他城市走地图服务实时取数`)
        .fontSize(TypeTokens.small.size)
        .fontColor(ColorTokens.muted)
        .textAlign(TextAlign.Center)
      if (this.mapCity) {
        Row({ space: SpaceTokens.sm }) {
          YoujingButton({
            variant: YoujingButtonVariant.PRIMARY,
            label: '重试',
            buttonWidth: 120,
            onAction: (): void => {
              this.load();
            }
          })
          YoujingButton({
            variant: YoujingButtonVariant.TEXT,
            label: '换城市',
            buttonWidth: 120,
            onAction: (): void => {
              this.backToInput();
            }
          })
        }
      } else {
        YoujingButton({
          variant: YoujingButtonVariant.PRIMARY,
          label: '换城市',
          buttonWidth: 160,
          onAction: (): void => {
            this.backToInput();
          }
        })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: SpaceTokens.base, right: SpaceTokens.base })
  }

  /** 官方标题栏：动作走 content.menu，不再自绘 SymbolGlyph + onClick */
  private titleBarOptions(): HdsNavigationTitleBarOptions {
    const items: Array<HdsNavigationMenuItemOptions> = [HdsChrome.item(
      $r('sys.symbol.plus'), '推荐更多', (): void => {
        this.markMore();
      })];
    return HdsChrome.bar({ themeTick: this.chromeThemeTick, mainTitle: '选想去的地方', menu: items, scrolled: this.barScrolled });
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

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        Column() {
          // 主链进度：这一屏此前完全不知道自己在这条流程的第几步
          Column() {
            FlowSteps({ step: FLOW_STEP_SPOT_PICK })
          }
          .width('100%')
          // 下方留一档：原来步骤指示与「已选…」灰带贴在一起，两段信息挤成一块
          .padding({ left: SpaceTokens.base, right: SpaceTokens.base,
            top: SpaceTokens.sm, bottom: SpaceTokens.sm })


          if (!this.loaded) {
            Column() {
              LoadingProgress()
                .width(48)
                .height(48)
                .color(ColorTokens.primary)
              Text('正在加载景点…')
                .fontSize(TypeTokens.caption.size)
                .fontColor(ColorTokens.muted)
                .margin({ top: SpaceTokens.sm })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else if (this.all.length === 0) {
            this.emptyState()
          } else {
            if (this.mapCity) {
              Column() {
                this.mapSourceNotice()
              }
              .width('100%')
              .padding({ left: SpaceTokens.base, right: SpaceTokens.base })
            }
            // 官方 List + ListItemGroup：分组头吸顶，组间靠留白分隔（禁令 12：不画分隔线）
            // 头部摘要卡与 AI 洞察卡同为 ListItem：同宽（List 内缩）、同间距（List space）
            List({ space: SpaceTokens.sm, scroller: this.barScroller }) {
              ListItem() {
                this.selectionSummary()
              }
              if (this.priorities.length > this.capacity) {
                ListItem() {
                  Column({ space: SpaceTokens.xxs }) {
                    Text('时间偏紧')
                      .fontSize(TypeTokens.overline.size)
                      .fontWeight(600)
                      .fontColor(ColorTokens.warning)
                    Text('按现在的节奏，建议给景点标优先级，行程会自动取舍')
                      .fontSize(TypeTokens.caption.size)
                      .fontColor(ColorTokens.body)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .width('100%')
                  .padding(SpaceTokens.sm)
                  .borderRadius(RadiusTokens.reason)
                  .backgroundColor(ColorTokens.surfacePanel)
                }
              }

              if (this.aiNote.length > 0) {
                ListItem() {
                  Row({ space: SpaceTokens.sm }) {
                    SymbolGlyph($r('sys.symbol.wand_and_stars'))
                      .fontSize(IconSizes.control)
                      .fontColor([ColorTokens.primary])
                      .padding(SpaceTokens.xs)
                      .backgroundColor(ColorTokens.primaryTint)
                      .borderRadius(RadiusTokens.pill)
                    Column({ space: SpaceTokens.xxs }) {
                      Text('AI 精选')
                        .fontSize(TypeTokens.overline.size)
                        .fontWeight(600)
                        .fontColor(ColorTokens.primary)
                      Text(this.aiNote)
                        .fontSize(TypeTokens.caption.size)
                        .fontWeight(450)
                        .fontColor(ColorTokens.body)
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Top)
                  .padding(SpaceTokens.base)
                  .borderRadius(RadiusTokens.card)
                  .backgroundColor(ColorTokens.surfaceElevated)
                  .border({ width: LayoutTokens.hairlineWidth, color: ColorTokens.primaryGlowEdge })
                }
              }

              ForEach(this.groups, (group: SpotGroup) => {
                ListItemGroup({ header: this.groupHeader(group) }) {
                  ForEach(group.spots, (sp: Spot) => {
                    ListItem() {
                      this.spotRow(sp)
                    }
                    // 理由变化必须换 key，否则 ForEach 复用旧行、AI 理由不落屏
                  }, (sp: Spot): string => `spot-${sp.id}-${this.reasons[sp.id] ?? ''}`)
                }
                .backgroundColor(ColorTokens.canvas)
                .borderRadius(RadiusTokens.card)
                .clip(true)
              }, (group: SpotGroup): string => `grp-${group.label}-${this.revealCap}`)
            }
            .lanes(listLanesForBreakpoint(this.bp))
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
            .sticky(StickyStyle.Header)
            .cachedCount(6)
            // 滚动预留只补吸底 CTA 条本体（2026-11-11 二级页全屏化后 dock 净空作废）
            .padding({ left: SpaceTokens.base, right: SpaceTokens.base,
              bottom: LayoutTokens.stickyBarScrollReserve })
            // 顶部让位已在外层 Column 承担（固定头不让位会叠标题），List 起点不再重复让位
            .contentStartOffset(0)
            .layoutWeight(1)
            .onDidScroll((): void => {
              this.syncBarScroll();
            })
          }
        }
        .width('100%')
        .height('100%')
        // 顶部让位放在外层：FlowSteps 与「已选」灰带是 List 之外的固定头，
        // 不让位会顶到标题栏下与主标题叠字；List 不再重复让位（否则头部下方多空一条缝）
        .padding({ top: HdsChrome.contentTopInset(this.statusBarHeight) })

        if (this.all.length > 0) {
          Column() {
            // IMP-04：原「跳过选择」与「确认选择」同调 confirm()，零选时行为完全相同，
            // 删重复钮；零勾选仍自动选前 8 热门（confirm 内 toast 口径不变）
            YoujingButton({
              variant: YoujingButtonVariant.PRIMARY,
              label: '确认选择',
              fullWidth: true,
              onAction: (): void => {
                this.confirm();
              }
            })
          }
          .width('100%')
          // 吸底 CTA 条原来只留 lg=16，后来让出 dock 净空 112；2026-11-11 二级页全屏化
          // 后 dock 作废，按契约「CTA 距底 ≥16」留一档呼吸
          .padding({ left: SpaceTokens.base, right: SpaceTokens.base, top: SpaceTokens.sm,
            bottom: SpaceTokens.base })
          .backgroundColor(ColorTokens.canvas)
        }
      }
    }
    // 不收栏（2026-11-08）：NavDestination 内容区恒预留 56vp 栏位、收栏后不回收，收起只留一条 175px 白带
    .bindToScrollable([this.barScroller])
    .clip(false)
    // HDS 深色档这层默认纯黑，透明栏会把它露成一条比画布暗一档的带（成因与实测见 Docs/INIT_REPORT.md §5ci 续 80）
    .backgroundColor(ColorTokens.canvas)
    .titleBar(this.titleBarOptions())
    .titleMode(HdsNavDestinationTitleMode.MINI)
  }
}
