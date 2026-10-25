/**
 * 通勤方式 → 系统 symbol 图标（屏8 交通腿、屏15 下一段通勤共用）。
 * 从 ItineraryPage 私有方法提取：屏15 原来写死汽车图标，
 * 下一段是地铁/公交/步行时会显示错误车标。
 * 认不出的模式按步行兜底（行程里最常见的一段）。
 */

export class TransitSymbol {
  static of(mode: string): Resource {
    if (mode.indexOf('地铁') >= 0 || mode.indexOf('轨道') >= 0 || mode.indexOf('轻轨') >= 0) {
      return $r('sys.symbol.subway');
    }
    if (mode.indexOf('公交') >= 0 || mode.indexOf('巴士') >= 0) {
      return $r('sys.symbol.bus_fill');
    }
    if (mode.indexOf('打车') >= 0 || mode.indexOf('出租') >= 0 || mode.indexOf('网约') >= 0) {
      return $r('sys.symbol.figure_and_taxi');
    }
    if (mode.indexOf('自驾') >= 0) {
      return $r('sys.symbol.car');
    }
    if (mode.indexOf('骑行') >= 0 || mode.indexOf('单车') >= 0) {
      return $r('sys.symbol.bicycle');
    }
    if (mode.indexOf('机场') >= 0 || mode.indexOf('航班') >= 0 || mode.indexOf('飞机') >= 0) {
      return $r('sys.symbol.airplane');
    }
    return $r('sys.symbol.figure_walk');
  }
}
