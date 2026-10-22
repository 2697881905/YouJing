/**
 * 屏9 行程编辑 · 拖动与替换（帧 ebe57eac）。
 * 拖拽配方（有据实证 + 项目记忆）：List.onItemDragStart 自定义拖影、
 * 把手只挂把手、onItemHover 记最后悬停位、onItemDragEnd 兜底落位。
 * 稿件中的移出空档/插入提示为拖拽过程态，由系统拖影与落位动画承担。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { Activity } from '../model/Trip';
import { MockTrip } from '../mock/MockTrip';

@Component
export struct EditItineraryPage {
  private pathStack: NavPathStack = APP_NAV;
  @State private acts: Activity[] = MockTrip.TRIP.days[0].activities.slice();
  @State private dragIdx: number = -1;
  @State private hoverIdx: number = -1;

  private move(from: number, to: number): void {
    if (from === to || from < 0 || to < 0) {
      return;
    }
    const next: Activity[] = this.acts.slice();
    const moved: Activity = next.splice(from, 1)[0];
    next.splice(to, 0, moved);
    this.acts = next;
  }

  @Builder
  handle() {
    Column({ space: 3 }) {
      Row().width(14).height(2).borderRadius(RadiusTokens.pill).backgroundColor(ColorTokens.faint)
      Row().width(14).height(2).borderRadius(RadiusTokens.pill).backgroundColor(ColorTokens.faint)
      Row().width(14).height(2).borderRadius(RadiusTokens.pill).backgroundColor(ColorTokens.faint)
    }
    .width(24)
    .height(LayoutTokens.minTouchTarget)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  rowPreview(act: Activity) {
    Row({ space: SpaceTokens.sm }) {
      Text(act.time)
        .fontSize(TypeTokens.time.size)
        .fontWeight(600)
        .fontColor(ColorTokens.primary)
        .fontFeature("'tnum' on")
      Text(act.title)
        .fontSize(TypeTokens.small.size)
        .fontWeight(600)
        .fontColor(ColorTokens.ink)
    }
    .padding(SpaceTokens.md)
    .borderRadius(RadiusTokens.card)
    .backgroundColor(ColorTokens.canvas)
    .shadow({ radius: 16, offsetX: 0, offsetY: 6, color: '#17000000' })
  }

  @Builder
  editRow(act: Activity, idx: number) {
    Row({ space: SpaceTokens.sm }) {
      this.handle()
      Text(act.time)
        .width(52)
        .fontSize(TypeTokens.time.size)
        .fontWeight(600)
        .fontColor(this.dragIdx === idx ? ColorTokens.primary : ColorTokens.ink)
        .textAlign(TextAlign.End)
        .fontFeature("'tnum' on")
      Column() {
        Text(act.title)
          .fontSize(TypeTokens.small.size)
          .fontWeight(600)
          .fontColor(ColorTokens.ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(act.address.replace('京都 ', ''))
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.arrow_2_circlepath'))
        .fontSize(22)
        .fontColor([ColorTokens.icon])
        .onClick(() => {
          this.pathStack.pushPath({ name: 'SpotPick' });
        })
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(22)
        .fontColor([ColorTokens.muted])
        .margin({ left: SpaceTokens.md })
        .onClick(() => {
          const next: Activity[] = this.acts.slice();
          next.splice(idx, 1);
          this.acts = next;
        })
    }
    .width('100%')
    .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
    .borderRadius(RadiusTokens.card)
    .backgroundColor(this.dragIdx === idx ? ColorTokens.primaryTint : ColorTokens.surfaceElevated)
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          Text('编辑行程')
            .fontSize(TypeTokens.body.size)
            .fontWeight(600)
            .fontColor(ColorTokens.ink)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          Row({ space: SpaceTokens.xs }) {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(22)
              .fontColor([ColorTokens.primary])
            Text('完成')
              .fontSize(TypeTokens.small.size)
              .fontColor(ColorTokens.primary)
          }
          .onClick(() => {
            this.pathStack.pop();
          })
        }
        .height(LayoutTokens.titleBarHeight)
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })

        List({ space: SpaceTokens.xs }) {
          ForEach(this.acts, (act: Activity, idx: number) => {
            ListItem() {
              this.editRow(act, idx)
            }
          }, (act: Activity): string => `edit-${act.id}`)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, bottom: LayoutTokens.bottomScrollReserve })
        .onItemDragStart((event: ItemDragInfo, itemIndex: number): CustomBuilder => {
          this.dragIdx = itemIndex;
          const act: Activity = this.acts[itemIndex];
          return (): void => {
            this.rowPreview(act);
          };
        })
        .onItemDrop((event: ItemDragInfo, itemIndex: number, insertIndex: number,
          isSuccess: boolean): void => {
          if (isSuccess && insertIndex >= 0) {
            this.move(itemIndex, insertIndex > itemIndex ? insertIndex - 1 : insertIndex);
          }
          this.dragIdx = -1;
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ColorTokens.canvas)
    }
    .hideTitleBar(true)
  }
}
