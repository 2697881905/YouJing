/**
 * 提示词 / Schema / 模型枚举 三者同源的回归（ai/PromptBuilder + ai/TripSchema）。
 *
 * TripSchema 头注释声明「Schema、接口、守卫三者同源：改枚举只改这里」——
 * 这句话此前没有任何用例在守。真漂移起来是静默的：
 * 模型多一个枚举值而 schema 没跟上，AI 就不产该值；schema 多而解析器不认，
 * 整份行程被判非法走屏7。所以这里把三对关系都钉住。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { PromptBuilder } from '../../../main/ets/ai/PromptBuilder';
import { TripSchema } from '../../../main/ets/ai/TripSchema';
import { ActivityCategory, ActivityStatus, IntensityLevel, MealType } from '../../../main/ets/model/Trip';

export default function promptContractTest(): void {
  describe('提示词与 Schema 同源', () => {
    it('system_prompt_carries_the_schema', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const sp: string = PromptBuilder.systemPrompt();
      expect(sp.indexOf(TripSchema.TRIP_JSON_SCHEMA) >= 0).assertTrue();
      // 天数与日期规则是解析器硬校验项，提示词里必须明说
      expect(sp.indexOf('days 数组长度必须等于') >= 0).assertTrue();
      expect(sp.indexOf('HH:mm') >= 0).assertTrue();
    });

    it('schema_names_every_key_the_parser_requires',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
        // TripParser 里 reqXxx 的键，少一个就会拿到「AI 产出但解析失败」的静默降级
        const required: string[] = ['days', 'activities', 'meals', 'time', 'endTime',
          'title', 'status', 'category', 'transport', 'summary', 'note', 'reason'];
        for (const k of required) {
          expect(TripSchema.TRIP_JSON_SCHEMA.indexOf(k) >= 0).assertTrue();
        }
      });

    it('schema_enums_match_model_enums_both_ways',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
        const statuses: string[] = [ActivityStatus.BOOKED, ActivityStatus.NOT_BOOKED,
          ActivityStatus.FULL, ActivityStatus.PENDING, ActivityStatus.NO_NEED];
        expect(statuses.length).assertEqual(TripSchema.ACTIVITY_STATUS.length);
        for (const s of statuses) {
          expect(TripSchema.ACTIVITY_STATUS.indexOf(s) >= 0).assertTrue();
        }
        const cats: string[] = [ActivityCategory.TRANSPORT, ActivityCategory.SIGHT,
          ActivityCategory.FOOD, ActivityCategory.SHOP, ActivityCategory.REST,
          ActivityCategory.HOTEL, ActivityCategory.OTHER];
        expect(cats.length).assertEqual(TripSchema.ACTIVITY_CATEGORY.length);
        for (const c of cats) {
          expect(TripSchema.ACTIVITY_CATEGORY.indexOf(c) >= 0).assertTrue();
        }
        const levels: string[] = [IntensityLevel.LOW, IntensityLevel.MEDIUM,
          IntensityLevel.HIGH];
        expect(levels.length).assertEqual(TripSchema.INTENSITY.length);
        for (const v of levels) {
          expect(TripSchema.INTENSITY.indexOf(v) >= 0).assertTrue();
        }
        const meals: string[] = [MealType.BREAKFAST, MealType.LUNCH,
          MealType.DINNER];
        expect(meals.length).assertEqual(TripSchema.MEAL_TYPE.length);
        for (const v of meals) {
          expect(TripSchema.MEAL_TYPE.indexOf(v) >= 0).assertTrue();
        }
      });
  });
}
