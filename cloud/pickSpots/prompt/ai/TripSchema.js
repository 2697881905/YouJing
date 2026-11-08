/* AUTO-GENERATED from entry/src/main/ets/ai/TripSchema.ets by bff/scripts/sync-prompt-contract.mjs. Do not edit. */
"use strict";
/**
 * LLM 输出 JSON Schema 常量（开发文档 §4.3 三层防线之第一/三层同源）。
 *
 * Schema 文本用于 Prompt 系统指令；枚举白名单数组同时被 TripParser 守卫引用——
 * 「Schema、接口、守卫三者同源」在本文件物理成立：改枚举只改这里。
 * response_format: {type:'json_schema', strict:true} 直接使用 TRIP_JSON_SCHEMA。
 *
 * 写法说明：ohosTest 编译管线对未定型对象字面量零容忍（arkts-no-untyped-obj-literals），
 * 故全部用 Record<string, Object> 逐键赋值构建。
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.TripSchema = void 0;
class TripSchema {
    static obj(type) {
        const o = {};
        o['type'] = type;
        return o;
    }
    static str(required) {
        const o = TripSchema.obj('string');
        if (!required) {
            o['nullable'] = true;
        }
        return o;
    }
    static enumOf(values) {
        const o = TripSchema.obj('string');
        o['enum'] = values;
        return o;
    }
    static arr(items) {
        const o = TripSchema.obj('array');
        o['items'] = items;
        return o;
    }
    static typed(type) {
        return TripSchema.obj(type);
    }
    static buildSchema() {
        const root = {};
        root['$schema'] = 'http://json-schema.org/draft-07/schema#';
        root['title'] = 'Trip';
        root['type'] = 'object';
        root['additionalProperties'] = false;
        // transport
        const transport = TripSchema.obj('object');
        const transportProps = {};
        transportProps['mode'] = TripSchema.str(true);
        transportProps['duration'] = TripSchema.typed('integer');
        transportProps['detail'] = TripSchema.str(true);
        transport['properties'] = transportProps;
        transport['required'] = ['mode', 'duration', 'detail'];
        transport['additionalProperties'] = false;
        // activity
        const activity = TripSchema.obj('object');
        const actProps = {};
        actProps['id'] = TripSchema.str(true);
        actProps['time'] = TripSchema.str(true);
        actProps['endTime'] = TripSchema.str(true);
        actProps['title'] = TripSchema.str(true);
        actProps['location'] = TripSchema.str(true);
        // address 允许留空：提示词第 12 条要求模型不要重写地址（省输出 token、免幻觉），
        // 真值由 utils/TripEnrich 按景点库回填，所以这里不再是必填
        actProps['address'] = TripSchema.str(false);
        actProps['longitude'] = TripSchema.typed('number');
        actProps['latitude'] = TripSchema.typed('number');
        actProps['status'] = TripSchema.enumOf(TripSchema.ACTIVITY_STATUS);
        actProps['category'] = TripSchema.enumOf(TripSchema.ACTIVITY_CATEGORY);
        actProps['note'] = TripSchema.str(false);
        actProps['reason'] = TripSchema.str(false);
        actProps['transport'] = transport;
        activity['properties'] = actProps;
        activity['required'] = ['id', 'time', 'endTime', 'title', 'location',
            'longitude', 'latitude', 'status', 'category'];
        activity['additionalProperties'] = false;
        // meal
        const meal = TripSchema.obj('object');
        const mealProps = {};
        mealProps['type'] = TripSchema.enumOf(TripSchema.MEAL_TYPE);
        mealProps['name'] = TripSchema.str(true);
        mealProps['time'] = TripSchema.str(false);
        mealProps['location'] = TripSchema.str(true);
        mealProps['note'] = TripSchema.str(false);
        mealProps['estimatedCost'] = TripSchema.typed('integer');
        meal['properties'] = mealProps;
        meal['required'] = ['type', 'name', 'location', 'estimatedCost'];
        meal['additionalProperties'] = false;
        // day
        const day = TripSchema.obj('object');
        const dayProps = {};
        dayProps['dayIndex'] = TripSchema.typed('integer');
        dayProps['date'] = TripSchema.str(true);
        dayProps['theme'] = TripSchema.str(true);
        dayProps['intensity'] = TripSchema.enumOf(TripSchema.INTENSITY);
        dayProps['risk'] = TripSchema.str(false);
        dayProps['dailyCost'] = TripSchema.typed('integer');
        dayProps['activities'] = TripSchema.arr(activity);
        dayProps['meals'] = TripSchema.arr(meal);
        dayProps['accommodation'] = TripSchema.str(false);
        day['properties'] = dayProps;
        day['required'] = ['dayIndex', 'date', 'theme', 'intensity', 'dailyCost', 'activities', 'meals'];
        day['additionalProperties'] = false;
        // overview
        const overview = TripSchema.obj('object');
        const ovProps = {};
        ovProps['totalCost'] = TripSchema.typed('integer');
        ovProps['highlights'] = TripSchema.arr(TripSchema.typed('string'));
        ovProps['summary'] = TripSchema.str(true);
        overview['properties'] = ovProps;
        overview['required'] = ['totalCost', 'highlights', 'summary'];
        overview['additionalProperties'] = false;
        // root properties
        const rootProps = {};
        rootProps['id'] = TripSchema.str(true);
        rootProps['destination'] = TripSchema.str(true);
        rootProps['startDate'] = TripSchema.str(true);
        rootProps['endDate'] = TripSchema.str(true);
        rootProps['people'] = TripSchema.typed('integer');
        rootProps['budget'] = TripSchema.typed('integer');
        rootProps['style'] = TripSchema.str(true);
        rootProps['overview'] = overview;
        rootProps['days'] = TripSchema.arr(day);
        rootProps['tips'] = TripSchema.arr(TripSchema.typed('string'));
        root['properties'] = rootProps;
        root['required'] = ['id', 'destination', 'startDate', 'endDate', 'people',
            'budget', 'style', 'overview', 'days', 'tips'];
        return root;
    }
}
exports.TripSchema = TripSchema;
TripSchema.ACTIVITY_STATUS = ['booked', 'not_booked', 'full', 'pending', 'no_need'];
TripSchema.ACTIVITY_CATEGORY = ['transport', 'sight', 'food', 'shop', 'rest', 'hotel', 'other'];
TripSchema.INTENSITY = ['low', 'medium', 'high'];
TripSchema.MEAL_TYPE = ['breakfast', 'lunch', 'dinner'];
TripSchema.TRIP_JSON_SCHEMA = JSON.stringify(TripSchema.buildSchema());
