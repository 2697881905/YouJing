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
export const FLOW_STEP_ITINERARY: number = 4;

@Component
export struct FlowSteps {
  /** 当前步序号，从 0 起 */
  @Prop step: number = 0;

  build() {
    Column({ space: SpaceTokens.sm }) {
      Row({ space: SpaceTokens.xs }) {
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
