/**
 * 付费引导页（商业化方案 §2 定价结构）。
 *
 * 三档展示：免费 / 行程通行证 9.9 元 / 订阅 19.9 元·月。
 * IAP 接线：通行证走 NONCONSUMABLE，订阅走 AUTORENEWABLE；
 * 购买成功后 BFF 校验 + EntitlementStore 更新 + finishPurchase 确认发货。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { Logger } from '../common/logger/Logger';
import { IapStore, PRODUCT_ID_SUB_MONTHLY, PRODUCT_ID_SUB_YEARLY, IapResult } from '../data/IapStore';
import { EntitlementStore } from '../data/EntitlementStore';
import { common } from '@kit.AbilityKit';

@Component
export struct PricingPage {
  @State private purchasing: boolean = false;
  @State private toastMsg: string = '';
  private pathStack: NavPathStack = APP_NAV;
  @Prop tripId: string = '';

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private showToast(msg: string): void {
    this.toastMsg = msg;
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
  }

  private async purchasePass(): Promise<void> {
    if (this.purchasing) {
      return;
    }
    this.purchasing = true;
    const localTripId: string = this.tripId.length > 0 ? this.tripId :
      (AppStorage.get<string>('activeTripId') ?? '');
    const result: IapResult = await IapStore.purchasePass(this.ctx(), localTripId);
    this.purchasing = false;
    if (result.success) {
      this.showToast('通行证已解锁');
      this.pathStack.pop();
    } else {
      this.showToast(result.message);
    }
  }

  private async purchaseSubscription(productId: string): Promise<void> {
    if (this.purchasing) {
      return;
    }
    this.purchasing = true;
    const result: IapResult = await IapStore.purchaseSubscription(this.ctx(), productId);
    this.purchasing = false;
    if (result.success) {
      this.showToast('订阅已激活');
      this.pathStack.pop();
    } else {
      this.showToast(result.message);
    }
  }

  private async restorePurchases(): Promise<void> {
    if (this.purchasing) {
      return;
    }
    this.purchasing = true;
    const result: IapResult = await IapStore.restorePurchases(this.ctx());
    this.purchasing = false;
    this.showToast(result.message);
    if (result.success) {
      this.pathStack.pop();
    }
  }

  build() {
    HdsNavDestination() {
      Column({ space: SpaceTokens.base }) {

        Column({ space: SpaceTokens.xxs }) {
          Text('解锁完整行程')
            .fontSize(TypeTokens.title.size)
            .fontWeight(700)
            .fontFamily(TypeTokens.title.family)
            .fontColor(ColorTokens.ink)
          Text('生成免费，导出与无限重排需解锁')
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .margin({ top: SpaceTokens.lg })

        this.planCard(
          '行程通行证',
          '¥9.9 / 单个行程',
          ['该行程无限次生成与重排', '导出日历 / 海报 / 分享', '优先生成队列'],
          true
        )

        this.planCard(
          '订阅会员',
          '¥19.9 / 月  ·  ¥98 / 年',
          ['每月 20 次生成上限', '全部高级能力', '行程历史无限保存'],
          false
        )

        this.planCard(
          '免费体验',
          '¥0',
          ['本机规则引擎生成', '注册赠 3 次 LLM 体验', '查看行程始终免费'],
          false
        )

        Column({ space: SpaceTokens.xs }) {
          YoujingButton({
            variant: YoujingButtonVariant.PRIMARY,
            label: this.purchasing ? '处理中…' : '购买行程通行证 ¥9.9',
            fullWidth: true,
            onAction: (): void => {
              this.purchasePass();
            }
          })
          YoujingButton({
            variant: YoujingButtonVariant.SECONDARY,
            label: '订阅会员 ¥19.9/月',
            fullWidth: true,
            onAction: (): void => {
              this.purchaseSubscription(PRODUCT_ID_SUB_MONTHLY);
            }
          })
          YoujingButton({
            variant: YoujingButtonVariant.SECONDARY,
            label: '订阅会员 ¥98/年',
            fullWidth: true,
            onAction: (): void => {
              this.purchaseSubscription(PRODUCT_ID_SUB_YEARLY);
            }
          })
          YoujingButton({
            variant: YoujingButtonVariant.TEXT,
            label: '恢复购买',
            fullWidth: true,
            onAction: (): void => {
              this.restorePurchases();
            }
          })
        }
        .width('100%')
        .margin({ top: SpaceTokens.sm })
        .padding({ bottom: LayoutTokens.floatingDockClearance })
      }
      .width('100%')
      .height('100%')
      .padding({ left: SpaceTokens.base, right: SpaceTokens.base })
      .backgroundColor(ColorTokens.canvas)
    }
    .backgroundColor(ColorTokens.canvas)
    // 整页是 Column 直排、没有 Scroll/List 可挂 scroller，磨砂等不到滚动帧 → 显式关掉滚动特效
    .titleBar(HdsChrome.bar({ mainTitle: '解锁行程', scrollable: false }))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .onReady((ctx: NavDestinationContext): void => {
      this.pathStack = ctx.pathStack;
    })
  }

  @Builder
  planCard(title: string, price: string, features: string[], highlight: boolean) {
    Column({ space: SpaceTokens.xxs }) {
      Row() {
        Text(title)
          .fontSize(TypeTokens.body.size)
          .fontWeight(highlight ? 700 : 500)
          .fontColor(ColorTokens.ink)
        Text(price)
          .fontSize(TypeTokens.body.size)
          .fontWeight(600)
          .fontColor(highlight ? ColorTokens.primary : ColorTokens.ink)
          .margin({ left: SpaceTokens.xs })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      ForEach(features, (f: string): void => {
        Row({ space: SpaceTokens.xxs }) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(14)
            .fontColor([ColorTokens.success])
          Text(f)
            .fontSize(TypeTokens.small.size)
            .fontColor(ColorTokens.muted)
        }
        .width('100%')
      }, (f: string, idx: number): string => `feat-${idx}`)
    }
    .width('100%')
    .padding(SpaceTokens.sm)
    .borderRadius(RadiusTokens.card)
    .backgroundColor(highlight ? ColorTokens.surfaceElevated : ColorTokens.surfaceSunken)
    .borderWidth(highlight ? 2 : 0)
    .borderColor(ColorTokens.primary)
    .borderStyle(BorderStyle.Solid)
  }
}
