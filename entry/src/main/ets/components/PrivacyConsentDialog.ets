/**
 * 隐私政策 / 用户协议明示同意弹窗（对齐「有据」PrivacyConsentDialog 的三出口结构）。
 *
 * 三个出口缺一不可：
 *   ①《隐私政策》②《用户协议》可点开看原文（跳转后返回会重新弹，见 Index 的 onPageShow 兜底）
 *   ③「不同意」必须能真的退出——不能只关掉弹窗继续采集，那是假闸门
 * 官方件收口：容器用 @CustomDialog + AlertDialog 级别的系统排版，不自绘遮罩层。
 */

import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { YoujingButton, YoujingButtonVariant } from './YoujingButton';
import { LegalDocReader } from './LegalDocReader';

@CustomDialog
export struct PrivacyConsentDialog {
  controller: CustomDialogController;
  /** 同意并继续 */
  onAgree: () => void = (): void => {};
  /** 不同意：调用方 terminateSelf */
  onDecline: () => void = (): void => {};
  /** 看原文（kind: 'privacy' | 'agreement'）；仅用于上报，正文由本组件就地展开 */
  onOpenDoc: (kind: string) => void = (kind: string): void => {};
  /** 非空 = 正在读哪一份。就地展开而不是 push 路由：CustomDialog 里推 NavDestination
   会留下「返回后弹窗还在不在、要不要重问」的竞态 */
  @State private reading: string = '';

  /**
   * 官方 TEXTUAL 档 Button，不是裸 Text 挂 onClick。
   * 原来那写法过不了 R4（布局尺），而且没有按压反馈、命中区只有字面行高；
   * TEXTUAL 档保留"链接"观感，把热区与 stateEffect 交回官方。
   */
  @Builder
  docLink(label: string, kind: string) {
    // IMP-17：TEXTUAL 钮命中区只有字面行高（真机口径），44 高 Row 包装承载点击，
    // 链接观感不变；Button 保留官方 TEXTUAL 档的按压反馈
    Row() {
      Button(label)
        .fontSize(TypeTokens.caption.size)
        .fontColor(ColorTokens.primary)
        .backgroundColor(Color.Transparent)
        .padding({ left: 0, right: 0 })
        .type(ButtonType.Capsule)
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .hitTestBehavior(HitTestMode.Transparent)
    }
    .height(LayoutTokens.minTouchTarget)
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.reading = kind;
      this.onOpenDoc(kind);
    })
  }

  build() {
    Column({ space: SpaceTokens.sm }) {
      if (this.reading.length > 0) {
        LegalDocReader({
          kind: this.reading,
          onBack: (): void => {
            this.reading = '';
          }
        })
      } else {
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

      Row({ space: SpaceTokens.base }) {
        this.docLink('《隐私政策》', 'privacy')
        this.docLink('《用户协议》', 'agreement')
      }

      Column({ space: SpaceTokens.xs }) {
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
      .margin({ top: SpaceTokens.xxs })
      }
    }
    .width('100%')
    .padding(LayoutTokens.sheetPanelPadding)
    .backgroundColor(ColorTokens.surfaceElevated)
    .borderRadius(RadiusTokens.card)
    .alignItems(HorizontalAlign.Start)
  }
}
