/**
 * 屏7 生成受阻 · 降级重试（帧 a21e614c）。
 * §7 必改已落：scroll padding 104/180→94、solution-info gap 2→0。
 * 触发：Generating 校验失败分支（真实管线阶段 6 接入）；骨架期可经
 * aa start --ps route GenerateFailed 直达（EntryAbility 预填通道）。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';

interface FixOption {
  title: string;
  desc: string;
}

@Component
export struct GenerateFailedPage {
  private pathStack: NavPathStack = APP_NAV;
  private fixes: FixOption[] = [
    { title: '把宇治移到第 4 天', desc: '第 4 天还有 3.5 小时空档' },
    { title: '宇治改为打车 42分钟 · ¥3,200', desc: '预算 +¥3,200' }
  ];

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
        .fontSize(22)
        .fontColor([ColorTokens.faint])
    }
    .width('100%')
    .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        Column() {
          Row() {
            SymbolGlyph($r('sys.symbol.chevron_backward'))
              .fontSize(22)
              .fontColor([ColorTokens.ink])
              .onClick(() => {
                this.pathStack.pop();
              })
            Blank()
            Text('生成受阻')
              .fontSize(TypeTokens.body.size)
              .fontWeight(600)
              .fontColor(ColorTokens.ink)
            Blank()
            Column().width(44)
          }
          .height(LayoutTokens.titleBarHeight)
          .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })

          Column() {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(48)
              .fontColor([ColorTokens.warning])
              .margin({ top: SpaceTokens.fiveXl, bottom: SpaceTokens.lg })
            Text('第 3 天没排通')
              .fontSize(TypeTokens.title.size)
              .fontWeight(700)
              .fontFamily(TypeTokens.title.family)
              .fontColor(ColorTokens.ink)
            Text('伏见稻荷大社 与 宇治平等院 之间的步行时间超过 90 分钟，无法安排在同一天。')
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
                  this.solutionRow(fix)
                  if (idx < this.fixes.length - 1) {
                    Divider()
                      .strokeWidth(LayoutTokens.hairlineWidth)
                      .color(ColorTokens.separator)
                  }
                }, (fix: FixOption): string => `fix-${fix.title}`)
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
            label: '按建议修复',
            fullWidth: true,
            onAction: (): void => {
              this.pathStack.popToName('Generating');
              this.pathStack.pushPath({ name: 'Generating' });
            }
          })
          YoujingButton({
            variant: YoujingButtonVariant.SECONDARY,
            label: '换一天',
            fullWidth: true,
            buttonWidth: '100%',
            onAction: (): void => {
              this.pathStack.pop();
            }
          })
          YoujingButton({
            variant: YoujingButtonVariant.SECONDARY,
            label: '去掉这个景点',
            fullWidth: true,
            buttonWidth: '100%',
            onAction: (): void => {
              this.pathStack.pop();
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
    .hideTitleBar(true)
  }
}
