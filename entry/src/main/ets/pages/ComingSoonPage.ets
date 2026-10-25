/**
 * 尚未落地的路由落点页。
 * 只写用户看得懂的话：不出现「批次」「路由名」这类工程内部说法。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';

@Component
export struct ComingSoonPage {
  @Prop title: string = '这个页面';
  @Prop why: string = '还在准备中，稍后回来试试。';
  private pathStack: NavPathStack = APP_NAV;

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
            this.pathStack.pop();
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
  }
}
