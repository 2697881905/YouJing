/**
 * 屏7 生成受阻 · 降级重试（帧 a21e614c）。
 * §7 必改已落：scroll padding 104/180→94、solution-info gap 2→0。
 * 触发：Generating 失败分支，带 FailInfo{code,detail} 进来（阶段 10 接真错误）。
 * 底稿里「第 3 天没排通 / 伏见稻荷与宇治步行超 90 分钟 / 打车 ¥3,200」是编造的诊断，
 * 现按错误码出人话标题、原始诊断做次要说明，两条修法改成真能跳过去的步骤。
 * 骨架期仍可经 aa start --ps route GenerateFailed 直达（EntryAbility 预填通道）。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { failureDetail, failureHeadline } from '../common/error/FailureCopy';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { KEY_WINDOW_WIDTH_VP, BP_MD_MIN_VP } from '../utils/breakpointCenter';
import { symmetricInsetForCap } from '../utils/responsive';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { BuildConfig } from '../common/constants/BuildConfig';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';

interface FixOption {
  title: string;
  desc: string;
  route: string;
}

@Component
export struct GenerateFailedPage {
  /** 窗口实测宽（vp），由断点中心一处测量；0 = 尚未测到，按不收窄处理 */
  @StorageProp(KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 0;

  /** 宽屏下的左右内缩：手机档原样返回 base（等于没改），折叠屏展开把内容收成 600vp 一栏 */
  private wideInset(): number {
    return symmetricInsetForCap(this.windowWidthVp, BP_MD_MIN_VP, SpaceTokens.lg);
  }
  private pathStack: NavPathStack = APP_NAV;
  @Prop code: number = 0;
  @Prop detail: string = '';
  /**
   * 三条可行修法。原来只有"景点"和"节奏"两条——
   * 而**通勤起点是屏5 选的住宿片区决定的**，屏5 的「帮我选」在候选片区都缺坐标时
   * 会退回推荐顺序（`StayPickPage` 那条 toast），这类受阻在屏7 没有任何一条出口能回去重选。
   * 补中间这条，落点 `StayPick` 走同一个 `goFix`（在栈上就 popToName，不在就 push）。
   */
  private fixes: FixOption[] = [
    { title: '回选点页增减景点', desc: '去掉一个必去站，或补几个备选站点', route: 'SpotPick' },
    { title: '换一片住宿再试', desc: '住宿片区决定通勤起点，换一片常能解掉超时', route: 'StayPick' },
    { title: '把每天的节奏调松', desc: '改成每天 3 站，给通勤留余量', route: 'PreferenceQA' }
  ];

  /**
   * 标题下面那行**一律是给人读的一句原因**（按错误码映射，debug/release 同一句）。
   * 原始 `detail` 不再直接铺出来——真机截图里它曾以「两次生成均失败: days 不能为空数组」
   * 的形式出现在用户眼前，那是校验术语。要留调试线索，就单独标「调试」另起一行。
   */
  private detailText(): string {
    // code=0 只有 `aa start --ps route GenerateFailed` 这条直入预览通道会走到，
    // 那时并没有真的失败过，不能对用户承诺"原因已记进日志"
    return this.code === 0 ? '可以先按下面的方法调整后再试一次。' : failureDetail(this.code);
  }

  @Builder
  solutionRow(fix: FixOption) {
    Row() {
      Column() {
        Text(fix.title)
          .fontSize(TypeTokens.small.size)
          .fontWeight(600)
          .fontColor(ColorTokens.ink)
        Text(fix.desc)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .fontFeature("'tnum' on")
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(IconSizes.control)
        .fontColor([ColorTokens.muted])
    }
    .width('100%')
    .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
  }

  /**
   * 「两条可行修法」每一行的落点。
   * 原来这里是 pushPath——把屏4/屏3 堆到失败页**上面**，而底部三颗钮又用
   * popToName 去同两个页面：同一个目的地两条路、栈结果不一样，失败页还会
   * 被压在下面继续留在栈里。统一成"能回到该页就回、回不去再 push"。
   */
  private goFix(route: string): void {
    if (this.pathStack.popToName(route) < 0) {
      this.pathStack.pushPath({ name: route });
    }
  }

  build() {
    HdsNavDestination() {
      // 原来正文与三颗动作钮叠在同一个 Stack(Bottom) 里：正文不滚、动作条浮在上面，
      // md 实拍「换一片住宿再试」的说明行被「再试一次」压掉半行。
      // 改成常规两段布局：正文段吃剩余高并可滚，动作段排在流内，永远不再互相盖。
      Column() {
        Scroll() {
          Column() {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(IconSizes.display)
              .fontColor([ColorTokens.warning])
              .margin({ top: SpaceTokens.fiveXl, bottom: SpaceTokens.lg })
            Text(failureHeadline(this.code))
              .fontSize(TypeTokens.title.size)
              .fontWeight(700)
              .fontFamily(TypeTokens.title.family)
              .fontColor(ColorTokens.ink)
            Text(this.detailText())
              .fontSize(TypeTokens.small.size)
              .fontColor(ColorTokens.body)
              .margin({ top: SpaceTokens.xs, bottom: SpaceTokens.xl })
              .textAlign(TextAlign.Center)
            // 原始诊断仍要在，但不能占用户读的那一行：debug 版另起一小行、明确标「调试」
            if (BuildConfig.IS_DEBUG && this.detail.length > 0) {
              Text(`调试：${this.detail}`)
                .fontSize(TypeTokens.caption.size)
                .fontColor(ColorTokens.muted)
                .margin({ top: SpaceTokens.xs, bottom: SpaceTokens.md })
                .textAlign(TextAlign.Center)
            }

            Column() {
              Text('需要决定')
                .fontSize(TypeTokens.overline.size)
                .fontWeight(600)
                .fontColor(ColorTokens.muted)
                .margin({ bottom: SpaceTokens.sm })
              Column() {
                Text(`${this.fixes.length} 条可行修法`)
                  .fontSize(TypeTokens.overline.size)
                  .fontWeight(600)
                  .fontColor(ColorTokens.muted)
                  .margin({ bottom: SpaceTokens.xs })
                ForEach(this.fixes, (fix: FixOption, idx: number) => {
                  // 官方 Button 承载整行：原来是裸 Column + onClick——没有按压态、
                  // 不是可聚焦控件，读屏与外接键盘都跳不过去
                  Button({ type: ButtonType.Normal, stateEffect: true }) {
                    this.solutionRow(fix)
                  }
                  .buttonStyle(ButtonStyleMode.TEXTUAL)
                  .width('100%')
                  .padding(0)
                  .borderRadius(RadiusTokens.capsule)
                  .accessibilityText(`${fix.title}，${fix.desc}`)
                  .onClick((): void => {
                    this.goFix(fix.route);
                  })
                  if (idx < this.fixes.length - 1) {
                    Divider()
                      .strokeWidth(LayoutTokens.hairlineWidth)
                      .color(ColorTokens.separator)
                  }
                }, (fix: FixOption): string => `fix-${fix.route}-${fix.title}`)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding(SpaceTokens.lg)
              .borderRadius(RadiusTokens.card)
              .backgroundColor(ColorTokens.surfaceElevated)
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
          }
          .padding({ left: this.wideInset(), right: this.wideInset() })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)

        Column({ space: SpaceTokens.sm }) {
          YoujingButton({
            variant: YoujingButtonVariant.PRIMARY,
            label: '再试一次',
            fullWidth: true,
            onAction: (): void => {
              // Generating 是被 replacePath 移出栈的（栈里没有它），popToName 会落空；
              // 再 pushPath 会把 Generating 堆到失败页上面，生成成功后 Itinerary 底下
              // 仍压着失败页。直接替换栈顶，语义就是「本屏换成重试屏」
              this.pathStack.replacePath({ name: 'Generating' });
            }
          })
          YoujingButton({
            variant: YoujingButtonVariant.SECONDARY,
            label: '改出行日期',
            fullWidth: true,
            buttonWidth: '100%',
            onAction: (): void => {
              // 按钮承诺的落点是屏2 基础输入：pop() 只会落到 StayPick，名不对实。
              // 栈里没有该页（深链直启本屏）时退回 push，别让按钮变死键
              if (this.pathStack.popToName('TripInput') < 0) {
                this.pathStack.pushPath({ name: 'TripInput' });
              }
            }
          })
          YoujingButton({
            variant: YoujingButtonVariant.SECONDARY,
            label: '去掉这个景点',
            fullWidth: true,
            buttonWidth: '100%',
            onAction: (): void => {
              // 落点是屏4 选点页，同上：popToName 失败则 push 兜底
              if (this.pathStack.popToName('SpotPick') < 0) {
                this.pathStack.pushPath({ name: 'SpotPick' });
              }
            }
          })
        }
        .width('100%')
        // 钉底动作条原来只留 xl(24)：这一屏也在悬浮 dock 上，实拍第三颗钮整颗被压住
        .padding({ left: this.wideInset(), right: this.wideInset(), bottom: LayoutTokens.floatingDockClearance })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ColorTokens.canvas)
    }
    // HDS 深色档这层默认纯黑，透明栏会把它露成一条比画布暗一档的带（成因与实测见 Docs/INIT_REPORT.md §5ci 续 80）
    .backgroundColor(ColorTokens.canvas)
    .titleBar(HdsChrome.bar({ mainTitle: '生成受阻' }))
    .titleMode(HdsNavDestinationTitleMode.MINI)
  }
}
