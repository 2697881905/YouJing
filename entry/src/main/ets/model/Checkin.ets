/**
 * 节点打卡（开发文档 §5 流程 8「旅行中 → 打卡」）。
 *
 * 刻意不进 Trip/Activity 契约：行程是 LLM 生成、由 TripParser 守卫的对象，
 * 打卡是本机用户态，混在一起会让 AI 契约长出与生成无关的字段。
 * 因此单独一张 checkin 表，按 (trip_id, activity_id) 唯一。
 */

export interface CheckinMark {
  tripId: string;
  activityId: string;
  /** 打卡时刻（ms） */
  checkedAt: number;
}
