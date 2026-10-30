/**
 * 错误码 → 文案映射回归（屏7）。纯函数，可在 hypium 内跑。
 * 目的：保证屏7 说人话且每个已定义的错误码都有归属，不出现空标题。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { failureDetail, failureHeadline } from '../../../main/ets/common/error/FailureCopy';
import { ErrorCode } from '../../../main/ets/common/error/ErrorCode';

export default function failureCopyTest(): void {
  describe('FailureCopy', () => {
    it('known_codes_have_headlines', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(failureHeadline(ErrorCode.TRIP_GENERATE_RETRY_EXHAUSTED)).assertEqual('试了两次都没排通');
      expect(failureHeadline(ErrorCode.TYPE_GUARD_FAILED)).assertEqual('AI 给的行程缺关键信息');
      expect(failureHeadline(ErrorCode.SCHEMA_VALIDATION_FAILED)).assertEqual('AI 给的行程缺关键信息');
      expect(failureHeadline(ErrorCode.LLM_UNAVAILABLE)).assertEqual('连不上行程服务');
      expect(failureHeadline(ErrorCode.NETWORK_TIMEOUT)).assertEqual('网络不通或超时');
      expect(failureHeadline(ErrorCode.MAP_CITY_DATA_FAILED)).assertEqual('地图数据没取到');
      expect(failureHeadline(ErrorCode.TRIP_NO_SPOT_SELECTED)).assertEqual('还没选景点');
      expect(failureHeadline(ErrorCode.TRIP_NO_AREA_SELECTED)).assertEqual('还没选住宿区域');
    });

    it('unknown_code_falls_back_not_empty', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(failureHeadline(0)).assertEqual('生成没能完成');
      expect(failureHeadline(9999)).assertEqual('生成没能完成');
      // 存储区段（3xxx）不该被当成生成问题文案，走兜底
      expect(failureHeadline(ErrorCode.RDB_TRANSACTION_FAILED)).assertEqual('生成没能完成');
    });

    it('detail_lines_are_human_readable', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(failureDetail(ErrorCode.TRIP_GENERATE_RETRY_EXHAUSTED))
        .assertEqual('连着两次拿到的排期都没能拆成可用的一天');
      expect(failureDetail(ErrorCode.SCHEMA_VALIDATION_FAILED))
        .assertEqual('返回的行程里缺了日期或站点，落不成行程');
      expect(failureDetail(ErrorCode.TRIP_NO_SPOT_SELECTED))
        .assertEqual('至少要选 1 个景点才排得出行程');
      expect(failureDetail(ErrorCode.MAP_CITY_DATA_FAILED))
        .assertEqual('地图服务没有返回这座城市的景点或住宿区，检查网络后再试');
    });

    it('detail_lines_never_leak_validation_terms',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
        // 真机屏7 上出现过「两次生成均失败: days 不能为空数组」——那是 TripParser 的校验术语。
        // 这条把"副标题不许出现内部词"钉住：以后加错误码也不能把 message 直接铺上去。
        const codes: number[] = [
          ErrorCode.TRIP_GENERATE_RETRY_EXHAUSTED,
          ErrorCode.SCHEMA_VALIDATION_FAILED,
          ErrorCode.TYPE_GUARD_FAILED,
          ErrorCode.JSON_PARSE_FAILED,
          ErrorCode.LLM_UNAVAILABLE,
          ErrorCode.NETWORK_TIMEOUT,
          ErrorCode.MAP_CITY_DATA_FAILED,
          ErrorCode.TRIP_NO_SPOT_SELECTED,
          ErrorCode.TRIP_NO_AREA_SELECTED,
          9999
        ];
        const banned: string[] = ['数组', 'schema', 'Schema', 'JSON', 'json', 'null', 'undefined', 'code'];
        for (let i = 0; i < codes.length; i++) {
          const line: string = failureDetail(codes[i]);
          expect(line.length > 0).assertTrue();
          for (let j = 0; j < banned.length; j++) {
            expect(line.indexOf(banned[j]) < 0).assertTrue();
          }
        }
      });
  });
}
