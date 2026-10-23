/**
 * 屏2 行程基础输入（帧 7d2eafa8）。
 * 必改表已落：budget-container gap 10→8；budget-track-wrapper gap 6→4；field-col gap 2→0。
 * 目的地/日期选择器与预算滑杆交互在批次 4 接入，本批为静态展示态 + 可选人数。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { PlanDraft } from '../data/PlanDraft';
import { TripBasicInput } from '../model/PlanParams';
import { DateUtils } from '../utils/DateUtils';
import { BudgetConfig } from '../common/constants/BudgetConfig';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';

const CITIES: string[] = ['北京', '上海', '广州', '深圳', '京都（演示）'];

@Component
export struct TripInputPage {
  private pathStack: NavPathStack = APP_NAV;
  @State private party: number = 2;
  @State private city: string = '北京';
  @State private startDate: string = '2026-07-01';
  @State private endDate: string = '2026-07-03';
  @State private showCity: boolean = false;
  @State private budget: number = BudgetConfig.DEFAULT;
  private basePartyOptions: number[] = [1, 2, 4];

  /** 屏2 是草稿的展示方：外部拉起（小艺/深链）预填与返回本屏都要回显真值 */
  aboutToAppear(): void {
    const b: TripBasicInput = PlanDraft.get().basic;
    if (CITIES.indexOf(b.destination) >= 0) {
      this.city = b.destination;
    }
    if (DateUtils.isValidIsoDate(b.startDate)) {
      this.startDate = b.startDate;
    }
    if (DateUtils.isValidIsoDate(b.endDate) && DateUtils.spanDays(this.startDate, b.endDate) >= 1) {
      this.endDate = b.endDate;
    }
    if (b.people > 0) {
      this.party = b.people;
    }
    if (b.budget >= BudgetConfig.MIN && b.budget <= BudgetConfig.MAX) {
      this.budget = b.budget;
    }
  }

  /** 快捷档位固定 1/2/4；小艺带来 3 或 5 等人数时把它补进选项，避免数字对但 chip 不高亮 */
  private partyOptions(): number[] {
    if (this.basePartyOptions.indexOf(this.party) < 0) {
      const options: number[] = this.basePartyOptions.slice();
      options.push(this.party);
      options.sort((a: number, b: number): number => a - b);
      return options;
    }
    return this.basePartyOptions;
  }

  private fmt(dateStr: string): string {
    const parts: string[] = dateStr.split('-');
    return `${Number(parts[1])}月${Number(parts[2])}日`;
  }

  private dayCount(): number {
    return Math.max(1, Math.round((Date.parse(this.endDate) - Date.parse(this.startDate)) / 86400000) + 1);
  }

  private pickDate(isStart: boolean): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date('2026-01-01'),
      end: new Date('2027-12-31'),
      selected: new Date(isStart ? this.startDate : this.endDate),
      onDateAccept: (value: Date): void => {
        const y: number = value.getFullYear();
        const m: string = `${value.getMonth() + 1}`.padStart(2, '0');
        const d: string = `${value.getDate()}`.padStart(2, '0');
        const iso: string = `${y}-${m}-${d}`;
        if (isStart) {
          this.startDate = iso;
          if (Date.parse(this.endDate) < Date.parse(iso)) {
            this.endDate = iso;
          }
        } else {
          this.endDate = iso;
        }
      }
    });
  }

  @Builder
  fieldLabel(label: string) {
    Text(label)
      .fontSize(TypeTokens.overline.size)
      .fontWeight(600)
      .fontColor(ColorTokens.muted)
  }

  @Builder
  chevron() {
    SymbolGlyph($r('sys.symbol.chevron_right'))
      .fontSize(22)
      .fontColor([ColorTokens.faint])
  }

  @Builder
  partyChip(count: number) {
    // 官方圆形 Button：选中态走 EMPHASIZED 档，不再自绘底色 + 描边
    Button(count.toString())
      .width(LayoutTokens.minTouchTarget)
      .height(LayoutTokens.minTouchTarget)
      .fontSize(TypeTokens.small.size)
      .fontWeight(600)
      .type(ButtonType.Circle)
      .buttonStyle(this.party === count ? ButtonStyleMode.EMPHASIZED : ButtonStyleMode.NORMAL)
      .onClick(() => {
        this.party = count;
      })
  }

  @Builder
  citySheet() {
    Column() {
      ForEach(CITIES, (c: string) => {
        Row() {
          Text(c)
            .fontSize(TypeTokens.body.size)
            .fontWeight(c === this.city ? 600 : 400)
            .fontColor(c === this.city ? ColorTokens.primary : ColorTokens.ink)
            .layoutWeight(1)
          if (c === this.city) {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(22)
              .fontColor([ColorTokens.primary])
          }
        }
        .width('100%')
        .height(LayoutTokens.minTouchTarget)
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })
        .onClick(() => {
          this.city = c;
          this.showCity = false;
        })
      }, (c: string): string => `city-${c}`)
    }
    .width('100%')
    .padding({ top: SpaceTokens.md, bottom: SpaceTokens.md })
    .backgroundColor(ColorTokens.canvas)
  }

  build() {
    HdsNavDestination() {
      Column() {
        Scroll() {
          Column() {
            Column() {
              Text('开启一次有迹可循的旅程')
                .fontSize(TypeTokens.title.size)
                .fontWeight(700)
                .fontFamily(TypeTokens.title.family)
                .fontColor(ColorTokens.ink)
              Text('设定出行基础参数，AI 将基于本地精选数据库构建动线')
                .fontSize(TypeTokens.small.size)
                .fontColor(ColorTokens.body)
                .margin({ top: SpaceTokens.xs })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .margin({ top: SpaceTokens.lg, bottom: SpaceTokens.xl })

            Column({ space: SpaceTokens.md }) {
              // 目的地
              Row() {
                Column() {
                  this.fieldLabel('目的地')
                  Text(this.city)
                    .fontSize(TypeTokens.headline.size)
                    .fontWeight(600)
                    .fontColor(ColorTokens.ink)
                    .margin({ top: SpaceTokens.xs })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                this.chevron()
              }
              .width('100%')
              .padding(SpaceTokens.lg)
              .borderRadius(RadiusTokens.card)
              .backgroundColor(ColorTokens.surfaceSubtle)
              .onClick(() => {
                this.showCity = true;
              })

              // 出行日期
              Row() {
                Column() {
                  this.fieldLabel('出行日期')
                  Text(`${this.fmt(this.startDate)} – ${this.fmt(this.endDate)}`)
                    .fontSize(TypeTokens.headline.size)
                    .fontWeight(600)
                    .fontColor(ColorTokens.ink)
                    .fontFeature("'tnum' on")
                    .margin({ top: SpaceTokens.xs })
                  Text(`${this.dayCount()}天${this.dayCount() - 1}晚`)
                    .fontSize(TypeTokens.caption.size)
                    .fontWeight(450)
                    .fontColor(ColorTokens.muted)
                    .fontFeature("'tnum' on")
                    .margin({ top: SpaceTokens.xs })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                this.chevron()
              }
              .width('100%')
              .padding(SpaceTokens.lg)
              .borderRadius(RadiusTokens.card)
              .backgroundColor(ColorTokens.surfaceSubtle)
              .onClick(() => {
                this.pickDate(true);
              })
              .gesture(LongPressGesture().onAction(() => {
                this.pickDate(false);
              }))

              // 同行人数
              Row() {
                Column() {
                  this.fieldLabel('同行人数')
                  Text(`${this.party} 位成人`)
                    .fontSize(TypeTokens.headline.size)
                    .fontWeight(600)
                    .fontColor(ColorTokens.ink)
                    .fontFeature("'tnum' on")
                    .margin({ top: SpaceTokens.xs })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Row({ space: SpaceTokens.xs }) {
                  ForEach(this.partyOptions(), (count: number) => {
                    this.partyChip(count)
                  }, (count: number): string => `party-${count}`)
                }
              }
              .width('100%')
              .padding(SpaceTokens.lg)
              .borderRadius(RadiusTokens.card)
              .backgroundColor(ColorTokens.surfaceSubtle)

              // 预算档位
              Column({ space: SpaceTokens.sm }) {
                Row() {
                  Column() {
                    this.fieldLabel('预算档位')
                    Text(`¥${this.budget.toLocaleString('en-US')} / 人`)
                      .fontSize(TypeTokens.headline.size)
                      .fontWeight(600)
                      .fontColor(ColorTokens.ink)
                      .fontFeature("'tnum' on")
                      .margin({ top: SpaceTokens.xs })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  this.chevron()
                }
                .width('100%')

                // 底稿是 55/45 的手绘轨道，实为可选区间 3,000–12,000/人（默认 8,000 恰落在 55%）
                Slider({
                  value: this.budget,
                  min: BudgetConfig.MIN,
                  max: BudgetConfig.MAX,
                  step: BudgetConfig.STEP,
                  style: SliderStyle.OutSet
                })
                  .width('100%')
                  .selectedColor(ColorTokens.primary)
                  .trackColor(ColorTokens.hairline)
                  .blockColor(ColorTokens.surfaceElevated)
                  .onChange((v: number) => {
                    this.budget = Math.round(v);
                  })

                Row() {
                  Text('经济')
                    .fontSize(TypeTokens.caption.size)
                    .fontWeight(450)
                    .fontColor(ColorTokens.muted)
                  Text('舒适')
                    .fontSize(TypeTokens.caption.size)
                    .fontWeight(450)
                    .fontColor(ColorTokens.muted)
                }
                .width('100%')
                .justifyContent(FlexAlign.SpaceBetween)
              }
              .width('100%')
              .padding(SpaceTokens.lg)
              .borderRadius(RadiusTokens.card)
              .backgroundColor(ColorTokens.surfaceSubtle)
            }
          }
          .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, bottom: LayoutTokens.bottomScrollReserve })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)

        Column() {
          YoujingButton({
            variant: YoujingButtonVariant.PRIMARY,
            label: '开始规划',
            fullWidth: true,
            trailingSymbol: $r('sys.symbol.arrow_right'),
            onAction: (): void => {
              const d: PlanDraft = PlanDraft.get();
              const basic: TripBasicInput = {
                destination: this.city, startDate: this.startDate,
                endDate: this.endDate, people: this.party, budget: this.budget
              };
              d.basic = basic;
              this.pathStack.pushPath({ name: 'PreferenceQA' });
            }
          })
        }
        .width('100%')
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, top: SpaceTokens.md, bottom: SpaceTokens.md })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ColorTokens.canvas)
      .bindSheet($$this.showCity, this.citySheet(), {
        height: 300,
        backgroundColor: ColorTokens.canvas,
        showClose: true
      })
    }
    .titleBar(HdsChrome.bar({ mainTitle: '有径', subTitle: '设定出行基础参数' }))
    .titleMode(HdsNavDestinationTitleMode.MINI)
  }
}
