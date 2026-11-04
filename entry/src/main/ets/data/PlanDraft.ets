/**
 * 规划草稿（跨页共享态，pages→data 单向依赖）。
 * 屏2/3/4/5 逐步写入，屏6 组装 PlanParams 消费；重置入口在生成完成或用户回首页新建。
 */

import { PaceOption, SelectedSpot, SelectedArea, TransitPreference, TravelStyle, TripBasicInput } from '../model/PlanParams';
import { BudgetConfig } from '../common/constants/BudgetConfig';
import { DateUtils } from '../utils/DateUtils';

export class PlanDraft {
  /** 屏2 未填日期时的默认档：今天起算 3 天 2 晚 */
  static readonly DEFAULT_DAYS: number = 3;
  private static instance: PlanDraft | null = null;

  // 日期默认留空：具体日期由屏2 按「今天起算」填充（写死字面量会让新装用户在
  // 若干个月后看到默认出发日在过去）。屏4/屏6 的静默兜底一律走 DateUtils.spanDays，
  // 空串在那里按 1 天处理，不会产生 NaN。
  basic: TripBasicInput = {
    destination: '北京', startDate: '', endDate: '', people: 2, budget: BudgetConfig.DEFAULT
  };
  style: TravelStyle = TravelStyle.LEISURE;
  stayTier: string = 'comfort';
  transit: TransitPreference = TransitPreference.PUBLIC;
  paces: PaceOption[] = [PaceOption.STANDARD];
  selectedSpots: SelectedSpot[] = [];
  selectedArea: SelectedArea = { areaId: '' };

  static get(): PlanDraft {
    if (PlanDraft.instance === null) {
      PlanDraft.instance = new PlanDraft();
    }
    PlanDraft.instance.basic = PlanDraft.repairInvertedRange(PlanDraft.instance.basic);
    return PlanDraft.instance;
  }

  /**
   * 反向日期区间修复（`endDate < startDate`）。
   * 外部 Want（小艺 / 深链）逐字段写草稿，只带 `start` 或只带 `end` 就留下反向对；
   * 反向区间不是任何一种用户意图，唯一动作是把返程拉回与出发同日。
   * 空串与过去日期都不在此列：空串是"用户还没选"的诚实占位（两条 hypium 用例钉着），
   * 能不能补记已走完的旅行属产品口径，未拍板前不动（§5ci 续 184）。
   */
  static repairInvertedRange(b: TripBasicInput): TripBasicInput {
    if (DateUtils.isValidIsoDate(b.startDate) && DateUtils.isValidIsoDate(b.endDate) &&
      b.endDate < b.startDate) {
      const fixed: TripBasicInput = {
        destination: b.destination, startDate: b.startDate,
        endDate: b.startDate, people: b.people, budget: b.budget
      };
      return fixed;
    }
    return b;
  }

  /**
   * 行程天数——**屏2 的显示与屏5/屏6/生成请求必须用同一个口径**。
   *
   * 为什么不能直接 `DateUtils.spanDays(b.startDate, b.endDate)`：草稿的日期默认是空串
   * （写死字面量会让新装用户的出发日在过去），而屏2 按「今天起算 3 天」填自己的页面 state。
   * 用户没点过「开始规划」就直进屏5（小艺 / 深链是受支持的入口）时，
   * `spanDays('', '')` 取到 **1 天**、上限 4 个，屏2 却写着 **3天2晚**（2026-11-04 真机实拍）——
   * 空串被当成了答案。这里把"没填"如实折算成屏2 那个默认档，草稿本身继续留空。
   */
  static days(b: TripBasicInput): number {
    if (!DateUtils.isValidIsoDate(b.startDate) || !DateUtils.isValidIsoDate(b.endDate)) {
      return PlanDraft.DEFAULT_DAYS;
    }
    return DateUtils.spanDays(b.startDate, b.endDate);
  }

  /**
   * 开一段新规划时丢弃旧草稿。
   * 之前只有一个实例方法 reset() 且从未被调用：连着规划第二次时，
   * 上一次的 selectedSpots / selectedArea / 节奏会静默带进来（真机连做三条行程时复现）。
   */
  static fresh(): void {
    PlanDraft.instance = null;
  }
}
