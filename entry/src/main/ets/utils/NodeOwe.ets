/**
 * 屏15「你欠着的那一站」的唯一规则。
 *
 * 这一屏有两个相关但**不同**的问题，各自一条规则，别再混成一个"当前"：
 *   · 「现在按钟点该在哪」→ hero 的当前节点、进度条、到站订阅，在 OnTripPage.reload 里算；
 *   · 「哪一站该做而没做」→ 本模块，喂给打卡列表的「进行中」行与建议条。
 * 用户准时时两者重合；一落后就分叉，所以两处**必须说清各自在回答哪个问题**，
 * 不能都叫「当前」。
 *
 * 只在**可操作站点**上算（交通与住宿不参与"欠"）：它们既不能跳过也不是顺延目标，
 * 把"欠"落在住宿上会让建议条彻底哑掉。
 *
 * 曾试过让 hero 也吃这条（"欠的那一站赢"），真机否决：整天一次卡都没打过时，
 * 它永远指向今天第一站，晚上九点半把 10:00 的入住办理当「当前节点」还让「完成打卡」
 * 去落它，比钟点站没用得多，而且建议条因为当前节点落在住宿上直接消失。
 */

/** 参与判定的一个节点：稳定 key + 当日开始分钟数 */
export interface OweItem {
  key: string;
  startMin: number;
}

export class NodeOwe {
  /**
   * 返回该被追的那一站在 `ordered` 里的下标，没有就返回 -1（调用方退回钟点规则）。
   * `ordered` 必须已按 `startMin` 升序。
   *
   * 只往后追、不回头：最后一个已打卡**之前**的漏站不再当"欠"，
   * 否则用户明明已经走过第 3 站，屏幕会把他按回第 1 站。
   */
  static indexOf(ordered: OweItem[], checkedKeys: string[], nowMin: number): number {
    let from: number = 0;
    for (let i = 0; i < ordered.length; i++) {
      if (NodeOwe.isChecked(ordered[i].key, checkedKeys)) {
        from = i + 1;
      }
    }
    for (let i = from; i < ordered.length; i++) {
      if (ordered[i].startMin > nowMin) {
        break;
      }
      if (!NodeOwe.isChecked(ordered[i].key, checkedKeys)) {
        return i;
      }
    }
    return -1;
  }

  private static isChecked(key: string, checkedKeys: string[]): boolean {
    for (const k of checkedKeys) {
      if (k === key) {
        return true;
      }
    }
    return false;
  }
}
