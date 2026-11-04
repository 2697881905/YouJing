/**
 * 时长文案的回归（屏15 信号条 / 当前节点行）。
 *
 * 真机实拍到「已过开始时间 431 分钟」——分钟数原样打出来等于把除法丢给用户。
 * 这份用例把「什么时候还留分钟、什么时候拆成时/分、什么时候拆到天」钉死。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { DurationCn } from '../../../main/ets/utils/DurationCn';

export default function durationCnTest(): void {
  describe('DurationCn', () => {
    it('under_one_hour_keeps_minutes', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      expect(DurationCn.text(0)).assertEqual('0分钟');
      expect(DurationCn.text(45)).assertEqual('45分钟');
      expect(DurationCn.text(59)).assertEqual('59分钟');
    });

    it('hour_boundary_and_remainder', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      expect(DurationCn.text(60)).assertEqual('1小时');
      expect(DurationCn.text(120)).assertEqual('2小时');
      expect(DurationCn.text(162)).assertEqual('2小时42分钟');
      expect(DurationCn.text(431)).assertEqual('7小时11分钟');
    });

    it('day_and_more', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      expect(DurationCn.text(1440)).assertEqual('1天');
      expect(DurationCn.text(1500)).assertEqual('1天1小时');
      // 负数与小数按 0 处理：文案不该出现「-3 分钟」
      expect(DurationCn.text(-3)).assertEqual('0分钟');
    });
  });
}
