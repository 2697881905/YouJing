import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { buildUserPrompt } from '../src/prompt/index.js';
import { richRequest } from './fixtures/trip.js';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));

function source(rel) {
  return readFileSync(join(ROOT, rel), 'utf8');
}

/** 抽 export interface Name { ... } 的直接字段名（本文件不处理嵌套对象） */
function interfaceFields(text, name) {
  const match = text.match(new RegExp(`export interface ${name} \\{([\\s\\S]*?)\\n\\}`));
  assert.ok(match, `找不到 interface ${name}`);
  const fields = [];
  for (const line of match[1].split('\n')) {
    const field = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)(\?)?:/);
    if (field) {
      fields.push(field[1]);
    }
  }
  return fields;
}

function assertFields(actual, expected, label) {
  for (const field of expected) {
    assert.ok(actual.includes(field), `${label} 缺少字段 ${field}（端侧与 BFF rich 分支已漂移）`);
  }
}

test('端侧 TripGeneratePayload 覆盖 BFF rich 分支的顶层字段', () => {
  const fields = interfaceFields(source('entry/src/main/ets/ai/TripRequestPayload.ets'),
    'TripGeneratePayload');
  assertFields(fields, [
    'destination', 'startDate', 'endDate', 'people', 'budget', 'style', 'stayTier',
    'transit', 'paces', 'selectedArea', 'selectedSpots', 'spots', 'area', 'passId', 'freeTier'
  ], 'TripGeneratePayload');
  const text = source('entry/src/main/ets/ai/TripRequestPayload.ets');
  assert.ok(text.includes('spots: Spot[]'), 'spots 必须是完整 Spot[]，不能退回 string[]');
  assert.ok(text.includes('area: Area'), 'area 必须是完整 Area，不能退回 string');
  assert.ok(text.includes('selectedSpots: SelectedSpot[]'), 'selectedSpots 必须是对象数组');
});

test('端侧 SelectedAreaRef / SelectedSpot 与 BFF 读取口径一致', () => {
  const areaRef = interfaceFields(source('entry/src/main/ets/ai/TripRequestPayload.ets'),
    'SelectedAreaRef');
  assertFields(areaRef, ['areaId', 'name'], 'SelectedAreaRef');
  const selected = interfaceFields(source('entry/src/main/ets/model/PlanParams.ets'), 'SelectedSpot');
  assertFields(selected, ['spotId', 'priority', 'userNote'], 'SelectedSpot');
});

test('端侧 Spot 覆盖 BFF normalizeSpot 的全部字段', () => {
  const fields = interfaceFields(source('entry/src/main/ets/model/Spot.ets'), 'Spot');
  assertFields(fields, [
    'id', 'name', 'city', 'tags', 'brief', 'suggestedDuration', 'openingHours',
    'popularity', 'nearbySpotIds', 'longitude', 'latitude', 'district', 'nearestMetro',
    'entranceTip', 'booking', 'provenance'
  ], 'Spot');
});

test('端侧预约/溯源子结构覆盖 BFF prompt 的预约文案字段', () => {
  const booking = interfaceFields(source('entry/src/main/ets/model/Spot.ets'), 'SpotBooking');
  assertFields(booking, [
    'requiresBooking', 'bookingMethod', 'advanceDays', 'releaseTime', 'closedDay', 'difficulty'
  ], 'SpotBooking');
  const provenance = interfaceFields(source('entry/src/main/ets/model/Spot.ets'), 'DataProvenance');
  assertFields(provenance, ['source', 'updatedAt', 'confidence'], 'DataProvenance');
});

test('端侧 Area 覆盖 BFF normalizeArea 的全部字段', () => {
  const fields = interfaceFields(source('entry/src/main/ets/model/Area.ets'), 'Area');
  assertFields(fields, [
    'id', 'name', 'city', 'longitude', 'latitude', 'description', 'anchorStations',
    'metroLines', 'airportMinutes', 'trainStationMinutes', 'commerceTags', 'diningDensity',
    'suitableCrowds', 'priceTier', 'priceRange', 'group', 'source', 'updatedAt'
  ], 'Area');
});

test('builder 确实把 params/spots/area 装进 payload', () => {
  const text = source('entry/src/main/ets/ai/TripRequestPayload.ets');
  for (const fragment of [
    'selectedSpots: params.selectedSpots',
    'selectedArea,',
    'spots,',
    'area,',
    'transit: params.transit',
    'paces: params.paces'
  ]) {
    assert.ok(text.includes(fragment), `builder 缺少 ${fragment}`);
  }
});

test('BFF rich 分支能用 entry 形状（selectedSpot.spotId）走完整 userPrompt', () => {
  const payload = richRequest();
  payload.selectedSpots = payload.spots.map((spot) => ({ spotId: spot.id, priority: 'must' }));
  const prompt = buildUserPrompt(payload);
  assert.ok(prompt.includes('已选景点（含完整规划信息）'));
  assert.ok(prompt.includes('建议90分钟'));
  assert.ok(prompt.includes('坐标(108.9400,34.2600)'));
  assert.ok(prompt.includes('住宿区域：碑林区'));
  assert.ok(prompt.includes('到机场 45 分钟'));
});

test('MapKit 形状仍走 rich，但按 MapKit 口径说未校准而不是补 0', () => {
  const payload = richRequest();
  payload.selectedSpots = payload.spots.map((spot) => ({ spotId: spot.id, priority: 'must' }));
  payload.area = {
    name: '碑林区',
    priceTier: 'comfort',
    metroLines: [],
    anchorStations: [],
    airportMinutes: 0,
    trainStationMinutes: 0,
    source: 'MapKit'
  };
  payload.spots[0].provenance = { source: 'MapKit 地点检索', updatedAt: '2026-11-01' };
  payload.spots[0].booking = { requiresBooking: false };
  const prompt = buildUserPrompt(payload);
  assert.ok(prompt.includes('地图服务区县'));
  assert.ok(prompt.includes('预约信息未获取，以官方为准'));
  assert.ok(!prompt.includes('到机场 0 分钟'));
});
