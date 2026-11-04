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
import { SpotDao } from '../data/SpotDao';
import { Spot } from '../model/Spot';
import { Badge, BadgeGroup, BadgeRecord, badgeCityCount, badgeDateText, badgeMeta,
  badgeRoute, badgeTotal, buildBadgeBoard } from '../utils/BadgeBoard';
import { CitySpotSet, CityStamp, buildCityStamps, stampMeta, stampOf } from '../utils/CityStamps';
import { DateUtils } from '../utils/DateUtils';
import { Logger } from '../common/logger/Logger';

@Component
export struct BadgePage {
  /** 断点（唯一来源 utils/breakpointCenter.ets）：宽屏下勋章按 2/3 列铺开 */
  @StorageProp(KEY_CURRENT_BREAKPOINT) bp: string = 'sm';

  private pathStack: NavPathStack = APP_NAV;
  @State private groups: BadgeGroup[] = [];
  /** 城市套章进度：与勋章组同序；没有种子数据的城市 total=0，不画进度 */
  @State private stamps: CityStamp[] = [];
  @State private loading: boolean = true;
  /** 顶栏磨砂两态：由**绝对**滚动偏移驱动（每帧增量会被松手回弹的负帧打灭，契约 §Translucency） */
  @State private barScrolled: boolean = false;
  private barScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.Context;
    try {
      const rows: BadgeRecord[] = await BadgeDao.listMine(ctx);
      const groups: BadgeGroup[] = buildBadgeBoard(rows);
      const sets: CitySpotSet[] = [];
      for (const group of groups) {
        const spots: Spot[] = await SpotDao.loadByCity(ctx, group.city);
        const names: string[] = [];
        for (const spot of spots) {
          names.push(spot.name);
        }
        const set: CitySpotSet = { city: group.city, names: names };
        sets.push(set);
      }
      this.groups = groups;
      this.stamps = buildCityStamps(sets, groups);
      this.loading = false;
    } catch (err) {
      this.loading = false;
      Logger.error('Ui.Badge', `勋章加载失败: ${(err as Error).message}`);
    }
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

  private stampTotal(city: string): number {
    const stamp: CityStamp | null = stampOf(this.stamps, city);
    return stamp === null ? 0 : stamp.total;
  }

  private stampCollected(city: string): number {
    const stamp: CityStamp | null = stampOf(this.stamps, city);
    return stamp === null ? 0 : stamp.collected;
  }

  private stampComplete(city: string): boolean {
    const stamp: CityStamp | null = stampOf(this.stamps, city);
    return stamp !== null && stamp.complete;
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
    Row({ space: SpaceTokens.sm }) {
      SymbolGlyph($r('sys.symbol.medal'))
        .fontSize(IconSizes.display)
        .fontColor([ColorTokens.primary])
      Column({ space: SpaceTokens.xxs }) {
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
    .padding(SpaceTokens.base)
    .borderRadius(RadiusTokens.hero)
    .backgroundColor(ColorTokens.surfaceElevated)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  cityHeader(city: string) {
    Column({ space: SpaceTokens.xxs }) {
      Row() {
        Text(city)
          .fontSize(TypeTokens.overline.size)
          .fontWeight(600)
          .fontColor(ColorTokens.muted)
        Blank()
        Text(stampMeta(stampOf(this.stamps, city), this.countIn(city)))
          .fontSize(TypeTokens.overline.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .fontFeature("'tnum' on")
      }
      .width('100%')

      if (this.stampTotal(city) > 0) {
        Progress({ value: this.stampCollected(city), total: this.stampTotal(city), type: ProgressType.Linear })
          .color(this.stampComplete(city) ? ColorTokens.success : ColorTokens.primary)
          // 空轨跟**它压在什么上面**走：这条坐画布 #121212，
          // sunken #0D0D0F 只差 5 档，实测整条看不见、只剩左边一小截蓝（屏13 真机 1/32 枚）
          .backgroundColor(ColorTokens.hairline)
          .width('100%')
          .accessibilityText(`城市套章进度 ${this.stampCollected(city)} / ${this.stampTotal(city)}`)
        if (this.stampComplete(city)) {
          Text('已集齐城市套章')
            .fontSize(TypeTokens.overline.size)
            .fontWeight(600)
            .fontColor(ColorTokens.success)
        }
      }
    }
    .width('100%')
    // 吸顶层要自带实底：sticky 头没有底板时，滚动行会从字下穿过去
    .backgroundColor(ColorTokens.canvas)
    .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.xxs })
  }

  @Builder
  badgeRow(badge: Badge) {
    // 整格可点：官方 Button 做壳（按压态/读屏焦点），视觉由内层承担
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: SpaceTokens.xs }) {
        SymbolGlyph($r('sys.symbol.medal'))
          .fontSize(IconSizes.control)
          .fontColor([ColorTokens.primary])
        Column({ space: SpaceTokens.xxs }) {
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
      .padding(SpaceTokens.sm)
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
    Column({ space: SpaceTokens.sm }) {
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
    .padding(SpaceTokens.base)
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
    HdsNavDestination() {
      Column() {
        if (this.loading) {
          Column({ space: SpaceTokens.sm }) {
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
          List({ space: SpaceTokens.xs, scroller: this.barScroller }) {
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
          .padding({ left: SpaceTokens.base, right: SpaceTokens.base,
            bottom: LayoutTokens.floatingDockClearance })
          .layoutWeight(1)
          .onDidScroll((): void => {
            this.syncBarScroll();
          })
        }
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(ColorTokens.canvas)
    }
    // HDS 深色档这层默认纯黑，透明栏会把它露成一条比画布暗一档的带（成因与实测见 Docs/INIT_REPORT.md §5ci 续 80）
    .backgroundColor(ColorTokens.canvas)
    .titleBar(HdsChrome.bar({
      mainTitle: '我的勋章',
      subTitle: this.loading || this.groups.length === 0 ? '' : `共 ${this.totalCount()} 枚`,
      scrolled: this.barScrolled
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
