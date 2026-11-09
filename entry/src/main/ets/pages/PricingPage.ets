/**
 * 付费引导页（商业化方案 §2 定价结构）。
 *
 * 三档展示：免费 / 行程通行证 9.9 元 / 订阅 19.9 元·月。
 * IAP 接线：通行证走 NONCONSUMABLE，订阅走 AUTORENEWABLE；
 * 购买成功后 BFF 校验 + EntitlementStore 更新 + finishPurchase 确认发货。
 */

import { PricingReason } from '../utils/PricingReason';
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
import {
  subCapLine, pricingHeadline, pricingSubtitle, passPriceLine, subPriceLine,
  buyPassLabel, subMonthLabel, subYearLabel
} from '../utils/PricingCopy';
import { subscriptionActive } from '../utils/MembershipCopy';
import { DateUtils } from '../utils/DateUtils';
import { common } from '@kit.AbilityKit';

@Component
export struct PricingPage {
  // 深浅档代 tick：翻档时 EntryAbility 自增，@StorageProp 变化带动本页 build 重跑，
  // 把新 tick 传进 HdsChrome.bar → 标题内容换新 ComponentContent 重挂载、按当前档重解色
  // （官方 HdsTitleBar 自绘内容不随配置切换重渲染，真机实证见 HdsChrome.themeTick）
  @StorageProp('chromeThemeTick') chromeThemeTick: number = 0;

  @State private purchasing: boolean = false;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @State private toastMsg: string = '';
  @State private headline: string = '解锁完整行程';
  @State private subtitle: string = '生成免费，导出与无限重排需解锁';
  /** 已订阅时隐藏两个订阅购买键，避免重复扣款；到期后自动恢复可买 */
  @State private isMember: boolean = false;
  @State private memberEnd: string = '';
  /** 该行程已解锁（通行证生效）时隐藏通行证购买键 */
  @State private passOwned: boolean = false;
  /** 上限数字跟服务端：写死会让同一屏「订阅解锁每月 N 次」与计划卡自相矛盾 */
  @State private subCap: string = '';
  private pathStack: NavPathStack = APP_NAV;
  @Prop tripId: string = '';

  aboutToAppear(): void {
    // 订阅用户用满每月额度时也会被送到这页：不能再说「解锁」「生成免费」
    const ent = EntitlementStore.get();
    const periodEnd: string = ent.subscription === null ? '' : ent.subscription.periodEnd;
    const status: string = ent.subscription === null ? '' : ent.subscription.status;
    const today: string = DateUtils.todayIso();
    this.isMember = subscriptionActive(status, periodEnd, today);
    this.memberEnd = periodEnd.length >= 10 ? periodEnd.slice(0, 10) : '';
    this.passOwned = this.tripId.length > 0 && EntitlementStore.hasPass(this.tripId);
    this.subCap = subCapLine(EntitlementStore.get().dailyCap);
    // 标题文案也按「在期」算：过期缓存不能再被说成「本月次数已用完」
    // giftSpent：非会员且赠送已用完 —— 他就是被「生成」的 402 送到这页的，
    // 不能再写「生成免费」（2026-11-04 真机走到这条时实拍到的误导）
    const giftSpent: boolean = !this.isMember && !this.passOwned && ent.giftRemaining <= 0;
    // 从导出/分享门禁进来的人刚做的动作不是生成，标题得换成导出口径（取用即清）
    const exportGate: boolean = PricingReason.takeExportGate();
    this.headline = pricingHeadline(this.isMember, ent.usedToday, ent.dailyCap, giftSpent, exportGate);
    this.subtitle = pricingSubtitle(this.isMember, ent.usedToday, ent.dailyCap, giftSpent, exportGate);
  }

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
    // 通行证是「绑一条行程」的商品：没有行程 id 就不能发起 IAP 购买，
    // 否则钱扣了、BFF 校验因缺 localTripId 拒绝，用户只能靠「恢复购买」兜底。
    if (localTripId.length === 0) {
      this.purchasing = false;
      this.showToast('通行证需要绑定一条行程，请先生成或打开一条行程');
      return;
    }
    // 二次拦截：该行程已有生效通行证时不能再买（会重复扣款）
    if (EntitlementStore.hasPass(localTripId)) {
      this.purchasing = false;
      this.showToast('该行程已解锁，无需重复购买');
      return;
    }
    const result: IapResult = await IapStore.purchasePass(this.ctx(), localTripId);
    this.purchasing = false;
    if (result.success) {
      this.showToast('通行证已解锁');
      this.pathStack.pop();
    } else {
      // 「校验…」说明钱已扣、只是服务端没确认：告诉用户还有「恢复购买」这条路
      const message: string = result.message.indexOf('校验') >= 0
        ? `${result.message}；可用「恢复购买」补领` : result.message;
      this.showToast(message);
    }
  }

  private async purchaseSubscription(productId: string): Promise<void> {
    if (this.purchasing) {
      return;
    }
    // 二次拦截：UI 可能还是旧态（缓存刚变），这里再确认一次，避免重复订阅扣款
    if (this.isMember) {
      this.showToast('你已是订阅会员，到期前无需重复购买');
      return;
    }
    this.purchasing = true;
    const result: IapResult = await IapStore.purchaseSubscription(this.ctx(), productId);
    this.purchasing = false;
    if (result.success) {
      this.showToast('订阅已激活');
      this.pathStack.pop();
    } else {
      const message: string = result.message.indexOf('校验') >= 0
        ? `${result.message}；可用「恢复购买」补领` : result.message;
      this.showToast(message);
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
          Text(this.headline)
            .fontSize(TypeTokens.title.size)
            .fontWeight(700)
            .fontFamily(TypeTokens.title.family)
            .fontColor(ColorTokens.ink)
          Text(this.subtitle)
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .margin({ top: SpaceTokens.lg })

        this.planCard(
          '行程通行证',
          passPriceLine(),
          // 「优先生成队列」全仓没有任何实现（BFF 无队列/并发优先级，见 §5ci 续 192），
          // 挂着就是拿一句做不到的承诺换一次付款。换成 determineQuotaSource 里成立的第三条：
          // 先判订阅额度、订阅用尽才落到 pass，而 pass 分支不计数 ⇒ 订阅用完仍能继续这一趟。
          ['该行程无限次生成与重排', '导出日历 / 海报 / 分享', '订阅次数用完后这一趟仍可继续'],
          true
        )

        this.planCard(
          '订阅会员',
          subPriceLine(),
          [this.subCap, '全部高级能力', '行程历史无限保存'],
          false
        )

        this.planCard(
          '免费体验',
          '¥0',
          ['本机规则引擎生成', '注册赠 3 次 LLM 体验', '查看行程始终免费'],
          false
        )

        Column({ space: SpaceTokens.xs }) {
          if (this.passOwned) {
            Text('该行程已解锁 · 通行证已生效')
              .fontSize(TypeTokens.small.size)
              .fontWeight(600)
              .fontColor(ColorTokens.primary)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: SpaceTokens.xs, bottom: SpaceTokens.xs })
          } else {
            YoujingButton({
              variant: YoujingButtonVariant.PRIMARY,
              label: this.purchasing ? '处理中…' : buyPassLabel(),
              fullWidth: true,
              disabled: this.purchasing,
              onAction: (): void => {
                this.purchasePass();
              }
            })
          }
          if (this.isMember) {
            Text(`已是订阅会员 · 有效期至 ${this.memberEnd}`)
              .fontSize(TypeTokens.small.size)
              .fontWeight(600)
              .fontColor(ColorTokens.primary)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: SpaceTokens.xs, bottom: SpaceTokens.xs })
          } else {
            YoujingButton({
              variant: YoujingButtonVariant.SECONDARY,
              label: subMonthLabel(),
              fullWidth: true,
              disabled: this.purchasing,
              onAction: (): void => {
                this.purchaseSubscription(PRODUCT_ID_SUB_MONTHLY);
              }
            })
            YoujingButton({
              variant: YoujingButtonVariant.SECONDARY,
              label: subYearLabel(),
              fullWidth: true,
              disabled: this.purchasing,
              onAction: (): void => {
                this.purchaseSubscription(PRODUCT_ID_SUB_YEARLY);
              }
            })
          }
          YoujingButton({
            variant: YoujingButtonVariant.TEXT,
            label: '恢复购买',
            fullWidth: true,
            disabled: this.purchasing,
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
      .padding({ top: HdsChrome.contentTopInset(this.statusBarHeight), left: SpaceTokens.base, right: SpaceTokens.base })
      .backgroundColor(ColorTokens.canvas)
    }
    .clip(false)
    .backgroundColor(ColorTokens.canvas)
    // 整页是 Column 直排、没有 Scroll/List 可挂 scroller，磨砂等不到滚动帧 → 显式关掉滚动特效
    .titleBar(HdsChrome.bar({ themeTick: this.chromeThemeTick, mainTitle: '解锁行程', scrollable: false }))
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
    .padding(SpaceTokens.base)
    .borderRadius(RadiusTokens.card)
    .backgroundColor(highlight ? ColorTokens.surfaceElevated : ColorTokens.surfaceSunken)
    .borderWidth(highlight ? 2 : 0)
    .borderColor(ColorTokens.primary)
    .borderStyle(BorderStyle.Solid)
  }
}
