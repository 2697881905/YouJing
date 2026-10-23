/**
 * 活动类别 → 色点颜色的唯一口径（屏8 时间线、屏10 详情、屏13 桌面卡片共用）。
 *
 * 这里只回答「这类该用哪个色名」，名字与 resources/{base,dark}/color.json 的条目同名，
 * 与底稿图例逐字对上：景点 primary、餐饮 bookmark、住宿 accent_mention、
 * 交通 icon、休息 faint。
 * 最后一步「色名 → Resource」各宿主自己映射：`$r()` 只接受字面量，
 * 卡片的 Form UIContext 也拿不到 design/ColorTokens，所以那一步合并不了。
 */

import { ActivityCategory } from '../model/Trip';

export class CategoryStyle {
  static readonly PRIMARY: string = 'primary';
  static readonly BOOKMARK: string = 'bookmark';
  static readonly ACCENT_MENTION: string = 'accent_mention';
  static readonly ICON: string = 'icon';
  static readonly FAINT: string = 'faint';

  /** 认不出的类别一律按景点蓝，与屏8 时间线同一条兜底 */
  static colorName(cat: ActivityCategory): string {
    if (cat === ActivityCategory.FOOD) {
      return CategoryStyle.BOOKMARK;
    }
    if (cat === ActivityCategory.HOTEL) {
      return CategoryStyle.ACCENT_MENTION;
    }
    if (cat === ActivityCategory.TRANSPORT) {
      return CategoryStyle.ICON;
    }
    if (cat === ActivityCategory.REST) {
      return CategoryStyle.FAINT;
    }
    return CategoryStyle.PRIMARY;
  }
}
