/**
 * iCalendar (.ics) 文本生成（开发文档 §6 阶段 10：分享导出）。
 *
 * 纯函数、不碰 @kit，可离线断言（RFC 5545 口径）：
 * - 行结束符必须 CRLF；超 75 字节折行，续行以空格开头；
 * - 文本里的 `\` `;` `,` 与换行要转义；
 * - 时间用本地浮动时间（不带 TZID），与行程里「09:00 出发」的语义一致，不硬套 UTC；
 * - 每个活动一个 VEVENT；需预约节点额外挂 VALARM（提前 N 天）。
 *
 * 每日餐饮只进 plainSummary（分享文本），不进 .ics：Meal 没有时刻字段，
 * VEVENT 必须有 DTSTART，编一个时间去写进别人日历比漏一条更糟。
 */

import { ActivityStatus, MealType } from '../model/Trip';
import { CategoryStyle } from './CategoryStyle';
import { TripSpan } from '../utils/TripSpan';
import type { Activity, Trip, TripDay } from '../model/Trip';

const LINE_MAX_BYTES: number = 74;

function utf8ByteLength(text: string): number {
  let bytes: number = 0;
  for (const ch of text) {
    const code: number = ch.codePointAt(0) === undefined ? 0 : (ch.codePointAt(0) as number);
    if (code < 0x80) {
      bytes += 1;
    } else if (code < 0x800) {
      bytes += 2;
    } else if (code < 0x10000) {
      bytes += 3;
    } else {
      bytes += 4;
    }
  }
  return bytes;
}

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

export class IcsBuilder {
  /** 需预约节点：与日历写入同一口径（已约也进 .ics，导入方需要看到整段行程） */
  static bookingNode(act: Activity): boolean {
    return act.status === ActivityStatus.NOT_BOOKED || act.status === ActivityStatus.PENDING ||
      act.status === ActivityStatus.FULL || act.status === ActivityStatus.BOOKED;
  }

  static bookingCount(trip: Trip): number {
    let n: number = 0;
    for (const day of trip.days) {
      for (const act of day.activities) {
        if (IcsBuilder.bookingNode(act)) {
          n++;
        }
      }
    }
    return n;
  }

  /** RFC 5545 文本值转义 */
  static escape(text: string): string {
    let out: string = '';
    for (const ch of text) {
      if (ch === '\\') {
        out += '\\\\';
      } else if (ch === ';') {
        out += '\\;';
      } else if (ch === ',') {
        out += '\\,';
      } else if (ch === '\n') {
        out += '\\n';
      } else {
        out += ch;
      }
    }
    return out;
  }

  /** 超 75 字节折行：按 UTF-8 字节数切，续行前置一个空格 */
  static fold(line: string): string {
    if (utf8ByteLength(line) <= LINE_MAX_BYTES) {
      return line;
    }
    const parts: string[] = [];
    let current: string = '';
    let currentBytes: number = 0;
    const limit: number = current.length === 0 ? LINE_MAX_BYTES : LINE_MAX_BYTES - 1;
    for (const ch of line) {
      const size: number = utf8ByteLength(ch);
      if (currentBytes + size > limit) {
        parts.push(current);
        current = ch;
        currentBytes = size;
      } else {
        current += ch;
        currentBytes += size;
      }
    }
    if (current.length > 0) {
      parts.push(current);
    }
    return `${parts[0]}\r\n ${parts.slice(1).join('\r\n ')}`;
  }

  /** `2026-07-01` + `09:00` → `20260701T090000`；时间缺省按 00:00 */
  static stamp(date: string, time: string): string {
    const day: string = date.replace(/-/g, '');
    const hm: string[] = time.length >= 5 ? time.substring(0, 5).split(':') : ['00', '00'];
    return `${day}T${hm[0]}${hm[1]}00`;
  }

  static build(trip: Trip, advanceDays: number): string {
    const lines: string[] = [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//YouJing//Trip Export//CN',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH'
    ];
    const now: Date = new Date();
    const dtstamp: string = `${now.getFullYear()}${pad2(now.getMonth() + 1)}${pad2(now.getDate())}` +
      `T${pad2(now.getHours())}${pad2(now.getMinutes())}${pad2(now.getSeconds())}`;
    for (const day of trip.days) {
      for (const act of day.activities) {
        lines.push('BEGIN:VEVENT');
        lines.push(`UID:${IcsBuilder.escape(`${trip.id}-${day.dayIndex}-${act.id}@youjing`)}`);
        lines.push(`DTSTAMP:${dtstamp}`);
        lines.push(`DTSTART:${IcsBuilder.stamp(day.date, act.time)}`);
        lines.push(`DTEND:${IcsBuilder.stamp(day.date, act.endTime.length > 0 ? act.endTime : act.time)}`);
        lines.push(`SUMMARY:${IcsBuilder.escape(`Day ${day.dayIndex} ${act.title}`)}`);
        const place: string = act.address.length > 0 ? act.address : act.location;
        if (place.length > 0) {
          lines.push(`LOCATION:${IcsBuilder.escape(place)}`);
        }
        const desc: string[] = [`${trip.destination} · ${trip.days.length} 天行程`, day.theme];
        if (act.note !== undefined && act.note.length > 0) {
          desc.push(act.note);
        }
        if (IcsBuilder.bookingNode(act)) {
          desc.push('需预约');
        }
        lines.push(`DESCRIPTION:${IcsBuilder.escape(desc.join('\n'))}`);
        if (IcsBuilder.bookingNode(act) && advanceDays > 0) {
          lines.push('BEGIN:VALARM');
          lines.push('ACTION:DISPLAY');
          lines.push(`DESCRIPTION:${IcsBuilder.escape(`${act.title} 需预约`)}`);
          lines.push(`TRIGGER:-P${advanceDays}D`);
          lines.push('END:VALARM');
        }
        lines.push('END:VEVENT');
      }
    }
    lines.push('END:VCALENDAR');
    return lines.map((l: string): string => IcsBuilder.fold(l)).join('\r\n');
  }

  /** 行程纯文本摘要（系统分享面板用，不含账号信息） */
  static plainSummary(trip: Trip): string {
    const out: string[] = [`${trip.destination} ${trip.startDate} ~ ${trip.endDate} · ` +
      `${TripSpan.text(trip.days.length)} · ${trip.people} 人`];
    // #29：overview.summary 与 overview.highlights 是 AI 产出却没有任何落点。
    // 分享文本是既有的输出面——行程"为什么这么排"本来就该跟着行程一起发出去
    if (trip.overview.summary.length > 0) {
      out.push(trip.overview.summary);
    }
    if (trip.overview.highlights.length > 0) {
      out.push(`亮点：${trip.overview.highlights.join(' · ')}`);
    }
    // tips 是 Schema 必填、模型每次都产，但此前全 App 零消费方（§5ci 续 119）。
    // 分享文本是既有输出面：出行提醒本来就该跟着行程一起发出去，与 summary/highlights 同一处理。
    if (trip.tips.length > 0) {
      out.push(`提示：${trip.tips.join(' · ')}`);
    }
    for (const day of trip.days) {
      out.push('');
      const pace: string = CategoryStyle.pace(day.intensity);
      const cost: string = day.dailyCost > 0 ? `预估 ¥${day.dailyCost}` : '';
      const tail: string = [pace, cost].filter((x: string): boolean => x.length > 0).join(' · ');
      out.push(`Day ${day.dayIndex} ${day.date} ${day.theme}` +
        (tail.length > 0 ? ` · ${tail}` : ''));
      const risk: string = day.risk === undefined ? '' : day.risk;
      if (risk.length > 0) {
        out.push(`  ⚠ ${risk}`);
      }
      for (const act of day.activities) {
        const mark: string = IcsBuilder.bookingNode(act) ? '（需预约）' : '';
        out.push(`  ${act.time} ${act.title}${mark}`);
      }
      // 每日餐饮是生成结果的一部分（屏13 卡片图例把「午餐」当一行），分享文本不能把它丢了
      for (const m of day.meals) {
        const where: string = m.location.length > 0 ? ` · ${m.location}` : '';
        out.push(`  ${IcsBuilder.mealLabel(m.type)} · ${m.name}${where}`);
      }
      // 住宿区域是用户屏5 亲手选的，真机 DB 实测 55/55 天都有值却全 App 零消费方（§4e）；
      // 帧没声明过「今晚住 X」这一行，所以先进分享文本这个既有输出面，界面位置留给用户定
      const stay: string = day.accommodation === undefined ? '' : day.accommodation;
      if (stay.length > 0) {
        out.push(`  当晚住 · ${stay}`);
      }
    }
    return out.join('\n');
  }

  /** 餐次中文标签（模型用英文稳定码，展示层负责映射） */
  static mealLabel(type: MealType): string {
    if (type === MealType.BREAKFAST) {
      return '早餐';
    }
    if (type === MealType.DINNER) {
      return '晚餐';
    }
    return '午餐';
  }

  /** 单节点纯文本摘要（屏10 详情面板的「分享」，本机现算，不含账号信息） */
  static nodeSummary(day: TripDay, act: Activity): string {
    const out: string[] = [`Day ${day.dayIndex} ${day.date} ${act.title}`];
    out.push(`时间 ${act.time}–${act.endTime}`);
    out.push(`地址 ${act.address.length > 0 ? act.address : act.location}`);
    const arrival: string = act.transport !== undefined ?
      `${act.transport.mode} ${act.transport.duration} 分钟` : '当日首站，无通勤';
    out.push(`到达 ${arrival}`);
    out.push(`预约 ${IcsBuilder.statusLabel(act)}`);
    if (act.note !== undefined && act.note.length > 0) {
      out.push(`提醒 ${act.note}`);
    }
    if (act.reason !== undefined && act.reason.length > 0) {
      out.push(`理由 ${act.reason}`);
    }
    return out.join('\n');
  }

  /** 预约状态中文标签（屏10 详情面板与单节点分享同一口径） */
  static statusLabel(act: Activity): string {
    if (act.status === ActivityStatus.BOOKED) {
      return '已预约';
    }
    if (act.status === ActivityStatus.FULL) {
      return '已约满，需改期或换时段';
    }
    if (act.status === ActivityStatus.PENDING) {
      return '待定';
    }
    if (act.status === ActivityStatus.NOT_BOOKED) {
      return '需预约，尚未确认';
    }
    // NO_NEED 也可能是「预约信息从未取到」（地图来源城市）：那种情况说「无需预约」
    // 等于替景点下结论。note 已标明未获取时照实说。
    if (act.note !== undefined && act.note.indexOf('预约信息未获取') >= 0) {
      return '预约信息未获取，以官方为准';
    }
    return '无需预约';
  }
}
