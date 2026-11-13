/**
 * 行程天数 / 同行人数的合法区间——**全工程唯一口径**。
 *
 * 为什么要有它（2026-11-13 真机实测出的缺陷 B）：两条外部预填路径各写了一个门槛，
 * 口径就分裂了——深链 Want（EntryAbility.applyWant）用 `days > 1`，
 * 于是「1 天」被当成「没给天数」，回落到默认 3 天；
 * 小艺 Skill（applySkillPrefill）没有门槛，1 天就是 1 天。
 * 同一句「去上海玩一天」，小艺进来显示 1 天、深链进来显示 3 天。
 * 区间抽到一处，Skill 脚本 / 深链 / 预填落盘校验共用，改边界只改一处。
 *
 * 放 utils 而不是 common/constants：它是**规则**（像 TripLength / TripSpan），
 * 且必须保持无 @kit 依赖——离线断言（tools/verify_skill_logic.sh）要能直接编译它。
 */

export class TripLimits {
  /** 行程天数（含首尾）：1 天就是 1 天，不存在「1 天算没给」这种回落 */
  static readonly MIN_DAYS: number = 1;
  static readonly MAX_DAYS: number = 30;

  /** 同行人数 */
  static readonly MIN_PEOPLE: number = 1;
  static readonly MAX_PEOPLE: number = 30;

  static isDaysValid(days: number): boolean {
    return Number.isInteger(days) && days >= TripLimits.MIN_DAYS && days <= TripLimits.MAX_DAYS;
  }

  static isPeopleValid(people: number): boolean {
    return Number.isInteger(people) &&
      people >= TripLimits.MIN_PEOPLE && people <= TripLimits.MAX_PEOPLE;
  }
}
