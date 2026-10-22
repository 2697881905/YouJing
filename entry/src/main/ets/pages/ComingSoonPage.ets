/**
 * 未落地路由占位页（批次 3 骨架期用，批次 4/5 逐屏替换）。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { SpaceTokens } from '../design/SpaceTokens';

@Component
export struct ComingSoonPage {
  @Prop routeName: string = '';
  private pathStack: NavPathStack = APP_NAV;

  build() {
    NavDestination() {
      Column({ space: SpaceTokens.md }) {
        Text('骨架占位')
          .fontSize(TypeTokens.title.size)
          .fontWeight(700)
          .fontFamily(TypeTokens.title.family)
          .fontColor(ColorTokens.ink)
        Text(`路由「${this.routeName}」将在后续批次按设计底稿落地`)
          .fontSize(TypeTokens.small.size)
          .fontColor(ColorTokens.body)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor(ColorTokens.canvas)
    }
    .hideTitleBar(true)
  }
}
