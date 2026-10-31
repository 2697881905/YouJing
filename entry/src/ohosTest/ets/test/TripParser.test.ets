/**
 * TripParser / TripSchema 真机回归（阶段 3 验收：Mock JSON 通过、非法数据被拦截）。
 * 纯函数层，不碰 UI/网络——有据经验：协议守卫必须进 hypium，不能只靠手点。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { TripParser } from '../../../main/ets/ai/TripParser';
import { TripSchema } from '../../../main/ets/ai/TripSchema';
import { MockTrip } from '../../../main/ets/mock/MockTrip';
import { AppError } from '../../../main/ets/common/error/AppError';
import { ErrorCode } from '../../../main/ets/common/error/ErrorCode';
import { Trip } from '../../../main/ets/model/Trip';

type Obj = Record<string, Object>;

function validJson(): string {
  return JSON.stringify(MockTrip.TRIP);
}

function mutateJson(mut: (o: Obj) => void): string {
  const o: Obj = JSON.parse(validJson()) as Obj;
  mut(o);
  return JSON.stringify(o);
}

function expectErrCode(fn: () => void, code: number): string {
  try {
    fn();
    return 'NO_THROW';
  } catch (err) {
    const e: AppError = err as AppError;
    return `${e.code}`;
  }
}

export default function tripParserTest(): void {
  describe('TripParser', () => {
    const tripJson: string = validJson();

    it('parse_valid_roundtrip', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const t: Trip = TripParser.parseTrip(tripJson);
      expect(t.id).assertEqual('trip-mock-kyoto');
      expect(t.days.length).assertEqual(3);
      expect(t.days[0].activities.length).assertEqual(5);
      expect(t.days[0].activities[0].reason !== undefined).assertTrue();
      expect(t.days[0].activities[1].transport?.mode).assertEqual('步行');
      expect(t.overview.highlights.length).assertEqual(3);
    });

    it('parse_fenced_json', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const fenced: string = '好的，以下是行程：\n```json\n' + tripJson + '\n```\n希望满意。';
      const t: Trip = TripParser.parseTrip(fenced);
      expect(t.destination).assertEqual('京都');
    });

    it('guard_missing_field', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      // ArkTS 禁 delete：用字符串级删除构造缺字段
      const bad: string = validJson().replace('"destination":"京都",', '');
      expect(expectErrCode(() => TripParser.parseTrip(bad), 0))
        .assertEqual(`${ErrorCode.SCHEMA_VALIDATION_FAILED}`);
    });

    it('guard_bad_enum', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const bad: string = mutateJson((o: Obj): void => {
        const days: Object[] = o['days'] as Object[];
        const day0: Obj = days[0] as Obj;
        const acts: Object[] = day0['activities'] as Object[];
        (acts[0] as Obj)['status'] = 'booked_yes';
      });
      expect(expectErrCode(() => TripParser.parseTrip(bad), 0))
        .assertEqual(`${ErrorCode.SCHEMA_VALIDATION_FAILED}`);
    });

    it('guard_wrong_type', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const bad: string = mutateJson((o: Obj): void => {
        o['people'] = '2';
      });
      expect(expectErrCode(() => TripParser.parseTrip(bad), 0))
        .assertEqual(`${ErrorCode.TYPE_GUARD_FAILED}`);
    });

    it('guard_day_index_gap', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const bad: string = mutateJson((o: Obj): void => {
        const days: Object[] = o['days'] as Object[];
        (days[1] as Obj)['dayIndex'] = 5;
      });
      expect(expectErrCode(() => TripParser.parseTrip(bad), 0))
        .assertEqual(`${ErrorCode.SCHEMA_VALIDATION_FAILED}`);
    });

    it('parse_empty_activity_location_allowed', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      // 提示词第 9 条允许无入口信息时留空串；旧解析器要求非空，MapKit 城市首发即撞
      const raw: string = mutateJson((o: Obj): void => {
        const days: Object[] = o['days'] as Object[];
        const acts: Object[] = (days[0] as Obj)['activities'] as Object[];
        (acts[0] as Obj)['location'] = '';
      });
      const t: Trip = TripParser.parseTrip(raw);
      expect(t.days[0].activities[0].location).assertEqual('');
    });

    it('normalize_duplicate_day_index_against_expected_window',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
        const bad: string = mutateJson((o: Obj): void => {
          const days: Object[] = o['days'] as Object[];
          (days[1] as Obj)['dayIndex'] = 1;
          (days[1] as Obj)['date'] = '2026-06-10';
        });
        const t: Trip = TripParser.parseTrip(bad, { days: 3, startDate: '2026-06-10' });
        expect(t.days.length).assertEqual(3);
        expect(t.days[1].dayIndex).assertEqual(2);
        expect(t.days[1].date).assertEqual('2026-06-11');
        expect(t.startDate).assertEqual('2026-06-10');
        expect(t.endDate).assertEqual('2026-06-12');
      });

    it('normalize_single_day_drops_extra_day', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      // 2026-10-31 真机失败形态：1 天行程被模型拆成两天，且两天 dayIndex 都是 1
      const bad: string = mutateJson((o: Obj): void => {
        o['startDate'] = '2026-10-31';
        o['endDate'] = '2026-10-31';
        const days: Object[] = o['days'] as Object[];
        (days[1] as Obj)['dayIndex'] = 1;
        (days[1] as Obj)['date'] = '2026-10-31';
      });
      const t: Trip = TripParser.parseTrip(bad, { days: 1, startDate: '2026-10-31' });
      expect(t.days.length).assertEqual(1);
      expect(t.days[0].dayIndex).assertEqual(1);
      expect(t.days[0].date).assertEqual('2026-10-31');
      expect(t.startDate).assertEqual('2026-10-31');
      expect(t.endDate).assertEqual('2026-10-31');
    });

    it('guard_fewer_days_than_expected', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      // 缺天不能靠截断修：没有内容可补，必须失败重试
      expect(expectErrCode(() => TripParser.parseTrip(validJson(),
        { days: 4, startDate: '2026-06-10' }), 0))
        .assertEqual(`${ErrorCode.SCHEMA_VALIDATION_FAILED}`);
    });

    it('guard_bad_time_format', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const bad: string = mutateJson((o: Obj): void => {
        const days: Object[] = o['days'] as Object[];
        const acts: Object[] = (days[0] as Obj)['activities'] as Object[];
        (acts[0] as Obj)['time'] = '6:00 上午';
      });
      expect(expectErrCode(() => TripParser.parseTrip(bad), 0))
        .assertEqual(`${ErrorCode.SCHEMA_VALIDATION_FAILED}`);
    });

    it('guard_end_time_not_later', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      // 22:45 起 4 小时会回卷成 02:45——真机曾因此渲染出「建议停留 0分钟」
      const bad: string = mutateJson((o: Obj): void => {
        const days: Object[] = o['days'] as Object[];
        const acts: Object[] = (days[0] as Obj)['activities'] as Object[];
        (acts[0] as Obj)['time'] = '22:45';
        (acts[0] as Obj)['endTime'] = '02:45';
      });
      expect(expectErrCode(() => TripParser.parseTrip(bad), 0))
        .assertEqual(`${ErrorCode.TYPE_GUARD_FAILED}`);
    });

    it('guard_date_order', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const bad: string = mutateJson((o: Obj): void => {
        o['startDate'] = '2026-06-20';
      });
      expect(expectErrCode(() => TripParser.parseTrip(bad), 0))
        .assertEqual(`${ErrorCode.SCHEMA_VALIDATION_FAILED}`);
    });

    it('guard_not_json', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(expectErrCode(() => TripParser.parseTrip('抱歉，我无法生成。'), 0))
        .assertEqual(`${ErrorCode.JSON_PARSE_FAILED}`);
    });

    it('schema_whitelists_match_model', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(TripSchema.ACTIVITY_STATUS.length).assertEqual(5);
      expect(TripSchema.ACTIVITY_CATEGORY.length).assertEqual(7);
      expect(TripSchema.INTENSITY.length).assertEqual(3);
      expect(TripSchema.MEAL_TYPE.length).assertEqual(3);
      expect(TripSchema.TRIP_JSON_SCHEMA.length > 500).assertTrue();
    });
  });
}
