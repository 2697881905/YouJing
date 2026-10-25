/**
 * 登录页（冷启第一屏，对齐「有据」的入口规范）。
 *
 * 为什么这里不是官方的 LoginWithHuaweiIDButton 组件：
 * 那个组件的回调只给 authorizationCode，换 unionId 必须打服务端
 * （有据是 LoginView.ets:246 exchangeHuaweiCode → setSession）。
 * 有径按产品定位是**纯 ArkTS 无后端**，没有可以换 code 的服务，
 * 所以走 Account Kit 的 authentication 请求直取 unionID（AccountStore.ets:85-94）——
 * 同样是官方能力，只是不经过服务端。这一条是设计约束，不是偷懒。
 *
 * 两道同意分开：进应用前的隐私明示同意在 PrivacyConsentDialog（一次性、落盘），
 * 本页的勾选是「本次登录行为」的同意（有据 LoginView.ets:29/119 同一做法），
 * 未勾选时登录入口 disabled，不给点。
 *
 * 游客出口必须留着：AccountStore.login 失败会静默退回游客态（AccountStore.ets:99-102），
 * 硬门禁没有退路就等于设备上没有华为账号 / 网络不通的人打不开 App。
 * 所以这里给的是一个需要主动点的次级按钮，而不是自动跳过——第一屏仍然是登录页。
 */

import { common } from '@kit.AbilityKit';
import { AccountStore } from '../data/AccountStore';
import { AccountState } from '../model/Account';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { IconSizes } from '../design/LayoutTokens';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';

@Component
export struct LoginView {
  /** 登录成功（拿到真账号分区） */
  onSignedIn: () => void = (): void => {};
  /** 主动选择本机游客空间 */
  onGuest: () => void = (): void => {};
  /** 打开协议原文（复用隐私弹窗的两个出口） */
  onOpenDoc: (kind: string) => void = (kind: string): void => {};

  @State private agreed: boolean = false;
  @State private working: boolean = false;
  @State private hint: string = '';

  private doLogin(): void {
    if (!this.agreed || this.working) {
      return;
    }
    this.working = true;
    this.hint = '';
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    AccountStore.login(ctx)
      .then((state: AccountState): void => {
        this.working = false;
        if (AccountStore.isGuest()) {
          // login() 内部吞异常退回游客态，这里必须说出来，否则用户只看到"点了没反应"
          this.hint = '华为账号登录未完成，可重试，或先用本机游客空间。';
          return;
        }
        this.onSignedIn();
      })
      .catch((err: Error): void => {
        this.working = false;
        this.hint = `登录失败：${err.message}`;
      });
  }

  build() {
    Column() {
      Blank()

      Column({ space: SpaceTokens.sm }) {
        Text('有径')
          .fontSize(TypeTokens.display.size)
          .fontWeight(TypeTokens.display.weight)
          .fontFamily(TypeTokens.display.family)
          .fontColor(ColorTokens.ink)
        Text('TRACEABLE ROUTES')
          .fontSize(TypeTokens.overline.size)
          .fontWeight(TypeTokens.overline.weight)
          .fontColor(ColorTokens.muted)
                  Text('有迹可循，有径可行')
          .fontSize(TypeTokens.body.size)
          .fontColor(ColorTokens.body)
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: SpaceTokens.xl })

      Column({ space: SpaceTokens.md }) {
        Text('登录后开始规划')
          .fontSize(TypeTokens.title.size)
          .fontWeight(TypeTokens.title.weight)
          .fontFamily(TypeTokens.title.family)
          .fontColor(ColorTokens.ink)
          .alignSelf(ItemAlign.Start)
        Text('华为账号仅用于在本机区分不同使用者的行程空间；行程、打卡与记账数据默认只保存在本机，不上传服务器。')
          .fontSize(TypeTokens.small.size)
          .fontColor(ColorTokens.muted)
          .lineHeight(TypeTokens.small.lineHeight)
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: SpaceTokens.xl })

      // 官方 Checkbox + 文本行：未勾选即禁用登录入口（明示同意，不做默认勾选）
      Row({ space: SpaceTokens.sm }) {
        Checkbox()
          .select(this.agreed)
          .selectedColor(ColorTokens.primary)
          .width(24)
          .height(24)
          .onChange((v: boolean): void => {
            this.agreed = v;
          })
        Text() {
          Span('我已阅读并同意')
          Span('《隐私政策》')
            .fontColor(ColorTokens.primary)
            .onClick((): void => {
              this.onOpenDoc('privacy');
            })
          Span('与')
          Span('《用户协议》')
            .fontColor(ColorTokens.primary)
            .onClick((): void => {
              this.onOpenDoc('agreement');
            })
        }
        .fontSize(TypeTokens.caption.size)
        .fontColor(ColorTokens.body)
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: SpaceTokens.lg })

      YoujingButton({
        variant: YoujingButtonVariant.PRIMARY,
        label: this.working ? '登录中…' : '华为账号一键登录',
        fullWidth: true,
        leadingSymbol: $r('sys.symbol.person_crop_circle_fill_1'),
        disabled: !this.agreed || this.working,
        onAction: (): void => {
          this.doLogin();
        }
      })

      if (this.hint.length > 0) {
        Text(this.hint)
          .fontSize(TypeTokens.caption.size)
          .fontColor(ColorTokens.danger)
          .margin({ top: SpaceTokens.sm })
          .width('100%')
      }

      YoujingButton({
        variant: YoujingButtonVariant.TEXT,
        label: '暂不登录，使用本机游客空间',
        fullWidth: true,
        onAction: (): void => {
          this.onGuest();
        }
      })
        .margin({ top: SpaceTokens.sm })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: LayoutTokens.pagePaddingWide,
      right: LayoutTokens.pagePaddingWide,
      top: SpaceTokens.xl,
      bottom: SpaceTokens.xl
    })
    .backgroundColor(ColorTokens.canvas)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
