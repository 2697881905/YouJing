/**
 * 屏4 景点挑选与优先级（帧 7d6e58d6）——真数据版（阶段 7）。
 * 数据源 PlanRepository（USE_MOCK_DATA 路由，京都走 mock 兜底、四城走 RDB 种子）。
 * 交互：点行循环 未选→必去→想去→可选→未选；「推荐更多」按热度补拉；
 * 容量提示：已选 > 天数×4 显示时间偏紧 advisory（§4.1-3）。
 * §10 必改保持：底栏实色悬浮、CTA 距底 ≥16、状态栏无玻璃。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { ShadowTokens } from '../design/ShadowTokens';
import { Spot, SpotTag } from '../model/Spot';
import { PlanRepository } from '../data/PlanRepository';
import { PlanDraft } from '../data/PlanDraft';
import { SelectedSpot, SpotPriority, TripBasicInput } from '../model/PlanParams';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { common } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import type { HdsNavigationMenuItemOptions, HdsNavigationTitleBarOptions } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';

interface SpotGroup {
  label: string;
  spots: Spot[];
}

const TAG_LABELS: string[] = ['必去', '经典', '小众', '亲子'];

@Component
export struct SpotPickPage {
  private pathStack: NavPathStack = APP_NAV;
  @StorageProp('isDarkMode') isDark: boolean = false;
  @State private groups: SpotGroup[] = [];
  @State private all: Spot[] = [];
  @State private priorities: SelectedSpot[] = [];
  private days: number = 3;

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const b: TripBasicInput = PlanDraft.get().basic;
    this.days = Math.max(1, Math.round((Date.parse(b.endDate) - Date.parse(b.startDate)) / 86400000) + 1);
    PlanRepository.loadSpots(ctx, b.destination).then((spots: Spot[]) => {
      this.all = spots;
      this.rebuildGroups(spots);
    });
  }

  private rebuildGroups(spots: Spot[]): void {
    const out: SpotGroup[] = [];
    for (let i = 0; i < TAG_LABELS.length; i++) {
      const tag: SpotTag = [SpotTag.MUST_SEE, SpotTag.CLASSIC, SpotTag.NICHE, SpotTag.FAMILY][i];
      const inTag: Spot[] = spots.filter((s: Spot): boolean => s.tags.indexOf(tag) >= 0);
      if (inTag.length > 0) {
        const g: SpotGroup = { label: TAG_LABELS[i], spots: inTag };
        out.push(g);
      }
    }
    this.groups = out;
  }

  private priorityOf(id: string): SpotPriority | undefined {
    const hit: SelectedSpot | undefined = this.priorities.find((p: SelectedSpot): boolean => p.spotId === id);
    return hit === undefined ? undefined : hit.priority;
  }

  private cycle(id: string): void {
    const next: SelectedSpot[] = this.priorities.slice();
    const idx: number = next.findIndex((p: SelectedSpot): boolean => p.spotId === id);
    const order: SpotPriority[] = [SpotPriority.MUST, SpotPriority.WANT, SpotPriority.OPTIONAL];
    if (idx < 0) {
      const sel: SelectedSpot = { spotId: id, priority: SpotPriority.MUST };
      next.push(sel);
    } else {
      const at: number = order.indexOf(next[idx].priority);
      if (at >= order.length - 1) {
        next.splice(idx, 1);
      } else {
        const updated: SelectedSpot = { spotId: id, priority: order[at + 1] };
        next.splice(idx, 1, updated);
      }
    }
    this.priorities = next;
  }

  private markMore(): void {
    const picked: number = this.priorities.length;
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
    if (added === 0 && picked >= 0) {
      // 已全部标注，无更多可推荐
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
    this.pathStack.pushPath({ name: 'StayPick' });
  }

  @Builder
  groupHeader(label: string, count: number) {
    Text(`${label} · ${count}`)
      .fontSize(TypeTokens.overline.size)
      .fontWeight(600)
      .fontColor(ColorTokens.muted)
      .width('100%')
      .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.xs })
  }

  @Builder
  spotRow(sp: Spot) {
    Row({ space: SpaceTokens.md }) {
      Column()
        .width(36)
        .height(48)
        .borderRadius(RadiusTokens.media)
        .backgroundColor(ColorTokens.surfaceSunken)
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
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

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
    .width('100%')
    .constraintSize({ minHeight: LayoutTokens.itineraryRowMinHeight })
    .padding({ left: SpaceTokens.md, right: SpaceTokens.md, top: SpaceTokens.md, bottom: SpaceTokens.md })
    .onClick(() => {
      this.cycle(sp.id);
    })
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

          Column({ space: SpaceTokens.xs }) {
            Text(`已选 ${this.priorities.length} / 可用 ${this.days}.0 天 · 建议上限 ${this.days * 4} 个`)
              .fontSize(TypeTokens.caption.size)
              .fontWeight(450)
              .fontColor(ColorTokens.body)
              .fontFeature("'tnum' on")
            Progress({
              value: Math.round(this.priorities.length * 100 / Math.max(1, this.days * 4)),
              total: 100,
              type: ProgressType.Linear
            })
              .color(ColorTokens.primary)
              .width('100%')
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .height(56)
          .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })
          .backgroundColor(ColorTokens.surfacePanel)

          // 官方 List + ListItemGroup：分组头吸顶，行间不再手画 Divider
          List({ space: 12 }) {
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
              ListItemGroup({ header: this.groupHeader(group.label, group.spots.length) }) {
                ForEach(group.spots, (sp: Spot) => {
                  ListItem() {
                    this.spotRow(sp)
                  }
                }, (sp: Spot): string => `spot-${sp.id}-${this.priorityOf(sp.id)}`)
              }
              .divider({ strokeWidth: LayoutTokens.hairlineWidth, color: ColorTokens.separator })
              .backgroundColor(ColorTokens.canvas)
              .borderRadius(RadiusTokens.card)
              .clip(true)
            }, (group: SpotGroup): string => `grp-${group.label}-${group.spots.length}`)
          }
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .sticky(StickyStyle.Header)
          .cachedCount(6)
          .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, bottom: 110 })
          .layoutWeight(1)
        }
        .width('100%')
        .height('100%')

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
            YoujingButton({
              variant: YoujingButtonVariant.PRIMARY,
              label: '确认选择',
              onAction: (): void => {
                this.confirm();
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
    .titleBar(this.titleBarOptions())
    .titleMode(HdsNavDestinationTitleMode.MINI)
  }
}
