/**
 * 通勤方式 → 系统 symbol 图标（屏8 交通腿、屏15 下一段通勤共用）。
 * 从 ItineraryPage 私有方法提取：屏15 原来写死汽车图标，
 * 下一段是地铁/公交/步行时会显示错误车标。
 * 认不出的模式按步行兜底（行程里最常见的一段）。
 */

export class TransitSymbol {
  /**
   * 通勤模式 → 封闭图标键。识别逻辑放这儿（而不是只藏在 of() 里）是为了可断言：
   * Resource 对象没有可比的值，测试只能比字符串。与 CategoryStyle.colorName 同一套理由。
   */
  static keyOf(mode: string): string {
    if (mode.indexOf('地铁') >= 0 || mode.indexOf('轨道') >= 0 || mode.indexOf('轻轨') >= 0) {
      return 'subway';
    }
    if (mode.indexOf('公交') >= 0 || mode.indexOf('巴士') >= 0) {
      return 'bus';
    }
    if (mode.indexOf('打车') >= 0 || mode.indexOf('出租') >= 0 || mode.indexOf('网约') >= 0) {
      return 'taxi';
    }
    if (mode.indexOf('自驾') >= 0) {
      return 'car';
    }
    if (mode.indexOf('骑行') >= 0 || mode.indexOf('单车') >= 0) {
      return 'bicycle';
    }
    if (mode.indexOf('机场') >= 0 || mode.indexOf('航班') >= 0 || mode.indexOf('飞机') >= 0) {
      return 'airplane';
    }
    return 'walk';
  }

  /** 图标键 → 系统 symbol（$r 只接受字面量，所以这层必须留在组件里） */
  static of(mode: string): Resource {
    const key: string = TransitSymbol.keyOf(mode);
    if (key === 'subway') {
      return $r('sys.symbol.subway');
    }
    if (key === 'bus') {
      return $r('sys.symbol.bus_fill');
    }
    if (key === 'taxi') {
      return $r('sys.symbol.figure_and_taxi');
    }
    if (key === 'car') {
      return $r('sys.symbol.car');
    }
    if (key === 'bicycle') {
      return $r('sys.symbol.bicycle');
    }
    if (key === 'airplane') {
      return $r('sys.symbol.airplane');
    }
    return $r('sys.symbol.figure_walk');
  }
}
