/**
 * 编辑期活动 id 铸造（纯逻辑，可进 hypium）。
 *
 * 为什么不能直接用 `spot.id`：`TripDao` 的活动主键是 `${tripId}:${activity.id}`，
 * 同一景点在一趟行程里出现两次（换天补选、或替换成行程里已有的景点）就会撞 UNIQUE，
 * 整次编辑保存失败。生成链路已经在落库前重铸成 `d{天}-a{序}`，编辑链路同样必须唯一。
 */
export function mintEditActivityId(prefix: string): string {
  return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
}
