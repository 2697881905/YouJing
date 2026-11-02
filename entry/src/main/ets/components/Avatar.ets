// 家族件：components.avatar ｜ 对标有据：design/components/Avatar.ets:7-36 ｜ 状态：已落地未挂载 ｜ 契约锚点：3fcc3a62

/**
 * Avatar —— 头像（三档封闭、永远圆形）。
 *
 * 契约 `components.avatar`（DESIGN.md:382-385）三行逐字映射：
 *   backgroundColor {colors.surface-subtle} → `ColorTokens.surfaceSubtle`（底）
 *   rounded {rounded.pill}                  → `RadiusTokens.pill`
 *   sizes "24px, 40px, 56px"                → `AvatarSizes.SM/MD/LG`（三档封闭，不许多）
 *
 * props：`avatar / name / avatarSize` 名字照搬有据（`Avatar.ets:8-10`）；
 * 有据只有 image 单分支（无图就回落到 `$r('app.media.default_avatar')` 位图），
 * 有径没有这个位图资源，而屏12 的资料区**今天就是双分支**（`MinePage.ets:111-121`
 * 按 `ProfileStore.avatarOf().kind` 分 symbol / image）——所以把 `symbol` 作为
 * 有径侧的第二分支加进 props，`kind` 判别仍由调用方（或 ProfileStore）给，
 * 件本身只认「有 url 走图，没 url 有 symbol 走官方符号，两个都没有留底」。
 * `name` 在件内不是装饰：它进 `accessibilityText`，读屏念得出「谁的头像是这个」，
 * 有据那份 `name` 声明了但没用（`Avatar.ets:9`），这里补上它的用处。
 *
 * `draggable(false)` 是硬要求（有据 `Avatar.ets:4-5` 与有径 `MinePage.ets:126` 都记过）：
 * Image 的 draggable 默认为 true，头像一旦可拖就会被系统拖拽接管，
 * 父容器的手势（PanGesture / LongPressGesture / Swiper）收不到 Update。
 *
 * 挂载时的一次像素变化（T2 复拍要看这一条）：屏12 现在是
 * `primaryTint` 圆底 + `primary` 符号 + `hairline` 描边，而契约 avatar 是
 * `surfaceSubtle` 底——本件按**契约**建，不照抄屏12 的现值；接管时要么接受换色，
 * 要么把契约这条改回去，两条路都要过产品负责人，不许件内偷偷做三元。
 */

import { ColorTokens } from '../design/ColorTokens';
import { RadiusTokens } from '../design/RadiusTokens';

/** 契约三档 24/40/56；除这三档之外不许传别的尺寸（简报 §1「三档 24/40/56」） */
export class AvatarSizes {
  static readonly SM: number = 24;
  static readonly MD: number = 40;
  static readonly LG: number = 56;
}

@Component
export struct Avatar {
  /** 图片地址（有据同名 props）；空串 = 走 symbol 分支 */
  @Prop avatar: string = '';
  /** 人名：只做可及名用，不在件内画文字头像 */
  @Prop name: string = '';
  /** 无图时的官方符号兜底（有径侧第二分支，对齐 ProfileStore 的 kind='symbol'） */
  @Prop symbol: Resource | undefined = undefined;
  /** 直径；取 AvatarSizes.SM / MD / LG 三档之一 */
  @Prop avatarSize: number = AvatarSizes.MD;

  private safeAvatar(): string {
    return this.avatar ?? '';
  }

  private safeName(): string {
    return this.name ?? '';
  }

  build() {
    if (this.safeAvatar().length > 0) {
      Image(this.safeAvatar())
        .width(this.avatarSize)
        .height(this.avatarSize)
        .borderRadius(RadiusTokens.pill)
        .objectFit(ImageFit.Cover)
        .draggable(false)
        .clip(true)
        .accessibilityText(this.safeName())
    } else if (this.symbol !== undefined) {
      Stack({ alignContent: Alignment.Center }) {
        Circle()
          .width(this.avatarSize)
          .height(this.avatarSize)
          .fill(ColorTokens.surfaceSubtle)
        // 符号占图形 0.62：屏12 现写资料区就是这一比例（MinePage.ets:119），
        // 圆形底 + 居中符号是 有径 侧「没有位图时」的唯一画法
        SymbolGlyph(this.symbol)
          .fontSize(this.avatarSize * 0.62)
          .fontColor([ColorTokens.icon])
      }
      .width(this.avatarSize)
      .height(this.avatarSize)
      .borderRadius(RadiusTokens.pill)
      .clip(true)
      .accessibilityText(this.safeName())
    } else {
      // 两分支都空：留一枚契约底，不画问号也不塞图标（缺内容不等于缺形状）
      Circle()
        .width(this.avatarSize)
        .height(this.avatarSize)
        .fill(ColorTokens.surfaceSubtle)
        .accessibilityText(this.safeName())
    }
  }
}
