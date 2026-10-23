/**
 * 屏9 行程编辑 · 拖动与替换（帧 ebe57eac）。
 * 拖拽配方（有据实证 + 项目记忆）：List.onItemDragStart 自定义拖影、
 * 把手只挂把手、onItemDrop 带 insertIndex 落位（onItemDragEnd 不存在）。
 *
 * 数据（阶段 10 接真）：吃屏8 传进来的 tripId + 当前日，改动在「完成」时整份聚合根回写 RDB。
 * 拖动语义 = 改游览顺序：当日的时间槽不变，节点按新顺序重新占槽
 * （否则把 18:30 的站拖到第二位会留下 09:00→18:30→13:15 的乱序时间线）。
 * 替换语义 = 换节点不换槽：保留该位置的时间、结束时间与到达通勤。
 */

import { APP_NAV, EditTarget } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { Activity, Trip } from '../model/Trip';
import { ActivityCategory, ActivityStatus } from '../model/Trip';
import { Spot } from '../model/Spot';
import { TripDao } from '../data/TripDao';
import { PlanRepository } from '../data/PlanRepository';
import { getSheetImmersiveMaterial } from '../utils/immersiveMaterial';
import { Logger } from '../common/logger/Logger';
import { common } from '@kit.AbilityKit';

@Component
export struct EditItineraryPage {
  private pathStack: NavPathStack = APP_NAV;
  @Prop tripId: string = '';
  @Prop dayIndex: number = 0;
  @State private acts: Activity[] = [];
  @State private dragIdx: number = -1;
  @State private showReplace: boolean = false;
  @State private replaceIdx: number = -1;
  @State private candidates: Spot[] = [];
  private trip: Trip | null = null;

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
    const next: Activity[] = this.acts.slice();
    const moved: Activity = next.splice(from, 1)[0];
    next.splice(to, 0, moved);
    this.acts = next;
    this.reflowTimes();
  }

  private removeAt(idx: number): void {
    const next: Activity[] = this.acts.slice();
    next.splice(idx, 1);
    this.acts = next;
    this.reflowTimes();
  }

  /** 打开替换面板：列本城景点库，排除当日已在的站 */
  private openReplace(idx: number): void {
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

  private applyReplace(spot: Spot): void {
    const idx: number = this.replaceIdx;
    if (idx < 0 || idx >= this.acts.length) {
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
      this.toast(`已保存 ${kept.length} 站`);
      this.pathStack.pop();
    }).catch((err: Error) => {
      Logger.error('Ui.Edit', `保存失败: ${err.message}`);
      this.toast('保存失败，改动未落库');
    });
  }

  @Builder
  handle() {
    Column({ space: 3 }) {
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
    .shadow({ radius: 16, offsetX: 0, offsetY: 6, color: '#17000000' })
  }

  @Builder
  editRow(act: Activity, idx: number) {
    Row({ space: SpaceTokens.sm }) {
      this.handle()
      Text(act.time)
        .width(52)
        .fontSize(TypeTokens.time.size)
        .fontWeight(600)
        .fontColor(this.dragIdx === idx ? ColorTokens.primary : ColorTokens.ink)
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
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.arrow_2_circlepath'))
        .fontSize(22)
        .fontColor([ColorTokens.icon])
        .onClick(() => {
          this.openReplace(idx);
        })
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(22)
        .fontColor([ColorTokens.muted])
        .margin({ left: SpaceTokens.md })
        .onClick(() => {
          this.removeAt(idx);
        })
    }
    .width('100%')
    .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
    .borderRadius(RadiusTokens.card)
    .backgroundColor(this.dragIdx === idx ? ColorTokens.primaryTint : ColorTokens.surfaceElevated)
  }

  @Builder
  replaceSheet() {
    Column() {
      Text('换一个')
        .fontSize(TypeTokens.title.size)
        .fontWeight(700)
        .fontFamily(TypeTokens.title.family)
        .fontColor(ColorTokens.ink)
        .margin({ top: SpaceTokens.xl, bottom: SpaceTokens.xs })
      Text('替换只换站点，该位置的时间与通勤保持不变')
        .fontSize(TypeTokens.caption.size)
        .fontColor(ColorTokens.muted)
        .margin({ bottom: SpaceTokens.md })

      List({ space: SpaceTokens.xs }) {
        ForEach(this.candidates, (spot: Spot) => {
          ListItem() {
            Column({ space: 2 }) {
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
            .onClick(() => {
              this.applyReplace(spot);
            })
          }
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

  build() {
    NavDestination() {
      Column() {
        Row() {
          Text('编辑行程')
            .fontSize(TypeTokens.body.size)
            .fontWeight(600)
            .fontColor(ColorTokens.ink)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          Row({ space: SpaceTokens.xs }) {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(22)
              .fontColor([ColorTokens.primary])
            Text('完成')
              .fontSize(TypeTokens.small.size)
              .fontColor(ColorTokens.primary)
          }
          .onClick((): void => {
            this.finish();
          })
        }
        .height(LayoutTokens.titleBarHeight)
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })

        if (this.acts.length === 0) {
          Column() {
            Text(this.tripId.length === 0 ? '未指定行程' : '当日暂无安排')
              .fontSize(TypeTokens.small.size)
              .fontColor(ColorTokens.muted)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: SpaceTokens.xs }) {
            ForEach(this.acts, (act: Activity, idx: number) => {
              ListItem() {
                this.editRow(act, idx)
              }
            }, (act: Activity): string => `edit-${act.id}-${act.time}-${act.title}`)
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, bottom: LayoutTokens.bottomScrollReserve })
          .onItemDragStart((event: ItemDragInfo, itemIndex: number): CustomBuilder => {
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
    .hideTitleBar(true)
  }
}
