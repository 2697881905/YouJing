/**
 * 屏7 生成受阻 · 降级重试（帧 a21e614c）。
 * §7 必改已落：scroll padding 104/180→94、solution-info gap 2→0。
 * 触发：Generating 失败分支，带 FailInfo{code,detail} 进来（阶段 10 接真错误）。
 * 底稿里「第 3 天没排通 / 伏见稻荷与宇治步行超 90 分钟 / 打车 ¥3,200」是编造的诊断，
 * 现按错误码出人话标题、原始诊断做次要说明，两条修法改成真能跳过去的步骤。
 * 骨架期仍可经 aa start --ps route GenerateFailed 直达（EntryAbility 预填通道）。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { failureHeadline } from '../common/error/FailureCopy';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { BuildConfig } from '../common/constants/BuildConfig';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';

interface FixOption {
  title: string;
  desc: string;
  route: string;
}

@Component
export struct GenerateFailedPage {
  private pathStack: NavPathStack = APP_NAV;
  @Prop code: number = 0;
  @Prop detail: string = '';
  private fixes: FixOption[] = [
    { title: '回选点页增减景点', desc: '去掉一个必去站，或补几个备选站点', route: 'SpotPick' },
    { title: '把每天的节奏调松', desc: '改成每天 3 站，给通勤留余量', route: 'PreferenceQA' }
  ];

  /** 原始诊断只在 debug 版露出；release 不甩「ApiConfig 占位」这类技术文本给用户 */
  private detailText(): string {
    if (!BuildConfig.IS_DEBUG) {
      return '可以按下面的方法调整后再试一次。';
    }
    return this.detail.length > 0 ? this.detail : '未收到具体原因（此屏为直接预览）';
  }

  @Builder
  solutionRow(fix: FixOption) {
    Row() {
      Column() {
        Text(fix.title)
          .fontSize(TypeTokens.small.size)
          .fontWeight(600)
          .fontColor(ColorTokens.ink)
        Text(fix.desc)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .fontFeature("'tnum' on")
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(IconSizes.control)
        .fontColor([ColorTokens.muted])
    }
    .width('100%')
    .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        Column() {

          Column() {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(IconSizes.display)
              .fontColor([ColorTokens.warning])
              .margin({ top: SpaceTokens.fiveXl, bottom: SpaceTokens.lg })
            Text(failureHeadline(this.code))
              .fontSize(TypeTokens.title.size)
              .fontWeight(700)
              .fontFamily(TypeTokens.title.family)
              .fontColor(ColorTokens.ink)
            Text(this.detailText())
              .fontSize(TypeTokens.small.size)
              .fontColor(ColorTokens.body)
              .margin({ top: SpaceTokens.xs, bottom: SpaceTokens.xl })
              .textAlign(TextAlign.Center)

            Column() {
              Text('需要决定')
                .fontSize(TypeTokens.overline.size)
                .fontWeight(600)
                .fontColor(ColorTokens.muted)
                .margin({ bottom: SpaceTokens.sm })
              Column() {
                Text('两条可行修法')
                  .fontSize(TypeTokens.overline.size)
                  .fontWeight(600)
                  .fontColor(ColorTokens.muted)
                  .margin({ bottom: SpaceTokens.xs })
                ForEach(this.fixes, (fix: FixOption, idx: number) => {
                  Column() {
                    this.solutionRow(fix)
                  }
                  .onClick((): void => {
                    this.pathStack.pushPath({ name: fix.route });
                  })
                  if (idx < this.fixes.length - 1) {
                    Divider()
                      .strokeWidth(LayoutTokens.hairlineWidth)
                      .color(ColorTokens.separator)
                  }
                }, (fix: FixOption): string => `fix-${fix.route}-${fix.title}`)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding(SpaceTokens.lg)
              .borderRadius(RadiusTokens.card)
              .backgroundColor(ColorTokens.surfaceElevated)
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
          }
          .layoutWeight(1)
          .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })
        }
        .width('100%')
        .height('100%')

        Column({ space: SpaceTokens.sm }) {
          YoujingButton({
            variant: YoujingButtonVariant.PRIMARY,
            label: '再试一次',
            fullWidth: true,
            onAction: (): void => {
              // Generating 是被 replacePath 移出栈的（栈里没有它），popToName 会落空；
              // 再 pushPath 会把 Generating 堆到失败页上面，生成成功后 Itinerary 底下
              // 仍压着失败页。直接替换栈顶，语义就是「本屏换成重试屏」
              this.pathStack.replacePath({ name: 'Generating' });
            }
          })
          YoujingButton({
            variant: YoujingButtonVariant.SECONDARY,
            label: '换一天',
            fullWidth: true,
            buttonWidth: '100%',
            onAction: (): void => {
              // 按钮承诺的落点是屏2 基础输入：pop() 只会落到 StayPick，名不对实。
              // 栈里没有该页（深链直启本屏）时退回 push，别让按钮变死键
              if (this.pathStack.popToName('TripInput') < 0) {
                this.pathStack.pushPath({ name: 'TripInput' });
              }
            }
          })
          YoujingButton({
            variant: YoujingButtonVariant.SECONDARY,
            label: '去掉这个景点',
            fullWidth: true,
            buttonWidth: '100%',
            onAction: (): void => {
              // 落点是屏4 选点页，同上：popToName 失败则 push 兜底
              if (this.pathStack.popToName('SpotPick') < 0) {
                this.pathStack.pushPath({ name: 'SpotPick' });
              }
            }
          })
        }
        .width('100%')
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, bottom: SpaceTokens.xl })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ColorTokens.canvas)
    }
    .titleBar(HdsChrome.bar({ mainTitle: '生成受阻' }))
    .titleMode(HdsNavDestinationTitleMode.MINI)
  }
}
