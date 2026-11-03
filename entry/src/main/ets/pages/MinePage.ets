/**
 * 「我的」页 · dock 第五格根页。
 *
 * 为什么单独一页而不是继续用 `TripsPage`：五格分工后「行程」格才是历史/编辑的入口，
 * 而这一格要装个人信息、勋章与设置。之前这三样全挤在 `TripsPage` 标题栏的三枚菜单里
 * （新建 / 我的勋章 / 退出登录），勋章墙做了两整轮切片却连个卡片位都没有。
 *
 * 结构照 `TripsPage` 的 rootMode 双分支：作为 TabContent 根页时自己挂 `HdsNavigation`
 * （`hideBackButton(true)` + `titleMode(MINI)`），被 push 时走 `HdsNavDestination`。
 * 取数一次在 `aboutToAppear`、之后靠 dock 广播重取 —— 只挂 `onShown` 会让根页永不取数
 * （真机实测过的坑，见 INIT_REPORT §4k）。
 *
 * 头像/昵称一律问 `data/ProfileStore`，不在这里写死：真头像是已确认的后续需求，
 * 两条实现路（profile scope 弹窗 vs 接服务端）都还没拍，出口留在这一层，
 * 接的时候页面结构一行不用动。
 */

import { PROFILE_NAV, TAB_MINE, TAB_SHOWN_KEY, isTabShownTick, enterPlanningFlow } from '../common/constants/AppNav';
import { routerMap } from './AppRouter';
import { AccountStore, AUTH_STATE_KEY } from '../data/AccountStore';
import { BadgeDao } from '../data/BadgeDao';
import { EntitlementStore } from '../data/EntitlementStore';
import { DateUtils } from '../utils/DateUtils';
import { membershipStatus, MembershipStatus } from '../utils/MembershipCopy';
import { BadgeGroup, BadgeRecord, badgeCityCount, badgeTotal, buildBadgeBoard } from '../utils/BadgeBoard';
import { ProfileStore } from '../data/ProfileStore';
import { LegalDocReader } from '../components/LegalDocReader';
import { Logger } from '../common/logger/Logger';
import { PlanDraft } from '../data/PlanDraft';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { HdsChrome } from '../design/HdsChrome';
import { common } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode, HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';

/** 设置区一行：标题 + 落点。kind 非空 = 就地展开这份法务文书 */
interface SettingRow {
  title: string;
  desc: string;
  symbol: Resource;
  docKind: string;
}

const SETTING_ROWS: SettingRow[] = [
  { title: '隐私政策', desc: '本机存储、定位与日历权限的口径', symbol: $r('sys.symbol.checkmark_shield'), docKind: 'privacy' },
  { title: '用户协议', desc: '使用前请读一遍', symbol: $r('sys.symbol.doc_text'), docKind: 'terms' },
  { title: '关于有径', desc: '版本与数据来源', symbol: $r('sys.symbol.info_circle'), docKind: 'about' }
];

@Component
export struct MinePage {
  /** true = 作为 dock 根页内联在 TabContent 里（路线 B），此时要自己挂 HdsNavigation */
  @Prop rootMode: boolean = false;
  /** 本页是 PROFILE_NAV 这条 tab 栈的宿主，push 必须落在自己的栈上 */
  private pathStack: NavPathStack = PROFILE_NAV;
  /** 切回这一格时重取勋章计数：在屏15 收了新章再切回来，不该还看到旧那份 */
  @StorageProp(TAB_SHOWN_KEY) @Watch('onDockShown') dockTick: string = '';
  /** 登录态：'' 水合中 / guest / huawei。资料区要跟它即时变 */
  @StorageProp(AUTH_STATE_KEY) authState: string = '';
  /** 权益变更（购买/刷新/登出）时即时刷新会员卡 */
  @StorageProp(EntitlementStore.TICK_KEY) @Watch('onEntitlementTick') entTick: number = 0;
  @State private badgeCount: number = 0;
  @State private cityCount: number = 0;
  /** 会员卡：订阅/通行证状态（付费后 App 内唯一能看到权益的地方） */
  @State private memberTitle: string = '未开通会员';
  @State private memberDetail: string = '生成免费；导出与无限重排需解锁';
  @State private memberActive: boolean = false;
  /** 非空 = 就地展开这份法务文书。不 push 路由：CustomDialog/页内展开才没有"返回后这页什么态"的竞态 */
  @State private reading: string = '';
  /** 顶栏磨砂两态：由**绝对**滚动偏移驱动（每帧增量会被松手回弹的负帧打灭，契约 §Translucency） */
  @State private barScrolled: boolean = false;
  private barScroller: Scroller = new Scroller();

  private onDockShown(): void {
    if (isTabShownTick(this.dockTick, TAB_MINE)) {
      this.reload();
    }
  }

  aboutToAppear(): void {
    this.reload();
  }

  private onEntitlementTick(): void {
    this.refreshMembership();
  }

  private refreshMembership(): void {
    this.refreshMembership();
  }

  private reload(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    BadgeDao.listMine(ctx).then((rows: BadgeRecord[]): void => {
      const groups: BadgeGroup[] = buildBadgeBoard(rows);
      this.badgeCount = badgeTotal(groups);
      this.cityCount = badgeCityCount(groups);
    }).catch((err: Error): void => {
      // 读失败只让卡片显示 0：这是概览，不是勋章墙本体，不该拦住这一格
      Logger.warn('Ui.Mine', `勋章计数读取失败: ${err.message}`);
    });
    this.refreshMembership();
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
            Logger.warn('Ui.Mine', `登出失败: ${err.message}`);
          });
        }
      }
    });
  }

  @Builder
  profileHeader() {
    Row({ space: SpaceTokens.base }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle()
          .width(LayoutTokens.profileAvatarSize)
          .height(LayoutTokens.profileAvatarSize)
          .fill(ColorTokens.primaryTint)
        // 头像来源只有一个出口：本轮恒返回官方符号占位，接真头像时改 ProfileStore 即可
        if (ProfileStore.avatarOf(AccountStore.uid()).kind === ProfileStore.KIND_SYMBOL) {
          SymbolGlyph(ProfileStore.avatarOf(AccountStore.uid()).symbol)
            .fontSize(LayoutTokens.profileAvatarSize * 0.62)
            .fontColor([ColorTokens.primary])
        } else {
          Image(ProfileStore.avatarOf(AccountStore.uid()).url)
            .width(LayoutTokens.profileAvatarSize)
            .height(LayoutTokens.profileAvatarSize)
            .borderRadius(RadiusTokens.pill)
            .objectFit(ImageFit.Cover)
            .draggable(false)
        }
      }
      .width(LayoutTokens.profileAvatarSize)
      .height(LayoutTokens.profileAvatarSize)
      .borderRadius(RadiusTokens.pill)
      .border({ width: LayoutTokens.hairlineWidth, color: ColorTokens.hairline })

      Column({ space: SpaceTokens.xxs }) {
        // headline 而非 title：这串是脱敏 ID（操作型文本），契约里 serif 只给编辑性标题
        Text(ProfileStore.displayName())
          .fontSize(TypeTokens.headline.size)
          .fontWeight(TypeTokens.headline.weight)
          .fontFamily(TypeTokens.headline.family)
          .fontColor(ColorTokens.ink)
        Text(ProfileStore.displayHint())
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: SpaceTokens.base, bottom: SpaceTokens.base })
  }

  @Builder
  memberCard() {
    Row({ space: SpaceTokens.sm }) {
      SymbolGlyph($r('sys.symbol.crown'))
        .fontSize(IconSizes.display)
        .fontColor([this.memberActive ? ColorTokens.primary : ColorTokens.icon])
      Column({ space: SpaceTokens.xxs }) {
        Text(this.memberTitle)
          .fontSize(TypeTokens.small.size)
          .fontWeight(600)
          .fontColor(ColorTokens.ink)
        Text(this.memberDetail)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(IconSizes.control)
        .fontColor([ColorTokens.muted])
    }
    .width('100%')
    .padding(SpaceTokens.base)
    .borderRadius(RadiusTokens.card)
    .backgroundColor(ColorTokens.surfaceElevated)
    .onClick((): void => {
      this.pathStack.pushPath({ name: 'Pricing' });
    })
  }

  @Builder
  medalCard() {
    Row({ space: SpaceTokens.sm }) {
      SymbolGlyph($r('sys.symbol.medal'))
        .fontSize(IconSizes.display)
        .fontColor([ColorTokens.primary])
      Column({ space: SpaceTokens.xxs }) {
        Text(this.badgeCount > 0 ? `已收 ${this.badgeCount} 枚勋章` : '还没有勋章')
          .fontSize(TypeTokens.small.size)
          .fontWeight(600)
          .fontColor(ColorTokens.ink)
        Text(this.badgeCount > 0 ? `走过 ${this.cityCount} 座城市 · 打卡即可能得章`
          : '打卡到过的景点会攒成勋章，按城市归档')
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(IconSizes.control)
        .fontColor([ColorTokens.muted])
    }
    .width('100%')
    .padding(SpaceTokens.base)
    .borderRadius(RadiusTokens.card)
    .backgroundColor(ColorTokens.surfaceElevated)
    .onClick((): void => {
      this.pathStack.pushPath({ name: 'Badges' });
    })
  }

  @Builder
  settingRow(row: SettingRow) {
    ListItem() {
      Row({ space: SpaceTokens.sm }) {
        SymbolGlyph(row.symbol)
          .fontSize(IconSizes.control)
          .fontColor([ColorTokens.icon])
          .width(IconSizes.control)
        Column({ space: SpaceTokens.xxs }) {
          Text(row.title)
            .fontSize(TypeTokens.small.size)
            .fontWeight(600)
            .fontColor(ColorTokens.ink)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(row.desc)
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(IconSizes.control)
          .fontColor([ColorTokens.muted])
      }
      // 行高交给内容 + 上下内缩，实测过 minTouchTarget；整行可点，
      // 触点不收在图标上（裸 SymbolGlyph 挂 onClick 会被第 8 把尺 R4 判成自绘按钮）
      .width('100%')
      .constraintSize({ minHeight: LayoutTokens.minTouchTarget })
      .padding({ top: SpaceTokens.xs, bottom: SpaceTokens.xs })
    }
    .onClick((): void => {
      this.reading = row.docKind;
    })
  }

  @Builder
  body() {
    Column() {
      if (this.reading.length > 0) {
        LegalDocReader({
          kind: this.reading,
          readerWidth: '100%',
          onBack: (): void => {
            this.reading = '';
          }
        })
      } else {
        List({ space: SpaceTokens.sm, scroller: this.barScroller }) {
          ListItem() {
            this.profileHeader()
          }
          // 游客分区也要能进来看看，所以登录 CTA 放在资料区之后而不是挡整页：
          // Index 的登录闸门已经拦过"没同意隐私就什么都不给看"，这里只处理已同意未登录
          if (this.authState === 'guest') {
            ListItem() {
              Button({ type: ButtonType.Normal }) {
                Text('登录华为账号')
                  .fontSize(TypeTokens.small.size)
                  .fontWeight(600)
                  .fontColor(ColorTokens.onPrimary)
              }
              .width('100%')
              .height(LayoutTokens.minTouchTarget)
              .borderRadius(RadiusTokens.pill)
              .backgroundColor(ColorTokens.primary)
              .onClick((): void => {
                this.goLogin();
              })
            }
          }
          ListItem() {
            this.memberCard()
          }
          ListItem() {
            this.medalCard()
          }
          ListItemGroup({ header: this.sectionHeader('设置') }) {
            ForEach(SETTING_ROWS, (row: SettingRow) => {
              this.settingRow(row)
            }, (row: SettingRow): string => row.docKind)
          }
          ListItem() {
            Button({ type: ButtonType.Normal }) {
              Text('退出登录')
                .fontSize(TypeTokens.small.size)
                .fontWeight(600)
                .fontColor(ColorTokens.danger)
            }
            .width('100%')
            .height(LayoutTokens.minTouchTarget)
            .borderRadius(RadiusTokens.pill)
            .backgroundColor(ColorTokens.surfaceElevated)
            .onClick((): void => {
              this.confirmLogout();
            })
          }
        }
        .width('100%')
        .height('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        // 末行住在悬浮 dock 底下，按实测净空让位（与 TripsPage/BadgePage 同一写法）
        .padding({ left: SpaceTokens.base, right: SpaceTokens.base,
          bottom: LayoutTokens.floatingDockClearance })
        .onDidScroll((): void => {
          this.syncBarScroll();
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ColorTokens.canvas)
  }

  @Builder
  sectionHeader(title: string) {
    Text(title)
      .fontSize(TypeTokens.overline.size)
      .fontWeight(600)
      .fontColor(ColorTokens.muted)
      .width('100%')
      .padding({ top: SpaceTokens.xs, bottom: SpaceTokens.xxs })
  }

  /**
   * 游客点「登录华为账号」：走的是 Index 那套登录闸门，不是本页自己拉账号接口。
   * 这里只把用户送回主链入口，避免在两个地方各写一次 AccountStore.login。
   */
  private goLogin(): void {
    this.getUIContext().getPromptAction().showToast({ message: '可在首页点「开始规划新行程」时登录' });
  }

  /** 绝对滚动偏移 → 顶栏磨砂开关（>0 即开，静止归零） */
  private syncBarScroll(): void {
    const y: number = this.barScroller.currentOffset().yOffset;
    const on: boolean = y > 0;
    if (on !== this.barScrolled) {
      this.barScrolled = on;
    }
  }

  build() {
    if (this.rootMode) {
      HdsNavigation(this.pathStack) {
        this.body()
      }
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(true)
      .titleBar(HdsChrome.bar({
        mainTitle: '我的',
        scrolled: this.barScrolled,
        menu: [HdsChrome.item($r('sys.symbol.plus'), '新建行程', (): void => {
          PlanDraft.fresh();
          enterPlanningFlow('TripInput');
        }), HdsChrome.item($r('sys.symbol.medal'), '我的勋章', (): void => {
          this.pathStack.pushPath({ name: 'Badges' });
        })]
      }))
      .navDestination(routerMap)
      .mode(NavigationMode.Stack)
      .width('100%')
      .height('100%')
    } else {
      HdsNavDestination() {
        this.body()
      }
      // HDS 深色档这层默认纯黑，透明栏会把它露成一条比画布暗一档的带（成因与实测见 Docs/INIT_REPORT.md §5ci 续 80）
      .backgroundColor(ColorTokens.canvas)
      .titleBar(HdsChrome.bar({ mainTitle: '我的', scrolled: this.barScrolled }))
      .titleMode(HdsNavDestinationTitleMode.MINI)
    }
  }
}
