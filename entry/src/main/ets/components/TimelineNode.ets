/**
 * 时间轴节点圆环（屏8 行程详情与屏9 编辑态共用）。
 *
 * 色名 → token 的映射原来长在 `ItineraryPage.dotColor` 里；`utils/CategoryStyle` 按
 * §分层 不能 import `design/`，所以映射放在组件这一层。
 * 圆环本体原来是屏8 私有 Builder，屏9 对表底稿（§5y）时发现这一屏根本没有节点，
 * 两处各写一份没意义，故提取共用。
 */

import { ActivityCategory } from '../model/Trip';
import { CategoryStyle } from '../utils/CategoryStyle';
import { ColorTokens } from '../design/ColorTokens';
import { LayoutTokens } from '../design/LayoutTokens';

@Component
export struct TimelineNode {
  @Prop cat: ActivityCategory = ActivityCategory.SIGHT;

  private dot(): Resource {
    const name: string = CategoryStyle.colorName(this.cat);
    if (name === CategoryStyle.BOOKMARK) {
      return ColorTokens.bookmark;
    }
    if (name === CategoryStyle.ACCENT_MENTION) {
      return ColorTokens.accentMention;
    }
    if (name === CategoryStyle.ICON) {
      return ColorTokens.icon;
    }
    if (name === CategoryStyle.FAINT) {
      return ColorTokens.faint;
    }
    return ColorTokens.primary;
  }

  build() {
    Stack() {
      // 官方 Circle 形状件：描边居中在 r=11 的圆上，22 + strokeWidth 2 的外沿即占位
      Circle()
        .width(22)
        .height(22)
        .fill(ColorTokens.canvas)
        .stroke(ColorTokens.ink)
        .strokeWidth(2)
      Circle()
        .width(LayoutTokens.itineraryNodeDot)
        .height(LayoutTokens.itineraryNodeDot)
        .fill(this.dot())
    }
    .width(LayoutTokens.itineraryNodeSize)
    .height(LayoutTokens.itineraryNodeSize)
  }
}
