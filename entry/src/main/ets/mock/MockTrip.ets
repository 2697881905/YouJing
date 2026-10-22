/**
 * 屏8 行程时间线 Mock（帧 9c0acbcd Day1 数据，逐行对齐稿件文案）。
 * 阶段 2 验收：空/部分/异常三态由页面数据分支覆盖，批次 4 补。
 */

import { Activity, ActivityCategory, ActivityStatus, Meal, MealType, Trip, TripDay } from '../model/Trip';
import { IntensityLevel } from '../model/Trip';

function act(id: string, time: string, endTime: string, title: string, district: string,
  category: ActivityCategory, status: ActivityStatus, reason?: string,
  transportMode?: string, transportMin?: number, transportDetail?: string): Activity {
  const a: Activity = {
    id: id,
    time: time,
    endTime: endTime,
    title: title,
    location: title,
    address: `京都 ${district}`,
    longitude: 135.7 + Math.random() * 0.1,
    latitude: 35.0 + Math.random() * 0.05,
    status: status,
    category: category,
    reason: reason,
    transport: transportMode === undefined ? undefined : {
      mode: transportMode,
      duration: transportMin === undefined ? 0 : transportMin,
      detail: transportDetail === undefined ? '' : transportDetail
    }
  };
  return a;
}

export class MockTrip {
  static readonly TRIP: Trip = (() => {
    const day1Activities: Activity[] = [
      act('d1-a1', '06:00', '08:00', '伏见稻荷大社', '枫日谷', ActivityCategory.SIGHT,
        ActivityStatus.NO_NEED, '06:30 前进入，能避开 9 点后的团队客流。'),
      act('d1-a2', '08:30', '10:30', '清水寺', '东山区', ActivityCategory.SIGHT,
        ActivityStatus.NOT_BOOKED, undefined, '步行', 18, '1.2km'),
      act('d1-a3', '11:00', '12:30', '二年坂 · 三年坂', '东山', ActivityCategory.SIGHT,
        ActivityStatus.NO_NEED, '连接清水寺与祇园的最顺动线，正午石板街光影最佳。', '打车', 25, '¥2,800'),
      act('d1-a4', '12:45', '13:45', '键善良房 本店', '祇园', ActivityCategory.FOOD,
        ActivityStatus.PENDING, undefined, '步行', 8, '500m'),
      act('d1-a5', '14:30', '16:00', '八坂神社', '祇园', ActivityCategory.SIGHT,
        ActivityStatus.NO_NEED, undefined)
    ];
    const meals: Meal[] = [
      { type: MealType.LUNCH, name: '键善良房 本店', location: '祇园', estimatedCost: 1800 }
    ];
    const day1: TripDay = {
      dayIndex: 1, date: '2026-06-10', theme: '东山 · 清水',
      intensity: IntensityLevel.HIGH, dailyCost: 12600,
      activities: day1Activities, meals: meals
    };
    const day2: TripDay = {
      dayIndex: 2, date: '2026-06-11', theme: '岚山 · 竹林',
      intensity: IntensityLevel.MEDIUM, dailyCost: 9800,
      activities: [
        act('d2-a1', '08:00', '10:00', '岚山竹林小径', '右京区', ActivityCategory.SIGHT,
          ActivityStatus.NO_NEED, '清晨无人时段出片， JR 岚山站下车步行 15 分钟即达。'),
        act('d2-a2', '10:30', '12:00', '天龙寺', '右京区', ActivityCategory.SIGHT,
          ActivityStatus.NOT_BOOKED, undefined, '步行', 12, '800m')
      ],
      meals: []
    };
    const day3: TripDay = {
      dayIndex: 3, date: '2026-06-12', theme: '伏见 · 宇治',
      intensity: IntensityLevel.LOW, dailyCost: 7400,
      activities: [
        act('d3-a1', '09:00', '11:30', '宇治抹茶街', '宇治市', ActivityCategory.SIGHT,
          ActivityStatus.NO_NEED, undefined)
      ],
      meals: []
    };
    const trip: Trip = {
      id: 'trip-mock-kyoto',
      destination: '京都',
      startDate: '2026-06-10',
      endDate: '2026-06-14',
      people: 2,
      budget: 16000,
      style: 'culture',
      overview: {
        totalCost: 39800,
        highlights: ['清晨空场走进伏见稻荷', '东山步道一日串联', '祇园老铺定食'],
        summary: '五日京都，以东山步道为主轴的文化线。'
      },
      days: [day1, day2, day3],
      tips: ['寺社避开 9–15 点团队客流', '巴士一日券随上随下']
    };
    return trip;
  })();
}
