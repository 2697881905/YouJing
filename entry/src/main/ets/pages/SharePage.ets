/**
 * 屏16 分享与导出（帧 074108e2）。
 * §7 必改已落：icon-btn margin 10→8、option-icon-box margin 6→4、scroll 76→94。
 * 阶段 10 接真：.ics 本机生成后走系统分享面板；行程文本同样走分享面板。
 * 无后端 ⇒ 生成不了「7 天有效」的链接，故按钮与副文案按实际能力改口（分享行程文本 / 本机生成不上传）。
 * 帧 hero 第三格是「步行 24.6km」：AI 载荷不给节点间步行距离、也无路线服务可算，不编造，
 * 该格改显「需预约」节点数（真数，且与 .ics 的提醒条数同源）。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { TripDao } from '../data/TripDao';
import { ShareExporter } from '../data/ShareExporter';
import { IcsBuilder } from '../utils/IcsBuilder';
import { Trip } from '../model/Trip';
import { Logger } from '../common/logger/Logger';
import { common } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';

interface ShareOption {
  symbol: Resource;
  title: string;
  desc: string;
}

@Component
export struct SharePage {
  private pathStack: NavPathStack = APP_NAV;
  @Prop tripId: string = '';
  @State private subtitle: string = '';
  @State private dayCount: number = 0;
  @State private stopCount: number = 0;
  @State private bookingCount: number = 0;
  @State private options: ShareOption[] = [
    { symbol: $r('sys.symbol.share'), title: '分享行程文本', desc: '经系统分享面板发出行程清单，不含账号信息' },
    { symbol: $r('sys.symbol.calendar'), title: '导出日历文件 (.ics)', desc: '本机生成，可导入任意日历应用' }
  ];
  private trip: Trip | null = null;

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
        this.subtitle = `${trip.destination} ${trip.days.length}天${trip.days.length - 1}晚 · ${stops} 个节点`;
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
    ShareExporter.shareIcs(this.ctx(), trip, 1).then((events: number): void => {
      Logger.info('Ui.Share', `ics 导出 ${events} 事件`);
    }).catch((err: Error) => {
      Logger.warn('Ui.Share', `ics 导出失败: ${err.message}`);
      this.toast('日历文件生成失败');
    });
  }

  @Builder
  optionRow(opt: ShareOption) {
    Column() {
      Row({ space: SpaceTokens.md }) {
        Column() {
          SymbolGlyph(opt.symbol)
            .fontSize(IconSizes.control)
            .fontColor([ColorTokens.ink])
        }
        .width(44)
        .height(44)
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

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(IconSizes.control)
          .fontColor([ColorTokens.faint])
      }
      .width('100%')
      .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
    }
    .width('100%')
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        Column() {

          // 官方 List：抬头 + 行程卡成一个 ListItem，两条动作成一个 ListItemGroup，
          // 行间不再手画 Divider，交给官方 .divider()
          List() {
            ListItem() {
              Column() {
                Text('分享这份行程')
                  .fontSize(TypeTokens.title.size)
                  .fontWeight(700)
                  .fontFamily(TypeTokens.title.family)
                  .fontColor(ColorTokens.ink)
                  .margin({ top: SpaceTokens.lg })
                Text(this.subtitle.length > 0 ? this.subtitle : '行程未就绪')
                  .fontSize(TypeTokens.small.size)
                  .fontColor(ColorTokens.body)
                  .fontFeature("'tnum' on")
                  .margin({ top: SpaceTokens.xs, bottom: SpaceTokens.xl })

                Column() {
                  // 「行程纸」：浅色档是白→#F1F2F5，压在浅灰卡上边界会消失（真机浅色拍到过），
                  // 补一条 hairline 描边，两档都读得出这是一块纸而不是空槽
                  Column()
                    .width('100%')
                    .height(140)
                    .borderRadius(RadiusTokens.media)
                    .border({ width: LayoutTokens.hairlineWidth, color: ColorTokens.borderSubtle })
                    .linearGradient({
                      angle: 180,
                      colors: [[ColorTokens.routeBgTop, 0], [ColorTokens.routeBgBottom, 1]]
                    })
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
                  .margin({ top: SpaceTokens.md })
                }
                .width('100%')
                .padding(SpaceTokens.lg)
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
              .padding({ left: SpaceTokens.md, right: SpaceTokens.md })
              .backgroundColor(ColorTokens.surfaceSubtle)
              .borderRadius(RadiusTokens.card)
              .clip(true)
              .margin({ top: SpaceTokens.xl })
            }
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .cachedCount(4)
          .alignListItem(ListItemAlign.Start)
          .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, bottom: LayoutTokens.shareBarScrollReserve })
        }
        .width('100%')
        .height('100%')

        Column({ space: SpaceTokens.sm }) {
          Row({ space: SpaceTokens.md }) {
            YoujingButton({
              variant: YoujingButtonVariant.SECONDARY,
              label: '导出 .ics',
              buttonWidth: 150,
              onAction: (): void => {
                this.exportIcs();
              }
            })
            YoujingButton({
              variant: YoujingButtonVariant.PRIMARY,
              label: '分享行程文本',
              onAction: (): void => {
                this.shareText();
              }
            })
              .layoutWeight(1)
          }
          .width('100%')

          Text('内容在本机生成，不上传服务器、不含账号信息')
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
        }
        .width('100%')
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, bottom: SpaceTokens.xl })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ColorTokens.canvas)
    }
    .titleBar(HdsChrome.bar({ mainTitle: '分享与导出' }))
    .titleMode(HdsNavDestinationTitleMode.MINI)
  }

}
