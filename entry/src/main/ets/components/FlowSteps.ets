/**
 * 建行程主链的共用步骤指示（屏2→屏6）。
 * 此前六步里只有屏3 自带「第 N/4 步」，其余各屏既不说流程多长、也不说走到哪，
 * 用户只能靠反复点「下一步」试探还有几步——这是「业务流程混乱」里最容易治的一条。
 */

import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';

/** 主链五步：屏2 基础信息 → 屏3 偏好 → 屏4 景点 → 屏5 住宿 → 屏8 行程 */
export const FLOW_STEPS: string[] = ['基础信息', '出行偏好', '选景点', '选住宿', '看行程'];

/** 各屏对应的步序（从 0 起），页面按此传值，避免各处硬写数字写歪 */
export const FLOW_STEP_TRIP_INPUT: number = 0;
export const FLOW_STEP_PREFERENCE_QA: number = 1;
export const FLOW_STEP_SPOT_PICK: number = 2;
export const FLOW_STEP_STAY_PICK: number = 3;
// 刻意**不给屏8 定义 step**：屏8 是结果页，而且从「行程」格点开一条老行程
// 也落在这屏——那时说"第 5 / 5 步"是错的。五档里最后一档「看行程」是终点标记，
// 由屏5 之后的生成流程兑现，不挂在屏8 顶栏下。

@Component
export struct FlowSteps {
  /** 当前步序号，从 0 起 */
  @Prop step: number = 0;

  build() {
    Column({ space: SpaceTokens.xs }) {
      Row({ space: SpaceTokens.xxs }) {
        ForEach(FLOW_STEPS, (label: string, index: number) => {
          Column()
            .layoutWeight(1)
            .height(LayoutTokens.routeLineWidth)
            .borderRadius(RadiusTokens.pill)
            .backgroundColor(index <= this.step ? ColorTokens.primary : ColorTokens.separator)
        }, (label: string, index: number): string => `flow-seg-${index}`)
      }
      .width('100%')

      Text(`第 ${this.step + 1} / ${FLOW_STEPS.length} 步 · ${FLOW_STEPS[this.step]}`)
        .fontSize(TypeTokens.caption.size)
        .fontWeight(450)
        .fontColor(ColorTokens.muted)
        .fontFeature("'tnum' on")
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}
