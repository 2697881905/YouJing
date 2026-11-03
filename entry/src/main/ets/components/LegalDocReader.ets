/**
 * 协议原文阅读器。
 *
 * 用在两处，都是**就地展开**而不是 push 路由：
 * 隐私同意弹窗是 CustomDialog，从弹窗里推 NavDestination 会留下
 * 「返回后弹窗还在不在、要不要重问」的竞态；登录页与弹窗的排版宽度也不同。
 * 所以由宿主切换显示内容，阅读器只管正文与一个返回动作。
 */

import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { YoujingButton, YoujingButtonVariant } from './YoujingButton';
import { docOf, LegalSection } from '../common/constants/LegalDocs';
import { KEY_CURRENT_BREAKPOINT } from '../utils/breakpointCenter';
import { longFormMaxWidth } from '../utils/responsive';

@Component
export struct LegalDocReader {
  /** 'privacy' | 'agreement' */
  @Prop kind: string = 'privacy';
  @Prop readerWidth: Length = '100%';
  /** 断点（唯一来源 utils/breakpointCenter.ets）：宽屏给正文一个可读上限 */
  @StorageProp(KEY_CURRENT_BREAKPOINT) bp: string = 'sm';
  onBack: () => void = (): void => {};

  build() {
    Column() {
      Row() {
        Text(docOf(this.kind).title)
          .fontSize(TypeTokens.title.size)
          .fontWeight(TypeTokens.title.weight)
          .fontFamily(TypeTokens.title.family)
          .fontColor(ColorTokens.ink)
          .layoutWeight(1)
        Text(`更新于 ${docOf(this.kind).updated}`)
          .fontSize(TypeTokens.overline.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .fontFeature("'tnum' on")
      }
      .alignItems(VerticalAlign.Bottom)
      .width('100%')

      Text(docOf(this.kind).intro)
        .fontSize(TypeTokens.small.size)
        .fontColor(ColorTokens.body)
        .lineHeight(TypeTokens.small.lineHeight)
        .margin({ top: SpaceTokens.xs, bottom: SpaceTokens.sm })

      // 正文可滚：宿主（弹窗 / 登录页）本身不是滚动容器，这里自带一档高度上限
      Scroll() {
        Column() {
          ForEach(docOf(this.kind).sections, (sec: LegalSection, index: number) => {
            Column({ space: SpaceTokens.xxs }) {
              Text(`${index + 1}. ${sec.heading}`)
                .fontSize(TypeTokens.small.size)
                .fontWeight(600)
                .fontColor(ColorTokens.ink)
              Text(sec.body)
                .fontSize(TypeTokens.caption.size)
                .fontColor(ColorTokens.body)
                .lineHeight(TypeTokens.caption.lineHeight)
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .margin({ bottom: SpaceTokens.sm })
          }, (sec: LegalSection, index: number): string => `legal-${this.kind}-${index}`)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)

      YoujingButton({
        variant: YoujingButtonVariant.SECONDARY,
        label: '返回',
        fullWidth: true,
        onAction: (): void => {
          this.onBack();
        }
      })
        .margin({ top: SpaceTokens.xs })
    }
    .alignItems(HorizontalAlign.Start)
    .width(this.readerWidth)
    // 这里的上限保持 `constraintSize.maxWidth` 而不是改成 .width()：
    // 本组件的宽度是调用方给的 `readerWidth`（@Prop），不能被返回值顶掉；
    // 而 屏2 那类"卡内子级 width('100%') 溢出被 clip"的问题在这里不存在——
    // 面板本身没有再套一层带内边距的父级。（两处口径不同，别统一改。）
    .constraintSize({ minHeight: LayoutTokens.sheetPanelWidth,
      maxWidth: longFormMaxWidth(this.bp, LayoutTokens.contentMaxWidth) })
    .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm, top: SpaceTokens.sm, bottom: SpaceTokens.xs })
    .borderRadius(RadiusTokens.reason)
    .backgroundColor(ColorTokens.surfacePanel)
  }
}
