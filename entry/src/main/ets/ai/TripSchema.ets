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

type Obj = Record<string, Object>;
type Objs = Object[];

export class TripSchema {
  static readonly ACTIVITY_STATUS: string[] =
    ['booked', 'not_booked', 'full', 'pending', 'no_need'];
  static readonly ACTIVITY_CATEGORY: string[] =
    ['transport', 'sight', 'food', 'shop', 'rest', 'hotel', 'other'];
  static readonly INTENSITY: string[] = ['low', 'medium', 'high'];
  static readonly MEAL_TYPE: string[] = ['breakfast', 'lunch', 'dinner'];

  static readonly TRIP_JSON_SCHEMA: string = JSON.stringify(TripSchema.buildSchema());

  private static obj(type: string): Obj {
    const o: Obj = {};
    o['type'] = type;
    return o;
  }

  private static str(required: boolean): Obj {
    const o: Obj = TripSchema.obj('string');
    if (!required) {
      o['nullable'] = true;
    }
    return o;
  }

  private static enumOf(values: string[]): Obj {
    const o: Obj = TripSchema.obj('string');
    o['enum'] = values as Objs;
    return o;
  }

  private static arr(items: Obj): Obj {
    const o: Obj = TripSchema.obj('array');
    o['items'] = items;
    return o;
  }

  private static typed(type: string): Obj {
    return TripSchema.obj(type);
  }

  private static buildSchema(): Obj {
    const root: Obj = {};
    root['$schema'] = 'http://json-schema.org/draft-07/schema#';
    root['title'] = 'Trip';
    root['type'] = 'object';
    root['additionalProperties'] = false;

    // transport
    const transport: Obj = TripSchema.obj('object');
    const transportProps: Obj = {};
    transportProps['mode'] = TripSchema.str(true);
    transportProps['duration'] = TripSchema.typed('integer');
    transportProps['detail'] = TripSchema.str(true);
    transport['properties'] = transportProps;
    transport['required'] = ['mode', 'duration', 'detail'];
    transport['additionalProperties'] = false;

    // activity
    const activity: Obj = TripSchema.obj('object');
    const actProps: Obj = {};
    actProps['id'] = TripSchema.str(true);
    actProps['time'] = TripSchema.str(true);
    actProps['endTime'] = TripSchema.str(true);
    actProps['title'] = TripSchema.str(true);
    actProps['location'] = TripSchema.str(true);
    actProps['address'] = TripSchema.str(true);
    actProps['longitude'] = TripSchema.typed('number');
    actProps['latitude'] = TripSchema.typed('number');
    actProps['status'] = TripSchema.enumOf(TripSchema.ACTIVITY_STATUS);
    actProps['category'] = TripSchema.enumOf(TripSchema.ACTIVITY_CATEGORY);
    actProps['note'] = TripSchema.str(false);
    actProps['reason'] = TripSchema.str(false);
    actProps['transport'] = transport;
    activity['properties'] = actProps;
    activity['required'] = ['id', 'time', 'endTime', 'title', 'location', 'address',
      'longitude', 'latitude', 'status', 'category'];
    activity['additionalProperties'] = false;

    // meal
    const meal: Obj = TripSchema.obj('object');
    const mealProps: Obj = {};
    mealProps['type'] = TripSchema.enumOf(TripSchema.MEAL_TYPE);
    mealProps['name'] = TripSchema.str(true);
    mealProps['location'] = TripSchema.str(true);
    mealProps['note'] = TripSchema.str(false);
    mealProps['estimatedCost'] = TripSchema.typed('integer');
    meal['properties'] = mealProps;
    meal['required'] = ['type', 'name', 'location', 'estimatedCost'];
    meal['additionalProperties'] = false;

    // day
    const day: Obj = TripSchema.obj('object');
    const dayProps: Obj = {};
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
    const overview: Obj = TripSchema.obj('object');
    const ovProps: Obj = {};
    ovProps['totalCost'] = TripSchema.typed('integer');
    ovProps['highlights'] = TripSchema.arr(TripSchema.typed('string'));
    ovProps['summary'] = TripSchema.str(true);
    overview['properties'] = ovProps;
    overview['required'] = ['totalCost', 'highlights', 'summary'];
    overview['additionalProperties'] = false;

    // root properties
    const rootProps: Obj = {};
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
