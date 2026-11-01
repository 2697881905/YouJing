/**
 * 行后旅行回顾（切片 5）。
 *
 * 底稿 13 帧没有这一屏——行后情绪件按既有设计语言就地长：
 * 画布/浮起两级表面、官方 List + ListItemGroup 分组、官方 Button 承载动作，
 * 图标只走系统 symbol，不新增色相。
 *
 * 数据全部派生自既有证据（utils/TripReview + BadgeDao + ExpenseDao），本页不写库。
 * 海报走「本机离屏快照 → JPEG 落 cache → 系统分享面板」；快照/打包失败时降级为
 * 分享行程文本，并如实告知，不假装海报已生成。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';
import { TripDao } from '../data/TripDao';
import { BadgeDao } from '../data/BadgeDao';
import { ExpenseDao } from '../data/ExpenseDao';
import { ShareExporter } from '../data/ShareExporter';
import { Trip } from '../model/Trip';
import { Badge, BadgeGroup, BadgeRecord, badgeDateText, buildBadgeBoard } from '../utils/BadgeBoard';
import { ReviewDay, ReviewItem, ReviewView, buildReview, reviewTimeText } from '../utils/TripReview';
import { MoneyText } from '../utils/MoneyText';
import { Logger } from '../common/logger/Logger';
import { BP_MD_MIN_VP, KEY_WINDOW_WIDTH_VP } from '../utils/breakpointCenter';
import { symmetricInsetForCap } from '../utils/responsive';

@Component
export struct TripReviewPage {
  @Prop tripId: string = '';
  /** 窗口实测宽（vp），由断点中心一处测量；0 = 尚未测到，按不收窄处理 */
  @StorageProp(KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 0;

  private pathStack: NavPathStack = APP_NAV;
  private trip: Trip | null = null;
  private review: ReviewView | null = null;

  @State private loading: boolean = true;
  @State private loaded: boolean = false;
  @State private sharing: boolean = false;
  @State private days: ReviewDay[] = [];
  @State private newBadges: Badge[] = [];
  @State private summaryText: string = '';
  @State private highlights: string[] = [];
  @State private checkedTotal: number = 0;
  @State private arrivalTotal: number = 0;
  @State private firstText: string = '';
  @State private lastText: string = '';

  /** 海报上的标量（离屏快照只读这些，避免 builder 里再解可空对象） */
  @State private pvCity: string = '';
  @State private pvDates: string = '';
  @State private pvMeta: string = '';
  @State private pvStops: string = '';
  @State private pvBadges: string = '';
  @State private pvSpend: string = '';

  aboutToAppear(): void {
    this.load();
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private wideInset(): number {
    return symmetricInsetForCap(this.windowWidthVp, BP_MD_MIN_VP, SpaceTokens.lg);
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1800 });
  }

  private async load(): Promise<void> {
    if (this.tripId.length === 0) {
      this.loading = false;
      return;
    }
    try {
      const ctx: common.UIAbilityContext = this.ctx();
      const trip: Trip | null = await TripDao.loadTrip(ctx, this.tripId);
      if (trip === null) {
        this.loading = false;
        return;
      }
      const records: BadgeRecord[] = await BadgeDao.listForTrip(ctx, this.tripId);
      // 新章判断要全局合并结果（同景点跨行程只算首次），本次回放只用本行程证据
      const groups: BadgeGroup[] = buildBadgeBoard(await BadgeDao.listMine(ctx));
      const expense: number = await ExpenseDao.totalOfTrip(ctx, this.tripId);
      const review: ReviewView = buildReview(trip, records, groups, expense);
      this.trip = trip;
      this.review = review;
      this.days = review.days;
      this.newBadges = review.newBadges;
      this.summaryText = review.summary;
      this.highlights = review.highlights;
      this.checkedTotal = review.checkedTotal;
      this.arrivalTotal = review.arrivalTotal;
      this.firstText = review.firstCheckedAt > 0 ? this.dateTimeText(review.firstCheckedAt) : '';
      this.lastText = review.lastCheckedAt > 0 ? this.dateTimeText(review.lastCheckedAt) : '';
      this.pvCity = review.city;
      this.pvDates = `${review.startDate} – ${review.endDate}`;
      this.pvMeta = `${review.dayCount} 天 · ${review.people} 人`;
      this.pvStops = `${review.checkedTotal}`;
      this.pvBadges = `${review.newBadges.length}`;
      this.pvSpend = review.expenseTotal > 0 ? MoneyText.yuan(review.expenseTotal) : '未记账';
      this.loaded = true;
      this.loading = false;
      Logger.info('Ui.Review', `${this.tripId} 回顾 打卡 ${review.checkedTotal}/${review.spotTotal} ` +
        `新章 ${review.newBadges.length}`);
    } catch (err) {
      this.loading = false;
      Logger.error('Ui.Review', `回顾加载失败: ${(err as Error).message}`);
    }
  }

  private dateTimeText(epochMs: number): string {
    return `${badgeDateText(epochMs)} ${reviewTimeText(epochMs)}`;
  }

  private mdText(iso: string): string {
    if (iso.length !== 10) {
      return iso;
    }
    return `${Number(iso.substring(5, 7))}月${Number(iso.substring(8, 10))}日`;
  }

  private openItinerary(): void {
    this.pathStack.pushPath({ name: 'Itinerary', param: this.tripId });
  }

  /**
   * 离屏快照海报 → JPEG → 系统分享。
   * 任何一步失败都退回分享行程文字：用户至少拿到内容，且弹窗说明降级原因。
   */
  private async sharePoster(): Promise<void> {
    const review: ReviewView | null = this.review;
    const trip: Trip | null = this.trip;
    if (this.sharing || review === null || trip === null) {
      return;
    }
    this.sharing = true;
    const ctx: common.UIAbilityContext = this.ctx();
    try {
      let path: string = '';
      try {
        const pixelMap: image.PixelMap = await this.getUIContext().getComponentSnapshot()
          .createFromBuilder(() => {
            this.posterShot();
          }, 0);
        const packer: image.ImagePacker = image.createImagePacker();
        const buf: ArrayBuffer = await packer.packToData(pixelMap, { format: 'image/jpeg', quality: 92 });
        await packer.release();
        await pixelMap.release();
        path = `${ctx.cacheDir}/youjing-review-${this.tripId}.jpg`;
        if (fs.accessSync(path)) {
          fs.unlinkSync(path);
        }
        const file: fs.File = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        fs.writeSync(file.fd, buf);
        fs.closeSync(file);
        Logger.info('Ui.Review', `海报生成 ${path} bytes=${buf.byteLength}`);
      } catch (err) {
        // 只有「生成不出图」才降级文本；分享面板本身打不开不再二次弹面板
        Logger.warn('Ui.Review', `海报生成失败，降级文本: ${(err as Error).message}`);
        this.toast('海报没生成出来，已改为分享行程文字');
        try {
          await ShareExporter.shareSummary(ctx, trip);
        } catch (err2) {
          Logger.warn('Ui.Review', `文本分享也失败: ${(err2 as Error).message}`);
          this.toast('分享面板未能打开');
        }
        return;
      }
      try {
        await ShareExporter.shareImage(ctx, path, `${review.city} 旅行回顾`);
      } catch (err) {
        // 用户在分享面板点取消也可能走到这里：此时图已生成，不再假装降级
        Logger.warn('Ui.Review', `分享面板未能打开或已取消: ${(err as Error).message}`);
        this.toast('分享面板未能打开');
      }
    } finally {
      this.sharing = false;
    }
  }

  @Builder
  posterStat(value: string, label: string) {
    Column({ space: SpaceTokens.xs }) {
      Text(value)
        .fontSize(TypeTokens.headline.size)
        .fontWeight(600)
        .fontColor(ColorTokens.ink)
        .fontFeature("'tnum' on")
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(label)
        .fontSize(TypeTokens.overline.size)
        .fontWeight(450)
        .fontColor(ColorTokens.muted)
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  /** 屏幕内按容器铺满；离屏快照用固定宽（builder 根宽为 0 会直接失败） */
  @Builder
  posterCard(fixedWidth: boolean) {
    Column({ space: SpaceTokens.sm }) {
      Row() {
        Text('旅途回放')
          .fontSize(TypeTokens.overline.size)
          .fontWeight(600)
          .fontColor(ColorTokens.muted)
        Blank()
        SymbolGlyph($r('sys.symbol.medal'))
          .fontSize(IconSizes.control)
          .fontColor([ColorTokens.primary])
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.pvCity)
        .fontSize(TypeTokens.title.size)
        .fontWeight(700)
        .fontFamily(TypeTokens.title.family)
        .fontColor(ColorTokens.ink)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: SpaceTokens.xs })

      Text(this.pvDates)
        .fontSize(TypeTokens.caption.size)
        .fontWeight(450)
        .fontColor(ColorTokens.muted)
        .fontFeature("'tnum' on")

      Text(this.pvMeta)
        .fontSize(TypeTokens.small.size)
        .fontWeight(450)
        .fontColor(ColorTokens.body)
        .fontFeature("'tnum' on")

      Row() {
        this.posterStat(this.pvStops, '打卡')
        this.posterStat(this.pvBadges, '新章')
        this.posterStat(this.pvSpend, '记账')
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .margin({ top: SpaceTokens.md })

      Text('有径 · 去过的地方都算数')
        .fontSize(TypeTokens.overline.size)
        .fontWeight(450)
        .fontColor(ColorTokens.muted)
        .margin({ top: SpaceTokens.md })
    }
    .width(fixedWidth ? 320 : '100%')
    .padding(SpaceTokens.xl)
    .borderRadius(RadiusTokens.hero)
    .backgroundColor(ColorTokens.surfaceElevated)
    .alignItems(HorizontalAlign.Start)
  }

  /** 离屏快照的外框：垫一层画布色，避免 JPEG 把卡片圆角外的透明区压成白角 */
  @Builder
  posterShot() {
    Column() {
      this.posterCard(true)
    }
    .width(352)
    .padding(SpaceTokens.lg)
    .backgroundColor(ColorTokens.canvas)
  }

  @Builder
  posterSection() {
    Column() {
      this.posterCard(false)
      Row({ space: SpaceTokens.md }) {
        YoujingButton({
          variant: YoujingButtonVariant.PRIMARY,
          label: this.sharing ? '生成中…' : '分享海报',
          buttonWidth: 150,
          disabled: this.sharing,
          onAction: (): void => {
            this.sharePoster();
          }
        })
        YoujingButton({
          variant: YoujingButtonVariant.TEXT,
          label: '完整行程',
          buttonWidth: 120,
          onAction: (): void => {
            this.openItinerary();
          }
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ top: SpaceTokens.md })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  /** 海报已展示三格统计，这里只补时间与凭证口径，避免同屏把同一组数字印两遍 */
  private arrivalLine(): string {
    return this.arrivalTotal > 0
      ? `到站打卡 ${this.arrivalTotal} 次 · 带位置凭证`
      : '均为手动打卡 · 未带位置凭证';
  }

  @Builder
  statsCard() {
    Column({ space: SpaceTokens.sm }) {
      Text(this.arrivalLine())
        .fontSize(TypeTokens.caption.size)
        .fontWeight(450)
        .fontColor(ColorTokens.muted)
        .fontFeature("'tnum' on")

      if (this.firstText.length > 0) {
        Text(`首次 ${this.firstText} · 末次 ${this.lastText}`)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .fontFeature("'tnum' on")
      }
    }
    .width('100%')
    .padding(SpaceTokens.lg)
    .borderRadius(RadiusTokens.card)
    .backgroundColor(ColorTokens.surfaceElevated)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  dayHeader(day: ReviewDay) {
    Column({ space: SpaceTokens.xs }) {
      Row() {
        Text(`Day ${day.dayIndex}`)
          .fontSize(TypeTokens.overline.size)
          .fontWeight(600)
          .fontColor(ColorTokens.muted)
          .fontFeature("'tnum' on")
        Text(this.mdText(day.date))
          .fontSize(TypeTokens.overline.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .fontFeature("'tnum' on")
          .margin({ left: SpaceTokens.sm })
        Blank()
        Text(`${day.checked.length} / ${day.total}`)
          .fontSize(TypeTokens.overline.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .fontFeature("'tnum' on")
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (day.theme.length > 0) {
        Text(day.theme)
          .fontSize(TypeTokens.overline.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .backgroundColor(ColorTokens.canvas)
    .padding({ top: SpaceTokens.md, bottom: SpaceTokens.xs })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  checkedRow(item: ReviewItem) {
    Row({ space: SpaceTokens.sm }) {
      SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
        .fontSize(IconSizes.control)
        .fontColor([ColorTokens.primary])
      Column({ space: SpaceTokens.xs }) {
        Text(item.title)
          .fontSize(TypeTokens.small.size)
          .fontWeight(600)
          .fontColor(ColorTokens.ink)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${item.time} 排定 · ${reviewTimeText(item.checkedAt)} 打卡`)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .fontFeature("'tnum' on")
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (item.arrival) {
        Text('到站')
          .fontSize(TypeTokens.overline.size)
          .fontWeight(600)
          .fontColor(ColorTokens.primary)
      }
    }
    .width('100%')
    .padding(SpaceTokens.md)
    .borderRadius(RadiusTokens.card)
    .backgroundColor(ColorTokens.surfaceElevated)
    .alignItems(VerticalAlign.Center)
    .margin({ bottom: SpaceTokens.sm })
  }

  @Builder
  emptyDayRow() {
    Text('这天没有打卡记录')
      .fontSize(TypeTokens.caption.size)
      .fontWeight(450)
      .fontColor(ColorTokens.muted)
      .width('100%')
      .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
  }

  @Builder
  badgesCard() {
    Column({ space: SpaceTokens.sm }) {
      Text(`本次收下 ${this.newBadges.length} 枚章`)
        .fontSize(TypeTokens.overline.size)
        .fontWeight(600)
        .fontColor(ColorTokens.muted)
        .fontFeature("'tnum' on")
      ForEach(this.newBadges, (badge: Badge) => {
        Row({ space: SpaceTokens.sm }) {
          SymbolGlyph($r('sys.symbol.medal'))
            .fontSize(IconSizes.control)
            .fontColor([ColorTokens.primary])
          Text(badge.spotName)
            .fontSize(TypeTokens.small.size)
            .fontWeight(600)
            .fontColor(ColorTokens.ink)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(badgeDateText(badge.earnedAt))
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
            .fontFeature("'tnum' on")
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }, (badge: Badge): string => `review-badge-${badge.firstCheckinId}`)
    }
    .width('100%')
    .padding(SpaceTokens.lg)
    .borderRadius(RadiusTokens.card)
    .backgroundColor(ColorTokens.surfaceElevated)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  overviewCard() {
    Column({ space: SpaceTokens.sm }) {
      Text('这趟的样子')
        .fontSize(TypeTokens.overline.size)
        .fontWeight(600)
        .fontColor(ColorTokens.muted)
      if (this.summaryText.length > 0) {
        Text(this.summaryText)
          .fontSize(TypeTokens.small.size)
          .fontWeight(450)
          .fontColor(ColorTokens.body)
      }
      ForEach(this.highlights, (item: string, i: number) => {
        Row({ space: SpaceTokens.sm }) {
          Text('·')
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.faint)
          Text(item)
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.body)
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }, (item: string, i: number): string => `review-hl-${i}-${item}`)
    }
    .width('100%')
    .padding(SpaceTokens.lg)
    .borderRadius(RadiusTokens.card)
    .backgroundColor(ColorTokens.surfaceElevated)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  content() {
    List({ space: SpaceTokens.md }) {
      ListItem() {
        this.posterSection()
      }
      ListItem() {
        this.statsCard()
      }
      ForEach(this.days, (day: ReviewDay) => {
        ListItemGroup({ header: this.dayHeader(day) }) {
          if (day.checked.length === 0) {
            ListItem() {
              this.emptyDayRow()
            }
          } else {
            ForEach(day.checked, (item: ReviewItem) => {
              ListItem() {
                this.checkedRow(item)
              }
            }, (item: ReviewItem): string => `review-${day.dayIndex}-${item.activityId}`)
          }
        }
      }, (day: ReviewDay): string => `review-day-${day.dayIndex}`)
      if (this.newBadges.length > 0) {
        ListItem() {
          this.badgesCard()
        }
      }
      if (this.summaryText.length > 0 || this.highlights.length > 0) {
        ListItem() {
          this.overviewCard()
        }
      }
      ListItem() {
        Text('回顾在本机生成，不上传服务器、不含账号信息')
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .cachedCount(6)
    .padding({ left: this.wideInset(), right: this.wideInset(),
      bottom: LayoutTokens.floatingDockClearance })
  }

  @Builder
  emptyState() {
    Column({ space: SpaceTokens.md }) {
      SymbolGlyph($r('sys.symbol.medal'))
        .fontSize(IconSizes.display)
        .fontColor([ColorTokens.muted])
      Text('这趟还没有可回顾的打卡')
        .fontSize(TypeTokens.title.size)
        .fontWeight(700)
        .fontFamily(TypeTokens.title.family)
        .fontColor(ColorTokens.ink)
        .textAlign(TextAlign.Center)
      Text('在「旅行中」给节点打卡，这里会按天回放你去过的地方')
        .fontSize(TypeTokens.small.size)
        .fontWeight(450)
        .fontColor(ColorTokens.muted)
        .textAlign(TextAlign.Center)
        .constraintSize({ maxWidth: 240 })
      YoujingButton({
        variant: YoujingButtonVariant.SECONDARY,
        label: '查看完整行程',
        buttonWidth: 180,
        onAction: (): void => {
          this.openItinerary();
        }
      })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding(SpaceTokens.lg)
  }

  build() {
    HdsNavDestination() {
      Column() {
        if (this.loading) {
          Column({ space: SpaceTokens.md }) {
            LoadingProgress()
              .width(IconSizes.display)
              .height(IconSizes.display)
              .color(ColorTokens.primary)
            Text('读取回顾…')
              .fontSize(TypeTokens.small.size)
              .fontColor(ColorTokens.muted)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (!this.loaded || this.checkedTotal === 0) {
          this.emptyState()
        } else {
          this.content()
        }
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(ColorTokens.canvas)
    }
    // HDS 深色档这层默认纯黑，透明栏会把它露成一条比画布暗一档的带（成因与实测见 Docs/INIT_REPORT.md §5ci 续 80）
    .backgroundColor(ColorTokens.canvas)
    .titleBar(HdsChrome.bar({ mainTitle: '旅行回顾' }))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .onReady((ctx: NavDestinationContext): void => {
      this.pathStack = ctx.pathStack;
    })
  }
}
