/**
 * 编辑期活动 id 的回归：必须唯一且带来源前缀。
 *
 * 背景：EditItineraryPage 曾直接拿 `spot.id` 当活动 id，同景点出现两次会撞
 * `TripDao` 的 `${tripId}:${activityId}` 主键，整次编辑保存失败。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { mintEditActivityId } from '../../../main/ets/utils/ActivityIds';

export default function activityIdsTest(): void {
  describe('ActivityIds', () => {
    it('minted_ids_are_unique_and_prefixed', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const a: string = mintEditActivityId('add');
      const b: string = mintEditActivityId('add');
      const c: string = mintEditActivityId('rep');
      expect(a === b).assertFalse();
      expect(a.indexOf('add-') === 0).assertTrue();
      expect(c.indexOf('rep-') === 0).assertTrue();
    });
  });
}
