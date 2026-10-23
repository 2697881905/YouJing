/**
 * 屏15 旅行中模式（帧 fc4e40cd）。
 * §7 必改已落：badge padding 3→4、check-right gap 6→4、stop-row padding 10→8、scroll 72→94。
 * hero 站名走 sans 21/700（禁令 8：serif 不上站名）。
 *
 * 数据（阶段 10 接真）：当日节点、当前时刻、进度、下一段通勤、行内金额与打卡状态全部取真值。
 * 打卡写 checkin 表（v4），行内金额取挂在该节点上的 expense 合计；
 * 底稿里「周一人少，10:00 后团队到达」「打车 ¥1,900」这类无来源文案不保留。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { FloatingDock } from '../components/FloatingDock';
import { Activity, ActivityStatus, Trip, TripDay } from '../model/Trip';
import { TripDao } from '../data/TripDao';
import { CheckinDao } from '../data/CheckinDao';
import { ExpenseDao } from '../data/ExpenseDao';
import { DateUtils } from '../utils/DateUtils';
import { Logger } from '../common/logger/Logger';
import { common } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';

interface CheckedRow {
  time: string;
  name: string;
  amount: string;
  ongoing: boolean;
}

function minutesOf(hhmm: string): number {
  const parts: string[] = hhmm.split(':');
  if (parts.length < 2) {
    return 0;
  }
  return Number(parts[0]) * 60 + Number(parts[1]);
}

function clockNow(): string {
  const d: Date = new Date();
  const h: string = `${d.getHours()}`;
  const m: string = `${d.getMinutes()}`;
  return `${h.length < 2 ? `0${h}` : h}:${m.length < 2 ? `0${m}` : m}`;
}

function hoursText(start: string, end: string): string {
  const mins: number = Math.max(0, minutesOf(end) - minutesOf(start));
  return `${Math.round(mins / 6) / 10}`;
}

@Component
export struct OnTripPage {
  private pathStack: NavPathStack = APP_NAV;
  @Prop tripId: string = '';
  @State private rows: CheckedRow[] = [];
  @State private current: Activity | null = null;
  @State private next: Activity | null = null;
  @State private checkedIn: boolean = false;
  @State private elapsedMin: number = 0;
  @State private totalMin: number = 0;
  @State private dayLabel: string = '';
  @State private clock: string = '';
  @State private nextLeg: string = '';
  private trip: Trip | null = null;

  aboutToAppear(): void {
    this.reload();
  }

  private ctx(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  private reload(): void {
    if (this.tripId.length === 0) {
      Logger.warn('Ui.OnTrip', '无 tripId，旅行中页保持空态');
      return;
    }
    const context: common.Context = this.ctx();
    const now: string = clockNow();
    this.clock = now;
    TripDao.loadTrip(context, this.tripId).then((trip: Trip | null): Promise<Record<string, number>> => {
      if (trip === null) {
        return Promise.resolve<Record<string, number>>({});
      }
      this.trip = trip;
      const day: TripDay | null = this.pickDay(trip);
      if (day === null || day.activities.length === 0) {
        this.dayLabel = '旅行中';
        this.current = null;
        this.next = null;
        return CheckinDao.listForTrip(context, trip.id);
      }
      this.dayLabel = `进行中 · Day ${day.dayIndex}`;
      const acts: Activity[] = day.activities;
      let cur: number = -1;
      for (let i = 0; i < acts.length; i++) {
        if (minutesOf(acts[i].time) <= minutesOf(now)) {
          cur = i;
        }
      }
      if (cur < 0) {
        cur = 0;
      }
      this.current = acts[cur];
      this.next = cur + 1 < acts.length ? acts[cur + 1] : null;
      const start: number = minutesOf(acts[cur].time);
      const end: number = Math.max(start + 1, minutesOf(acts[cur].endTime));
      this.totalMin = end - start;
      this.elapsedMin = Math.max(0, Math.min(this.totalMin, minutesOf(now) - start));
      if (this.next !== null && this.next.transport !== undefined) {
        const t = this.next.transport;
        this.nextLeg = `${t.mode} ${t.duration}分钟${t.detail.length > 0 ? ` · ${t.detail}` : ''}`;
      } else {
        this.nextLeg = '';
      }
      return CheckinDao.listForTrip(context, trip.id);
    }).then((marks: Record<string, number>): Promise<Record<string, number>> => {
      const cur: Activity | null = this.current;
      this.checkedIn = cur !== null && marks[cur.id] !== undefined;
      return this.buildRows(marks);
    }).catch((err: Error) => {
      Logger.error('Ui.OnTrip', `加载失败: ${err.message}`);
    });
  }

  /** 今天落在行程区间内就取那天；不在区间（提前查看/回放）取第一天 */
  private pickDay(trip: Trip): TripDay | null {
    if (trip.days.length === 0) {
      return null;
    }
    const today: string = DateUtils.todayIso();
    for (const d of trip.days) {
      if (d.date === today) {
        return d;
      }
    }
    return trip.days[0];
  }

  /** 今日已打卡的行；金额取挂在该节点上的开销合计 */
  private buildRows(marks: Record<string, number>): Promise<Record<string, number>> {
    const trip: Trip | null = this.trip;
    if (trip === null) {
      return Promise.resolve<Record<string, number>>({});
    }
    const day: TripDay | null = this.pickDay(trip);
    return ExpenseDao.sumGroupedByActivity(this.ctx(), trip.id)
      .then((sums: Record<string, number>): Record<string, number> => {
        const list: CheckedRow[] = [];
        if (day !== null) {
          for (const a of day.activities) {
            if (marks[a.id] === undefined) {
              continue;
            }
            const paid: number | undefined = sums[a.id];
            const row: CheckedRow = {
              time: a.time, name: a.title,
              amount: paid === undefined ? '' : `¥${paid.toLocaleString('en-US')}`,
              ongoing: false
            };
            list.push(row);
          }
        }
        this.rows = list;
        return sums;
      });
  }

  private toggleCheckin(): void {
    const cur: Activity | null = this.current;
    const trip: Trip | null = this.trip;
    if (cur === null || trip === null) {
      this.toast('当前无节点');
      return;
    }
    const target: boolean = !this.checkedIn;
    CheckinDao.set(this.ctx(), trip.id, cur.id, target).then((): void => {
      this.checkedIn = target;
      this.reload();
      this.toast(target ? `已打卡 ${cur.title}` : '已取消打卡');
    }).catch((err: Error) => {
      Logger.error('Ui.OnTrip', `打卡失败: ${err.message}`);
      this.toast('打卡失败');
    });
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1500 });
  }

  private heroMeta(): string {
    const cur: Activity | null = this.current;
    if (cur === null) {
      return '今日暂无安排';
    }
    return `${cur.time} 开始 · 建议 ${hoursText(cur.time, cur.endTime)}小时 · 已过 ${this.elapsedMin}分钟`;
  }

  private progressPct(): number {
    return Math.max(1, Math.min(100, Math.round((this.elapsedMin / Math.max(1, this.totalMin)) * 100)));
  }

  private nextTitle(): string {
    const next: Activity | null = this.next;
    return next === null ? '' : next.title;
  }

  private nextNeedsBooking(): boolean {
    const next: Activity | null = this.next;
    return next !== null && (next.status === ActivityStatus.NOT_BOOKED ||
      next.status === ActivityStatus.PENDING || next.status === ActivityStatus.FULL);
  }

  private nextMeta(): string {
    const next: Activity | null = this.next;
    if (next === null) {
      return '';
    }
    const place: string = next.address.length > 0 ? next.address : next.location;
    return `建议停留 ${hoursText(next.time, next.endTime)}小时 · ${place}`;
  }

  @Builder
  groupHeader() {
    Text('今日已打卡')
      .fontSize(TypeTokens.overline.size)
      .fontWeight(600)
      .fontColor(ColorTokens.muted)
      .width('100%')
      .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.xs })
  }

  @Builder
  checkRow(row: CheckedRow) {
    Row() {
      Text(row.time)
        .fontSize(TypeTokens.time.size)
        .fontWeight(600)
        .fontColor(row.ongoing ? ColorTokens.primary : ColorTokens.muted)
        .fontFeature("'tnum' on")
        .width(52)
      Text(row.name)
        .fontSize(TypeTokens.small.size)
        .fontWeight(row.ongoing ? 600 : 400)
        .fontColor(ColorTokens.ink)
        .layoutWeight(1)
      if (row.amount.length > 0) {
        Text(row.amount)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.body)
          .fontFeature("'tnum' on")
          .margin({ right: SpaceTokens.sm })
      }
      Text(row.ongoing ? '进行中' : '已打卡')
        .fontSize(TypeTokens.overline.size)
        .fontWeight(600)
        .fontColor(row.ongoing ? ColorTokens.primary : ColorTokens.success)
      if (!row.ongoing) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(14)
          .fontColor([ColorTokens.success])
          .margin({ left: SpaceTokens.xs })
      }
    }
    .width('100%')
    .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
      // 官方 List：hero / 下一段 / 打卡分组各占一个 ListItem，分组头吸顶、行间交给 .divider()
      List({ space: SpaceTokens.lg }) {
        ListItem() {
          Column() {
            Text('当前节点')
              .fontSize(TypeTokens.overline.size)
              .fontWeight(600)
              .fontColor(ColorTokens.muted)
            Text(this.current === null ? '今日暂无安排' : this.current.title)
              .fontSize(TypeTokens.title.size)
              .fontWeight(700)
              .fontColor(ColorTokens.ink)
              .margin({ top: SpaceTokens.xs })
            Text(this.heroMeta())
              .fontSize(TypeTokens.caption.size)
              .fontWeight(450)
              .fontColor(ColorTokens.body)
              .fontFeature("'tnum' on")
              .margin({ top: 2 })
            Progress({ value: this.progressPct(), total: 100, type: ProgressType.Linear })
              .color(ColorTokens.primary)
              .width('100%')
              .margin({ top: SpaceTokens.md })
            if (this.current !== null && this.current.note !== undefined && this.current.note.length > 0) {
              Text(this.current.note)
                .fontSize(TypeTokens.caption.size)
                .fontWeight(450)
                .fontColor(ColorTokens.warning)
                .margin({ top: SpaceTokens.sm })
            }
            Row({ space: SpaceTokens.md }) {
              YoujingButton({
                variant: YoujingButtonVariant.SECONDARY,
                label: this.checkedIn ? '已打卡' : '完成打卡',
                buttonWidth: 140,
                onAction: (): void => {
                  this.toggleCheckin();
                }
              })
              YoujingButton({
                variant: YoujingButtonVariant.PRIMARY,
                label: '记一笔费用',
                buttonWidth: 150,
                onAction: (): void => {
                  this.pathStack.pushPath({ name: 'Expense', param: this.tripId });
                }
              })
            }
            .margin({ top: SpaceTokens.lg })
            Text('打卡与记账只存本机，不上传服务器')
              .fontSize(TypeTokens.overline.size)
              .fontWeight(450)
              .fontColor(ColorTokens.faint)
              .margin({ top: SpaceTokens.sm })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(SpaceTokens.lg)
          .borderRadius(RadiusTokens.hero)
          .backgroundColor(ColorTokens.surfaceElevated)
        }

        // 下一段：真实通勤腿 + 下一节点
        if (this.next !== null) {
          ListItem() {
            Column() {
              Row() {
                Column().width(52)
                Column()
                  .width(2)
                  .height(44)
                  .border({ width: { left: 2 }, color: ColorTokens.separator, style: BorderStyle.Dashed })
                Row({ space: SpaceTokens.xs }) {
                  SymbolGlyph($r('sys.symbol.car'))
                    .fontSize(14)
                    .fontColor([ColorTokens.icon])
                  Text(this.nextLeg)
                    .fontSize(TypeTokens.caption.size)
                    .fontWeight(450)
                    .fontColor(ColorTokens.muted)
                    .fontFeature("'tnum' on")
                }
                .padding({ left: SpaceTokens.sm })
              }
              .height(44)
              .alignItems(VerticalAlign.Center)

              Row({ space: SpaceTokens.sm }) {
                Text(this.next === null ? '' : this.next.time)
                  .fontSize(TypeTokens.time.size)
                  .fontWeight(600)
                  .fontColor(ColorTokens.ink)
                  .fontFeature("'tnum' on")
                  .width(52)
                Row({ space: SpaceTokens.xs }) {
                  Text(this.nextTitle())
                    .fontSize(TypeTokens.small.size)
                    .fontWeight(600)
                    .fontColor(ColorTokens.ink)
                  if (this.nextNeedsBooking()) {
                    Text('需预约')
                      .fontSize(TypeTokens.overline.size)
                      .fontWeight(600)
                      .fontColor(ColorTokens.onPrimary)
                      .height(18)
                      .padding({ left: 6, right: 6 })
                      .borderRadius(RadiusTokens.pill)
                      .backgroundColor(ColorTokens.warning)
                  }
                }
                .layoutWeight(1)
              }
              .width('100%')
              .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })

              Text(this.nextMeta())
                .fontSize(TypeTokens.caption.size)
                .fontWeight(450)
                .fontColor(ColorTokens.muted)
                .margin({ left: 60 })
                .alignSelf(ItemAlign.Start)
            }
            .width('100%')
          }
        }

        ListItemGroup({ header: this.groupHeader() }) {
          if (this.rows.length === 0) {
            ListItem() {
              Text('还没有打卡节点')
                .fontSize(TypeTokens.caption.size)
                .fontColor(ColorTokens.muted)
                .width('100%')
                .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
            }
          }
          ForEach(this.rows, (row: CheckedRow) => {
            ListItem() {
              this.checkRow(row)
            }
          }, (row: CheckedRow): string => `ck-${row.time}-${row.name}-${row.amount}`)
        }
        .divider({ strokeWidth: LayoutTokens.hairlineWidth, color: ColorTokens.separator })
        .padding({ left: SpaceTokens.md, right: SpaceTokens.md })
        .backgroundColor(ColorTokens.canvas)
        .borderRadius(RadiusTokens.card)
        .clip(true)
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .sticky(StickyStyle.Header)
      .cachedCount(6)
      .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, bottom: LayoutTokens.bottomScrollReserve })
      .width('100%')
      .height('100%')
      .backgroundColor(ColorTokens.canvas)
      FloatingDock({ activeIndex: 0, tripId: this.tripId })
    }
    .width('100%')
    .height('100%')
    }
    .titleBar(HdsChrome.bar({ mainTitle: this.dayLabel.length > 0 ? this.dayLabel : '旅行中', subTitle: this.clock }))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .onShown((): void => {
      this.reload();
    })
  }
}
