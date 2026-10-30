/**
 * 我的勋章（切片2 打卡勋章的行后落点）。
 *
 * 底稿 13 帧没有这一屏——勋章是产品路线图里明确要求的行后情绪件，
 * 按既有的设计语言就地长：画布/浮起两级表面、官方 List + ListItemGroup 分组、
 * 官方 Button 承载行、图标只走系统 symbol，不自绘奖章图形、不新增色相。
 *
 * 数据全部派生自打卡证据（utils/BadgeBoard + data/BadgeDao），这里不写库、不做去重判断。
 * 行可点：回到打卡当次行程——今天在行程区间内进「旅行中」，否则进行程详情。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { KEY_CURRENT_BREAKPOINT } from '../utils/breakpointCenter';
import { listLanesForBreakpoint } from '../utils/responsive';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';
import { common } from '@kit.AbilityKit';
import { BadgeDao } from '../data/BadgeDao';
import { Badge, BadgeGroup, BadgeRecord, badgeCityCount, badgeDateText, badgeMeta,
  badgeRoute, badgeTotal, buildBadgeBoard } from '../utils/BadgeBoard';
import { DateUtils } from '../utils/DateUtils';
import { Logger } from '../common/logger/Logger';

@Component
export struct BadgePage {
  /** 断点（唯一来源 utils/breakpointCenter.ets）：宽屏下勋章按 2/3 列铺开 */
  @StorageProp(KEY_CURRENT_BREAKPOINT) bp: string = 'sm';

  private pathStack: NavPathStack = APP_NAV;
  @State private groups: BadgeGroup[] = [];
  @State private loading: boolean = true;

  aboutToAppear(): void {
    this.reload();
  }

  private reload(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.Context;
    return BadgeDao.listMine(ctx).then((rows: BadgeRecord[]): void => {
      this.groups = buildBadgeBoard(rows);
      this.loading = false;
    }).catch((err: Error): void => {
      this.loading = false;
      Logger.error('Ui.Badge', `勋章加载失败: ${err.message}`);
    });
  }

  private totalCount(): number {
    return badgeTotal(this.groups);
  }

  private cityCount(): number {
    return badgeCityCount(this.groups);
  }

  private countIn(city: string): number {
    for (const group of this.groups) {
      if (group.city === city) {
        return group.badges.length;
      }
    }
    return 0;
  }

  /** 最近一枚是哪天收的；没有勋章时返回空串（空态不画总览卡） */
  private latestText(): string {
    if (this.groups.length === 0 || this.groups[0].badges.length === 0) {
      return '';
    }
    return badgeDateText(this.groups[0].badges[0].earnedAt);
  }

  private openTrip(badge: Badge): void {
    const route: string = badgeRoute(badge, DateUtils.todayIso());
    this.pathStack.pushPath({ name: route, param: badge.firstTripId });
  }

  @Builder
  summaryCard() {
    Row({ space: SpaceTokens.md }) {
      SymbolGlyph($r('sys.symbol.medal'))
        .fontSize(IconSizes.display)
        .fontColor([ColorTokens.primary])
      Column({ space: SpaceTokens.xs }) {
        Text('行囊里的勋章')
          .fontSize(TypeTokens.overline.size)
          .fontWeight(600)
          .fontColor(ColorTokens.muted)
        Text(`已收集 ${this.totalCount()} 枚`)
          .fontSize(TypeTokens.title.size)
          .fontWeight(700)
          .fontFamily(TypeTokens.title.family)
          .fontColor(ColorTokens.ink)
          .fontFeature("'tnum' on")
        Text(`${this.cityCount()} 个城市 · 最近 ${this.latestText()}`)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.body)
          .fontFeature("'tnum' on")
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(SpaceTokens.lg)
    .borderRadius(RadiusTokens.hero)
    .backgroundColor(ColorTokens.surfaceElevated)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  cityHeader(city: string) {
    Row() {
      Text(city)
        .fontSize(TypeTokens.overline.size)
        .fontWeight(600)
        .fontColor(ColorTokens.muted)
      Blank()
      Text(`${this.countIn(city)} 枚`)
        .fontSize(TypeTokens.overline.size)
        .fontWeight(450)
        .fontColor(ColorTokens.muted)
        .fontFeature("'tnum' on")
    }
    .width('100%')
    // 吸顶层要自带实底：sticky 头没有底板时，滚动行会从字下穿过去
    .backgroundColor(ColorTokens.canvas)
    .padding({ top: SpaceTokens.md, bottom: SpaceTokens.xs })
  }

  @Builder
  badgeRow(badge: Badge) {
    // 整格可点：官方 Button 做壳（按压态/读屏焦点），视觉由内层承担
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: SpaceTokens.sm }) {
        SymbolGlyph($r('sys.symbol.medal'))
          .fontSize(IconSizes.control)
          .fontColor([ColorTokens.primary])
        Column({ space: SpaceTokens.xs }) {
          Text(badge.spotName)
            .fontSize(TypeTokens.body.size)
            .fontWeight(600)
            .fontColor(ColorTokens.ink)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(badgeMeta(badge))
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
            .fontFeature("'tnum' on")
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(IconSizes.control)
          .fontColor([ColorTokens.icon])
      }
      .width('100%')
      .padding(SpaceTokens.md)
      .alignItems(VerticalAlign.Center)
      .borderRadius(RadiusTokens.card)
      .backgroundColor(ColorTokens.surfaceElevated)
    }
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .width('100%')
    .padding(0)
    .borderRadius(RadiusTokens.card)
    .accessibilityText(`${badge.spotName}，${badgeMeta(badge)}，打开行程`)
    .onClick((): void => {
      this.openTrip(badge);
    })
  }

  @Builder
  emptyState() {
    Column({ space: SpaceTokens.md }) {
      SymbolGlyph($r('sys.symbol.medal'))
        .fontSize(IconSizes.display)
        .fontColor([ColorTokens.muted])
      Text('还没有勋章')
        .fontSize(TypeTokens.title.size)
        .fontWeight(700)
        .fontFamily(TypeTokens.title.family)
        .fontColor(ColorTokens.ink)
      Text('在「旅行中」给行程节点打卡，这枚章就会收进来')
        .fontSize(TypeTokens.small.size)
        .fontWeight(450)
        .fontColor(ColorTokens.muted)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding(SpaceTokens.lg)
  }

  build() {
    HdsNavDestination() {
      Column() {
        if (this.loading) {
          Column({ space: SpaceTokens.md }) {
            LoadingProgress()
              .width(IconSizes.display)
              .height(IconSizes.display)
              .color(ColorTokens.primary)
            Text('读取勋章…')
              .fontSize(TypeTokens.small.size)
              .fontColor(ColorTokens.muted)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.groups.length === 0) {
          this.emptyState()
        } else {
          List({ space: SpaceTokens.sm }) {
            ListItem() {
              this.summaryCard()
            }
            ForEach(this.groups, (group: BadgeGroup) => {
              ListItemGroup({ header: this.cityHeader(group.city) }) {
                ForEach(group.badges, (badge: Badge) => {
                  ListItem() {
                    this.badgeRow(badge)
                  }
                }, (badge: Badge): string => badge.firstCheckinId)
              }
            }, (group: BadgeGroup): string => group.city)
          }
          .lanes(listLanesForBreakpoint(this.bp))
          .alignListItem(ListItemAlign.Start)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .sticky(StickyStyle.Header)
          .cachedCount(6)
          .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg,
            bottom: LayoutTokens.floatingDockClearance })
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(ColorTokens.canvas)
    }
    .titleBar(HdsChrome.bar({
      mainTitle: '我的勋章',
      subTitle: this.loading || this.groups.length === 0 ? '' : `共 ${this.totalCount()} 枚`
    }))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .onReady((ctx: NavDestinationContext): void => {
      this.pathStack = ctx.pathStack;
    })
    .onShown((): void => {
      this.reload();
    })
  }
}
