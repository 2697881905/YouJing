/**
 * 展示文案层的回归：金额千分位（MoneyText）、停留时长（TimeText）、
 * 跨页签/草稿广播的字符串协议（AppNav 的两个谓词）。
 *
 * 为什么单独一份：这三处都是本仓从"六个渲染点各拼各的"收口出来的统一入口，
 * 屏面上一眼就能看出错（`¥16000`、`4小时30分`、红点该灭不灭），
 * 但它们全是纯字符串函数，不需要真机、不需要 DB——正是最该钉住的一层。
 * 时间档位（Responsive.test.ets）管的是布局，这里管的是文案。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { MoneyText } from '../../../main/ets/utils/MoneyText';
import { TimeText } from '../../../main/ets/utils/TimeText';
import { isTabShownTick, isDraftDirty, announceTabShown, markDraftDirty, TAB_SHOWN_KEY, DRAFT_DIRTY_KEY } from '../../../main/ets/common/constants/AppNav';
import { Activity, ActivityStatus, ActivityCategory } from '../../../main/ets/model/Trip';

function act(time: string, endTime: string): Activity {
  const a: Activity = {
    id: 't-1', time: time, endTime: endTime, title: '测试节点', location: '测试地点',
    address: '测试地址', longitude: 0, latitude: 0,
    status: ActivityStatus.NO_NEED, category: ActivityCategory.SIGHT
  };
  return a;
}

export default function displayTextTest(): void {
  describe('MoneyText', () => {

    it('groups_only_above_thousands', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(MoneyText.group(0)).assertEqual('0');
      expect(MoneyText.group(999)).assertEqual('999');
      expect(MoneyText.group(1000)).assertEqual('1,000');
      expect(MoneyText.group(16000)).assertEqual('16,000');
      expect(MoneyText.group(1234567)).assertEqual('1,234,567');
      // 整百万是分组最容易错位的一档（前导 1 后面要跟两个逗号）
      expect(MoneyText.group(1000000)).assertEqual('1,000,000');
    });

    it('keeps_sign_and_drops_fraction', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      // 超支是负数场景，负号必须留在最前而不是被分组挤到数字中间
      expect(MoneyText.group(-840)).assertEqual('-840');
      expect(MoneyText.group(-1240)).assertEqual('-1,240');
      // 金额没有小数语义（预算/记账都是整数元），传进来带小数要先截断
      expect(MoneyText.group(1234.9)).assertEqual('1,234');
    });

    it('yuan_always_renders_even_zero', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(MoneyText.yuan(16000)).assertEqual('¥16,000');
      // 0 要能读出"确实没花"，不是缺字段——空串会让费用页那格凭空消失
      expect(MoneyText.yuan(0)).assertEqual('¥0');
    });
  });

  describe('TimeText', () => {

    it('renders_hours_and_minutes', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(TimeText.stayMinutes(act('09:00', '13:30'))).assertEqual(270);
      expect(TimeText.stayOf(act('09:00', '13:30'))).assertEqual('4小时30分钟');
      expect(TimeText.stayOf(act('09:00', '13:00'))).assertEqual('4小时');
      expect(TimeText.stayOf(act('09:00', '09:45'))).assertEqual('45分钟');
    });

    it('returns_empty_for_missing_or_inverted', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      // AI 可以不给 endTime（旧数据也没有），倒挂是重排可能造出来的态。
      // 这两种都必须回空串让调用方兜底，不能输出「-60分钟」这种可读的胡说
      expect(TimeText.stayOf(act('09:00', ''))).assertEqual('');
      expect(TimeText.stayOf(act('10:00', '09:00'))).assertEqual('');
      expect(TimeText.stayOf(act('09:00', '09:00'))).assertEqual('');
    });
  });

  describe('BroadcastStringProtocol', () => {

    it('tab_tick_matches_its_own_index_only', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      // 协议是 `<index>:<时间戳>`。前缀匹配最怕多档页签互撞：
      // '10:…' 不能被当成第 1 页签的广播
      expect(isTabShownTick('2:1730000000000', 2)).assertTrue();
      expect(isTabShownTick('2:1730000000000', 3)).assertFalse();
      expect(isTabShownTick('10:1730000000000', 1)).assertFalse();
      expect(isTabShownTick('1:1730000000000', 1)).assertTrue();
      // 冷启还没有任何广播：空串必须谁都不匹配
      expect(isTabShownTick('', 0)).assertFalse();
    });

    it('draft_dirty_is_explicit_both_ways', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(isDraftDirty('1:1730000000000')).assertTrue();
      // 「清干净」也必须写值而不是留旧值，否则首启会凭空冒出"继续未完成的规划"
      expect(isDraftDirty('0:1730000000000')).assertFalse();
      expect(isDraftDirty('')).assertFalse();
    });

    it('write_side_helpers_produce_the_protocol', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      // 谓词与生成器必须同源：改了 announce 的格式，这一条要先红
      announceTabShown(2);
      const tick: string = AppStorage.get<string>(TAB_SHOWN_KEY) ?? '';
      expect(isTabShownTick(tick, 2)).assertTrue();

      markDraftDirty(true);
      const dirty: string = AppStorage.get<string>(DRAFT_DIRTY_KEY) ?? '';
      expect(isDraftDirty(dirty)).assertTrue();

      markDraftDirty(false);
      const cleared: string = AppStorage.get<string>(DRAFT_DIRTY_KEY) ?? '';
      expect(isDraftDirty(cleared)).assertFalse();
    });
  });
}
