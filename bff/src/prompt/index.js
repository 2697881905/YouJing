/**
 * BFF 侧的 prompt 组装。
 *
 * 系统提示词与 JSON Schema 不在此手写：它们来自 `contract.js`，而 contract 又来自
 * entry/ 侧 SOT 的生成物。本文件只负责把 BFF 收到的请求体映射成 PromptBuilder 的入参。
 *
 * 两种用户消息路径：
 * 1. rich：请求里带 `spots[]` + `area` 的完整字段时，直接调用 ets 的
 *    `PromptBuilder.userPrompt`（与端侧同一份代码）；
 * 2. sparse：端侧当前只发 `selectedSpots: string[]` + `selectedArea` 名称，
 *    此时不伪造停留/坐标/预约/开放时间，如实说明缺口。等端侧 payload 扩字段后
 *    自动走 rich 路径，不需要再改 BFF。
 */

import { createRequire } from 'node:module';
import { TRIP_JSON_SCHEMA, TRIP_SCHEMA_OBJECT, buildResponseFormat } from './contract.js';

const require = createRequire(import.meta.url);
const { PromptBuilder } = require('./generated/ai/PromptBuilder.js');
const { DateUtils } = require('./generated/utils/DateUtils.js');

export { TRIP_JSON_SCHEMA, TRIP_SCHEMA_OBJECT, buildResponseFormat };

function isPlainObject(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function spotNameOf(value) {
  if (typeof value === 'string') {
    return value.trim();
  }
  if (isPlainObject(value)) {
    const name = value.name || value.spotId || '';
    return typeof name === 'string' ? name.trim() : '';
  }
  return '';
}

function areaNameOf(body) {
  if (typeof body.selectedArea === 'string') {
    return body.selectedArea.trim();
  }
  if (isPlainObject(body.selectedArea)) {
    const name = body.selectedArea.name || body.selectedArea.areaId || '';
    if (typeof name === 'string') {
      return name.trim();
    }
  }
  if (isPlainObject(body.area)) {
    return typeof body.area.name === 'string' ? body.area.name.trim() : '';
  }
  return '';
}

function hasRichArea(area) {
  return isPlainObject(area) &&
    typeof area.name === 'string' && area.name.length > 0 &&
    typeof area.priceTier === 'string' &&
    Array.isArray(area.metroLines) &&
    Array.isArray(area.anchorStations) &&
    Number.isFinite(area.airportMinutes) &&
    Number.isFinite(area.trainStationMinutes);
}

function hasRichSpot(spot) {
  return isPlainObject(spot) &&
    typeof spot.name === 'string' && spot.name.length > 0 &&
    Number.isFinite(spot.suggestedDuration) &&
    Number.isFinite(spot.longitude) &&
    Number.isFinite(spot.latitude) &&
    isPlainObject(spot.booking) &&
    typeof spot.booking.requiresBooking === 'boolean';
}

function hasRichPayload(body) {
  if (!Array.isArray(body.spots) || body.spots.length === 0 || !hasRichArea(body.area)) {
    return false;
  }
  const selected = Array.isArray(body.selectedSpots) ? body.selectedSpots : [];
  if (selected.length === 0) {
    return false;
  }
  return selected.every((sel) => {
    const name = spotNameOf(sel);
    const spot = name.length > 0
      ? body.spots.find((item) => typeof item === 'object' && item !== null &&
        (item.name === name || item.id === name))
      : undefined;
    return spot !== undefined && hasRichSpot(spot);
  });
}

function normalizeSpot(spot, fallbackCity) {
  const booking = spot.booking || {};
  return {
    id: spot.id || spot.name,
    name: spot.name,
    city: spot.city || fallbackCity,
    tags: Array.isArray(spot.tags) ? spot.tags : [],
    brief: typeof spot.brief === 'string' ? spot.brief : '',
    suggestedDuration: spot.suggestedDuration,
    openingHours: typeof spot.openingHours === 'string' ? spot.openingHours : undefined,
    popularity: Number.isFinite(spot.popularity) ? spot.popularity : 0,
    nearbySpotIds: Array.isArray(spot.nearbySpotIds) ? spot.nearbySpotIds : [],
    longitude: spot.longitude,
    latitude: spot.latitude,
    district: typeof spot.district === 'string' ? spot.district : '',
    nearestMetro: typeof spot.nearestMetro === 'string' ? spot.nearestMetro : '',
    entranceTip: typeof spot.entranceTip === 'string' ? spot.entranceTip : undefined,
    booking: {
      requiresBooking: booking.requiresBooking === true,
      bookingMethod: typeof booking.bookingMethod === 'string' ? booking.bookingMethod : undefined,
      advanceDays: Number.isFinite(booking.advanceDays) ? booking.advanceDays : undefined,
      releaseTime: typeof booking.releaseTime === 'string' ? booking.releaseTime : undefined,
      closedDay: typeof booking.closedDay === 'string' ? booking.closedDay : undefined,
      difficulty: typeof booking.difficulty === 'string' ? booking.difficulty : undefined
    },
    provenance: isPlainObject(spot.provenance) && typeof spot.provenance.source === 'string'
      ? {
        source: spot.provenance.source,
        updatedAt: typeof spot.provenance.updatedAt === 'string'
          ? spot.provenance.updatedAt : DateUtils.todayIso(),
        confidence: spot.provenance.confidence
      }
      : { source: 'BFF 请求', updatedAt: DateUtils.todayIso() }
  };
}

function normalizeArea(area, destination) {
  return {
    id: area.id || area.name,
    name: area.name,
    city: area.city || destination,
    longitude: Number.isFinite(area.longitude) ? area.longitude : 0,
    latitude: Number.isFinite(area.latitude) ? area.latitude : 0,
    description: typeof area.description === 'string' ? area.description : '',
    anchorStations: area.anchorStations,
    metroLines: area.metroLines,
    airportMinutes: area.airportMinutes,
    trainStationMinutes: area.trainStationMinutes,
    commerceTags: Array.isArray(area.commerceTags) ? area.commerceTags : [],
    diningDensity: typeof area.diningDensity === 'string' ? area.diningDensity : '',
    suitableCrowds: Array.isArray(area.suitableCrowds) ? area.suitableCrowds : [],
    priceTier: area.priceTier,
    priceRange: typeof area.priceRange === 'string' ? area.priceRange : undefined,
    group: typeof area.group === 'string' ? area.group : 'core',
    source: typeof area.source === 'string' ? area.source : 'BFF 请求',
    updatedAt: typeof area.updatedAt === 'string' ? area.updatedAt : DateUtils.todayIso()
  };
}

function richUserPrompt(body) {
  const destination = typeof body.destination === 'string' ? body.destination : '';
  const spots = body.spots.map((spot) => normalizeSpot(spot, destination));
  const selectedSpots = body.selectedSpots.map((sel) => {
    const name = spotNameOf(sel);
    const spot = spots.find((item) => item.name === name || item.id === name);
    return {
      spotId: spot ? spot.id : name,
      priority: isPlainObject(sel) && typeof sel.priority === 'string' ? sel.priority : 'must',
      userNote: isPlainObject(sel) && typeof sel.userNote === 'string' ? sel.userNote : undefined
    };
  });
  const area = normalizeArea(body.area, destination);
  const params = {
    basic: {
      destination,
      startDate: body.startDate,
      endDate: body.endDate,
      people: body.people,
      budget: body.budget
    },
    style: typeof body.style === 'string' && body.style.length > 0 ? body.style : 'leisure',
    stayTier: typeof body.stayTier === 'string' ? body.stayTier : area.priceTier,
    transit: typeof body.transit === 'string' ? body.transit : 'public',
    paces: Array.isArray(body.paces) && body.paces.length > 0 ? body.paces : ['standard'],
    selectedSpots,
    selectedArea: { areaId: area.id }
  };
  return PromptBuilder.userPrompt(params, spots, area);
}

function sparseUserPrompt(body) {
  const destination = typeof body.destination === 'string' && body.destination.length > 0
    ? body.destination : '未提供';
  const startDate = typeof body.startDate === 'string' ? body.startDate : '未提供';
  const endDate = typeof body.endDate === 'string' ? body.endDate : '未提供';
  const dayCount = DateUtils.isValidIsoDate(startDate) && DateUtils.isValidIsoDate(endDate)
    ? DateUtils.spanDays(startDate, endDate) : '未提供';
  const people = Number.isFinite(body.people) ? body.people : '未提供';
  const budget = Number.isFinite(body.budget) ? body.budget : '未提供';
  const style = typeof body.style === 'string' && body.style.length > 0 ? body.style : '未提供';
  const stayTier = typeof body.stayTier === 'string' && body.stayTier.length > 0
    ? body.stayTier : '未提供';
  const transit = typeof body.transit === 'string' && body.transit.length > 0
    ? body.transit : '未提供';
  const paces = Array.isArray(body.paces) && body.paces.length > 0
    ? body.paces.join('/') : '未提供';
  const area = areaNameOf(body);

  const lines = [];
  lines.push(`目的地：${destination}；日期：${startDate} 至 ${endDate}；` +
    `计划天数：${dayCount} 天；人数：${people}；预算：${budget} 元/人。`);
  lines.push(`风格：${style}；住宿档位：${stayTier}；交通偏好：${transit}；节奏：${paces}。`);
  if (area.length > 0) {
    lines.push(`住宿区域：${area}（客户端只提供区域名，未提供档位、通勤、餐饮与地铁细节；` +
      '不要编造未提供的字段，具体住宿以平台实时信息为准）。');
  } else {
    lines.push('住宿区域：未提供（不要编造区域、通勤或住宿档位）。');
  }
  lines.push('已选景点（客户端只提供名称与优先级，未提供停留时长、坐标、预约、开放时间与周边）：');
  const selected = Array.isArray(body.selectedSpots) ? body.selectedSpots : [];
  if (selected.length === 0) {
    lines.push('- 未提供');
  } else {
    for (const sel of selected) {
      const name = spotNameOf(sel);
      if (name.length === 0) {
        continue;
      }
      if (isPlainObject(sel) && typeof sel.priority === 'string') {
        lines.push(`- [${sel.priority}] ${name}`);
      } else {
        lines.push(`- ${name}`);
      }
    }
  }
  lines.push('排期要求：按系统规则安排；地址与经纬度按规则 12 留空/0；' +
    '预约与开放时间未提供时写「以官方为准」，禁止编造。');
  return lines.join('\n');
}

/** 规则 + JSON Schema 的系统提示词（与 entry/ PromptBuilder 同一份 SOT；条数由 prompt.test.js 管） */
export function buildSystemPrompt(freeTier = false) {
  const prompt = PromptBuilder.systemPrompt();
  return freeTier
    ? `${prompt}\n输出尽量精简，避免冗余解释；但 JSON 字段与枚举必须完整。`
    : prompt;
}

/** 仅用于日志/验收：当前请求会走 rich 还是 sparse */
export function promptMode(body) {
  return hasRichPayload(body) ? 'rich' : 'sparse';
}

/** 用户消息：有完整景点/区域数据走 ets 同源代码，否则走如实缺口的 sparse 版本 */
export function buildUserPrompt(body) {
  return hasRichPayload(body) ? richUserPrompt(body) : sparseUserPrompt(body);
}

/** OpenAI/DeepSeek 兼容的 messages */
export function buildMessages(body, options = {}) {
  return [
    { role: 'system', content: buildSystemPrompt(options.freeTier === true) },
    { role: 'user', content: buildUserPrompt(body) }
  ];
}

/** 行程天数以用户输入为准，用于服务端校验 */
export function expectedDayCount(body) {
  if (typeof body.startDate !== 'string' || typeof body.endDate !== 'string') {
    return 1;
  }
  return DateUtils.spanDays(body.startDate, body.endDate);
}
