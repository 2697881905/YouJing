/**
 * 屏4 景点挑选与优先级（帧 7d6e58d6）——真数据版（阶段 7）。
 * 数据源 PlanRepository（USE_MOCK_DATA 路由，京都走 mock 演示、四城走 RDB 种子）。
 * 交互：点行循环 未选→必去→想去→可选→未选；「推荐更多」按热度补拉；
 * 容量提示：已选 > 天数×4 显示时间偏紧 advisory（§4.1-3）。
 * §3.3 第一层（App 端规则筛选）：每个标签组按热度取前 revealCap 个，
 * 「推荐更多」同时放宽展示上限并补选；不把 32 个景点一次全摊给用户。
 * §10 必改保持：底栏实色悬浮、CTA 距底 ≥16、状态栏无玻璃。
 */

import { APP_NAV, markDraftDirty } from '../common/constants/AppNav';
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
import { DateUtils } from '../utils/DateUtils';
import { Logger } from '../common/logger/Logger';
import { KEY_CURRENT_BREAKPOINT } from '../utils/breakpointCenter';
import { listLanesForBreakpoint } from '../utils/responsive';
import { getMenuImmersiveMaterial } from '../utils/immersiveMaterial';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { common } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import type { HdsNavigationMenuItemOptions, HdsNavigationTitleBarOptions } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';
import { isMapCity } from '../common/constants/Cities';

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
  /** 断点（唯一来源 utils/breakpointCenter.ets）：宽屏下列表并成多栏，不再被整屏拉宽 */
  @StorageProp(KEY_CURRENT_BREAKPOINT) bp: string = 'sm';

  private pathStack: NavPathStack = APP_NAV;
  @State private groups: SpotGroup[] = [];
  @State private all: Spot[] = [];
  @State private priorities: SelectedSpot[] = [];
  @State private revealCap: number = REVEAL_CAP;
  @State private loaded: boolean = false;
  /** Map Kit 城市：空态/重试/来源提示与种子城市分开说 */
  @State private mapCity: boolean = false;
  @State private loadFailed: boolean = false;
  private destination: string = '';
  private days: number = 3;

  aboutToAppear(): void {
    this.load();
  }

  private load(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const b: TripBasicInput = PlanDraft.get().basic;
    this.days = DateUtils.spanDays(b.startDate, b.endDate);
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
    }).catch((err: Error) => {
      this.loaded = true;
      this.loadFailed = true;
      Logger.error('Ui.SpotPick', `景点库加载失败: ${err.message}`);
    });
  }

  /** 每组按热度降序取前 revealCap 个（§3.3 第一层精简列表） */
  private rebuildGroups(spots: Spot[]): void {
    const byPop: Spot[] = spots.slice().sort((a: Spot, b: Spot): number => b.popularity - a.popularity);
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
      final = this.all.slice(0, 8).map((s: Spot, i: number): SelectedSpot => {
        const sel: SelectedSpot = { spotId: s.id, priority: i < 3 ? SpotPriority.MUST : SpotPriority.WANT };
        return sel;
      });
    }
    PlanDraft.get().selectedSpots = final;
    markDraftDirty(true);
    this.pathStack.pushPath({ name: 'StayPick' });
  }

  @Builder
  groupHeader(group: SpotGroup) {
    Text(group.spots.length < group.total
      ? `${group.label} · ${group.spots.length}/${group.total}`
      : `${group.label} · ${group.total}`)
      .fontSize(TypeTokens.overline.size)
      .fontWeight(600)
      .fontColor(ColorTokens.muted)
      .width('100%')
      .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.xs })
  }

  @Builder
  spotRow(sp: Spot) {
    Row({ space: SpaceTokens.md }) {
      // 原来行首挂着一块 36×48 的 surfaceSunken 缩略位，但这一屏从头到尾
      // 没有任何 Image() ——`Spot` 契约里没有图片字段，它永远是空的灰块，
      // 实拍就是每行左边一条对不上内容的深色矩形。
      // 与屏8 行内、屏10 面板、屏16 行程纸同一判据：装饰件永远没有内容就删
      Column() {
        Row({ space: SpaceTokens.sm }) {
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
              .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm })
              .borderRadius(RadiusTokens.pill)
              .backgroundColor(ColorTokens.warning)
          }
        }
        Text(`${sp.district} · 建议停留 ${Math.floor(sp.suggestedDuration / 60)}小时${sp.suggestedDuration % 60 > 0 ? `${sp.suggestedDuration % 60}分钟` : ''}`)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .fontFeature("'tnum' on")
          .margin({ top: SpaceTokens.xs })
        if (sp.openingHours !== undefined && sp.openingHours.length > 0) {
          // 只展示各天一致的时段；不一致/闭馆/没有数据时这里不出现，统一以官方为准
          Text(`开放 ${sp.openingHours} · 地图服务`)
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.body)
            .fontFeature("'tnum' on")
            .margin({ top: SpaceTokens.xs })
        }
        // 预约硬信息口径（§3.2/§7）：标注「以官方为准」，不放任用户当成实时准确
        if (sp.booking.requiresBooking) {
          Text('预约规则以官方为准')
            .fontSize(TypeTokens.overline.size)
            .fontWeight(400)
            .fontColor(ColorTokens.muted)
            .margin({ top: SpaceTokens.xs })
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
    .constraintSize({ minHeight: LayoutTokens.itineraryRowMinHeight })
    .padding({ left: SpaceTokens.md, right: SpaceTokens.md, top: SpaceTokens.md, bottom: SpaceTokens.md })
  }

  private backToInput(): void {
    if (this.pathStack.popToName('TripInput') < 0) {
      this.pathStack.pushPath({ name: 'TripInput' });
    }
  }

  @Builder
  mapSourceNotice() {
    Column({ space: SpaceTokens.xs }) {
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
    .padding(SpaceTokens.md)
    .borderRadius(RadiusTokens.reason)
    .backgroundColor(ColorTokens.surfacePanel)
    .margin({ top: SpaceTokens.sm })
  }

  @Builder
  emptyState() {
    Column({ space: SpaceTokens.md }) {
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
      Text(this.mapCity ? '检查网络后重试，或换一座城市' : '首批支持北京、上海、广州、深圳，换一座城市试试')
        .fontSize(TypeTokens.small.size)
        .fontColor(ColorTokens.muted)
        .textAlign(TextAlign.Center)
      if (this.mapCity) {
        Row({ space: SpaceTokens.md }) {
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
    .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })
  }

  /** 官方标题栏：动作走 content.menu，不再自绘 SymbolGlyph + onClick */
  private titleBarOptions(): HdsNavigationTitleBarOptions {
    const items: Array<HdsNavigationMenuItemOptions> = [HdsChrome.item(
      $r('sys.symbol.plus'), '推荐更多', (): void => {
        this.markMore();
      })];
    return HdsChrome.bar({ mainTitle: '选想去的地方', menu: items });
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
          .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg,
            top: SpaceTokens.md, bottom: SpaceTokens.md })


          if (this.loaded && this.all.length === 0) {
            this.emptyState()
          } else {
            if (this.mapCity) {
              Column() {
                this.mapSourceNotice()
              }
              .width('100%')
              .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })
            }
            Column({ space: SpaceTokens.xs }) {
              Text(`已选 ${this.priorities.length} / 可用 ${this.days} 天 · 建议上限 ${this.days * 4} 个`)
                .fontSize(TypeTokens.caption.size)
                .fontWeight(450)
                .fontColor(ColorTokens.body)
                .fontFeature("'tnum' on")
              // 这一屏的核心动作只有一个入口：行右侧那枚 24vp 的空圆环。
              // 整行刻意不可点（源码写明「点名字就改了优先级」会误触），
              // 于是新用户站在这屏不知道该怎么"选"——给一条只在没选过时出现的引导
              if (this.priorities.length === 0) {
                Text('点每行右侧的圆环，标记必去 / 想去 / 可去')
                  .fontSize(TypeTokens.overline.size)
                  .fontWeight(450)
                  .fontColor(ColorTokens.muted)
              }
              Progress({
                value: Math.round(this.priorities.length * 100 / Math.max(1, this.days * 4)),
                total: 100,
                type: ProgressType.Linear
              })
                .color(ColorTokens.primary)
                .backgroundColor(ColorTokens.surfaceSunken)
                .width('100%')
                // 进度条不给可及名时，读屏念的是框架的「100.000000」——
                // 这一屏 dumpLayout 里就是这么显示的，等于把内部比例甩给使用者
                .accessibilityText(`已选 ${this.priorities.length} 个景点，` +
                  `按 ${this.days} 天建议上限 ${this.days * 4} 个`)
            }
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            // 原来钉死 height(56)：内容（16 文字 + 4 间距 + 进度条）居中后
            // 进度条正好压在灰带下沿上，实拍读起来像这条带被裁了一半
            .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg,
              top: SpaceTokens.md, bottom: SpaceTokens.md })
            .backgroundColor(ColorTokens.surfacePanel)

            // 官方 List + ListItemGroup：分组头吸顶，组间靠留白分隔（禁令 12：不画分隔线）
            List({ space: SpaceTokens.md }) {
              if (this.priorities.length > this.days * 4) {
                ListItem() {
                  Column({ space: SpaceTokens.xs }) {
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
                  .padding(SpaceTokens.md)
                  .borderRadius(RadiusTokens.reason)
                  .backgroundColor(ColorTokens.surfacePanel)
                }
              }

              ForEach(this.groups, (group: SpotGroup) => {
                ListItemGroup({ header: this.groupHeader(group) }) {
                  ForEach(group.spots, (sp: Spot) => {
                    ListItem() {
                      this.spotRow(sp)
                    }
                  }, (sp: Spot): string => `spot-${sp.id}`)
                }
                .backgroundColor(ColorTokens.canvas)
                .borderRadius(RadiusTokens.card)
                .clip(true)
              }, (group: SpotGroup): string => `grp-${group.label}-${this.revealCap}`)
            }
            .lanes(listLanesForBreakpoint(this.bp))
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
            .sticky(StickyStyle.Header)
            .cachedCount(6)
            // 滚动预留跟着钉底条抬高的一档补回来
            .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg,
              bottom: LayoutTokens.stickyBarScrollReserve + LayoutTokens.floatingDockClearance })
            .layoutWeight(1)
          }
        }
        .width('100%')
        .height('100%')

        if (this.all.length > 0) {
          Column() {
            Row({ space: SpaceTokens.md }) {
              YoujingButton({
                variant: YoujingButtonVariant.SECONDARY,
                label: '跳过选择',
                buttonWidth: 120,
                onAction: (): void => {
                  this.confirm();
                }
              })
              // 权重给原生包装层，自定义组件上的 .layoutWeight 不生效（屏5/屏9 同族）
              Column() {
                YoujingButton({
                  variant: YoujingButtonVariant.PRIMARY,
                  label: '确认选择',
                  fullWidth: true,
                  onAction: (): void => {
                    this.confirm();
                  }
                })
              }
              .layoutWeight(1)
            }
          }
          .width('100%')
          // 吸底 CTA 条让位实测 dock 净空（原来只有 lg=16，按钮下沿藏在 dock 底下）
          .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, top: SpaceTokens.md,
            bottom: LayoutTokens.floatingDockClearance })
          .backgroundColor(ColorTokens.canvas)
        }
      }
    }
    .titleBar(this.titleBarOptions())
    .titleMode(HdsNavDestinationTitleMode.MINI)
  }
}
