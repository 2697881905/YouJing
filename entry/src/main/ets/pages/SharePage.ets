/**
 * 屏16 分享与导出（帧 074108e2）。
 * §7 必改已落：icon-btn margin 10→8、option-icon-box margin 6→4、scroll 76→94。
 * 阶段 10 接真：.ics 本机生成后走系统分享面板；行程文本同样走分享面板。
 * 无后端 ⇒ 生成不了「7 天有效」的链接，故按钮与副文案按实际能力改口（分享行程文本 / 本机生成不上传）。
 * 帧 hero 第三格是「步行 24.6km」：AI 载荷不给节点间步行距离、也无路线服务可算，不编造，
 * 该格改显「需预约」节点数（真数，且与 .ics 的提醒条数同源）。
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
import { TripDao } from '../data/TripDao';
import { ShareExporter } from '../data/ShareExporter';
import { IcsBuilder } from '../utils/IcsBuilder';
import { EntitlementStore } from '../data/EntitlementStore';
import { APP_NAV } from '../common/constants/AppNav';
import { Trip } from '../model/Trip';
import { Logger } from '../common/logger/Logger';
import { common } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode, HideMode } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';
import { TripSpan } from '../utils/TripSpan';
import { requestSystemBarRefresh } from '../utils/systemBar';

interface ShareOption {
  symbol: Resource;
  title: string;
  desc: string;
}

/** .ics 提醒提前天数：与 CalendarSync 同一口径（固定 1 天） */
const ICS_ADVANCE_DAYS: number = 1;

@Component
export struct SharePage {
  /** 窗口实测宽（vp），由断点中心一处测量；0 = 尚未测到，按不收窄处理 */
  @StorageProp(KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 0;

  /** 宽屏下的左右内缩：手机档原样返回 base（等于没改），折叠屏展开把内容收成 600vp 一栏 */
  private wideInset(): number {
    return symmetricInsetForCap(this.windowWidthVp, BP_MD_MIN_VP, SpaceTokens.base);
  }
  @Prop tripId: string = '';
  @State private subtitle: string = '';
  @State private dayCount: number = 0;
  @State private stopCount: number = 0;
  @State private bookingCount: number = 0;
  @State private options: ShareOption[] = [
    { symbol: $r('sys.symbol.share'), title: '分享行程文本', desc: '经系统分享面板发出行程清单，不含账号信息' },
    { symbol: $r('sys.symbol.calendar'), title: '导出日历文件 (.ics)', desc: '本机生成，可导入任意日历应用' }
  ];
  /** 顶栏磨砂两态：由**绝对**滚动偏移驱动（每帧增量会被松手回弹的负帧打灭，契约 §Translucency） */
  @State private barScrolled: boolean = false;
  private barScroller: Scroller = new Scroller();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  private trip: Trip | null = null;
  private pathStack: NavPathStack = APP_NAV;

  aboutToAppear(): void {
    if (this.tripId.length === 0) {
      return;
    }
    TripDao.loadTrip(this.getUIContext().getHostContext() as common.UIAbilityContext, this.tripId)
      .then((trip: Trip | null): void => {
        if (trip === null) {
          return;
        }
        this.trip = trip;
        let stops: number = 0;
        for (const d of trip.days) {
          stops += d.activities.length;
        }
        this.dayCount = trip.days.length;
        this.stopCount = stops;
        this.bookingCount = IcsBuilder.bookingCount(trip);
        this.subtitle = `${trip.destination} ${TripSpan.text(trip.days.length)} · ${stops} 个节点`;
        this.options = [
          { symbol: $r('sys.symbol.share'), title: '分享行程文本',
            desc: '经系统分享面板发出行程清单，不含账号信息' },
          { symbol: $r('sys.symbol.calendar'), title: '导出日历文件 (.ics)',
            desc: `含 ${this.bookingCount} 个需预约提醒，可导入任意日历应用` }
        ];
      }).catch((err: Error) => {
        Logger.error('Ui.Share', `行程加载失败: ${err.message}`);
      });
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1800 });
  }

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

  private exportIcs(): void {
    const trip: Trip | null = this.trip;
    if (trip === null) {
      this.toast('行程未就绪');
      return;
    }
    if (!EntitlementStore.canExport(this.tripId)) {
      // 反馈落在目的页标题上（真机实测：toast 紧跟 pushPath 时提示根本不显示，
      // 截图里整屏没有浮层）——先标理由，付费页据此换成导出口径
      PricingReason.markExportGate();
      this.pathStack.pushPath({ name: 'Pricing', param: this.tripId });
      return;
    }
    // 提醒提前量与 CalendarSync 同一口径：固定提前 1 天（Activity 不带 advanceDays）
    ShareExporter.shareIcs(this.ctx(), trip, ICS_ADVANCE_DAYS).then((events: number): void => {
      // 成功不再补 toast：面板本身就是反馈。真机复拍确认拉起的是系统分享面板，
      // 里面已经写着「北京 行程日历.ics · 3.38 KB」——在它背后再喊一句只是噪音。
      Logger.info('Ui.Share', `ics 导出 ${events} 事件`);
    }).catch((err: Error) => {
      Logger.warn('Ui.Share', `ics 导出失败: ${err.message}`);
      this.toast('日历文件生成失败');
    });
  }

  @Builder
  optionRow(opt: ShareOption) {
    Column() {
      Row({ space: SpaceTokens.sm }) {
        Column() {
          SymbolGlyph(opt.symbol)
            .fontSize(IconSizes.control)
            .fontColor([ColorTokens.ink])
        }
        .width(LayoutTokens.minTouchTarget)
        .height(LayoutTokens.minTouchTarget)
        .justifyContent(FlexAlign.Center)
        .borderRadius(RadiusTokens.media)
        .backgroundColor(ColorTokens.surfaceSubtle)

        Column() {
          Text(opt.title)
            .fontSize(TypeTokens.small.size)
            .fontWeight(600)
            .fontColor(ColorTokens.ink)
          Text(opt.desc)
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

      }
      .width('100%')
      .padding({ top: SpaceTokens.xs, bottom: SpaceTokens.xs })
    }
    .width('100%')
  }

  /** 路线带上的编号：最多画 6 个，超出部分在副标题里报真实站数 */
  private nodeLabels(): string[] {
    const cap: number = this.stopCount > 6 ? 6 : this.stopCount;
    const out: string[] = [];
    for (let i = 1; i <= cap; i++) {
      out.push(`${i}`);
    }
    return out;
  }

  private ribbonCaption(): string {
    if (this.stopCount <= 0) {
      return '这条行程还没有节点';
    }
    if (this.stopCount > 6) {
      return `共 ${this.stopCount} 站，图上只画前 6 站`;
    }
    return `全程 ${this.stopCount} 站`;
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

          // 官方 List：抬头 + 行程卡成一个 ListItem，两条动作成一个 ListItemGroup，
          // 行间不再手画 Divider，交给官方 .divider()
          List({ scroller: this.barScroller }) {
            ListItem() {
              Column() {
                Text('分享这份行程')
                  .fontSize(TypeTokens.title.size)
                  .fontWeight(700)
                  .fontFamily(TypeTokens.title.family)
                  .fontColor(ColorTokens.ink)
                  .margin({ top: SpaceTokens.base })
                Text(this.subtitle.length > 0 ? this.subtitle : '行程未就绪')
                  .fontSize(TypeTokens.small.size)
                  .fontColor(ColorTokens.body)
                  .fontFeature("'tnum' on")
                  .margin({ top: SpaceTokens.xxs, bottom: SpaceTokens.lg })

                Column() {
                  // 底稿这块是「路线图带」：编号圆点串在一条线上，下面压一道浅色河带。
                  // 上一轮删掉的 140vp「行程纸」之所以是空占位，是因为它想画这张图却没数据源；
                  // 现在用**真实节点数**画出来（不编任何数据），删占位留下的半屏空洞一并补上。
                  // 帧的原话是「编号圆点串在一条线上，下面压一道浅色河带」——河带是**垫在圆点下面**
                  // 那条线，不是圆点之外再画一道空槽。上一版把它画成脱离圆点行的独立灰条，
                  // 实拍读起来就是"还在加载的骨架条"（2026-11-04 真机）。改成 Stack 垫底。
                  Stack({ alignContent: Alignment.Center }) {
                    Column()
                      .width('88%')
                      .height(10)
                      .borderRadius(RadiusTokens.pill)
                      .backgroundColor(ColorTokens.surfaceSubtle)
                    Row({ space: 0 }) {
                      ForEach(this.nodeLabels(), (lab: string, i: number) => {
                      if (i > 0) {
                        Column()
                          .width(22)
                          .height(LayoutTokens.routeLineWidth)
                          .backgroundColor(ColorTokens.separator)
                      }
                      Stack() {
                        Circle()
                          .width(26)
                          .height(26)
                          .fill(i === 0 ? ColorTokens.primary : ColorTokens.surfaceElevated)
                          .stroke(i === 0 ? ColorTokens.primary : ColorTokens.separator)
                          .strokeWidth(1)
                        Text(lab)
                          .fontSize(TypeTokens.overline.size)
                          .fontWeight(600)
                          .fontColor(i === 0 ? ColorTokens.onPrimary : ColorTokens.body)
                          .fontFeature("'tnum' on")
                      }
                      .width(26)
                      .height(26)
                    }, (lab: string, i: number): string => `share-node-${i}-${lab}`)
                    }
                    .justifyContent(FlexAlign.Center)
                    .width('100%')
                  }
                  .width('100%')
                  .height(30)

                  Text(this.ribbonCaption())
                    .fontSize(TypeTokens.overline.size)
                    .fontWeight(450)
                    .fontColor(ColorTokens.muted)
                    .fontFeature("'tnum' on")
                    .margin({ top: SpaceTokens.xxs, bottom: SpaceTokens.base })

                  Row() {
                    // 三个数在 build 内直读状态变量：@Builder 形参是值快照，行程异步到达后不会刷新
                    Column() {
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
                    Column() {
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
                    Column() {
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
                  }
                  .width('100%')
                  .justifyContent(FlexAlign.SpaceAround)
                  .margin({ top: SpaceTokens.sm })
                }
                .width('100%')
                .padding(SpaceTokens.base)
                .borderRadius(RadiusTokens.card)
                .backgroundColor(ColorTokens.surfaceElevated)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
            }

            if (this.options.length >= 2) {
              ListItemGroup() {
                ListItem() {
                  this.optionRow(this.options[0])
                }
                .onClick((): void => {
                  this.shareText();
                })
                ListItem() {
                  this.optionRow(this.options[1])
                }
                .onClick((): void => {
                  this.exportIcs();
                })
              }
              .divider({ strokeWidth: LayoutTokens.hairlineWidth, color: ColorTokens.separator })
              .padding({ left: SpaceTokens.base, right: SpaceTokens.base })
              .backgroundColor(ColorTokens.surfaceSubtle)
              .borderRadius(RadiusTokens.card)
              .clip(true)
              .margin({ top: SpaceTokens.lg })
            }
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .cachedCount(4)
          .alignListItem(ListItemAlign.Start)
          // 钉底动作条已撤（见下），只需让出 dock 自身净空
          .padding({ left: this.wideInset(), right: this.wideInset(),
            bottom: LayoutTokens.floatingDockClearance })
          .onDidScroll((): void => {
            this.syncBarScroll();
          })
        }
        .padding({ top: HdsChrome.contentTopInset(this.statusBarHeight) })
        .width('100%')
        .height('100%')

        // 底稿屏16 没有钉底动作条：两个动作就是列表里那两行。
        // 原来这里又摆一颗「导出 .ics」+一颗「分享行程文本」，与上面两行完全重复
        // （同一屏两套入口，正是"业务流程混乱"的形态之一），撤掉，只留常驻的诚实说明。
        Column({ space: SpaceTokens.xs }) {
          Text('内容在本机生成，不上传服务器、不含账号信息')
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
        }
        .width('100%')
        // 钉底动作条原来只留 xl(24)：这一屏也挂在悬浮 dock 上，
        // 结果「导出 .ics / 分享行程文本」整条被 dock 压住、说明文字裁掉半行
        // （与屏2、首页同一类缺陷）。改成让出实测 dock 净空
        .padding({ left: this.wideInset(), right: this.wideInset(), bottom: LayoutTokens.floatingDockClearance })
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
    .titleBar(HdsChrome.bar({ mainTitle: '分享与导出', scrolled: this.barScrolled }))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .onReady((ctx: NavDestinationContext): void => {
      this.pathStack = ctx.pathStack;
    })
  }

}
