/**
 * 设置页 · 「我的」页右上角齿轮进入。
 *
 * 分区排版 1:1 照搬「有据」`pages/SettingsPage.ets`：分组标题单独一个 ListItem，
 * 一组行收进卡片式 `ListItemGroup`（圆角 + 浮起面 + clip），行内是
 * 「图标 / 标题 / 右箭头」三段、左右 16 上下 12 内缩，末尾退出登录独立成组。
 * 有据的账号绑定 / 隐私设置 / 通知设置 / 深色模式 / 清除缓存 / 账号注销
 * 在有径没有对应实现，一律不造空行——只保留实际有的三份法务文书与退出登录。
 *
 * 差异只在本仓技术契约：顶栏走 `HdsNavDestination + HdsChrome`（Navigation 子页必需，
 * 有据是自绘 Row + BackButton），图标走 `sys.symbol`，色/字/圆角走 design tokens，
 * 底部比有据多让一档悬浮 dock 净空。
 *
 * 文书用 `bindSheet` 而不是页内 if 分支：设置页在导航栈里，就地展开的图层
 * 抢不到返回键（Index.onBackPress ① 直接交 Navigation pop）；半模态由系统收返回。
 * 阅读器不传 fillHost —— sheet 自带 78% 高度上限，正是它默认的 wrap 形态。
 */

import { AccountStore } from '../data/AccountStore';
import { Logger } from '../common/logger/Logger';
import { LegalDocReader } from '../components/LegalDocReader';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { HdsChrome } from '../design/HdsChrome';
import { GlassBlurStyle, getSheetImmersiveMaterial, isSystemMaterialActive } from '../utils/immersiveMaterial';
import { requestSystemBarRefresh } from '../utils/systemBar';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';

/** 设置区一行：标题 + 落点。kind 决定点开哪份法务文书 */
interface SettingItem {
  title: string;
  symbol: Resource;
  docKind: string;
}

const LEGAL_ROWS: SettingItem[] = [
  { title: '隐私政策', symbol: $r('sys.symbol.checkmark_shield'), docKind: 'privacy' },
  { title: '用户协议', symbol: $r('sys.symbol.doc_text'), docKind: 'terms' },
  { title: '关于有径', symbol: $r('sys.symbol.info_circle'), docKind: 'about' }
];

@Component
export struct SettingsPage {
  // 深浅档代 tick：翻档时 EntryAbility 自增，@StorageProp 变化带动本页 build 重跑，
  // 把新 tick 传进 HdsChrome.bar → 标题内容换新 ComponentContent 重挂载、按当前档重解色
  // （官方 HdsTitleBar 自绘内容不随配置切换重渲染，真机实证见 HdsChrome.themeTick）
  @StorageProp('chromeThemeTick') chromeThemeTick: number = 0;

  @State private showDoc: boolean = false;
  /** 先写 kind 再翻 showDoc：bindSheet 的内容不随打开后的状态重赋值重绘 */
  @State private docKind: string = 'privacy';
  /** 顶栏磨砂两态：由绝对滚动偏移驱动 */
  @State private barScrolled: boolean = false;
  private barScroller: Scroller = new Scroller();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  private openDoc(kind: string): void {
    this.docKind = kind;
    this.showDoc = true;
  }

  private confirmLogout(): void {
    this.getUIContext().showAlertDialog({
      title: '确认退出登录？',
      message: '退出后回到本机游客空间；该账号下的行程仍留在本机。',
      primaryButton: { value: '取消', action: (): void => {} },
      secondaryButton: {
        value: '退出登录',
        fontColor: ColorTokens.danger,
        action: (): void => {
          AccountStore.logout().then((): void => {
            this.getUIContext().getPromptAction().showToast({ message: '已退出，回到登录页' });
          }).catch((err: Error): void => {
            Logger.warn('Ui.Settings', `登出失败: ${err.message}`);
          });
        }
      }
    });
  }

  /** 绝对滚动偏移 → 顶栏磨砂开关（>0 即开，静止归零） */
  private syncBarScroll(): void {
    const y: number = this.barScroller.currentOffset().yOffset;
    const on: boolean = y > 0;
    if (on !== this.barScrolled) {
      this.barScrolled = on;
      if (!on) {
        requestSystemBarRefresh();
      }
    }
  }

  @Builder
  docSheet() {
    // 半模态顶距：sheet 内容首行要与右上 ✕ 同心（SheetPage 不给顶部 inset，
    // 不补就贴顶——全工程 sheet 家族统一 top: base，见 detailSheet 同款）
    Column() {
      LegalDocReader({
        kind: this.docKind,
        // 右上角让位给系统 ✕（官方钮占 [961..1086]px，日期直抵卡缘被压住）
        closeSafeInset: SpaceTokens.xxl,
        onBack: (): void => {
          this.showDoc = false;
        }
      })
    }
    .width('100%')
    .padding({ top: SpaceTokens.base })
  }

  /** 分组标题：有据是 13fp 次级字，本仓字阶无 13，取 small 14 */
  @Builder
  groupHeader(title: string) {
    Text(title)
      .fontSize(TypeTokens.small.size)
      .fontWeight(450)
      .fontColor(ColorTokens.muted)
      .width('100%')
      .padding({ left: SpaceTokens.base, top: SpaceTokens.xs, bottom: SpaceTokens.xxs })
  }

  /** 一行：图标 / 标题 / 右箭头，整行可点（热区不收在图标上） */
  @Builder
  sectionRow(symbol: Resource, title: string, onTap: () => void) {
    ListItem() {
      Row({ space: SpaceTokens.sm }) {
        SymbolGlyph(symbol)
          .fontSize(IconSizes.control)
          .fontColor([ColorTokens.icon])
          .width(IconSizes.control)
        Text(title)
          .fontSize(TypeTokens.body.size)
          .fontColor(ColorTokens.ink)
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(IconSizes.control)
          .fontColor([ColorTokens.muted])
      }
      .width('100%')
      .constraintSize({ minHeight: LayoutTokens.minTouchTarget })
      .padding({
        left: SpaceTokens.base, right: SpaceTokens.base,
        top: SpaceTokens.sm, bottom: SpaceTokens.sm
      })
    }
    .onClick(onTap)
  }

  @Builder
  logoutRow() {
    ListItem() {
      Row({ space: SpaceTokens.sm }) {
        SymbolGlyph($r('sys.symbol.arrow_right'))
          .fontSize(IconSizes.control)
          .fontColor([ColorTokens.danger])
          .width(IconSizes.control)
        Text('退出登录')
          .fontSize(TypeTokens.body.size)
          .fontColor(ColorTokens.danger)
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(IconSizes.control)
          .fontColor([ColorTokens.muted])
      }
      .width('100%')
      .constraintSize({ minHeight: LayoutTokens.minTouchTarget })
      .padding({
        left: SpaceTokens.base, right: SpaceTokens.base,
        top: SpaceTokens.sm, bottom: SpaceTokens.sm
      })
    }
    .onClick((): void => {
      this.confirmLogout();
    })
  }

  build() {
    HdsNavDestination() {
      Column() {
        List({ space: SpaceTokens.xs, scroller: this.barScroller }) {
          ListItem() {
            this.groupHeader('关于')
          }

          ListItemGroup() {
            ForEach(LEGAL_ROWS, (row: SettingItem) => {
              this.sectionRow(row.symbol, row.title, (): void => {
                this.openDoc(row.docKind);
              })
            }, (row: SettingItem): string => row.docKind)
          }
          .borderRadius(RadiusTokens.card)
          .backgroundColor(ColorTokens.surfaceElevated)
          .clip(true)

          ListItemGroup() {
            this.logoutRow()
          }
          .borderRadius(RadiusTokens.card)
          .backgroundColor(ColorTokens.surfaceElevated)
          .clip(true)
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .padding({
          left: SpaceTokens.base, right: SpaceTokens.base,
          bottom: LayoutTokens.floatingDockClearance
        })
        // 穿底让位只挪首屏起点，滚动后内容照常穿到栏下被糊掉
        .contentStartOffset(HdsChrome.contentTopInset(this.statusBarHeight))
        .onDidScroll((): void => {
          this.syncBarScroll();
        })
      }
      .width('100%')
      .height('100%')
      .bindSheet($$this.showDoc, this.docSheet(), {
        height: '78%',
        showClose: true,
        systemMaterial: getSheetImmersiveMaterial(),
        blurStyle: isSystemMaterialActive() ? BlurStyle.NONE : GlassBlurStyle.Floating,
        backgroundColor: isSystemMaterialActive() ? undefined : ColorTokens.canvas
      })
    }
    // HDS 深色档这层默认纯黑，透明栏会把它露成一条比画布暗一档的带
    .backgroundColor(ColorTokens.canvas)
    .titleBar(HdsChrome.bar({ themeTick: this.chromeThemeTick, mainTitle: '设置', scrolled: this.barScrolled }))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .bindToScrollable([this.barScroller])
    .clip(false)
  }
}
