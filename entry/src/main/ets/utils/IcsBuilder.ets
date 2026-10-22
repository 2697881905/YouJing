/**
 * iCalendar (.ics) 文本生成（开发文档 §6 阶段 10：分享导出）。
 *
 * 纯函数、不碰 @kit，可离线断言（RFC 5545 口径）：
 * - 行结束符必须 CRLF；超 75 字节折行，续行以空格开头；
 * - 文本里的 `\` `;` `,` 与换行要转义；
 * - 时间用本地浮动时间（不带 TZID），与行程里「09:00 出发」的语义一致，不硬套 UTC；
 * - 每个活动一个 VEVENT；需预约节点额外挂 VALARM（提前 N 天）。
 */

import { ActivityStatus } from '../model/Trip';
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
      `${trip.days.length}天${trip.days.length - 1}晚 · ${trip.people} 人`];
    for (const day of trip.days) {
      out.push('');
      out.push(`Day ${day.dayIndex} ${day.date} ${day.theme}`);
      for (const act of day.activities) {
        const mark: string = IcsBuilder.bookingNode(act) ? '（需预约）' : '';
        out.push(`  ${act.time} ${act.title}${mark}`);
      }
    }
    return out.join('\n');
  }
}
