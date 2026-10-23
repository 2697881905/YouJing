/**
 * 屏8 行程时间线主视图（帧 9c0acbcd）。
 * §7 必改已落：booking-badge padding 3→4、dock padding 10→8、
 * reason-block margin 10→8、scroll 底部预留 138→94、transit gap 6→4。
 * 顶栏/吸顶/分段栏/dock 四点位玻璃=系统材质（骨架期用 backgroundBlurStyle 回退档，
 * 精修批次换 EXQUISITE）；深色零阴影经 isDarkMode 门控。
 */

import { APP_NAV, EditTarget } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { ShadowTokens } from '../design/ShadowTokens';
import { Activity, ActivityCategory, ActivityStatus, IntensityLevel, TripDay, Trip } from '../model/Trip';
import { TripDao } from '../data/TripDao';
import { AccessFlags, CalendarSync, SyncResult } from '../data/CalendarSync';
import { Logger } from '../common/logger/Logger';
import { common } from '@kit.AbilityKit';
import { ImmersiveSegmentBar, SegmentedItem } from '../components/ImmersiveSegmentBar';
import { barMaterial, getSheetImmersiveMaterial, isSystemMaterialActive } from '../utils/immersiveMaterial';
import { uiMaterial } from '@kit.ArkUI';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { FloatingDock } from '../components/FloatingDock';

const ROW_HEIGHT: number = 76;

@Component
export struct ItineraryPage {
  private pathStack: NavPathStack = APP_NAV;
  @StorageProp('isDarkMode') isDark: boolean = false;
  /** 玻璃点位①③是否由系统材质接管（接管处撤自绘背景与阴影）；仅浅色模式下实验 */
  private glassOn: boolean = isSystemMaterialActive();
  @Prop tripId: string = '';
  @State private dayIndex: number = 0;
  @State private showDetail: boolean = false;
  @State private detailAct: Activity | undefined = undefined;
  @State private showSystemAccess: boolean = false;
  @State private syncCalendar: boolean = false;
  @State private syncCard: boolean = true;
  @State private syncRemind: boolean = false;
  @State private days: TripDay[] = [];
  @State private bookingCount: number = 0;
  @State private dayCount: number = 0;
  private trip: Trip | null = null;
  // 中性占位：加载前不能报一个编造的目的地与天数
  @State private titleText: string = '行程详情';
  @State private segments: SegmentedItem[] = [
    { label: 'Day 1' }, { label: 'Day 2' }, { label: 'Day 3' }
  ];

  /** 编辑页返回后要吃回写的库数据，故加载挂在 onShown 而非 aboutToAppear */
  private reload(): void {
    if (this.tripId.length > 0) {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      TripDao.loadTrip(ctx, this.tripId).then((trip: Trip | null) => {
        if (trip !== null) {
          this.trip = trip;
          this.days = trip.days;
          this.bookingCount = CalendarSync.bookingCount(trip);
          this.dayCount = trip.days.length;
          const nights: number = trip.days.length - 1;
          this.titleText = `${trip.destination} · ${trip.days.length}天${nights}晚`;
          this.segments = trip.days.map((d: TripDay): SegmentedItem => {
            const item: SegmentedItem = { label: `Day ${d.dayIndex}` };
            return item;
          });
        }
      }).catch((err: Error) => {
        Logger.error('Ui.Itinerary', `加载行程失败: ${err.message}`);
      });
      CalendarSync.loadFlags(ctx).then((f: AccessFlags): void => {
        this.syncCalendar = f.calendar;
        this.syncCard = f.card;
        this.syncRemind = f.remind;
      }).catch((err: Error) => {
        Logger.warn('Ui.Itinerary', `触达开关读取失败: ${err.message}`);
      });
    }
  }

  /** 屏14 预览取真实待写节点：优先详情面板选中的活动，否则当日首站 */
  private previewTarget(): Activity | undefined {
    if (this.detailAct !== undefined) {
      return this.detailAct;
    }
    const acts: Activity[] = this.curDay().activities;
    return acts.length > 0 ? acts[0] : undefined;
  }

  private previewWhen(): string {
    const act: Activity | undefined = this.previewTarget();
    if (act === undefined) {
      return '';
    }
    return `${this.curDay().date} ${act.time}–${act.endTime}`;
  }

  private previewWhat(): string {
    const act: Activity | undefined = this.previewTarget();
    return act === undefined ? '' : `${act.title} · ${CalendarSync.isBookingNode(act) ? '需预约' : '无需预约'}`;
  }

  private previewWhere(): string {
    const act: Activity | undefined = this.previewTarget();
    if (act === undefined) {
      return '';
    }
    return `地址 ${act.address.length > 0 ? act.address : act.location}`;
  }

  /** 与 CalendarSync 实际写入的 description 对齐，预览不承诺没写的东西 */
  private previewNote(): string {
    const act: Activity | undefined = this.previewTarget();
    if (act === undefined) {
      return '';
    }
    const desc: string = act.reason === undefined ? act.location : `${act.location} · ${act.reason}`;
    return `备注 ${desc}`;
  }

  /** 同意并写入：先申请权限，未授权不写任何数据；开关状态落 preferences */
  private writeToSystem(): void {
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const flags: AccessFlags = {
      calendar: this.syncCalendar, card: this.syncCard, remind: this.syncRemind
    };
    const toast = (msg: string): void => {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
    };
    CalendarSync.saveFlags(ctx, flags).catch((err: Error) => {
      Logger.warn('Ui.Itinerary', `触达开关保存失败: ${err.message}`);
    });
    if (!flags.calendar) {
      toast('行程仅保存在本机');
      this.showSystemAccess = false;
      return;
    }
    const trip: Trip | null = this.trip;
    if (trip === null) {
      toast('行程数据未就绪，稍后再试');
      return;
    }
    CalendarSync.requestPermission(ctx).then((granted: boolean): Promise<SyncResult> => {
      if (!granted) {
        throw new Error('未授予日历权限');
      }
      return CalendarSync.syncTrip(ctx, trip, flags);
    }).then((r: SyncResult): void => {
      toast(`已写入 ${r.bookingEvents} 个预约节点 + ${r.dayEvents} 天行程`);
    }).catch((err: Error) => {
      Logger.warn('Ui.Itinerary', `日历写入失败: ${err.message}`);
      toast(`日历写入失败：${err.message}`);
    }).finally((): void => {
      this.showSystemAccess = false;
    });
  }

  private detailList(): Activity[] {
    return this.curDay().activities;
  }

  private detailIndex(): number {
    const act: Activity | undefined = this.detailAct;
    if (act === undefined) {
      return -1;
    }
    const list: Activity[] = this.detailList();
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === act.id) {
        return i;
      }
    }
    return -1;
  }

  private dayPos(): number {
    const i: number = this.detailIndex();
    return i < 0 ? 1 : i + 1;
  }

  private detailAddressLine(): string {
    const act: Activity | undefined = this.detailAct;
    if (act === undefined) {
      return '';
    }
    return act.address.length > 0 ? act.address : act.location;
  }

  private statusChip(): string {
    const act: Activity | undefined = this.detailAct;
    if (act === undefined) {
      return '';
    }
    if (act.status === ActivityStatus.BOOKED) {
      return '已约';
    }
    if (act.status === ActivityStatus.FULL) {
      return '约满';
    }
    if (act.status === ActivityStatus.PENDING) {
      return '待定';
    }
    return '';
  }

  private statusFullText(): string {
    const act: Activity | undefined = this.detailAct;
    if (act === undefined) {
      return '';
    }
    if (act.status === ActivityStatus.NOT_BOOKED) {
      return '需预约，尚未确认';
    }
    if (act.status === ActivityStatus.BOOKED) {
      return '已预约';
    }
    if (act.status === ActivityStatus.FULL) {
      return '已约满，需改期或换时段';
    }
    if (act.status === ActivityStatus.PENDING) {
      return '待定';
    }
    return '无需预约';
  }

  private commuteText(): string {
    const act: Activity | undefined = this.detailAct;
    if (act === undefined || act.transport === undefined) {
      return '—';
    }
    return `${act.transport.duration}分钟`;
  }

  private arrivalText(): string {
    const act: Activity | undefined = this.detailAct;
    if (act === undefined || act.transport === undefined) {
      return '当日首站，无通勤';
    }
    const detail: string = act.transport.detail.length > 0 ? ` · ${act.transport.detail}` : '';
    return `${act.transport.mode} ${act.transport.duration}分钟${detail}`;
  }

  private prevTitle(): string {
    const i: number = this.detailIndex();
    return i > 0 ? this.detailList()[i - 1].title : '今日首站';
  }

  private prevLabel(): string {
    const i: number = this.detailIndex();
    return i > 0 ? `上一站 ${this.detailList()[i - 1].time}` : '当日第 1 站';
  }

  private nextTitle(): string {
    const i: number = this.detailIndex();
    const list: Activity[] = this.detailList();
    return i >= 0 && i < list.length - 1 ? list[i + 1].title : '今日末站';
  }

  private nextLabel(): string {
    const i: number = this.detailIndex();
    const list: Activity[] = this.detailList();
    return i >= 0 && i < list.length - 1 ? `下一站 ${list[i + 1].time}` : '当日最后';
  }

  /** 通勤图标按模式取真图标（图标名已对本机 id_defined.json 核实），认不出的一律走步行 */
  private transitSymbol(mode: string): Resource {
    if (mode.indexOf('地铁') >= 0 || mode.indexOf('轨道') >= 0 || mode.indexOf('轻轨') >= 0) {
      return $r('sys.symbol.subway');
    }
    if (mode.indexOf('公交') >= 0 || mode.indexOf('巴士') >= 0) {
      return $r('sys.symbol.bus_fill');
    }
    if (mode.indexOf('打车') >= 0 || mode.indexOf('出租') >= 0 || mode.indexOf('网约') >= 0) {
      return $r('sys.symbol.figure_and_taxi');
    }
    if (mode.indexOf('自驾') >= 0) {
      return $r('sys.symbol.car');
    }
    if (mode.indexOf('骑行') >= 0 || mode.indexOf('单车') >= 0) {
      return $r('sys.symbol.bicycle');
    }
    if (mode.indexOf('机场') >= 0 || mode.indexOf('航班') >= 0 || mode.indexOf('飞机') >= 0) {
      return $r('sys.symbol.airplane');
    }
    return $r('sys.symbol.figure_walk');
  }

  /** 地图面板摘要：只报当日真实通勤段数与模式，底稿的「6.4km」无数据来源故不保留 */
  private dayRouteSummary(): string {
    const acts: Activity[] = this.curDay().activities;
    const order: string[] = [];
    const counts: Record<string, number> = {};
    for (const a of acts) {
      if (a.transport === undefined) {
        continue;
      }
      const mode: string = a.transport.mode.length > 0 ? a.transport.mode : '步行';
      if (counts[mode] === undefined) {
        counts[mode] = 0;
        order.push(mode);
      }
      counts[mode] = counts[mode] + 1;
    }
    if (order.length === 0) {
      return '当日仅一站，无通勤';
    }
    const parts: string[] = order.map((m: string): string => `${m} ${counts[m]} 段`);
    return parts.join(' · ');
  }

  private curDay(): TripDay {
    if (this.days.length === 0) {
      const placeholder: TripDay = {
        dayIndex: 1, date: '————', theme: '', intensity: IntensityLevel.LOW,
        dailyCost: 0, activities: [], meals: []
      };
      return placeholder;
    }
    return this.days[Math.min(this.dayIndex, this.days.length - 1)];
  }

  private dotColor(cat: ActivityCategory): Resource {
    if (cat === ActivityCategory.FOOD) {
      return ColorTokens.bookmark;
    }
    if (cat === ActivityCategory.HOTEL) {
      return ColorTokens.accentMention;
    }
    if (cat === ActivityCategory.TRANSPORT) {
      return ColorTokens.icon;
    }
    if (cat === ActivityCategory.REST) {
      return ColorTokens.faint;
    }
    return ColorTokens.primary;
  }

  private bookingText(status: ActivityStatus): string {
    if (status === ActivityStatus.NOT_BOOKED) {
      return '需预约';
    }
    if (status === ActivityStatus.FULL) {
      return '约满';
    }
    if (status === ActivityStatus.BOOKED) {
      return '已约';
    }
    if (status === ActivityStatus.PENDING) {
      return '待定';
    }
    return '';
  }

  private bookingColor(status: ActivityStatus): Resource {
    if (status === ActivityStatus.FULL) {
      return ColorTokens.danger;
    }
    if (status === ActivityStatus.BOOKED) {
      return ColorTokens.success;
    }
    if (status === ActivityStatus.PENDING) {
      return ColorTokens.bookmark;
    }
    return ColorTokens.warning;
  }

  @Builder
  spineNode(cat: ActivityCategory) {
    Stack() {
      Column()
        .width(24)
        .height(24)
        .borderRadius(RadiusTokens.pill)
        .backgroundColor(ColorTokens.canvas)
        .border({ width: 2, color: ColorTokens.ink })
      Column()
        .width(10)
        .height(10)
        .borderRadius(RadiusTokens.pill)
        .backgroundColor(this.dotColor(cat))
    }
    .width(24)
    .height(24)
  }

  @Builder
  transitLeg(next: Activity) {
    Row() {
      Column().width(52)
      Column()
        .width(LayoutTokens.routeLineWidth)
        .height(LayoutTokens.transitLegHeight)
        .border({ width: { left: 2 }, color: ColorTokens.separator, style: BorderStyle.Dashed })
      Row({ space: SpaceTokens.xs }) {
        SymbolGlyph(this.transitSymbol(next.transport === undefined ? '' : next.transport.mode))
          .fontSize(14)
          .fontColor([ColorTokens.icon])
        Text(`${next.transport?.mode} ${next.transport?.duration}分钟 · ${next.transport?.detail}`)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .fontFeature("'tnum' on")
      }
      .alignItems(VerticalAlign.Center)
      .padding({ left: SpaceTokens.sm })
    }
    .width('100%')
    .height(LayoutTokens.transitLegHeight)
    .alignItems(VerticalAlign.Center)
  }

  private durationText(act: Activity): string {
    const t: string[] = act.time.split(':');
    const e: string[] = act.endTime.split(':');
    const mins: number = Number(e[0]) * 60 + Number(e[1]) - Number(t[0]) * 60 - Number(t[1]);
    if (mins <= 0) {
      return '—';
    }
    const h: number = Math.floor(mins / 60);
    const m: number = mins % 60;
    if (h > 0 && m > 0) {
      return `${h}小时${m}分钟`;
    }
    return h > 0 ? `${h}小时` : `${m}分钟`;
  }

  @Builder
  stopRow(act: Activity, isLast: boolean) {
    Column() {
      Row() {
        Text(act.time)
          .width(52)
          .fontSize(TypeTokens.time.size)
          .fontWeight(600)
          .fontColor(ColorTokens.ink)
          .textAlign(TextAlign.End)
          .fontFeature("'tnum' on")
          .padding({ right: SpaceTokens.md, top: SpaceTokens.xs })
        Stack({ alignContent: Alignment.Top }) {
          Column()
            .width(LayoutTokens.routeLineWidth)
            .height(isLast ? 12 : '100%')
            .backgroundColor(ColorTokens.surfaceSunken)
          this.spineNode(act.category)
        }
        .width(24)
        .height('100%')
        Column() {
          Row({ space: SpaceTokens.sm }) {
            Text(act.title)
              .fontSize(TypeTokens.headline.size)
              .fontWeight(600)
              .fontColor(ColorTokens.ink)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            if (this.bookingText(act.status).length > 0) {
              Text(this.bookingText(act.status))
                .fontSize(TypeTokens.overline.size)
                .fontWeight(600)
                .fontColor(ColorTokens.onPrimary)
                .height(22)
                .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm })
                .borderRadius(RadiusTokens.pill)
                .backgroundColor(this.bookingColor(act.status))
            }
            Column()
              .width(36)
              .height(48)
              .borderRadius(RadiusTokens.media)
              .backgroundColor(ColorTokens.surfaceSunken)
          }
          .alignItems(VerticalAlign.Center)

          Text(`建议停留 ${this.durationText(act)} · ${act.address}`)
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
            .margin({ top: SpaceTokens.xs })
          if (act.reason !== undefined) {
            Column() {
              Text('为什么排在这里')
                .fontSize(TypeTokens.overline.size)
                .fontWeight(600)
                .fontColor(ColorTokens.muted)
              Text(act.reason)
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
            .margin({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .alignItems(VerticalAlign.Top)
      .width('100%')
      .height(ROW_HEIGHT + (act.reason !== undefined ? 84 : 0))
      .onClick(() => {
        this.detailAct = act;
        this.showDetail = true;
      })
    }
    .width('100%')
  }

  @Builder
  statCol(value: string, label: string) {
    Column() {
      Text(value)
        .fontSize(TypeTokens.small.size)
        .fontWeight(600)
        .fontColor(ColorTokens.ink)
        .fontFeature("'tnum' on")
      Text(label)
        .fontSize(TypeTokens.overline.size)
        .fontWeight(450)
        .fontColor(ColorTokens.muted)
        .margin({ top: 2 })
    }
    .layoutWeight(1)
  }

  @Builder
  hoursRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(TypeTokens.small.size)
        .fontColor(ColorTokens.muted)
      Blank()
      Text(value)
        .fontSize(TypeTokens.small.size)
        .fontWeight(600)
        .fontColor(ColorTokens.ink)
        .fontFeature("'tnum' on")
    }
    .width('100%')
    .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
  }

  @Builder
  miniNode(idx: number, meta: string, name: string, active: boolean) {
    Column({ space: SpaceTokens.xs }) {
      Stack() {
        Column()
          .width(24)
          .height(24)
          .borderRadius(RadiusTokens.pill)
          .backgroundColor(active ? ColorTokens.primary : ColorTokens.canvas)
          .border({ width: 2, color: active ? ColorTokens.primary : ColorTokens.ink })
        if (!active && idx >= 1 && idx <= this.detailList().length) {
          Text(`${idx}`)
            .fontSize(TypeTokens.caption.size)
            .fontWeight(600)
            .fontColor(ColorTokens.ink)
            .fontFeature("'tnum' on")
        }
      }
      Text(meta)
        .fontSize(TypeTokens.overline.size)
        .fontColor(active ? ColorTokens.primary : ColorTokens.muted)
        .fontFeature("'tnum' on")
      Text(name)
        .fontSize(TypeTokens.caption.size)
        .fontWeight(active ? 600 : 400)
        .fontColor(active ? ColorTokens.ink : ColorTokens.body)
    }
    .layoutWeight(1)
  }

  @Builder
  detailSheet() {
    Column() {
      if (this.detailAct !== undefined) {
        Scroll() {
          Column() {
            Row({ space: SpaceTokens.md }) {
              Column()
                .width(96)
                .height(120)
                .borderRadius(RadiusTokens.media)
                .backgroundColor(ColorTokens.surfaceSunken)
              Column() {
                Text(this.detailAct.title)
                  .fontSize(TypeTokens.headline.size)
                  .fontWeight(600)
                  .fontColor(ColorTokens.ink)
                Text(this.detailAddressLine())
                  .fontSize(TypeTokens.caption.size)
                  .fontWeight(450)
                  .fontColor(ColorTokens.muted)
                  .margin({ top: SpaceTokens.xs })
                Row({ space: SpaceTokens.xs }) {
                  if (this.statusChip() !== '') {
                    Text(this.statusChip())
                      .fontSize(TypeTokens.overline.size)
                      .fontWeight(600)
                      .fontColor(ColorTokens.bookmark)
                      .height(22)
                      .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm })
                      .borderRadius(RadiusTokens.pill)
                      .backgroundColor(ColorTokens.surfaceSubtle)
                  }
                  if (this.detailAct.status === ActivityStatus.NOT_BOOKED) {
                    Text('需预约')
                      .fontSize(TypeTokens.overline.size)
                      .fontWeight(600)
                      .fontColor(ColorTokens.onPrimary)
                      .height(22)
                      .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm })
                      .borderRadius(RadiusTokens.pill)
                      .backgroundColor(ColorTokens.warning)
                  }
                }
                .margin({ top: SpaceTokens.sm })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .alignItems(VerticalAlign.Top)
            .width('100%')

            Row() {
              this.statCol(this.durationText(this.detailAct), '停留建议')
              this.statCol(this.detailAct.time, '计划到达')
              this.statCol(this.commuteText(), '到达耗时')
              this.statCol('—', '门票费用')
            }
            .width('100%')
            .padding(SpaceTokens.md)
            .borderRadius(RadiusTokens.card)
            .attributeModifier(barMaterial(uiMaterial.ImmersiveStyle.ULTRA_THIN, true, this.glassOn && !this.isDark))
          .backgroundColor(this.glassOn && !this.isDark ? Color.Transparent : ColorTokens.surfaceElevated)
            .margin({ top: SpaceTokens.lg })

            Column() {
              this.hoursRow('预约状态', this.statusFullText())
              Divider().strokeWidth(LayoutTokens.hairlineWidth).color(ColorTokens.separator)
              this.hoursRow('到达方式', this.arrivalText())
            }
            .width('100%')
            .padding({ left: SpaceTokens.md, right: SpaceTokens.md })
            .margin({ top: SpaceTokens.md })

            if (this.detailAct.note !== undefined && this.detailAct.note.length > 0) {
              Text(this.detailAct.note)
                .fontSize(TypeTokens.caption.size)
                .fontWeight(450)
                .fontColor(ColorTokens.warning)
                .fontFeature("'tnum' on")
                .width('100%')
                .margin({ top: SpaceTokens.xs })
            }

            if (this.detailAct.reason !== undefined) {
              Column() {
                Text('为什么排在这里')
                  .fontSize(TypeTokens.overline.size)
                  .fontWeight(600)
                  .fontColor(ColorTokens.muted)
                Text(this.detailAct.reason)
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
            }

            Column() {
              Text('动线位置')
                .fontSize(TypeTokens.overline.size)
                .fontWeight(600)
                .fontColor(ColorTokens.muted)
                .alignSelf(ItemAlign.Start)
              Row() {
                this.miniNode(this.dayPos() - 1, this.prevLabel(), this.prevTitle(), false)
                this.miniNode(this.dayPos(), '当前站点', this.detailAct.title, true)
                this.miniNode(this.dayPos() + 1, this.nextLabel(), this.nextTitle(), false)
              }
              .width('100%')
              .padding({ top: SpaceTokens.md })
            }
            .width('100%')
            .padding(SpaceTokens.md)
            .borderRadius(RadiusTokens.card)
            .backgroundColor(ColorTokens.surfaceElevated)
            .margin({ top: SpaceTokens.md, bottom: SpaceTokens.xl })
          }
          .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)

        Row({ space: SpaceTokens.md }) {
          YoujingButton({
            variant: YoujingButtonVariant.SECONDARY,
            label: '换一个时间',
            buttonWidth: 160,
            onAction: (): void => {
              this.showDetail = false;
            }
          })
          YoujingButton({
            variant: YoujingButtonVariant.PRIMARY,
            label: '加入日历提醒',
            onAction: (): void => {
              this.showDetail = false;
              this.showSystemAccess = true;
            }
          })
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, top: SpaceTokens.sm, bottom: SpaceTokens.md })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ColorTokens.canvas)
  }

  @Builder
  accessRow(title: string, desc: string, on: boolean, setter: (v: boolean) => void) {
    Row() {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(TypeTokens.small.size)
          .fontWeight(600)
          .fontColor(ColorTokens.ink)
        Text(desc)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .fontFeature("'tnum' on")
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: on })
        .selectedColor(ColorTokens.primary)
        .onChange((isOn: boolean) => {
          setter(isOn);
        })
    }
    .width('100%')
    .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
  }

  @Builder
  systemAccessSheet() {
    Column() {
      Text('让行程走到系统里')
        .fontSize(TypeTokens.title.size)
        .fontWeight(700)
        .fontFamily(TypeTokens.title.family)
        .fontColor(ColorTokens.ink)
        .margin({ top: SpaceTokens.xl })
      Text('行程数据只存在本机，写入系统应用由你决定')
        .fontSize(TypeTokens.small.size)
        .fontColor(ColorTokens.body)
        .margin({ top: SpaceTokens.xs, bottom: SpaceTokens.lg })

      Column() {
        this.accessRow('日历同步', `写入 ${this.bookingCount} 个预约节点 + ${this.dayCount} 天行程`,
          this.syncCalendar,
          (v: boolean): void => {
            this.syncCalendar = v;
          })
        Divider().strokeWidth(LayoutTokens.hairlineWidth).color(ColorTokens.separator)
        this.accessRow('行程卡片', '桌面常驻今日节点，随系统周期刷新（最小 30 分钟）', this.syncCard,
          (v: boolean): void => {
            this.syncCard = v;
          })
        Divider().strokeWidth(LayoutTokens.hairlineWidth).color(ColorTokens.separator)
        this.accessRow('提醒', '需预约节点提前 1 天提醒', this.syncRemind,
          (v: boolean): void => {
            this.syncRemind = v;
          })
      }
      .width('100%')
      .padding({ left: SpaceTokens.md, right: SpaceTokens.md })

      Column({ space: 2 }) {
        Text('写入内容预览')
          .fontSize(TypeTokens.overline.size)
          .fontWeight(600)
          .fontColor(ColorTokens.muted)
          .alignSelf(ItemAlign.Start)
        Text(this.previewWhen())
          .fontSize(TypeTokens.caption.size)
          .fontColor(ColorTokens.ink)
          .fontFeature("'tnum' on")
        Text(this.previewWhat())
          .fontSize(TypeTokens.caption.size)
          .fontColor(ColorTokens.ink)
        Text(this.previewWhere())
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
        Text(this.previewNote())
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .fontFeature("'tnum' on")
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(SpaceTokens.md)
      .borderRadius(RadiusTokens.reason)
      .backgroundColor(ColorTokens.surfacePanel)
      .margin({ top: SpaceTokens.md })

      Row({ space: SpaceTokens.md }) {
        YoujingButton({
          variant: YoujingButtonVariant.SECONDARY,
          label: '仅本机保存',
          buttonWidth: 150,
          onAction: (): void => {
            const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
            CalendarSync.saveFlags(ctx, { calendar: false, card: this.syncCard, remind: false })
              .catch((err: Error): void => {
                Logger.warn('Ui.Itinerary', `触达开关保存失败: ${err.message}`);
              });
            this.showSystemAccess = false;
          }
        })
        YoujingButton({
          variant: YoujingButtonVariant.PRIMARY,
          label: '同意并写入',
          onAction: (): void => {
            this.writeToSystem();
          }
        })
          .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: SpaceTokens.xl })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, bottom: SpaceTokens.xl })
    .backgroundColor(ColorTokens.canvas)
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        Column() {
          // 顶栏（玻璃点位①：骨架期回退档）
          Column() {
            Row() {
              Text(this.titleText)
                .fontSize(TypeTokens.headline.size)
                .fontWeight(600)
                .fontColor(ColorTokens.ink)
                .fontFeature("'tnum' on")
                .layoutWeight(1)
              SymbolGlyph($r('sys.symbol.share'))
                .fontSize(22)
                .fontColor([ColorTokens.ink])
                .onClick(() => {
                  this.pathStack.pushPath({ name: 'Share', param: this.tripId });
                })
              SymbolGlyph($r('sys.symbol.ellipsis_circle'))
                .fontSize(22)
                .fontColor([ColorTokens.ink])
                .margin({ left: SpaceTokens.lg })
                .onClick(() => {
                  this.pathStack.pushPath({
                    name: 'EditItinerary',
                    param: { tripId: this.tripId, dayIndex: this.dayIndex } as EditTarget
                  });
                })
            }
            .width('100%')
            .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })

            Row() {
              ImmersiveSegmentBar({
                items: this.segments,
                selectedIndex: $dayIndex,
                buttonVerticalPadding: 2.15
              })
            }
            .width('100%')
            .justifyContent(FlexAlign.Start)
            .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, bottom: SpaceTokens.sm })
          }
          .backgroundColor(ColorTokens.surfaceElevated)

          Scroll() {
            Column() {
              // 地图面板（route-paper 渐变占位）
              Stack({ alignContent: Alignment.BottomStart }) {
                Column()
                  .width('100%')
                  .height('100%')
                  .linearGradient({
                    angle: 180,
                    colors: [[ColorTokens.routeBgTop, 0], [ColorTokens.routeBgBottom, 1]]
                  })
                Text(this.dayRouteSummary())
                  .fontSize(TypeTokens.caption.size)
                  .fontWeight(450)
                  .fontColor(ColorTokens.ink)
                  .fontFeature("'tnum' on")
                  .height(28)
                  .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm })
                  .borderRadius(RadiusTokens.pill)
                  .backgroundColor(ColorTokens.canvas)
                  .margin(LayoutTokens.mapOverlayInset - 8)
              }
              .width('100%')
              .height(LayoutTokens.mapHeightCompact)
              .borderRadius(RadiusTokens.card)
              .clip(true)
              .margin({ top: SpaceTokens.md })

              // 吸顶日标题（玻璃点位④：骨架期实色）
              Row() {
                Text(`Day ${this.curDay().dayIndex} · ${this.curDay().date.slice(5).replace('-', '月')}日`)
                  .fontSize(TypeTokens.body.size)
                  .fontWeight(600)
                  .fontColor(ColorTokens.ink)
                  .fontFeature("'tnum' on")
                Blank()
                Text(this.curDay().theme)
                  .fontSize(TypeTokens.caption.size)
                  .fontWeight(450)
                  .fontColor(ColorTokens.muted)
              }
              .width('100%')
              .height(LayoutTokens.dayDividerHeight)
              .margin({ top: SpaceTokens.md })

              Column() {
                ForEach(this.curDay().activities,
                  (act: Activity, idx: number) => {
                    this.stopRow(act, idx === this.curDay().activities.length - 1)
                    if (idx < this.curDay().activities.length - 1 &&
                      this.curDay().activities[idx + 1].transport !== undefined) {
                      this.transitLeg(this.curDay().activities[idx + 1])
                    }
                  }, (act: Activity): string => `itin-${this.tripId}-${this.dayIndex}-${act.id}-${act.title}`)
              }
              .width('100%')
            }
            .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, bottom: LayoutTokens.bottomScrollReserve })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
        }
        .width('100%')
        .height('100%')

        // 浮动 dock（玻璃点位③，共享组件；屏14 触达面板挂在这层壳上，
        // 因为一个节点只能挂一个 bindSheet，Stack 自己已经绑了屏10 详情面板）
        Column() {
          FloatingDock({ activeIndex: 0, tripId: this.tripId })
        }
        .bindSheet($$this.showSystemAccess, this.systemAccessSheet(), {
          height: SheetSize.FIT_CONTENT,
          backgroundColor: ColorTokens.canvas,
          showClose: true,
          systemMaterial: getSheetImmersiveMaterial()
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ColorTokens.canvas)
      .bindSheet($$this.showDetail, this.detailSheet(), {
        height: '85%',
        backgroundColor: ColorTokens.canvas,
        showClose: true,
        systemMaterial: getSheetImmersiveMaterial()
      })
    }
    .hideTitleBar(true)
    .onShown((): void => {
      this.reload();
    })
  }
}
