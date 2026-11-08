/* AUTO-GENERATED from entry/src/main/ets/utils/TripLength.ets by bff/scripts/sync-prompt-contract.mjs. Do not edit. */
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.TripLength = void 0;
const DateUtils_1 = require("./DateUtils");
class TripLength {
    static days(b) {
        if (!DateUtils_1.DateUtils.isValidIsoDate(b.startDate) || !DateUtils_1.DateUtils.isValidIsoDate(b.endDate)) {
            return TripLength.DEFAULT_DAYS;
        }
        return DateUtils_1.DateUtils.spanDays(b.startDate, b.endDate);
    }
}
exports.TripLength = TripLength;
/** 屏2 未填日期时的默认档：今天起算 3 天 2 晚 */
TripLength.DEFAULT_DAYS = 3;
