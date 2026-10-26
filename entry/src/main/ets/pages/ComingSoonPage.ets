/**
 * 尚未落地的路由落点页。
 * 只写用户看得懂的话：不出现「批次」「路由名」这类工程内部说法。
 */

import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';

@Component
export struct ComingSoonPage {
  @Prop title: string = '这个页面';
  @Prop why: string = '还在准备中，稍后回来试试。';
  /**
   * 本页是「没认出来的路由名」的统一落点，四条 tab 栈都可能渲染它。
   * 原来硬用 APP_NAV：从地图/费用/我的那三条栈进来时，「返回行程」弹的是
   * 另一条栈——按钮点了没反应。改由 NavDestination.onReady 拿**自己所属**的栈。
   */
  private pathStack: NavPathStack | null = null;

  build() {
    NavDestination() {
      Column({ space: SpaceTokens.md }) {
        Text(this.title)
          .fontSize(TypeTokens.title.size)
          .fontWeight(700)
          .fontFamily(TypeTokens.title.family)
          .fontColor(ColorTokens.ink)
          .alignSelf(ItemAlign.Start)
        Text(this.why)
          .fontSize(TypeTokens.small.size)
          .fontColor(ColorTokens.body)
          .lineHeight(TypeTokens.small.lineHeight)
          .alignSelf(ItemAlign.Start)
        YoujingButton({
          variant: YoujingButtonVariant.SECONDARY,
          label: '返回行程',
          buttonWidth: 180,
          onAction: (): void => {
            if (this.pathStack !== null) {
              this.pathStack.pop();
            }
          }
        })
          .margin({ top: SpaceTokens.xl })
          .alignSelf(ItemAlign.Start)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: LayoutTokens.pagePadding, right: LayoutTokens.pagePadding })
      .backgroundColor(ColorTokens.canvas)
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext): void => {
      this.pathStack = ctx.pathStack;
    })
  }
}
