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
import { ErrorCode } from '../common/error/ErrorCode';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { KEY_WINDOW_WIDTH_VP, BP_MD_MIN_VP } from '../utils/breakpointCenter';
import { symmetricInsetForCap } from '../utils/responsive';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { Pressable } from '../components/Pressable';
import { GlassPanel } from '../components/GlassPanel';
import { BuildConfig } from '../common/constants/BuildConfig';
import { GenerationChannel } from '../utils/GenerationChannel';
import { HdsNavDestination, HdsNavDestinationTitleMode, HideMode } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';
import { requestSystemBarRefresh } from '../utils/systemBar';

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
    return symmetricInsetForCap(this.windowWidthVp, BP_MD_MIN_VP, SpaceTokens.base);
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

  /** 顶栏磨砂两态：由**绝对**滚动偏移驱动（每帧增量会被松手回弹的负帧打灭，契约 §Translucency） */
  @State private barScrolled: boolean = false;
  private barScroller: Scroller = new Scroller();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

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

  /** 服务/网络这一族失败：改行程内容帮不上忙，别把用户往选点页/住宿页/节奏页引 */
  private isServiceFailure(): boolean {
    return this.code === ErrorCode.LLM_UNAVAILABLE || this.code === ErrorCode.NETWORK_REQUEST_FAILED ||
      this.code === ErrorCode.NETWORK_TIMEOUT || this.code === ErrorCode.CLOUD_RATE_LIMITED;
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
    .padding({ top: SpaceTokens.xs, bottom: SpaceTokens.xs })
    // 可及名挂在行内容上：Pressable 的 builder 尾随闭包之后不能再接属性
    .accessibilityText(`${fix.title}，${fix.desc}`)
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

  /** 绝对滚动偏移 → 顶栏磨砂开关（>0 即开，静止归零） */
  private syncBarScroll(): void {
    const y: number = this.barScroller.currentOffset().yOffset;
    const on: boolean = y > 0;
    if (on !== this.barScrolled) {
      this.barScrolled = on;
      if (!on) {
        // 偏移回到 0：HDS 在这一帧回写系统栏内容色，补设通道连发四发压住它（utils/systemBar.ets）
        requestSystemBarRefresh();
      }
    }
  }

  build() {
    HdsNavDestination() {
      // 原来正文与三颗动作钮叠在同一个 Stack(Bottom) 里：正文不滚、动作条浮在上面，
      // md 实拍「换一片住宿再试」的说明行被「再试一次」压掉半行。
      // 改成常规两段布局：正文段吃剩余高并可滚，动作段排在流内，永远不再互相盖。
      Column() {
        Scroll(this.barScroller) {
          Column() {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(IconSizes.display)
              .fontColor([ColorTokens.warning])
              .margin({ top: SpaceTokens.xxl, bottom: SpaceTokens.base })
            Text(failureHeadline(this.code))
              .fontSize(TypeTokens.headline.size)
              .fontWeight(TypeTokens.headline.weight)
              .fontFamily(TypeTokens.title.family)
              .fontColor(ColorTokens.ink)
            Text(this.detailText())
              .fontSize(TypeTokens.small.size)
              .fontColor(ColorTokens.body)
              .margin({ top: SpaceTokens.xxs, bottom: SpaceTokens.lg })
              .textAlign(TextAlign.Center)
            // 原始诊断仍要在，但不能占用户读的那一行：debug 版另起一小行、明确标「调试」
            if (BuildConfig.IS_DEBUG && this.detail.length > 0) {
              Text(`调试：${this.detail}`)
                .fontSize(TypeTokens.caption.size)
                .fontColor(ColorTokens.muted)
                .margin({ top: SpaceTokens.xxs, bottom: SpaceTokens.sm })
                .textAlign(TextAlign.Center)
            }

            if (!this.isServiceFailure()) {
            Column() {
              Text('需要决定')
                .fontSize(TypeTokens.overline.size)
                .fontWeight(600)
                .fontColor(ColorTokens.muted)
                .margin({ bottom: SpaceTokens.xs })
              Column() {
                Text(`${this.fixes.length} 条可行修法`)
                  .fontSize(TypeTokens.overline.size)
                  .fontWeight(600)
                  .fontColor(ColorTokens.muted)
                  .margin({ bottom: SpaceTokens.xxs })
                ForEach(this.fixes, (fix: FixOption, idx: number) => {
                  // 整行可点：按压反馈交给家族唯一的 Pressable
                  Pressable({
                    fillWidth: true,
                    action: (): void => {
                      this.goFix(fix.route);
                    }
                  }) {
                    this.solutionRow(fix)
                  }
                  if (idx < this.fixes.length - 1) {
                    Divider()
                      .strokeWidth(LayoutTokens.hairlineWidth)
                      .color(ColorTokens.separator)
                  }
                }, (fix: FixOption): string => `fix-${fix.route}-${fix.title}`)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding(SpaceTokens.base)
              .borderRadius(RadiusTokens.card)
              .backgroundColor(ColorTokens.surfaceElevated)
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            }
            if (this.isServiceFailure()) {
              // 服务/网络出问题时，「去掉一个景点」「换一片住宿」全帮不上忙——
              // 照直说，并把两条真能走通的出口摆在页脚：再试一次 / 改用本机规则引擎。
              GlassPanel({ radius: RadiusTokens.card }) {
                Text('这次不是行程本身的问题：行程服务暂时没有响应。'
                  + '改景点、换住宿或调节奏都不会让它更快恢复——可以等一会儿再点「再试一次」，'
                  + '也可以直接用本机规则引擎出方案（离线可跑，个性化会少一些）。')
                  .fontSize(TypeTokens.callout.size)
                  .fontColor(ColorTokens.body)
                  .width('100%')
              }
            }
          }
          .padding({ left: this.wideInset(), right: this.wideInset() })
        }
        .padding({ top: HdsChrome.contentTopInset(this.statusBarHeight) })
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .onDidScroll((): void => {
          this.syncBarScroll();
        })

        Column({ space: SpaceTokens.xs }) {
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
          if (this.isServiceFailure()) {
            YoujingButton({
              variant: YoujingButtonVariant.SECONDARY,
              label: '改用本机规则引擎',
              fullWidth: true,
              buttonWidth: '100%',
              onAction: (): void => {
                // 端侧合成不依赖网络，也不占 BFF 额度：服务受阻时这是当场唯一能走通的出口。
                // 开关是一次性的，由 GeneratingPage 离开时复位（utils/GenerationChannel）。
                GenerationChannel.useLocalOnce();
                this.pathStack.replacePath({ name: 'Generating' });
              }
            })
          }
          if (!this.isServiceFailure()) {
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
        }
        .width('100%')
        // 钉底动作条原来只留 xl(24)：这一屏也在悬浮 dock 上，实拍第三颗钮整颗被压住
        .padding({ left: this.wideInset(), right: this.wideInset(), bottom: LayoutTokens.floatingDockClearance })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ColorTokens.canvas)
    }
    // 不收栏（2026-11-08）：NavDestination 内容区恒预留 56vp 栏位、收栏后不回收，收起只留一条 175px 白带
    .bindToScrollable([this.barScroller])
    .clip(false)
    // HDS 深色档这层默认纯黑，透明栏会把它露成一条比画布暗一档的带（成因与实测见 Docs/INIT_REPORT.md §5ci 续 80）
    .backgroundColor(ColorTokens.canvas)
    .titleBar(HdsChrome.bar({ mainTitle: '生成受阻', scrolled: this.barScrolled }))
    .titleMode(HdsNavDestinationTitleMode.MINI)
  }
}
