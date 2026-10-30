/**
 * 「收下勋章」弹窗（屏15 打卡成功后）。
 *
 * 用官方 @CustomDialog，不自绘遮罩：结构与 PrivacyConsentDialog 同族。
 * 只在「这次打卡就是这枚章的首次收下」时由屏15 打开，重复打卡不弹——
 * 行中一天要打多次卡，每次都拦一下会把流程拖慢。
 */

import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { LayoutTokens, IconSizes } from '../design/LayoutTokens';
import { YoujingButton, YoujingButtonVariant } from './YoujingButton';

@CustomDialog
export struct BadgeEarnedDialog {
  controller: CustomDialogController;
  spotName: string = '';
  city: string = '';
  /** '到站打卡' / '手动打卡'——来源如实写，不把手动打卡说成到站 */
  sourceLabel: string = '';
  /** 收下后行囊里共几枚 */
  total: number = 0;
  onViewWall: () => void = (): void => {};
  /** 关掉后让宿主把控制器引用清掉（继续行程与点遮罩都算） */
  onDismiss: () => void = (): void => {};

  build() {
    Column({ space: SpaceTokens.md }) {
      SymbolGlyph($r('sys.symbol.medal'))
        .fontSize(IconSizes.display)
        .fontColor([ColorTokens.primary])
      Text('已收下这枚勋章')
        .fontSize(TypeTokens.overline.size)
        .fontWeight(600)
        .fontColor(ColorTokens.muted)
        .margin({ top: SpaceTokens.xs })
      Text(this.spotName)
        .fontSize(TypeTokens.title.size)
        .fontWeight(700)
        .fontFamily(TypeTokens.title.family)
        .fontColor(ColorTokens.ink)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
      Text(`${this.city} · ${this.sourceLabel}`)
        .fontSize(TypeTokens.caption.size)
        .fontWeight(450)
        .fontColor(ColorTokens.body)
      Text(`行囊里已有 ${this.total} 枚`)
        .fontSize(TypeTokens.caption.size)
        .fontWeight(450)
        .fontColor(ColorTokens.muted)
        .fontFeature("'tnum' on")

      Column({ space: SpaceTokens.sm }) {
        YoujingButton({
          variant: YoujingButtonVariant.PRIMARY,
          label: '查看勋章',
          fullWidth: true,
          onAction: (): void => {
            this.onViewWall();
          }
        })
        YoujingButton({
          variant: YoujingButtonVariant.TEXT,
          label: '继续行程',
          fullWidth: true,
          onAction: (): void => {
            this.onDismiss();
          }
        })
      }
      .margin({ top: SpaceTokens.xs })
    }
    .width('100%')
    .padding(LayoutTokens.sheetPanelPadding)
    .backgroundColor(ColorTokens.surfaceElevated)
    .borderRadius(RadiusTokens.card)
    .alignItems(HorizontalAlign.Center)
  }
}
