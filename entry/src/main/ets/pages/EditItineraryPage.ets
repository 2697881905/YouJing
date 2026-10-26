/**
 * 屏9 行程编辑 · 拖动与替换（帧 ebe57eac）。
 * 拖拽配方（有据实证 + 项目记忆）：List.onItemDragStart 自定义拖影、
 * 把手只挂把手、onItemDrop 带 insertIndex 落位（onItemDragEnd 不存在）。
 *
 * 数据（RDB 已接真）：吃屏8 传进来的 tripId + 当前日，改动在「完成」时整份聚合根回写 RDB。
 * 拖动语义 = 改游览顺序：当日的时间槽不变，节点按新顺序重新占槽
 * （否则把 18:30 的站拖到第二位会留下 09:00→18:30→13:15 的乱序时间线）。
 * 替换语义 = 换节点不换槽：保留该位置的时间、结束时间与到达通勤。
 */

import { APP_NAV, EditTarget } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { ShadowTokens } from '../design/ShadowTokens';
import { Activity, Trip } from '../model/Trip';
import { ActivityCategory, ActivityStatus } from '../model/Trip';
import { Spot } from '../model/Spot';
import { TripDao } from '../data/TripDao';
import { WidgetSync } from '../widget/TodayCard';
import { PlanRepository } from '../data/PlanRepository';
import { getSheetImmersiveMaterial } from '../utils/immersiveMaterial';
import { Logger } from '../common/logger/Logger';
import { common } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import type { HdsNavigationMenuItemOptions, HdsNavigationTitleBarOptions } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';

@Component
export struct EditItineraryPage {
  private pathStack: NavPathStack = APP_NAV;
  @StorageProp('isDarkMode') isDark: boolean = false;
  @Prop tripId: string = '';
  @Prop dayIndex: number = 0;
  @State private acts: Activity[] = [];
  @State private dragIdx: number = -1;
  @State private showReplace: boolean = false;
  /** -1 = 补选模式（往当日末尾追加），>=0 = 替换该位置 */
  @State private replaceIdx: number = -1;
  @State private candidates: Spot[] = [];
  /** 底稿屏9 声明了「撤销修改」：删除/替换/拖动都是破坏性编辑，没有回退就等于不敢点 */
  private history: Activity[][] = [];
  private trip: Trip | null = null;

  private snapshot(): void {
    this.history.push(this.acts.slice());
  }

  private undo(): void {
    const last: Activity[] | undefined = this.history.pop();
    if (last === undefined) {
      this.toast('还没有可撤销的改动');
      return;
    }
    this.acts = last;
  }

  aboutToAppear(): void {
    if (this.tripId.length === 0) {
      return;
    }
    TripDao.loadTrip(this.ctx(), this.tripId).then((trip: Trip | null): void => {
      if (trip === null || this.dayIndex >= trip.days.length) {
        Logger.warn('Ui.Edit', `行程或当日不存在 trip=${this.tripId} day=${this.dayIndex}`);
        return;
      }
      this.trip = trip;
      this.acts = trip.days[this.dayIndex].activities.slice();
    }).catch((err: Error) => {
      Logger.error('Ui.Edit', `加载失败: ${err.message}`);
    });
  }

  private ctx(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1600 });
  }

  /** 时间槽不变，节点按新顺序重占槽 */
  private reflowTimes(): void {
    const slots: Activity[] = this.acts.slice().sort((a: Activity, b: Activity): number =>
      a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
    const next: Activity[] = this.acts.map((act: Activity, i: number): Activity => {
      const slot: Activity = slots[i];
      const kept: Activity = {
        id: act.id, time: slot.time, endTime: slot.endTime, title: act.title,
        location: act.location, address: act.address, longitude: act.longitude,
        latitude: act.latitude, status: act.status, category: act.category,
        note: act.note, reason: act.reason, transport: act.transport
      };
      return kept;
    });
    this.acts = next;
  }

  private move(from: number, to: number): void {
    if (from === to || from < 0 || to < 0) {
      return;
    }
    this.snapshot();
    const next: Activity[] = this.acts.slice();
    const moved: Activity = next.splice(from, 1)[0];
    next.splice(to, 0, moved);
    this.acts = next;
    this.reflowTimes();
  }

  private removeAt(idx: number): void {
    this.snapshot();
    const next: Activity[] = this.acts.slice();
    next.splice(idx, 1);
    this.acts = next;
    this.reflowTimes();
  }

  /** 打开替换面板：列本城景点库，排除当日已在的站 */
  private openReplace(idx: number): void {
    this.loadCandidates(idx);
  }

  /** 底稿屏9 的「补选景点」：当日只能减不能加是缺通路，复用同一张候选面板 */
  private openAdd(): void {
    this.loadCandidates(-1);
  }

  private loadCandidates(idx: number): void {
    const trip: Trip | null = this.trip;
    if (trip === null) {
      this.toast('行程未就绪');
      return;
    }
    this.replaceIdx = idx;
    PlanRepository.loadSpots(this.ctx(), trip.destination).then((spots: Spot[]): void => {
      const taken: string[] = this.acts.map((a: Activity): string => a.title);
      this.candidates = spots.filter((s: Spot): boolean => taken.indexOf(s.name) < 0);
      this.showReplace = true;
    }).catch((err: Error) => {
      Logger.warn('Ui.Edit', `景点库加载失败: ${err.message}`);
      this.toast('景点库加载失败');
    });
  }

  private static minsOf(hhmm: string): number {
    const parts: string[] = hhmm.split(':');
    if (parts.length < 2) {
      return 9 * 60;
    }
    return Number(parts[0]) * 60 + Number(parts[1]);
  }

  private static hhmm(mins: number): string {
    const clamped: number = Math.max(0, Math.min(23 * 60 + 45, mins));
    const h: string = `${Math.floor(clamped / 60)}`.padStart(2, '0');
    const m: string = `${clamped % 60}`.padStart(2, '0');
    return `${h}:${m}`;
  }

  private applyReplace(spot: Spot): void {
    const idx: number = this.replaceIdx;
    this.snapshot();
    if (idx < 0) {
      this.applyAdd(spot);
      return;
    }
    if (idx >= this.acts.length) {
      return;
    }
    const old: Activity = this.acts[idx];
    const replacement: Activity = {
      id: spot.id, time: old.time, endTime: old.endTime, title: spot.name,
      location: `${spot.city} ${spot.district}`, address: spot.district,
      longitude: spot.longitude, latitude: spot.latitude,
      status: spot.booking.requiresBooking ? ActivityStatus.NOT_BOOKED : ActivityStatus.NO_NEED,
      category: ActivityCategory.SIGHT, note: old.note, reason: old.reason, transport: old.transport
    };
    const next: Activity[] = this.acts.slice();
    next[idx] = replacement;
    this.acts = next;
    this.showReplace = false;
    this.replaceIdx = -1;
  }

  /** 补选：接在当日末尾，开始时间取上一站的结束时间 + 15 分钟缓冲 */
  private applyAdd(spot: Spot): void {
    const acts: Activity[] = this.acts.slice();
    const last: Activity | undefined = acts.length > 0 ? acts[acts.length - 1] : undefined;
    const start: number = last === undefined ? 9 * 60 : EditItineraryPage.minsOf(last.endTime) + 15;
    const added: Activity = {
      id: spot.id, time: EditItineraryPage.hhmm(start),
      endTime: EditItineraryPage.hhmm(start + spot.suggestedDuration),
      title: spot.name,
      location: `${spot.city} ${spot.district}`, address: spot.district,
      longitude: spot.longitude, latitude: spot.latitude,
      status: spot.booking.requiresBooking ? ActivityStatus.NOT_BOOKED : ActivityStatus.NO_NEED,
      category: ActivityCategory.SIGHT,
      note: spot.booking.requiresBooking ? `预约：${spot.booking.bookingMethod ?? '官方渠道'}（以官方为准）` : undefined,
      reason: undefined,
      // 不编通勤腿：补选进来的站点没有真实距离，缺 transport 时时间线本就不画这一段
      transport: undefined
    };
    acts.push(added);
    this.acts = acts;
    this.reflowTimes();
    this.showReplace = false;
    this.replaceIdx = -1;
    this.toast(`已补选 ${spot.name}`);
  }

  /** 完成：回写当日节点并整份聚合根落库 */
  private finish(): void {
    const trip: Trip | null = this.trip;
    if (trip === null || this.dayIndex >= trip.days.length) {
      this.pathStack.pop();
      return;
    }
    const days = trip.days.slice();
    const kept: Activity[] = this.acts.map((a: Activity): Activity => {
      const copy: Activity = {
        id: a.id, time: a.time, endTime: a.endTime, title: a.title, location: a.location,
        address: a.address, longitude: a.longitude, latitude: a.latitude, status: a.status,
        category: a.category, note: a.note, reason: a.reason, transport: a.transport
      };
      return copy;
    });
    days[this.dayIndex].activities = kept;
    const updated: Trip = {
      id: trip.id, destination: trip.destination, startDate: trip.startDate,
      endDate: trip.endDate, people: trip.people, budget: trip.budget, style: trip.style,
      overview: trip.overview, days: days, tips: trip.tips
    };
    TripDao.saveTrip(this.ctx(), updated).then((): void => {
      Logger.info('Ui.Edit', `保存 Day ${this.dayIndex + 1} 共 ${kept.length} 站`);
      WidgetSync.refreshAll(this.ctx()).catch((err: Error) => {
        Logger.warn('Ui.Edit', `卡片刷新失败: ${err.message}`);
      });
      this.toast(`已保存 ${kept.length} 站`);
      this.pathStack.pop();
    }).catch((err: Error) => {
      Logger.error('Ui.Edit', `保存失败: ${err.message}`);
      this.toast('保存失败，改动未落库');
    });
  }

  @Builder
  handle() {
    Column({ space: SpaceTokens.xs }) {
      Row().width(14).height(2).borderRadius(RadiusTokens.pill).backgroundColor(ColorTokens.faint)
      Row().width(14).height(2).borderRadius(RadiusTokens.pill).backgroundColor(ColorTokens.faint)
      Row().width(14).height(2).borderRadius(RadiusTokens.pill).backgroundColor(ColorTokens.faint)
    }
    .width(24)
    .height(LayoutTokens.minTouchTarget)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  rowPreview(act: Activity) {
    Row({ space: SpaceTokens.sm }) {
      Text(act.time)
        .fontSize(TypeTokens.time.size)
        .fontWeight(600)
        .fontColor(ColorTokens.primary)
        .fontFeature("'tnum' on")
      Text(act.title)
        .fontSize(TypeTokens.small.size)
        .fontWeight(600)
        .fontColor(ColorTokens.ink)
    }
    .padding(SpaceTokens.md)
    .borderRadius(RadiusTokens.card)
    .backgroundColor(ColorTokens.canvas)
    .shadow(this.isDark ? { radius: 0 } : ShadowTokens.floating)
  }

  @Builder
  editRow(act: Activity, idx: number) {
    Row({ space: SpaceTokens.sm }) {
      this.handle()
      Text(act.time)
        .width(LayoutTokens.itineraryTimeGutter)
        .fontSize(TypeTokens.time.size)
        .fontWeight(600)
        // 拖动态字色恒为 ink：tint 底上压 primary 蓝字双端 sub-AA（DESIGN §9）；
        // 「正在拖」由 tint 底 + 左侧 primary 竖条表达，不靠蓝字
        .fontColor(ColorTokens.ink)
        .textAlign(TextAlign.End)
        .fontFeature("'tnum' on")
      Column() {
        Text(act.title)
          .fontSize(TypeTokens.small.size)
          .fontWeight(600)
          .fontColor(ColorTokens.ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(act.address.length > 0 ? act.address : act.location)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 底稿这两个动作叫「替换景点 / 移除景点」。原来是裸 SymbolGlyph + onClick：
      // 22px 触点低于平台最小热区，也不可聚焦、读屏念不出动作。
      // 换成官方 Button（Circle + TEXTUAL 档，不出额外表面），图标与配色原样。
      Button() {
        SymbolGlyph($r('sys.symbol.arrow_2_circlepath'))
          .fontSize(IconSizes.control)
          .fontColor([ColorTokens.icon])
      }
      .type(ButtonType.Circle)
      .buttonStyle(ButtonStyleMode.TEXTUAL)
      .padding(0)
      .width(LayoutTokens.minTouchTarget)
      .height(LayoutTokens.minTouchTarget)
      .accessibilityText('替换景点')
      .onClick(() => {
        this.openReplace(idx);
      })

      Button() {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(IconSizes.control)
          .fontColor([ColorTokens.muted])
      }
      .type(ButtonType.Circle)
      .buttonStyle(ButtonStyleMode.TEXTUAL)
      .padding(0)
      .width(LayoutTokens.minTouchTarget)
      .height(LayoutTokens.minTouchTarget)
      .accessibilityText('移除景点')
      .onClick(() => {
        this.removeAt(idx);
      })
    }
    .width('100%')
    .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
    .borderRadius(RadiusTokens.card)
    .backgroundColor(this.dragIdx === idx ? ColorTokens.primaryTint : ColorTokens.surfaceElevated)
    // 拖动态的左竖条：2px primary（契约 route-line 同宽），补上蓝字让位后的状态表达
    .border({
      width: { left: this.dragIdx === idx ? LayoutTokens.routeLineWidth : 0 },
      color: ColorTokens.primary
    })
  }

  @Builder
  replaceSheet() {
    Column() {
      Text(this.replaceIdx < 0 ? '补选景点' : '换一个')
        .fontSize(TypeTokens.title.size)
        .fontWeight(700)
        .fontFamily(TypeTokens.title.family)
        .fontColor(ColorTokens.ink)
        .margin({ top: SpaceTokens.xl, bottom: SpaceTokens.xs })
      Text(this.replaceIdx < 0 ? '补选接在当日末尾，时间与通勤按新顺序重排' :
        '替换只换站点，该位置的时间与通勤保持不变')
        .fontSize(TypeTokens.caption.size)
        .fontColor(ColorTokens.muted)
        .margin({ bottom: SpaceTokens.md })

      List({ space: SpaceTokens.xs }) {
        if (this.candidates.length === 0) {
          // 空态：本城景点库已全部在当日（或库为空），别给一张空 List 不吭声
          ListItem() {
            Column({ space: SpaceTokens.sm }) {
              SymbolGlyph($r('sys.symbol.checkmark_circle'))
                .fontSize(IconSizes.display)
                .fontColor([ColorTokens.muted])
              Text(this.replaceIdx < 0 ? '本城景点都已在这天里了' : '没有可替换的其它景点')
                .fontSize(TypeTokens.small.size)
                .fontColor(ColorTokens.muted)
            }
            .width('100%')
            .padding({ top: SpaceTokens.xl, bottom: SpaceTokens.xl })
            .justifyContent(FlexAlign.Center)
          }
        }
        ForEach(this.candidates, (spot: Spot) => {
          ListItem() {
            // 候选项整块可点：官方 Button 承载（裸 Column 无按压态、读屏进不去）
          Button({ type: ButtonType.Normal, stateEffect: true }) {
          Column() {
              Text(spot.name)
                .fontSize(TypeTokens.small.size)
                .fontWeight(600)
                .fontColor(ColorTokens.ink)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`${spot.district} · 建议 ${Math.round(spot.suggestedDuration / 60 * 10) / 10}小时` +
                `${spot.booking.requiresBooking ? ' · 需预约' : ''}`)
                .fontSize(TypeTokens.caption.size)
                .fontWeight(450)
                .fontColor(ColorTokens.muted)
                .fontFeature("'tnum' on")
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding(SpaceTokens.md)
            .borderRadius(RadiusTokens.card)
            .backgroundColor(ColorTokens.surfacePanel)
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .width('100%')
          .padding(0)
          .borderRadius(RadiusTokens.card)
          .accessibilityText(`替换为 ${spot.name}，${spot.district}`)
          .onClick(() => {
            this.applyReplace(spot);
          })          }
        }, (spot: Spot): string => `rep-${spot.id}`)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
    .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, bottom: SpaceTokens.xl })
    .backgroundColor(ColorTokens.canvas)
  }

  /** 官方标题栏：完成/补选/撤销走 content.menu，不再自绘图标 + 文字按钮 */
  private titleBarOptions(): HdsNavigationTitleBarOptions {
    const items: Array<HdsNavigationMenuItemOptions> = [
      HdsChrome.item($r('sys.symbol.checkmark'), '完成', (): void => {
        this.finish();
      }),
      HdsChrome.item($r('sys.symbol.plus_circle'), '补选景点', (): void => {
        this.openAdd();
      }),
      // 常驻而不是按 canUndo 显隐：HdsNavigation 的 titleBar 不随异步状态重建（屏11 副标题踩过），
      // 动态增减会留下一个永远点不出来的死项，所以空历史时如实提示
      HdsChrome.item($r('sys.symbol.arrow_counterclockwise'), '撤销修改', (): void => {
        this.undo();
      })];
    return HdsChrome.bar({ mainTitle: '编辑行程', menu: items });
  }

  build() {
    HdsNavDestination() {
      Column() {

        if (this.acts.length === 0) {
          // 「未指定行程」是说给开发者听的话：用户站在这屏只知道一片黑，
          // 而顶栏三颗钮（完成/添加/撤销）看着全都能点。改成说清缺什么、去哪儿补
          Column({ space: SpaceTokens.sm }) {
            Text(this.tripId.length === 0 ? '没有带进行程' : '这一天还没有节点')
              .fontSize(TypeTokens.title.size)
              .fontWeight(700)
              .fontFamily(TypeTokens.title.family)
              .fontColor(ColorTokens.ink)
              .textAlign(TextAlign.Center)
            Text(this.tripId.length === 0 ? '从「我的行程」里选一条行程再进来' : '点右上角 ⊕ 可以补选景点')
              .fontSize(TypeTokens.small.size)
              .fontColor(ColorTokens.body)
              .textAlign(TextAlign.Center)
              .constraintSize({ maxWidth: 240 })
          }
          .alignItems(HorizontalAlign.Center)
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: SpaceTokens.xs }) {
            ForEach(this.acts, (act: Activity, idx: number) => {
              ListItem() {
                this.editRow(act, idx)
              }
            // key 只用稳定 id：拖动会改 time，带 time 的 key 会让整项重建、丢掉拖动态
            }, (act: Activity): string => `edit-${act.id}`)
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg,
            bottom: LayoutTokens.floatingDockClearance })
          .onItemDragStart((event: ItemDragInfo, itemIndex: number): CustomBuilder => {
            // 官方 API 限制：onItemDragStart 挂在 List 级（整行长按触发），
            // 与「把手只挂把手」的视觉约定有差距——拖影由本函数自定义，
            // 命中区收窄做不到，靠长按 + 拖影反馈兜底
            this.dragIdx = itemIndex;
            const act: Activity = this.acts[itemIndex];
            return (): void => {
              this.rowPreview(act);
            };
          })
          .onItemDrop((event: ItemDragInfo, itemIndex: number, insertIndex: number,
            isSuccess: boolean): void => {
            if (isSuccess && insertIndex >= 0) {
              this.move(itemIndex, insertIndex > itemIndex ? insertIndex - 1 : insertIndex);
            }
            this.dragIdx = -1;
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ColorTokens.canvas)
      .bindSheet($$this.showReplace, this.replaceSheet(), {
        height: '70%',
        backgroundColor: ColorTokens.canvas,
        showClose: true,
        systemMaterial: getSheetImmersiveMaterial()
      })
    }
    .titleBar(this.titleBarOptions())
    .titleMode(HdsNavDestinationTitleMode.MINI)
  }
}
