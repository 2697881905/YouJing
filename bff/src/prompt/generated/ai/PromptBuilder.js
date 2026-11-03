/* AUTO-GENERATED from entry/src/main/ets/ai/PromptBuilder.ets by bff/scripts/sync-prompt-contract.mjs. Do not edit. */
"use strict";
/**
 * Prompt 构造（开发文档 §3.3 第三层 / §4.3 第一层防线）。
 * 系统指令内嵌完整 JSON Schema（与 TripParser/TripSchema 同源常量），
 * 用户消息带 SelectedSpot 完整信息 + 区域通勤 + 基础参数。
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.PromptBuilder = void 0;
const TripSchema_1 = require("./TripSchema");
const DateUtils_1 = require("../utils/DateUtils");
class PromptBuilder {
    static buildRequest(params, spots, area) {
        const req = {
            system: PromptBuilder.systemPrompt(),
            user: PromptBuilder.userPrompt(params, spots, area),
            jsonSchemaStrict: true
        };
        return req;
    }
    static systemPrompt() {
        const days = [];
        days.push('你是旅行行程规划引擎。只输出一个符合给定 JSON Schema 的 JSON 对象，禁止输出任何其他文字、注释或代码围栏。');
        days.push('规则：');
        days.push('1. days 数组长度必须等于用户消息里的「计划天数」，dayIndex 从 1 连续递增；' +
            'date 第一天等于 startDate，逐日 +1，最后一天等于 endDate。');
        days.push('2. 每个活动 time/endTime 为 HH:mm；相邻活动间如有通勤，写入后一活动的 transport（mode/duration分钟/detail）；' +
            'category=transport 的节点本身就是这段通勤，不要再给它填 transport 字段，避免同一条腿被重复计算。');
        days.push('3. status 只能取 booked|not_booked|full|pending|no_need；category 只能取 transport|sight|food|shop|rest|hotel|other。');
        days.push('4. 必须覆盖用户标记为 must 的全部景点；want 尽量覆盖；optional 视时间取舍。餐饮每天至少午餐、晚餐各一条（meals）。');
        days.push('5. 景点的预约信息（booking）必须体现在对应活动的 note 或 reason 中，并注明「以官方为准」。');
        days.push('6. reason 字段：为节奏紧张或清晨/夜间安排给出一句中文理由。');
        days.push('7. 金额一律整数人民币元；overview.totalCost 约等于各天 dailyCost 之和。');
        days.push('8. 每餐 meals[].time 给 HH:mm 用餐时刻（早餐 07:00–09:00、午餐 11:30–13:30、晚餐 17:30–20:30 之间取整），屏15 会把餐次与节点按时间并排。');
        days.push('9. 活动的 location 填「到访点位/入口别称」（如「山脚入口」「北门」「正殿前」），不得与 title 或 address 重复；没有明确入口信息时留空串。');
        days.push('10. 某天确有明确风险才写 days[i].risk（闭馆日、雨季、需提前抢票等一句话）；没有风险就省略该字段，不要为凑字段编造风险。');
        // 直连 DeepSeek 实测（2026-10-27）：模型会在中文里用英文双引号做强调，
        // 例如 "本次行程未安排"可选加"" —— 整段 JSON 因此语法不合法，屏7 报「days: 期望 array」。
        // json_schema strict 这条端点不支持（见 ApiConfig.SUPPORTS_JSON_SCHEMA），所以只能从提示词侧堵。
        days.push('11. 字符串值内**禁止出现英文双引号 " 与反斜杠**；需要强调或引用名称时一律用中文书名号「」。输出必须是可被 JSON.parse 直接解析的单个对象。');
        // 直连实测（2026-10-27）：模型会把景点地址整段重写（北京市延庆区八达岭镇八达岭长城景区），
        // 而库里本来就有这些字段——白烧输出 token 又可能写错。让它留空，落库前按 spotId 回填。
        days.push('12. 活动的 address 一律填空串、longitude/latitude 一律填 0：到访地址由 App 按景点库回填，你重写只会写错。location 仍按第 9 条填入口别称。');
        // 真机实测（2026-10-27，thinking 关闭）：首日（抵达日）整个 meals 键被省略，
        // TripParser 报「days[0].meals: 缺字段」→ 重试一次，单次生成账单直接翻倍。
        days.push('13. 每个 day 必须同时给出 dayIndex、date、theme、intensity、dailyCost、activities、meals 七个键，一个都不能省；某天没有用餐安排时 meals 写空数组 []（按第 4 条正常每天都有午/晚两餐）。');
        days.push('14. 若景点给出「开放」时段，排期必须落在该时段内；没有开放信息时不要编造开放时间。');
        days.push('15. 景点预约信息为「未获取」时，禁止编造预约方式/提前天数，写「以官方为准」即可。');
        // 真机实测（2026-10-31）：1 天行程只给「同一天至同一天」时，模型拆成两天且 dayIndex 重复
        days.push('16. 计划天数为 1 时，days 必须恰好包含 1 个元素（dayIndex=1，date 等于 startDate 和 endDate）；' +
            '不得把行程拆成「抵达日 + 游玩日」两天，也不得输出第 2 天。');
        days.push('17. 计划天数为 1 时：停留 + 通勤总时长不超过 10 小时（含往返住宿区）；' +
            '首站不早于 07:30，末站不晚于 21:00；装不下时保留 must，删减 want/optional，' +
            '不要用「早起 + 深夜」硬塞。');
        // 2026-11-03 真机 + 真模型实测：meals 已经写「老北京炸酱面 13:30」，activities 里又来一条
        // 「午餐 13:30」，屏8 的当日序列（活动 ∪ 餐次）于是出现两顿午饭。
        days.push('18. 午餐/晚餐只写进 meals，**不要**再在 activities 里输出「午餐/晚餐」这类通用用餐条目；' +
            '只有本身是游览内容的特色餐饮（小吃街、下午茶、市场）才可作为 category=food 的活动，' +
            '且不得与 meals 里的同一餐重复。');
        days.push('JSON Schema:');
        days.push(TripSchema_1.TripSchema.TRIP_JSON_SCHEMA);
        return days.join('\n');
    }
    static userPrompt(params, spots, area) {
        const lines = [];
        const b = params.basic;
        const dayCount = DateUtils_1.DateUtils.spanDays(b.startDate, b.endDate);
        lines.push(`目的地：${b.destination}；日期：${b.startDate} 至 ${b.endDate}；` +
            `计划天数：${dayCount} 天；人数：${b.people}；预算：${b.budget} 元/人。`);
        lines.push(`风格：${params.style}；住宿档位：${params.stayTier}；交通偏好：${params.transit}；节奏：${params.paces.join('/') || 'standard'}。`);
        if (area.source.indexOf('MapKit') >= 0) {
            // 地图服务区县没有档位/通勤/地铁字段；不能把 0 分钟、空线路喂给模型
            lines.push(`住宿区域：${area.name}（地图服务区县；住宿档、通勤与餐饮未校准，` +
                `具体住宿以平台实时信息为准）。`);
        }
        else {
            lines.push(`住宿区域：${area.name}（价格档位 ${area.priceTier}，` +
                `${area.metroLines.join('/')}，锚定站 ${area.anchorStations.join('/')}，` +
                `到机场 ${area.airportMinutes} 分钟、火车站 ${area.trainStationMinutes} 分钟）。`);
        }
        lines.push('已选景点（含完整规划信息）：');
        for (const sel of params.selectedSpots) {
            const spot = spots.find((s) => s.id === sel.spotId);
            if (spot === undefined) {
                continue;
            }
            const isMapSpot = spot.provenance.source.indexOf('MapKit') >= 0;
            let bk;
            if (isMapSpot) {
                // MapKit 没有预约字段：不能对模型说「无需预约」，只能如实说未获取
                bk = '预约信息未获取，以官方为准';
            }
            else if (spot.booking.requiresBooking) {
                bk = `需预约(${spot.booking.bookingMethod ?? '官方渠道'}${spot.booking.advanceDays !== undefined ? ` 提前${spot.booking.advanceDays}天` : ''}${spot.booking.closedDay !== undefined ? ` 闭馆:${spot.booking.closedDay}` : ''})`;
            }
            else {
                bk = '无需预约';
            }
            const hours = spot.openingHours !== undefined && spot.openingHours.length > 0
                ? `｜开放:${spot.openingHours}` : '';
            lines.push(`- [${sel.priority}] ${spot.name}｜${spot.district}｜建议${spot.suggestedDuration}分钟｜` +
                `坐标(${spot.longitude.toFixed(4)},${spot.latitude.toFixed(4)})｜${bk}${hours}｜周边:${spot.nearbySpotIds.join(',') || '无'}` +
                `${sel.userNote !== undefined ? `｜用户备注:${sel.userNote}` : ''}`);
        }
        return lines.join('\n');
    }
}
exports.PromptBuilder = PromptBuilder;
