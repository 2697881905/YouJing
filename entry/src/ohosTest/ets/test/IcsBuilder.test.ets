/**
 * 阶段 10 分享导出回归：IcsBuilder 纯函数（RFC 5545 口径）。
 * 先离线 tsc --strict + node 断言跑通（8/8），此处固化为真机可跑用例。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { IcsBuilder } from '../../../main/ets/utils/IcsBuilder';
import { util } from '@kit.ArkTS';
import { Activity, ActivityCategory, ActivityStatus, IntensityLevel, Trip, TripDay } from '../../../main/ets/model/Trip';

function act(id: string, time: string, end: string, title: string, status: ActivityStatus): Activity {
  const a: Activity = { id, time, endTime: end, title, location: 'L', address: 'A;B,C',
    longitude: 0, latitude: 0, status, category: ActivityCategory.SIGHT, note: 'x\ny' };
  return a;
}

function fixture(): Trip {
  const d1: TripDay = { dayIndex: 1, date: '2026-07-01', theme: '东城', intensity: IntensityLevel.LOW,
    dailyCost: 0,
    activities: [act('d1-a1', '09:00', '13:00', '故宫博物院', ActivityStatus.NOT_BOOKED),
      act('d1-a2', '14:00', '15:00', '南锣鼓巷', ActivityStatus.NO_NEED)], meals: [] };
  const d2: TripDay = { dayIndex: 2, date: '2026-07-02', theme: '海淀', intensity: IntensityLevel.MEDIUM,
    dailyCost: 0, activities: [act('d2-a1', '08:30', '12:00', '颐和园', ActivityStatus.FULL)], meals: [] };
  const t: Trip = { id: 't-9', destination: '北京', startDate: '2026-07-01', endDate: '2026-07-03',
    people: 2, budget: 8000, style: 'leisure',
    overview: { totalCost: 0, highlights: [], summary: '' }, days: [d1, d2], tips: [] };
  return t;
}

function countOf(hay: string, needle: string): number {
  return hay.split(needle).length - 1;
}

export default function icsBuilderTest(): void {
  describe('IcsBuilder', () => {
    it('crlf_and_envelope', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const s: string = IcsBuilder.build(fixture(), 1);
      expect(s.includes('\r\n')).assertTrue();
      expect(s.startsWith('BEGIN:VCALENDAR')).assertTrue();
      expect(s.endsWith('END:VCALENDAR')).assertTrue();
      // 折行只允许 CRLF+空格，正文不得出现裸 LF
      expect(countOf(s, '\n') === countOf(s, '\r\n')).assertTrue();
    });

    it('event_and_alarm_counts', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const s: string = IcsBuilder.build(fixture(), 1);
      expect(countOf(s, 'BEGIN:VEVENT')).assertEqual(3);
      expect(countOf(s, 'BEGIN:VALARM')).assertEqual(2);
      expect(s.includes('TRIGGER:-P1D')).assertTrue();
      expect(s.includes('DTSTART:20260701T090000')).assertTrue();
      expect(s.includes('DTEND:20260701T130000')).assertTrue();
      expect(s.includes('TZID=')).assertFalse();
    });

    it('escape_rules', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(IcsBuilder.escape('a;b,c\\d\ne')).assertEqual('a\\;b\\,c\\\\d\\ne');
      const s: string = IcsBuilder.build(fixture(), 1);
      expect(s.includes('A\\;B\\,C')).assertTrue();
    });

    it('fold_keeps_lines_within_75_bytes', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const long: string = 'DESCRIPTION:' + '故'.repeat(60) + ',尾';
      const folded: string = IcsBuilder.fold(long);
      const lines: string[] = folded.split('\r\n');
      expect(lines.length > 1).assertTrue();
      expect(lines[1].startsWith(' ')).assertTrue();
      for (const l of lines) {
        expect(new util.TextEncoder().encodeInto(l).byteLength <= 75).assertTrue();
      }
      expect(folded.replace(/\r\n /g, '')).assertEqual(long);
    });

    it('booking_count_matches_calendar', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(IcsBuilder.bookingCount(fixture())).assertEqual(2);
    });

    it('plain_summary_marks_booking', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const t: string = IcsBuilder.plainSummary(fixture());
      expect(t.includes('北京 2026-07-01 ~ 2026-07-03')).assertTrue();
      expect(t.includes('2天1晚')).assertTrue();
      expect(t.includes('09:00 故宫博物院（需预约）')).assertTrue();
      expect(t.includes('南锣鼓巷（需预约）')).assertFalse();
    });

    it('node_summary_is_one_node_only', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const t: Trip = fixture();
      const s: string = IcsBuilder.nodeSummary(t.days[0], t.days[0].activities[0]);
      const lines: string[] = s.split('\n');
      expect(lines[0]).assertEqual('Day 1 2026-07-01 故宫博物院');
      expect(lines[1]).assertEqual('时间 09:00–13:00');
      expect(lines[2]).assertEqual('地址 A;B,C');
      expect(lines[3]).assertEqual('到达 当日首站，无通勤');
      expect(lines[4]).assertEqual('预约 需预约，尚未确认');
      // 分享只含本站：不得把同日他站或没写过的理由段落带进来
      expect(s.includes('南锣鼓巷')).assertFalse();
      expect(s.includes('理由')).assertFalse();
      // note 原样透传（自身可含换行），故不锁总行数
      expect(s.includes('提醒 x\ny')).assertTrue();
      const full: string = IcsBuilder.nodeSummary(t.days[1], t.days[1].activities[0]);
      expect(full.includes('预约 已约满，需改期或换时段')).assertTrue();
    });
  });
}
