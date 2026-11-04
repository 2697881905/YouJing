/**
 * 行程天数——**唯一口径**（第 18 把尺 `tools/audit_span_source.py` R1 管这个）。
 *
 * 为什么不能各处直接 `DateUtils.spanDays(basic.startDate, basic.endDate)`：
 * 草稿的日期默认是空串（占位语义有 hypium 用例钉着），`spanDays('', '')` 取到 **1**，
 * 而屏2 显示的是「今天起算 3 天」。深链/小艺不经屏2 写回就能落到屏5 与生成请求，
 * 于是同一趟旅行出现「屏2 写 3天2晚、屏5 只给 4 个名额、模型被要求排 1 天」
 * （2026-11-05 真机实拍）。空串不是"1 天"，那是把没填的默认值当成了答案。
 *
 * 放 utils 而不是留在 `PlanDraft`：`ai/`（PromptBuilder / LlmClient）也要用同一口径，
 * 而 ai→data 不是既有分层。
 */
import { TripBasicInput } from '../model/PlanParams';
import { DateUtils } from './DateUtils';

export class TripLength {
  /** 屏2 未填日期时的默认档：今天起算 3 天 2 晚 */
  static readonly DEFAULT_DAYS: number = 3;

  static days(b: TripBasicInput): number {
    if (!DateUtils.isValidIsoDate(b.startDate) || !DateUtils.isValidIsoDate(b.endDate)) {
      return TripLength.DEFAULT_DAYS;
    }
    return DateUtils.spanDays(b.startDate, b.endDate);
  }
}
