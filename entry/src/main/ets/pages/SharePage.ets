/**
 * 屏16 分享与导出 · 2026-11-11 全面重构（用户令「分享功能太简陋，所有分享页重构」）。
 *
 * 重构思路（一句话：所见即所发 + 四种高效出口）：
 * 1) 预览卡就是长图本身（同一个 builder：页内 width 100%，离屏快照固定 320）——
 *    用户不用先点「生成」再猜发出去长什么样，WYSIWYG。
 * 2) 动作扁平一列（2026-11-11 用户令「化繁为简」，删页题/分组头/格式说明行）：
 *    分享行程（primary）/ 分享长图（secondary）/ 复制文本（ghost，剪贴板直写，不开面板）/
 *    导出 .ics（列表行）。文本清单仍是系统分享面板的完整版。
 * 3) 长图主角：静态地图就绪 → 动线图；未就绪/失败 → 每日行（每天前两站 + 「等 N 站」，
 *    最多 4 天，超出如实写「另有 N 天」）。文本清单始终逐站全量（含餐饮/住宿/提示）。
 * 4) 口径不变：行程数据不上传业务服务器、不含账号信息；.ics 与长图走导出付费墙。
 *    长图底图由 Map Kit staticMap 离屏渲染（图钉=全部可上图站点，动线仅单天行程画——
 *    跨天直连线会误导，取景与口径见 utils/StaticMapPlan.ets），失败静默降级回每日行。
 *
 * 帧 074108e2 的路线带（编号圆点）改成了真实每日行——圆点编号只是装饰，
 * 分享页真正的说服力是「目的地 + 日期 + 每天去哪」，这里按真值画。
 */

import { PricingReason } from '../utils/PricingReason';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { KEY_WINDOW_WIDTH_VP, BP_MD_MIN_VP } from '../utils/breakpointCenter';
import { symmetricInsetForCap } from '../utils/responsive';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { Pressable } from '../components/Pressable';
import { TripDao } from '../data/TripDao';
import { ShareExporter } from '../data/ShareExporter';
import { IcsBuilder } from '../utils/IcsBuilder';
import { EntitlementStore } from '../data/EntitlementStore';
import { APP_NAV } from '../common/constants/AppNav';
import { Trip } from '../model/Trip';
import { Logger } from '../common/logger/Logger';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';
import { TripSpan } from '../utils/TripSpan';
import { requestSystemBarRefresh } from '../utils/systemBar';
import { mapCommon, staticMap } from '@kit.MapKit';
import { MapStops, MapStop } from '../utils/MapStops';
import { StaticMapPlan } from '../utils/StaticMapPlan';

/** 长图里最多画几天：再多就只在图上写「另有 N 天」，避免分享图变成一屏长条 */
const POSTER_MAX_DAYS: number = 4;
/** 每天最多列几站（后面用「等 N 站」收口，不把长图撑爆） */
const POSTER_STOPS_PER_DAY: number = 2;
/** .ics 提醒提前天数：与 CalendarSync 同一口径（固定 1 天） */
const ICS_ADVANCE_DAYS: number = 1;
/** 静态地图图幅（px，scale=1 上限 1024）：卡内显示 288×176vp，三倍屏下 960px 够清晰 */
const MAP_IMAGE_WIDTH: number = 960;
const MAP_IMAGE_HEIGHT: number = 600;
/** 卡内地图带显示高度（vp）：16:10 图幅在 288vp 卡宽下的视觉高度 */
const MAP_CARD_HEIGHT: number = 176;
/** 静态图动线色：与 TripMapView.LINE_LIGHT 同源（route_path 档浅色，Map Kit 只吃 ARGB） */
const MAP_LINE_COLOR: number = 0xFF0066CC;

/** 长图/预览卡用的每日一行 */
interface ShareDayRow {
  index: number;
  date: string;
  theme: string;
  stops: string;
}

@Component
export struct SharePage {
  // 深浅档代 tick：翻档时 EntryAbility 自增，@StorageProp 变化带动本页 build 重跑，
  // 把新 tick 传进 HdsChrome.bar → 标题内容换新 ComponentContent 重挂载、按当前档重解色
  // （官方 HdsTitleBar 自绘内容不随配置切换重渲染，真机实证见 HdsChrome.themeTick）
  @StorageProp('chromeThemeTick') chromeThemeTick: number = 0;

  /** 窗口实测宽（vp），由断点中心一处测量；0 = 尚未测到，按不收窄处理 */
  @StorageProp(KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 0;

  /** 宽屏下的左右内缩：手机档原样返回 base（等于没改），折叠屏展开把内容收成 600vp 一栏 */
  private wideInset(): number {
    return symmetricInsetForCap(this.windowWidthVp, BP_MD_MIN_VP, SpaceTokens.base);
  }

  @Prop tripId: string = '';
  @State private destination: string = '';
  @State private dateRangeText: string = '';
  @State private people: number = 0;
  @State private dayCount: number = 0;
  @State private stopCount: number = 0;
  @State private bookingCount: number = 0;
  /** 长图每日行（最多 POSTER_MAX_DAYS 条），随行程加载一次性算好 */
  @State private dayRows: ShareDayRow[] = [];
  /** 超出 POSTER_MAX_DAYS 的天数；0 = 长图已覆盖全程 */
  @State private moreDays: number = 0;
  /** 静态地图（Map Kit 离屏渲染）：非空时长图主角从每日行换成动线图 */
  @State private mapImage: image.PixelMap | null = null;
  /** 已发起静态图请求的行程：防重入；失败时清空允许重试 */
  private mapTripId: string = '';
  /** 长图生成中：按钮给进行态，避免连点重复生成 */
  @State private sharingPoster: boolean = false;
  /** 顶栏磨砂两态：由**绝对**滚动偏移驱动（每帧增量会被松手回弹的负帧打灭，契约 §Translucency） */
  @State private barScrolled: boolean = false;
  private barScroller: Scroller = new Scroller();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  private trip: Trip | null = null;
  private pathStack: NavPathStack = APP_NAV;

  aboutToAppear(): void {
    this.loadTrip();
  }

  private loadTrip(): void {
    if (this.tripId.length === 0) {
      return;
    }
    TripDao.loadTrip(this.ctx(), this.tripId).then((trip: Trip | null): void => {
      if (trip === null) {
        return;
      }
      this.trip = trip;
      let stops: number = 0;
      for (const d of trip.days) {
        stops += d.activities.length;
      }
      this.destination = trip.destination;
      this.dateRangeText = `${this.longDate(trip.startDate)} – ${this.longDate(trip.endDate)}`;
      this.people = trip.people;
      this.dayCount = trip.days.length;
      this.stopCount = stops;
      this.bookingCount = IcsBuilder.bookingCount(trip);

      const rows: ShareDayRow[] = [];
      const cap: number = Math.min(trip.days.length, POSTER_MAX_DAYS);
      for (let i = 0; i < cap; i++) {
        const day = trip.days[i];
        const names: string[] = day.activities.map((a): string => a.title);
        const shown: string[] = names.slice(0, POSTER_STOPS_PER_DAY);
        let stopsText: string = shown.join(' · ');
        if (names.length === 0) {
          stopsText = '自由活动';
        } else if (names.length > shown.length) {
          stopsText += ` 等 ${names.length} 站`;
        }
        rows.push({
          index: day.dayIndex,
          date: this.shortDay(day.date),
          theme: day.theme.length > 0 ? day.theme : `第 ${day.dayIndex} 天`,
          stops: stopsText
        });
      }
      this.dayRows = rows;
      this.moreDays = trip.days.length - cap;
      this.loadStaticMap(trip);
    }).catch((err: Error) => {
      Logger.error('Ui.Share', `行程加载失败: ${err.message}`);
    });
  }

  /**
   * 静态地图：Map Kit 离屏渲染一张动线图（图钉+动线），成功后长图主角从每日行换成它。
   * 失败（断网/配额/鉴权）静默降级回每日行——预览与长图共用同一份状态，两处永远一致。
   */
  private loadStaticMap(trip: Trip): void {
    if (this.mapTripId === this.tripId) {
      return;
    }
    this.mapTripId = this.tripId;
    const stops: MapStop[] = MapStops.fromDays(trip.days);
    const spec = StaticMapPlan.build(stops, MAP_IMAGE_WIDTH, MAP_IMAGE_HEIGHT);
    if (spec === null) {
      this.mapTripId = '';
      return;
    }
    const opts: staticMap.StaticMapOptions = {
      location: {
        latitude: spec.centerLatitude, longitude: spec.centerLongitude
      } as mapCommon.LatLng,
      zoom: spec.zoom,
      imageWidth: MAP_IMAGE_WIDTH,
      imageHeight: MAP_IMAGE_HEIGHT
    };
    opts.markers = spec.points.map((s: MapStop): staticMap.StaticMapMarker => {
      const m: staticMap.StaticMapMarker = {
        location: { latitude: s.latitude, longitude: s.longitude } as mapCommon.LatLng
      };
      m.defaultIconSize = staticMap.IconSize.SMALL;
      return m;
    });
    if (spec.withPath) {
      opts.path = {
        locations: spec.points.map((s: MapStop): mapCommon.LatLng => {
          return { latitude: s.latitude, longitude: s.longitude } as mapCommon.LatLng;
        }),
        color: MAP_LINE_COLOR,
        width: 8
      };
    }
    staticMap.getMapImage(this.ctx(), opts).then((px: image.PixelMap): void => {
      this.mapImage = px;
      Logger.info('Ui.Share', `静态图就绪 zoom=${spec.zoom} pins=${spec.points.length}`);
    }).catch((err: Error): void => {
      Logger.warn('Ui.Share', `静态图失败(降级每日行): ${err.message}`);
      this.mapTripId = '';
    });
  }

  /** 2026-11-10 → 11月10日（长图日期行） */
  private longDate(iso: string): string {
    if (iso.length !== 10) {
      return iso;
    }
    return `${Number(iso.substring(5, 7))}月${Number(iso.substring(8, 10))}日`;
  }

  /** 2026-11-10 → 11/10（每日行左侧的 D 列） */
  private shortDay(iso: string): string {
    if (iso.length !== 10) {
      return iso;
    }
    return `${Number(iso.substring(5, 7))}/${Number(iso.substring(8, 10))}`;
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1800 });
  }

  /** 主动作：完整文本清单走系统分享面板（免费，不含账号信息） */
  private shareText(): void {
    const trip: Trip | null = this.trip;
    if (trip === null) {
      this.toast('行程未就绪');
      return;
    }
    ShareExporter.shareSummary(this.ctx(), trip).catch((err: Error) => {
      Logger.warn('Ui.Share', `文本分享失败: ${err.message}`);
      this.toast('分享面板未能打开');
    });
  }

  /** 复制完整文本：不想开系统面板、只想粘到微信/备忘录时的高频出口 */
  private copyText(): void {
    const trip: Trip | null = this.trip;
    if (trip === null) {
      this.toast('行程未就绪');
      return;
    }
    const data: pasteboard.PasteData =
      pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, IcsBuilder.plainSummary(trip));
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      Logger.info('Ui.Share', '行程文本已复制');
      this.toast('行程文本已复制');
    }).catch((err: Error) => {
      Logger.warn('Ui.Share', `复制失败: ${err.message}`);
      this.toast('复制失败，请重试');
    });
  }

  private exportIcs(): void {
    const trip: Trip | null = this.trip;
    if (trip === null) {
      this.toast('行程未就绪');
      return;
    }
    if (!EntitlementStore.canExport(this.tripId)) {
      // 反馈落在目的页标题上（真机实测：toast 紧跟 pushPath 时提示根本不显示）
      PricingReason.markExportGate();
      this.pathStack.pushPath({ name: 'Pricing', param: this.tripId });
      return;
    }
    // 提醒提前量与 CalendarSync 同一口径：固定提前 1 天（Activity 不带 advanceDays）
    ShareExporter.shareIcs(this.ctx(), trip, ICS_ADVANCE_DAYS).then((events: number): void => {
      // 成功不再补 toast：面板本身就是反馈
      Logger.info('Ui.Share', `ics 导出 ${events} 事件`);
    }).catch((err: Error) => {
      Logger.warn('Ui.Share', `ics 导出失败: ${err.message}`);
      this.toast('日历文件生成失败');
    });
  }

  /**
   * 分享长图：离屏快照同一个 shareCard → JPEG → 系统分享。
   * 生成失败才降级为文本分享并如实告知；面板打不开不二次弹面板。
   */
  private async sharePoster(): Promise<void> {
    const trip: Trip | null = this.trip;
    if (this.sharingPoster || trip === null) {
      return;
    }
    if (!EntitlementStore.canExport(this.tripId)) {
      PricingReason.markExportGate();
      this.pathStack.pushPath({ name: 'Pricing', param: this.tripId });
      return;
    }
    this.sharingPoster = true;
    const ctx: common.UIAbilityContext = this.ctx();
    try {
      let path: string = '';
      try {
        // delay 给地图像素图留纹理上传时间：0 会让 Image(pixelMap) 在离屏快照里截成白块
        // （真机实证 45.88KB 的全白长图），500ms 后同一张卡完整出图
        const pixelMap: image.PixelMap = await this.getUIContext().getComponentSnapshot()
          .createFromBuilder(() => {
            this.sharePosterShot();
          }, 500);
        const packer: image.ImagePacker = image.createImagePacker();
        const buf: ArrayBuffer = await packer.packToData(pixelMap, { format: 'image/jpeg', quality: 92 });
        await packer.release();
        await pixelMap.release();
        path = `${ctx.cacheDir}/youjing-share-${this.tripId}.jpg`;
        if (fs.accessSync(path)) {
          fs.unlinkSync(path);
        }
        const file: fs.File = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        fs.writeSync(file.fd, buf);
        fs.closeSync(file);
        Logger.info('Ui.Share', `长图生成 ${path} bytes=${buf.byteLength}`);
      } catch (err) {
        Logger.warn('Ui.Share', `长图生成失败，降级文本: ${(err as Error).message}`);
        this.toast('长图没生成出来，已改为分享行程文字');
        try {
          await ShareExporter.shareSummary(ctx, trip);
        } catch (err2) {
          Logger.warn('Ui.Share', `文本分享也失败: ${(err2 as Error).message}`);
          this.toast('分享面板未能打开');
        }
        return;
      }
      try {
        await ShareExporter.shareImage(ctx, path, `${trip.destination} 行程长图`);
      } catch (err) {
        // 用户在分享面板点取消也可能走到这里：此时图已生成，不假称生成失败
        Logger.warn('Ui.Share', `分享面板未能打开或已取消: ${(err as Error).message}`);
        this.toast('分享面板未能打开');
      }
    } finally {
      this.sharingPoster = false;
    }
  }

  /**
   * 长图本体：页内 width 100%，离屏快照固定 320。
   * 所有内容直读 @State（@Builder 的形参是创建时的值快照，行程异步到达后不会刷新——
   * 旧版这里正是踩过这条，故统计不走参数化 builder）。
   */
  @Builder
  shareCard(fixedWidth: boolean) {
    Column({ space: SpaceTokens.xxs }) {
      Row() {
        Text('有径')
          .fontSize(TypeTokens.overline.size)
          .fontWeight(600)
          .fontColor(ColorTokens.primary)
        Text(' · 行程分享')
          .fontSize(TypeTokens.overline.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
        Blank()
        Text('本机生成')
          .fontSize(TypeTokens.overline.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.destination.length > 0 ? this.destination : '行程')
        .fontSize(TypeTokens.title.size)
        .fontWeight(700)
        .fontFamily(TypeTokens.title.family)
        .fontColor(ColorTokens.ink)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: SpaceTokens.xs })

      Text(`${this.dateRangeText} · ${TripSpan.text(this.dayCount)} · ${this.people} 人`)
        .fontSize(TypeTokens.caption.size)
        .fontWeight(450)
        .fontColor(ColorTokens.muted)
        .fontFeature("'tnum' on")

      if (this.mapImage !== null) {
        // 行程→地图（2026-11-11 用户裁决）：静态图就绪后长图主角换成真实底图动线。
        // 每日行的信息不丢：分享行程（文本）仍是逐站全量清单，卡片下方统计行保留合计。
        Image(this.mapImage)
          .width('100%')
          .height(MAP_CARD_HEIGHT)
          .objectFit(ImageFit.Cover)
          // 卡级圆角（20）：media(6) 在三倍屏上几乎不可读（真机放大实测仅一丝弧线），
          // 与外框 hero(28) 同心收缩一档，地图才像「嵌进卡片的一块」而不是贴边直角
          .borderRadius(RadiusTokens.card)
          .margin({ top: SpaceTokens.sm })
          .accessibilityText(`${this.destination}行程动线地图，共 ${this.stopCount} 站`)
      } else if (this.dayRows.length > 0) {
        Column({ space: SpaceTokens.sm }) {
          ForEach(this.dayRows, (row: ShareDayRow) => {
            Row({ space: SpaceTokens.sm }) {
              // 天次徽章：品牌色胶囊 + 日期，整列居中（2026-11-11 卡片布局优化：
              // 裸文字 D1 读起来像标签残留，胶囊给它一个明确的「第几天」身份）
              Column({ space: SpaceTokens.xxs }) {
                Text(`D${row.index}`)
                  .fontSize(TypeTokens.overline.size)
                  .fontWeight(600)
                  .fontColor(ColorTokens.primary)
                  .fontFeature("'tnum' on")
                  .padding({
                    left: SpaceTokens.xxs, right: SpaceTokens.xxs,
                    top: SpaceTokens.xxs, bottom: SpaceTokens.xxs
                  })
                  .borderRadius(RadiusTokens.pill)
                  .backgroundColor(ColorTokens.primaryTint)
                Text(row.date)
                  .fontSize(TypeTokens.caption.size)
                  .fontWeight(450)
                  .fontColor(ColorTokens.muted)
                  .fontFeature("'tnum' on")
              }
              .alignItems(HorizontalAlign.Center)
              .width(40)

              Column({ space: SpaceTokens.xxs }) {
                Text(row.theme)
                  .fontSize(TypeTokens.small.size)
                  .fontWeight(600)
                  .fontColor(ColorTokens.ink)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(row.stops)
                  .fontSize(TypeTokens.caption.size)
                  .fontWeight(450)
                  .fontColor(ColorTokens.muted)
                  .lineHeight(TypeTokens.caption.lineHeight)
                  // 两行上限：单行会把「等 N 站」截成「等 3…」，收口语反而丢读者
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          }, (row: ShareDayRow): string => `share-day-${row.index}-${row.theme}`)

          if (this.moreDays > 0) {
            Text(`另有 ${this.moreDays} 天 · 共 ${this.stopCount} 站`)
              .fontSize(TypeTokens.caption.size)
              .fontWeight(450)
              .fontColor(ColorTokens.muted)
              .fontFeature("'tnum' on")
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .margin({ top: SpaceTokens.xs })
        .padding({ top: SpaceTokens.xs })
        .border({ width: { top: LayoutTokens.hairlineWidth }, color: ColorTokens.separator })
      }

      Row() {
        // 三个数直读状态（见方法头注释：参数化 builder 会冻在首帧的 0）
        Column({ space: SpaceTokens.xxs }) {
          Text(`${this.dayCount}`)
            .fontSize(TypeTokens.headline.size)
            .fontWeight(600)
            .fontColor(ColorTokens.ink)
            .fontFeature("'tnum' on")
          Text('天')
            .fontSize(TypeTokens.overline.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column({ space: SpaceTokens.xxs }) {
          Text(`${this.stopCount}`)
            .fontSize(TypeTokens.headline.size)
            .fontWeight(600)
            .fontColor(ColorTokens.ink)
            .fontFeature("'tnum' on")
          Text('站')
            .fontSize(TypeTokens.overline.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column({ space: SpaceTokens.xxs }) {
          Text(`${this.bookingCount}`)
            .fontSize(TypeTokens.headline.size)
            .fontWeight(600)
            .fontColor(ColorTokens.ink)
            .fontFeature("'tnum' on")
          Text('需预约')
            .fontSize(TypeTokens.overline.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .margin({ top: SpaceTokens.sm })

      Text('有径 · 有迹可循的旅程')
        .fontSize(TypeTokens.overline.size)
        .fontWeight(450)
        .fontColor(ColorTokens.muted)
        .margin({ top: SpaceTokens.sm })
    }
    .width(fixedWidth ? 320 : '100%')
    .padding(SpaceTokens.lg)
    .borderRadius(RadiusTokens.hero)
    .backgroundColor(ColorTokens.surfaceElevated)
    .alignItems(HorizontalAlign.Start)
  }

  /** 离屏快照外框：垫画布色，避免 JPEG 把卡片圆角外压成白角 */
  @Builder
  sharePosterShot() {
    Column() {
      this.shareCard(true)
    }
    .width(352)
    .padding(SpaceTokens.base)
    .backgroundColor(ColorTokens.canvas)
  }

  /** 导出日历行：图标盒 + 标题/说明 + chevron */
  @Builder
  exportRow() {
    Pressable({
      fillWidth: true,
      action: (): void => {
        this.exportIcs();
      }
    }) {
      Row({ space: SpaceTokens.sm }) {
        Column() {
          SymbolGlyph($r('sys.symbol.calendar'))
            .fontSize(IconSizes.control)
            .fontColor([ColorTokens.ink])
        }
        .width(LayoutTokens.minTouchTarget)
        .height(LayoutTokens.minTouchTarget)
        .justifyContent(FlexAlign.Center)
        .borderRadius(RadiusTokens.media)
        .backgroundColor(ColorTokens.surfaceSubtle)

        Column({ space: SpaceTokens.xxs }) {
          Text('导出日历文件 (.ics)')
            .fontSize(TypeTokens.small.size)
            .fontWeight(600)
            .fontColor(ColorTokens.ink)
          Text(this.bookingCount > 0
            ? `含 ${this.bookingCount} 个预约提醒 · 可导入任意日历`
            : '按站点时刻生成，可导入任意日历')
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
            .fontFeature("'tnum' on")
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(IconSizes.control)
          .fontColor([ColorTokens.icon])
      }
      .width('100%')
      .padding(SpaceTokens.base)
      .alignItems(VerticalAlign.Center)
      .borderRadius(RadiusTokens.card)
      .backgroundColor(ColorTokens.surfaceElevated)
      .accessibilityText(`导出日历文件，含 ${this.bookingCount} 个预约提醒`)
    }
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
      Column() {
        Scroll(this.barScroller) {
          Column({ space: SpaceTokens.base }) {
            // 长图预览：所见即所发（与离屏快照同一个 builder）。页题与「发给朋友 / 导出与备份」
            // 分组头已删（2026-11-11 用户令「化繁为简」）：导航栏已有标题、卡片自带目的地日期，
            // 它们只是重复；四个出口一列排开，视觉权重递减
            this.shareCard(false)

            YoujingButton({
              variant: YoujingButtonVariant.PRIMARY,
              label: '分享行程',
              fullWidth: true,
              leadingSymbol: $r('sys.symbol.share'),
              onAction: (): void => {
                this.shareText();
              }
            })

            YoujingButton({
              variant: YoujingButtonVariant.SECONDARY,
              label: this.sharingPoster ? '生成中…' : '分享长图',
              fullWidth: true,
              leadingSymbol: $r('sys.symbol.picture'),
              disabled: this.sharingPoster,
              onAction: (): void => {
                this.sharePoster();
              }
            })

            // 复制是轻量出口：ghost 档，不与两条「分享出去」抢视觉权重
            YoujingButton({
              variant: YoujingButtonVariant.TEXT,
              label: '复制文本',
              fullWidth: true,
              leadingSymbol: $r('sys.symbol.doc_text_on_doc_text'),
              onAction: (): void => {
                this.copyText();
              }
            })

            // 导出日历：备份出口
            this.exportRow()

            // 诚实口径：一句话说完，不笼统称「全本机」（底图图块走 Map Kit 配额）
            Text('行程数据不上传业务服务器；长图底图由系统地图服务渲染。')
              .fontSize(TypeTokens.caption.size)
              .fontWeight(450)
              .fontColor(ColorTokens.muted)
              .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({
            top: SpaceTokens.base,
            left: this.wideInset(),
            right: this.wideInset(),
            bottom: SpaceTokens.xl
          })
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        // 穿底让位（2026-11-08 对标有据）：让位从外层 padding 移到 contentStartOffset，
        // 只挪首屏起点；滚动后内容才穿得到标题栏下被材质糊掉。
        .contentStartOffset(HdsChrome.contentTopInset(this.statusBarHeight))
        .onDidScroll((): void => {
          this.syncBarScroll();
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ColorTokens.canvas)
    }
    // 不收栏（2026-11-08）：NavDestination 内容区恒预留 56vp 栏位、收栏后不回收，收起只留一条 175px 白带
    .bindToScrollable([this.barScroller])
    .clip(false)
    // HDS 深色档这层默认纯黑，透明栏会把它露成一条比画布暗一档的带（成因与实测见 Docs/INIT_REPORT.md §5ci 续 80）
    .backgroundColor(ColorTokens.canvas)
    .titleBar(HdsChrome.bar({ themeTick: this.chromeThemeTick, mainTitle: '分享与导出', scrolled: this.barScrolled }))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .onReady((ctx: NavDestinationContext): void => {
      this.pathStack = ctx.pathStack;
    })
  }
}
