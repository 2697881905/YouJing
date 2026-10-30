/**
 * 切片 3 回归：天气简报/解析、三信号阈值与优先级、顺延排程。
 * 与 tools/weather_signals_check.ts 同源；这里跑真机 hypium 侧，不碰 @kit。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import {
  Activity, ActivityCategory, ActivityStatus, IntensityLevel, Meal, MealType, TripDay
} from '../../../main/ets/model/Trip';
import { WeatherDay, WeatherHour } from '../../../main/ets/model/Weather';
import { WeatherParser } from '../../../main/ets/common/weather/WeatherParser';
import { AppError } from '../../../main/ets/common/error/AppError';
import { ErrorCode } from '../../../main/ets/common/error/ErrorCode';
import { WeatherAdvisor } from '../../../main/ets/data/WeatherAdvisor';
import {
  SignalAction, SignalContext, SignalKind, TripSignals, TripSuggestion
} from '../../../main/ets/data/TripSignals';
import { SkipPlanner } from '../../../main/ets/data/SkipPlanner';
import { Geo, GeoPoint } from '../../../main/ets/utils/Geo';

function act(id: string, time: string, endTime: string, title: string,
  category: ActivityCategory = ActivityCategory.SIGHT,
  status: ActivityStatus = ActivityStatus.NOT_BOOKED,
  lat: number = 34.27, lng: number = 108.07): Activity {
  const a: Activity = {
    id: id, time: time, endTime: endTime, title: title, location: 'loc', address: 'addr',
    longitude: lng, latitude: lat, status: status, category: category
  };
  return a;
}

function marker(id: string, time: string, endTime: string): Activity {
  const a: Activity = act(id, time, endTime, '空闲', ActivityCategory.REST, ActivityStatus.NO_NEED);
  a.note = '已跳过：某站';
  return a;
}

function meal(type: MealType, time?: string): Meal {
  const m: Meal = { type: type, name: 'meal', location: 'loc', estimatedCost: 0 };
  if (time !== undefined) {
    m.time = time;
  }
  return m;
}

function dayOf(acts: Activity[], meals: Meal[]): TripDay {
  const d: TripDay = {
    dayIndex: 1, date: '2026-10-30', theme: 't', intensity: IntensityLevel.LOW,
    dailyCost: 0, activities: acts, meals: meals
  };
  return d;
}

function find(day: TripDay, id: string): Activity {
  for (const a of day.activities) {
    if (a.id === id) {
      return a;
    }
  }
  throw new Error(`missing activity ${id}`);
}

function hoursOf(specs: number[][]): WeatherHour[] {
  const out: WeatherHour[] = [];
  for (const s of specs) {
    const h: WeatherHour = { startMin: s[0], code: s[1], tempC: s[2], rainProb: s[3] };
    out.push(h);
  }
  return out;
}

/** 降水概率全天下同一个值：信号测试只关心阈值两侧 */
function weatherOf(rainProb: number): WeatherDay {
  const d: WeatherDay = {
    date: '2026-10-30', code: 61, tempMax: 21, tempMin: 12, rainMax: rainProb,
    hours: hoursOf([[0, 61, 16, rainProb], [900, 61, 18, rainProb], [960, 61, 17, rainProb]])
  };
  return d;
}

function ctxOf(nowMin: number, fix: GeoPoint | null, checked: string[],
  weather: WeatherDay | null): SignalContext {
  const c: SignalContext = {
    isToday: true, nowMin: nowMin, fix: fix, checkedIds: checked, weather: weather
  };
  return c;
}

function codeOf(fn: () => void): number {
  try {
    fn();
    return 0;
  } catch (err) {
    if (err instanceof AppError) {
      return err.code;
    }
    return -1;
  }
}

const WEATHER_JSON: string = '{"daily":{"time":["2026-10-29","2026-10-30"],'
  + '"weather_code":[3,61],"temperature_2m_max":[19,21],'
  + '"temperature_2m_min":[10,12],"precipitation_probability_max":[10,70]},'
  + '"hourly":{"time":["2026-10-29T15:00","2026-10-30T15:00","2026-10-30T16:00",'
  + '"2026-10-30T17:00","2026-10-31T00:00"],'
  + '"weather_code":[3,61,61,61,3],"temperature_2m":[17,18,17,16,15],'
  + '"precipitation_probability":[5,65,70,null,80]}}';

function signalDay(): TripDay {
  return dayOf([
    act('a0', '09:00', '10:00', '早饭散步', ActivityCategory.SIGHT, ActivityStatus.NOT_BOOKED,
      34.30, 108.10),
    act('a2', '14:00', '15:00', '博物馆', ActivityCategory.SIGHT, ActivityStatus.NOT_BOOKED,
      34.27, 108.07),
    act('a3', '15:30', '16:30', '城墙', ActivityCategory.SIGHT, ActivityStatus.NOT_BOOKED,
      34.26, 108.08),
    act('a4', '19:00', '20:00', '夜景', ActivityCategory.SIGHT, ActivityStatus.BOOKED,
      34.25, 108.09)
  ], [meal(MealType.LUNCH, '12:00'), meal(MealType.DINNER, '18:00')]);
}

function shiftDay(): TripDay {
  return dayOf([
    act('a1', '09:00', '10:00', '早饭散步'),
    act('a2', '14:00', '15:00', '博物馆'),
    act('a3', '15:30', '16:30', '城墙'),
    act('a4', '16:45', '17:30', '小店', ActivityCategory.SHOP, ActivityStatus.NO_NEED),
    act('a5', '19:00', '20:00', '夜景', ActivityCategory.SIGHT, ActivityStatus.BOOKED)
  ], [meal(MealType.LUNCH, '12:00'), meal(MealType.DINNER, '18:00')]);
}

export default function weatherSignalsTest(): void {
  describe('WeatherSignals', () => {
    it('weather_labels_and_brief', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(WeatherAdvisor.label(0)).assertEqual('晴');
      expect(WeatherAdvisor.label(3)).assertEqual('阴');
      expect(WeatherAdvisor.label(61)).assertEqual('雨');
      expect(WeatherAdvisor.label(80)).assertEqual('阵雨');
      expect(WeatherAdvisor.label(4)).assertEqual('多云');
      const wd: WeatherDay = {
        date: '2026-10-30', code: 61, tempMax: 21, tempMin: 12, rainMax: 70,
        hours: hoursOf([[0, 61, 16, 0], [900, 61, 18, 65], [960, 61, 17, 70]])
      };
      const brief = WeatherAdvisor.brief(wd);
      expect(brief.text).assertEqual('今日 21°/12° 雨 · 降水 70%');
      expect(brief.advice).assertEqual('15:00 后降水 65%');
      expect(WeatherAdvisor.firstRain(wd, 0)?.startMin ?? -1).assertEqual(900);
      expect(WeatherAdvisor.rainIn(wd, 930, 990)).assertEqual(70);
      expect(WeatherAdvisor.rainIn(wd, 60, 120)).assertEqual(-1);
    });

    it('weather_parser_contract', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const parsed: WeatherDay = WeatherParser.parse(WEATHER_JSON, '2026-10-30');
      expect(parsed.date).assertEqual('2026-10-30');
      expect(parsed.code).assertEqual(61);
      expect(parsed.tempMax).assertEqual(21);
      expect(parsed.tempMin).assertEqual(12);
      expect(parsed.rainMax).assertEqual(70);
      expect(parsed.hours.length).assertEqual(3);
      expect(parsed.hours[0].startMin).assertEqual(900);
      expect(parsed.hours[1].rainProb).assertEqual(70);
      expect(parsed.hours[2].rainProb).assertEqual(-1);

      const fallback: WeatherDay = WeatherParser.parse(WEATHER_JSON, '2026-01-01');
      expect(fallback.date).assertEqual('2026-10-29');
      expect(fallback.hours.length).assertEqual(1);

      expect(codeOf((): void => {
        WeatherParser.parse('not json', '');
      })).assertEqual(ErrorCode.JSON_PARSE_FAILED);
      expect(codeOf((): void => {
        WeatherParser.parse('{}', '');
      })).assertEqual(ErrorCode.TYPE_GUARD_FAILED);
      expect(codeOf((): void => {
        WeatherParser.parse('{"daily":{"time":[]},"hourly":{}}', '');
      })).assertEqual(ErrorCode.SCHEMA_VALIDATION_FAILED);
    });

    it('signal_priority_off_route_over_behind',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
        const far: GeoPoint = { latitude: 34.29, longitude: 108.07 };
        const near: GeoPoint = { latitude: 34.275, longitude: 108.07 };
        const target: GeoPoint = { latitude: 34.27, longitude: 108.07 };
        expect(Geo.distanceM(far, target) > 1000).assertTrue();
        expect(Geo.distanceM(near, target) < 1000).assertTrue();

        const off: TripSuggestion | null = TripSignals.suggest(signalDay(),
          ctxOf(870, far, ['a0'], null));
        expect(off !== null).assertTrue();
        if (off === null) {
          return;
        }
        expect(off.kind).assertEqual(SignalKind.OFF_ROUTE);
        expect(off.targetId).assertEqual('a2');
        expect(off.action).assertEqual(SignalAction.SKIP);
        expect(off.actionLabel).assertEqual('跳过这一站');
        expect(off.title.indexOf('离「博物馆」')).assertEqual(0);

        const nearOut: TripSuggestion | null = TripSignals.suggest(signalDay(),
          ctxOf(870, near, ['a0'], null));
        expect(nearOut !== null).assertTrue();
        if (nearOut === null) {
          return;
        }
        expect(nearOut.kind).assertEqual(SignalKind.BEHIND);
        expect(nearOut.deltaMin).assertEqual(30);
        expect(nearOut.actionLabel).assertEqual('顺延 30 分钟');
      });

    it('signal_thresholds_and_checkin', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const far: GeoPoint = { latitude: 34.29, longitude: 108.07 };
      expect(TripSignals.suggest(signalDay(), ctxOf(845, far, ['a0'], null))).assertNull();
      expect(TripSignals.suggest(signalDay(), ctxOf(880, null, ['a0', 'a2'], null))).assertNull();
      expect(TripSignals.suggest(signalDay(), ctxOf(870, far, ['a0', 'a2'], null))).assertNull();
      const notToday: SignalContext = {
        isToday: false, nowMin: 870, fix: far, checkedIds: [], weather: null
      };
      expect(TripSignals.suggest(signalDay(), notToday)).assertNull();

      const round: TripSuggestion | null = TripSignals.suggest(signalDay(),
        ctxOf(871, null, ['a0'], null));
      expect(round !== null).assertTrue();
      if (round === null) {
        return;
      }
      expect(round.deltaMin).assertEqual(45);
      expect(round.detail).assertEqual('「博物馆」还没打卡，后续按原时间排');
    });

    it('signal_behind_without_shift_targets',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
        const day: TripDay = dayOf([
          act('a0', '09:00', '10:00', '早饭散步'),
          act('a2', '14:00', '15:00', '博物馆'),
          act('a3', '15:30', '16:30', '城墙', ActivityCategory.SIGHT, ActivityStatus.BOOKED)
        ], []);
        const s: TripSuggestion | null = TripSignals.suggest(day, ctxOf(870, null, ['a0'], null));
        expect(s !== null).assertTrue();
        if (s === null) {
          return;
        }
        expect(s.kind).assertEqual(SignalKind.BEHIND);
        expect(s.action).assertEqual(SignalAction.SKIP);
        expect(s.detail.indexOf('今天没有可顺延的站') > 0).assertTrue();
      });

    it('signal_rain_threshold_and_outdoor', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const rain: TripSuggestion | null = TripSignals.suggest(signalDay(),
        ctxOf(850, null, ['a0'], weatherOf(70)));
      expect(rain !== null).assertTrue();
      if (rain === null) {
        return;
      }
      expect(rain.kind).assertEqual(SignalKind.RAIN);
      expect(rain.targetId).assertEqual('a3');
      expect(rain.title).assertEqual('前方室外站有雨');
      expect(rain.detail.indexOf('15:30–16:30') > 0).assertTrue();
      expect(rain.detail.indexOf('降水 70%') > 0).assertTrue();

      expect(TripSignals.suggest(signalDay(), ctxOf(850, null, ['a0'], weatherOf(50)))).assertNull();
      const indoor: TripDay = dayOf([
        act('a0', '09:00', '10:00', '早饭散步'),
        act('a2', '14:00', '15:00', '博物馆'),
        act('a3', '15:30', '16:30', '餐馆', ActivityCategory.FOOD, ActivityStatus.NO_NEED)
      ], []);
      expect(TripSignals.suggest(indoor, ctxOf(850, null, ['a0'], weatherOf(70)))).assertNull();
    });

    it('shift_targets_and_basic', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(SkipPlanner.isShiftTarget(find(shiftDay(), 'a3'), 845)).assertTrue();
      expect(SkipPlanner.isShiftTarget(find(shiftDay(), 'a3'), 930)).assertTrue();
      expect(SkipPlanner.isShiftTarget(find(shiftDay(), 'a3'), 931)).assertFalse();
      expect(SkipPlanner.isShiftTarget(find(shiftDay(), 'a5'), 845)).assertFalse();
      expect(SkipPlanner.isShiftTarget(find(shiftDay(), 'a1'), 845)).assertFalse();

      const shifted = SkipPlanner.shiftRemaining(shiftDay(), 845, 45);
      expect(shifted.changed).assertTrue();
      expect(find(shifted.day, 'a3').time).assertEqual('16:15');
      expect(find(shifted.day, 'a3').endTime).assertEqual('17:15');
      expect(find(shifted.day, 'a4').time).assertEqual('20:00');
      expect(find(shifted.day, 'a4').endTime).assertEqual('20:45');
      expect(find(shifted.day, 'a2').time).assertEqual('14:00');
      expect(find(shifted.day, 'a5').time).assertEqual('19:00');
      expect(shifted.day.activities.map((a: Activity): string => a.id).join(','))
        .assertEqual('a1,a2,a3,a4,a5');
      expect(shifted.day.meals[1].time ?? '').assertEqual('18:00');
      expect(shifted.note.indexOf('已顺延 45 分钟')).assertEqual(0);
      expect(shifted.note.indexOf('待调整')).assertEqual(-1);
    });

    it('shift_respects_current_stop_and_overflow',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
        const cur: TripDay = dayOf([
          act('c1', '09:00', '10:00', '早饭'),
          act('c2', '14:00', '16:30', '排长队'),
          act('c3', '15:00', '15:30', '下一站')
        ], []);
        const curShift = SkipPlanner.shiftRemaining(cur, 845, 15);
        expect(find(curShift.day, 'c3').time).assertEqual('16:30');

        const late = SkipPlanner.shiftRemaining(dayOf([
          act('s1', '18:30', '19:30', '夜游'),
          act('s2', '23:10', '23:50', '塔')
        ], []), 1100, 40);
        expect(find(late.day, 's1').time).assertEqual('19:10');
        expect(find(late.day, 's2').time).assertEqual('23:10');
        expect((find(late.day, 's2').note ?? '').indexOf('待调整') >= 0).assertTrue();
        expect(late.note.indexOf('部分站点待调整') > 0).assertTrue();
      });

    it('shift_no_targets_and_markers', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
        const noTargetDay: TripDay = dayOf([
          act('a1', '09:00', '10:00', '早饭'),
          act('a5', '19:00', '20:00', '夜景', ActivityCategory.SIGHT, ActivityStatus.BOOKED)
        ], []);
        const noTarget = SkipPlanner.shiftRemaining(noTargetDay, 845, 45);
        expect(noTarget.changed).assertFalse();
        expect(noTarget.note).assertEqual('没有需要顺延的站点');
        expect(find(noTarget.day, 'a5').time).assertEqual('19:00');
        expect(SkipPlanner.shiftRemaining(shiftDay(), 845, 0).changed).assertFalse();

        const markerDay: TripDay = dayOf([
          act('a1', '09:00', '10:00', '早饭'),
          marker('m1', '14:30', '15:00'),
          act('a3', '15:30', '16:30', '城墙')
        ], []);
        const markerShift = SkipPlanner.shiftRemaining(markerDay, 780, 30);
        expect(find(markerShift.day, 'm1').time).assertEqual('14:30');
        expect(find(markerShift.day, 'a3').time).assertEqual('16:00');
      });
  });
}
