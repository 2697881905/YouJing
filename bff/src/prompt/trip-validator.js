/**
 * 服务端 Trip 校验（BFF 侧第三层防线的提前拦截）。
 *
 * 字段/必填/枚举/类型全部从 `contract.js` 的同源 JSON Schema 驱动，
 * 不在这里再抄一份字段表。Schema 之外补 TripParser 已有的语义约束：
 * days 非空、天数不少于用户窗口、startDate <= endDate、endTime > time、
 * TripParser 要求非空的字符串；另加一条餐次业务兜底（见文末）。
 *
 * 口径取舍：TripParser 对多余属性是容忍的（只读它认识的键），
 * 所以本校验器也不因 additionalProperties 报错；对多余天数同样容忍，
 * 由端侧 TripParser 按窗口截断。BFF 主要拦「端侧一定解析失败」的输出；
 * 餐次兜底是额外业务规则，不属于 TripParser 的结构校验：PromptBuilder 规则 6
 * 要求每天至少 lunch + dinner 各一条，BFF 提前拦，避免模型漏餐次后仍落库。
 */

import { TRIP_SCHEMA_OBJECT } from './contract.js';

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
const HHMM = /^\d{2}:\d{2}$/;

function isPlainObject(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function validateValue(value, schema, path, errors) {
  // TripParser 把 transport:null 当「没有通勤」；Schema 的 transport 非 nullable，
  // 这里按解析器口径放行，避免服务端比端侧更严导致可用的 Trip 被退回。
  if (value === null && path.endsWith('.transport')) {
    return;
  }
  if (value === undefined || value === null) {
    if (value === null && schema && schema.nullable !== true) {
      errors.push(`${path}: 不允许 null`);
    }
    return;
  }
  if (!schema || typeof schema !== 'object') {
    return;
  }
  const type = schema.type;
  if (type === 'object') {
    if (!isPlainObject(value)) {
      errors.push(`${path}: 期望 object`);
      return;
    }
    for (const key of schema.required || []) {
      if (!Object.prototype.hasOwnProperty.call(value, key)) {
        errors.push(`${path}.${key}: 缺字段`);
      }
    }
    const props = schema.properties || {};
    for (const key of Object.keys(props)) {
      if (Object.prototype.hasOwnProperty.call(value, key)) {
        validateValue(value[key], props[key], `${path}.${key}`, errors);
      }
    }
    return;
  }
  if (type === 'array') {
    if (!Array.isArray(value)) {
      errors.push(`${path}: 期望 array`);
      return;
    }
    if (schema.items) {
      value.forEach((item, index) => validateValue(item, schema.items, `${path}[${index}]`, errors));
    }
    return;
  }
  if (type === 'string') {
    if (typeof value !== 'string') {
      errors.push(`${path}: 期望 string`);
      return;
    }
    if (Array.isArray(schema.enum) && schema.enum.indexOf(value) < 0) {
      errors.push(`${path}: '${value}' 不在枚举 [${schema.enum.join(',')}]`);
    }
    return;
  }
  if (type === 'integer') {
    if (typeof value !== 'number' || !Number.isInteger(value)) {
      errors.push(`${path}: 期望整数`);
    }
    return;
  }
  if (type === 'number') {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      errors.push(`${path}: 期望 number`);
    }
  }
}

function nonEmpty(value, path, errors) {
  if (typeof value === 'string' && value.length === 0) {
    errors.push(`${path}: 不能为空串`);
  }
}

function checkActivity(activity, path, errors) {
  if (!isPlainObject(activity)) {
    return;
  }
  nonEmpty(activity.id, `${path}.id`, errors);
  nonEmpty(activity.title, `${path}.title`, errors);
  if (typeof activity.time === 'string') {
    nonEmpty(activity.time, `${path}.time`, errors);
    if (HHMM.test(activity.time) === false) {
      errors.push(`${path}.time: '${activity.time}' 非 HH:mm`);
    }
  }
  if (typeof activity.endTime === 'string') {
    nonEmpty(activity.endTime, `${path}.endTime`, errors);
    if (HHMM.test(activity.endTime) === false) {
      errors.push(`${path}.endTime: '${activity.endTime}' 非 HH:mm`);
    }
  }
  if (typeof activity.time === 'string' && typeof activity.endTime === 'string' &&
    HHMM.test(activity.time) && HHMM.test(activity.endTime) &&
    activity.endTime <= activity.time) {
    errors.push(`${path}.endTime: ${activity.endTime} 必须晚于 time(${activity.time})`);
  }
  if (isPlainObject(activity.transport)) {
    nonEmpty(activity.transport.mode, `${path}.transport.mode`, errors);
    nonEmpty(activity.transport.detail, `${path}.transport.detail`, errors);
  }
}

function checkMeal(meal, path, errors) {
  if (!isPlainObject(meal)) {
    return;
  }
  nonEmpty(meal.name, `${path}.name`, errors);
  nonEmpty(meal.location, `${path}.location`, errors);
}

/**
 * @param {object} trip
 * @param {{days?: number, startDate?: string}} [expect]
 * @returns {{valid: boolean, errors: string[]}}
 */
export function validateTrip(trip, expect = {}) {
  const errors = [];
  validateValue(trip, TRIP_SCHEMA_OBJECT, 'trip', errors);
  if (!isPlainObject(trip)) {
    return { valid: false, errors };
  }

  nonEmpty(trip.id, 'trip.id', errors);
  nonEmpty(trip.destination, 'trip.destination', errors);
  nonEmpty(trip.style, 'trip.style', errors);
  if (isPlainObject(trip.overview)) {
    nonEmpty(trip.overview.summary, 'trip.overview.summary', errors);
  }

  if (typeof trip.startDate === 'string') {
    if (ISO_DATE.test(trip.startDate) === false) {
      errors.push(`trip.startDate: '${trip.startDate}' 非 YYYY-MM-DD`);
    }
  }
  if (typeof trip.endDate === 'string') {
    if (ISO_DATE.test(trip.endDate) === false) {
      errors.push(`trip.endDate: '${trip.endDate}' 非 YYYY-MM-DD`);
    }
  }
  if (typeof trip.startDate === 'string' && typeof trip.endDate === 'string' &&
    ISO_DATE.test(trip.startDate) && ISO_DATE.test(trip.endDate) &&
    trip.startDate > trip.endDate) {
    errors.push('trip.startDate: 晚于 endDate');
  }

  if (Array.isArray(trip.days)) {
    if (trip.days.length === 0) {
      errors.push('trip.days: 不能为空数组');
    }
    if (Number.isInteger(expect.days) && expect.days > 0 && trip.days.length < expect.days) {
      errors.push(`trip.days: 只有 ${trip.days.length} 天，本次行程要求 ${expect.days} 天`);
    }
    trip.days.forEach((day, index) => {
      if (!isPlainObject(day)) {
        return;
      }
      nonEmpty(day.date, `trip.days[${index}].date`, errors);
      nonEmpty(day.theme, `trip.days[${index}].theme`, errors);
      if (Array.isArray(day.activities)) {
        day.activities.forEach((activity, activityIndex) =>
          checkActivity(activity, `trip.days[${index}].activities[${activityIndex}]`, errors));
      }
      if (Array.isArray(day.meals)) {
        const mealTypes = day.meals
          .filter((meal) => isPlainObject(meal))
          .map((meal) => meal.type);
        if (mealTypes.filter((type) => type === 'lunch').length === 0) {
          errors.push(`trip.days[${index}].meals: 缺少午餐（每天至少 lunch 一条）`);
        }
        if (mealTypes.filter((type) => type === 'dinner').length === 0) {
          errors.push(`trip.days[${index}].meals: 缺少晚餐（每天至少 dinner 一条）`);
        }
        day.meals.forEach((meal, mealIndex) =>
          checkMeal(meal, `trip.days[${index}].meals[${mealIndex}]`, errors));
      }
    });
  }

  return { valid: errors.length === 0, errors };
}
