/**
 * 屏幕适配层的映射回归。
 *
 * 为什么要有这一份：宽屏/折叠展开的**实机渲染至今没拿到一帧**，
 * 但「断点 → 列数 / 正文上限」这套映射是纯函数，可以离线钉死。
 * 这里验的是机制，不是某个具体设备上的像素；真机宽屏渲染仍是未验项。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { listLanesForBreakpoint, longFormMaxWidth } from '../../../main/ets/utils/responsive';
import { isWideBreakpoint, BP_MD_MIN_VP, BP_LG_MIN_VP } from '../../../main/ets/utils/breakpointCenter';

/** 卡片实测的最小可读列宽（vp）：低于它，我的行程卡的站名会被压成省略号、
 *  统计格会竖排（把断点钉成 lg 在 360vp 手机上复现过） */
const MIN_LANE_VP: number = 180;

/** 单列长文在宽屏上的上限，取自 design/LayoutTokens.contentMaxWidth */
const CAP_VP: number = 720;

export default function responsiveTest(): void {
  describe('Responsive', () => {
    it('lanes_follow_breakpoint_ladder', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(listLanesForBreakpoint('sm')).assertEqual(1);
      expect(listLanesForBreakpoint('md')).assertEqual(2);
      expect(listLanesForBreakpoint('lg')).assertEqual(3);
      // 未识别的断点串一律退回单列，不能让 List.lanes 拿到 0 或 undefined
      expect(listLanesForBreakpoint('')).assertEqual(1);
      expect(listLanesForBreakpoint('whatever')).assertEqual(1);
    });

    it('only_sm_is_narrow_pane', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(isWideBreakpoint('sm')).assertFalse();
      expect(isWideBreakpoint('md')).assertTrue();
      expect(isWideBreakpoint('lg')).assertTrue();
    });

    it('long_form_is_uncapped_on_phone_and_capped_on_wide',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
        // 手机竖屏返回 '100%'，等于不收窄——这一档必须是字符串而不是数字，
        // 否则 constraintSize.maxWidth 会拿到一个比屏宽还小的数、把表单压窄
        expect(longFormMaxWidth('sm', CAP_VP)).assertEqual('100%');
        expect(longFormMaxWidth('md', CAP_VP)).assertEqual(CAP_VP);
        expect(longFormMaxWidth('lg', CAP_VP)).assertEqual(CAP_VP);
      });

    it('every_ladder_step_keeps_lanes_readable', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      // 断点阈值与列数必须成对：某一步的"起始宽 ÷ 列数"若低于最小列宽，
      // 卡片就会在那个断点上崩版（阈值被改动时这条会先红）
      const mdCols: number = listLanesForBreakpoint('md');
      const lgCols: number = listLanesForBreakpoint('lg');
      expect(Math.floor(BP_MD_MIN_VP / mdCols) >= MIN_LANE_VP).assertTrue();
      expect(Math.floor(BP_LG_MIN_VP / lgCols) >= MIN_LANE_VP).assertTrue();
      // 阈值本身也钉住，防止有人把 md 调到 320 让手机也进多列
      expect(BP_MD_MIN_VP).assertEqual(600);
      expect(BP_LG_MIN_VP).assertEqual(840);
    });
  });
}
