/**
 * 纯配置/口径回归：CategoryStyle 五映射与 QuestionFlowConfig 四题。
 * 拼错一个选项 value 即静默错档（屏3 与 PlanParams 枚举对不上时用户选了没反应），
 * 这两处必须离线可断言。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { CategoryStyle } from '../../../main/ets/utils/CategoryStyle';
import { QuestionFlowConfig } from '../../../main/ets/common/constants/QuestionFlowConfig';
import { ActivityCategory } from '../../../main/ets/model/Trip';
import { PaceOption, TransitPreference, TravelStyle } from '../../../main/ets/model/PlanParams';

export default function styleConfigTest(): void {
  describe('CategoryStyle', () => {
    it('five_type_mapping_closed', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 契约活动类型色点五对：景点 primary / 餐饮 bookmark / 住宿 accent_mention /
      // 交通 icon / 休息 faint；第六种用图标或文字，不许新色相
      expect(CategoryStyle.colorName(ActivityCategory.SIGHT)).assertEqual('primary');
      expect(CategoryStyle.colorName(ActivityCategory.FOOD)).assertEqual('bookmark');
      expect(CategoryStyle.colorName(ActivityCategory.HOTEL)).assertEqual('accent_mention');
      expect(CategoryStyle.colorName(ActivityCategory.TRANSPORT)).assertEqual('icon');
      expect(CategoryStyle.colorName(ActivityCategory.REST)).assertEqual('faint');
    });

    it('unknown_category_falls_back_to_sight', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 认不出的类别按景点蓝兜底（与屏8 时间线同一条口径）
      expect(CategoryStyle.colorName(ActivityCategory.SHOP)).assertEqual('primary');
      expect(CategoryStyle.colorName(ActivityCategory.OTHER)).assertEqual('primary');
    });
  });

  describe('QuestionFlowConfig', () => {
    it('four_questions_match_doc', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const qs = QuestionFlowConfig.QUESTIONS;
      expect(qs.length).assertEqual(4);
      expect(qs[0].id).assertEqual('style');
      expect(qs[0].options.length).assertEqual(5);
      expect(qs[1].id).assertEqual('stay');
      expect(qs[1].options.length).assertEqual(3);
      expect(qs[2].id).assertEqual('transit');
      expect(qs[2].options.length).assertEqual(3);
      expect(qs[3].id).assertEqual('pace');
      expect(qs[3].multiSelect).assertTrue();
    });

    it('option_values_hit_model_enums', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 选项 value 必须落在模型枚举里，否则屏3 选了但生成参数对不上
      const styleVals: string[] = [TravelStyle.LEISURE, TravelStyle.FAST_PACE, TravelStyle.FAMILY,
        TravelStyle.FOODIE, TravelStyle.CULTURE];
      for (const opt of QuestionFlowConfig.QUESTIONS[0].options) {
        expect(styleVals.indexOf(opt.value) >= 0).assertTrue();
      }
      const transitVals: string[] = [TransitPreference.PUBLIC, TransitPreference.TAXI_MAIN,
        TransitPreference.CHARTER];
      for (const opt of QuestionFlowConfig.QUESTIONS[2].options) {
        expect(transitVals.indexOf(opt.value) >= 0).assertTrue();
      }
      const paceVals: string[] = [PaceOption.RELAXED, PaceOption.STANDARD, PaceOption.PACKED];
      for (const opt of QuestionFlowConfig.QUESTIONS[3].options) {
        expect(paceVals.indexOf(opt.value) >= 0);
      }
    });

    it('default_values_are_valid_options', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 「用户不操作也能生成」的兜底：每题默认值必须是该题选项之一
      for (const q of QuestionFlowConfig.QUESTIONS) {
        expect(q.defaultValues.length > 0).assertTrue();
        for (const dv of q.defaultValues) {
          const hit = q.options.some((o) => o.value === dv);
          expect(hit).assertTrue();
        }
      }
    });
  });
}
