/**
 * 导航方式判定与底部避让量的纯计算回归（utils/navInset）。
 * 钉的是真机踩过的重叠区间：模拟器手势条 27.9vp 与真机三键栏 27.8vp 只看高度判不开，
 * 只看高度的旧写法会把手势条当三键、Dock 白抬 ~28.9vp（有据 navMode.ets 文件头记录的实测后果）。
 */
import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import {
  GESTURE_INDICATOR_MAX, NAV_INSET_EXTRA, GESTURE_INDICATOR_INSET,
  spansFullWidth, isThreeButton, computeNavInset, computeBarInset
} from '../../../main/ets/utils/navInset';

export default function navInsetTest(): void {
  describe('navInset 底部避让判定', () => {
    it('gesture_bar_is_not_three_button_at_overlapping_height',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
        // 手势条：高 27.9vp 但只是居中窄胶囊（实测宽占比 35%）
        expect(spansFullWidth(137, 391)).assertFalse();
        expect(isThreeButton(27.9, 137, 391)).assertFalse();
        expect(computeNavInset(27.9, 137, 391)).assertEqual(0);
        expect(computeBarInset(27.9, 137, 391)).assertEqual(GESTURE_INDICATOR_INSET);
      });

    it('three_button_bar_detected_by_height_and_full_width',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
        // 三键栏：高 27.8vp 且避让矩形横贯整屏
        expect(spansFullWidth(1136, 1136)).assertTrue();
        expect(isThreeButton(27.8, 363.5, 363.5)).assertTrue();
        expect(computeNavInset(27.8, 363.5, 363.5)).assertEqual(27.8 + NAV_INSET_EXTRA);
      });

    it('short_three_button_still_gesture_because_height_threshold',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
        // 阈值 24 以下一律不判三键（满宽也不能翻）
        expect(GESTURE_INDICATOR_MAX).assertEqual(24);
        expect(isThreeButton(20, 363.5, 363.5)).assertFalse();
      });

    it('missing_signal_falls_back_to_gesture_conservatively',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
        // 上报缺项（宽 0）→ 保守判手势：避让 0，维持原布局，不把 dock 白抬
        expect(isThreeButton(30, 0, 363.5)).assertFalse();
        expect(computeNavInset(30, 0, 363.5)).assertEqual(0);
      });

    it('zero_window_width_never_divides',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
        expect(spansFullWidth(100, 0)).assertFalse();
      });
  });
}
