import test from 'node:test';
import assert from 'node:assert/strict';

import { validateTrip } from '../src/prompt/trip-validator.js';
import { validTrip } from './fixtures/trip.js';

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

test('合法 Trip 通过校验', () => {
  const result = validateTrip(validTrip(), { days: 1, startDate: '2026-11-06' });
  assert.equal(result.valid, true);
  assert.deepEqual(result.errors, []);
});

test('缺必填字段被同源 Schema 拦下', () => {
  const trip = clone(validTrip());
  delete trip.days;
  const result = validateTrip(trip);
  assert.equal(result.valid, false);
  assert.ok(result.errors.some((error) => error.includes('trip.days: 缺字段')));
});

test('枚举越界被拦下', () => {
  const trip = clone(validTrip());
  trip.days[0].activities[0].status = 'unknown';
  const result = validateTrip(trip);
  assert.equal(result.valid, false);
  assert.ok(result.errors.some((error) => error.includes("status: 'unknown' 不在枚举")));
});

test('数值类型错误被拦下', () => {
  const trip = clone(validTrip());
  trip.people = '2';
  trip.days[0].dailyCost = 500.5;
  trip.days[0].meals[0].estimatedCost = 120.5;
  const result = validateTrip(trip);
  assert.equal(result.valid, false);
  assert.ok(result.errors.some((error) => error.includes('trip.people: 期望整数')));
  assert.ok(result.errors.some((error) => error.includes('dailyCost: 期望整数')));
  assert.ok(result.errors.some((error) => error.includes('estimatedCost: 期望整数')));
});

test('空数组 / 天数不足 / 日期倒挂被拦下', () => {
  const emptyDays = clone(validTrip());
  emptyDays.days = [];
  const result1 = validateTrip(emptyDays);
  assert.equal(result1.valid, false);
  assert.ok(result1.errors.some((error) => error.includes('不能为空数组')));

  const shortDays = clone(validTrip());
  const result2 = validateTrip(shortDays, { days: 3 });
  assert.equal(result2.valid, false);
  assert.ok(result2.errors.some((error) => error.includes('要求 3 天')));

  const inverted = clone(validTrip());
  inverted.startDate = '2026-11-08';
  inverted.endDate = '2026-11-06';
  const result3 = validateTrip(inverted);
  assert.equal(result3.valid, false);
  assert.ok(result3.errors.some((error) => error.includes('晚于 endDate')));
});

test('endTime 不晚于 time 被拦下', () => {
  const trip = clone(validTrip());
  trip.days[0].activities[0].endTime = '09:00';
  const result = validateTrip(trip);
  assert.equal(result.valid, false);
  assert.ok(result.errors.some((error) => error.includes('必须晚于 time')));
});

test('空串必填与非法时刻格式被拦下', () => {
  const trip = clone(validTrip());
  trip.destination = '';
  trip.days[0].activities[0].time = '9:00';
  const result = validateTrip(trip);
  assert.equal(result.valid, false);
  assert.ok(result.errors.some((error) => error.includes('trip.destination: 不能为空串')));
  assert.ok(result.errors.some((error) => error.includes('非 HH:mm')));
});

test('每天必须至少一条午餐和一条晚餐', () => {
  const missingDinner = clone(validTrip());
  missingDinner.days[0].meals = missingDinner.days[0].meals.filter((meal) => meal.type !== 'dinner');
  const dinnerResult = validateTrip(missingDinner);
  assert.equal(dinnerResult.valid, false);
  assert.ok(dinnerResult.errors.some((error) => error.includes('缺少晚餐')));

  const missingLunch = clone(validTrip());
  missingLunch.days[0].meals = missingLunch.days[0].meals.filter((meal) => meal.type !== 'lunch');
  const lunchResult = validateTrip(missingLunch);
  assert.equal(lunchResult.valid, false);
  assert.ok(lunchResult.errors.some((error) => error.includes('缺少午餐')));
});

test('transport:null 按 TripParser 口径视为无通勤', () => {
  const trip = clone(validTrip());
  trip.days[0].activities[0].transport = null;
  const result = validateTrip(trip);
  assert.equal(result.valid, true);
});

test('多余字段与多余天数保持 TripParser 的容忍口径', () => {
  const trip = clone(validTrip());
  trip.extra = 'ignored';
  trip.days[0].activities[0].extra = 'ignored';
  trip.days.push(clone(trip.days[0]));
  const result = validateTrip(trip, { days: 1 });
  assert.equal(result.valid, true);
});
