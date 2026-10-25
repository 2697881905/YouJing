/**
 * 隐私政策 / 用户协议明示同意弹窗（对齐「有据」PrivacyConsentDialog 的三出口结构）。
 *
 * 三个出口缺一不可：
 *   ①《隐私政策》②《用户协议》可点开看原文（跳转后返回会重新弹，见 Index 的 onPageShow 兜底）
 *   ③「不同意」必须能真的退出——不能只关掉弹窗继续采集，那是假闸门
 * 官方件收口：容器用 @CustomDialog + AlertDialog 级别的系统排版，不自绘遮罩层。
 */

import { promptAction } from '@kit.ArkUI';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { YoujingButton, YoujingButtonVariant } from './YoujingButton';

@CustomDialog
export struct PrivacyConsentDialog {
  controller: CustomDialogController;
  /** 同意并继续 */
  onAgree: () => void = (): void => {};
  /** 不同意：调用方 terminateSelf */
  onDecline: () => void = (): void => {};
  /** 看原文（kind: 'privacy' | 'agreement'） */
  onOpenDoc: (kind: string) => void = (kind: string): void => {};

  @Builder
  docLink(label: string, kind: string) {
    Text(label)
      .fontSize(TypeTokens.caption.size)
      .fontColor(ColorTokens.primary)
      .padding({ top: SpaceTokens.xs, bottom: SpaceTokens.xs })
      .onClick((): void => {
        this.onOpenDoc(kind);
      })
  }

  build() {
    Column({ space: SpaceTokens.md }) {
      Text('使用前请先阅读并同意')
        .fontSize(TypeTokens.title.size)
        .fontWeight(TypeTokens.title.weight)
        .fontFamily(TypeTokens.title.family)
        .fontColor(ColorTokens.ink)
        .alignSelf(ItemAlign.Start)

      Text('有径是一款本地优先的行程规划工具。你的行程、打卡与记账数据默认只保存在本机；'
        + '使用华为账号登录仅用于在本机区分不同使用者的数据分区。')
        .fontSize(TypeTokens.small.size)
        .fontColor(ColorTokens.body)
        .lineHeight(TypeTokens.small.lineHeight)

      Row({ space: SpaceTokens.lg }) {
        this.docLink('《隐私政策》', 'privacy')
        this.docLink('《用户协议》', 'agreement')
      }

      Column({ space: SpaceTokens.sm }) {
        YoujingButton({
          variant: YoujingButtonVariant.PRIMARY,
          label: '同意并继续',
          fullWidth: true,
          onAction: (): void => {
            this.onAgree();
          }
        })
        YoujingButton({
          variant: YoujingButtonVariant.TEXT,
          label: '不同意并退出',
          fullWidth: true,
          onAction: (): void => {
            this.onDecline();
          }
        })
      }
      .margin({ top: SpaceTokens.xs })
    }
    .width('100%')
    .padding(LayoutTokens.sheetPanelPadding)
    .backgroundColor(ColorTokens.surfaceElevated)
    .borderRadius(RadiusTokens.card)
    .alignItems(HorizontalAlign.Start)
  }
}

/** 看原文时如果对应页面还没落地，用这条统一兜底文案（不静默失败） */
export function toastDocPending(): void {
  promptAction.showToast({ message: '协议原文页面整理中，稍后可在本页查看', duration: 1800 });
}
