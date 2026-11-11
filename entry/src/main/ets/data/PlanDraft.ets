/**
 * 规划草稿（跨页共享态，pages→data 单向依赖）。
 * 屏2/3/4/5 逐步写入，屏6 组装 PlanParams 消费；重置入口在生成完成或用户回首页新建。
 */

import { PaceOption, SelectedSpot, SelectedArea, TransitPreference, TravelStyle, TripBasicInput } from '../model/PlanParams';
import { BudgetConfig } from '../common/constants/BudgetConfig';
import { DateUtils } from '../utils/DateUtils';
import { TripLength } from '../utils/TripLength';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Logger } from '../common/logger/Logger';
import { markDraftDirty } from '../common/constants/AppNav';

const TAG: string = 'PlanDraft';
const DRAFT_STORE: string = 'planDraft';
const DRAFT_KEY: string = 'draft_v1';

/** 落盘形态：与草稿七字段一一对应（JSON 往返），不新增业务字段 */
export interface PlanDraftSnapshot {
  basic: TripBasicInput;
  style: TravelStyle;
  stayTier: string;
  transit: TransitPreference;
  paces: PaceOption[];
  selectedSpots: SelectedSpot[];
  selectedArea: SelectedArea;
}

export class PlanDraft {
  /** 屏2 未填日期时的默认档：今天起算 3 天 2 晚 */
  static readonly DEFAULT_DAYS: number = TripLength.DEFAULT_DAYS;
  private static instance: PlanDraft | null = null;

  // 日期默认留空：具体日期由屏2 按「今天起算」填充（写死字面量会让新装用户在
  // 若干个月后看到默认出发日在过去）。屏4/屏6 的静默兜底一律走 DateUtils.spanDays，
  // 空串在那里按 1 天处理，不会产生 NaN。
  basic: TripBasicInput = {
    destination: '北京', startDate: '', endDate: '', people: 2, budget: BudgetConfig.DEFAULT
  };
  style: TravelStyle = TravelStyle.LEISURE;
  stayTier: string = 'comfort';
  transit: TransitPreference = TransitPreference.PUBLIC;
  paces: PaceOption[] = [PaceOption.STANDARD];
  selectedSpots: SelectedSpot[] = [];
  selectedArea: SelectedArea = { areaId: '' };

  static get(): PlanDraft {
    if (PlanDraft.instance === null) {
      PlanDraft.instance = new PlanDraft();
    }
    PlanDraft.instance.basic = PlanDraft.repairInvertedRange(PlanDraft.instance.basic);
    return PlanDraft.instance;
  }

  /**
   * 反向日期区间修复（`endDate < startDate`）。
   * 外部 Want（小艺 / 深链）逐字段写草稿，只带 `start` 或只带 `end` 就留下反向对；
   * 反向区间不是任何一种用户意图，唯一动作是把返程拉回与出发同日。
   * 空串与过去日期都不在此列：空串是"用户还没选"的诚实占位（两条 hypium 用例钉着），
   * 能不能补记已走完的旅行属产品口径，未拍板前不动（§5ci 续 184）。
   */
  static repairInvertedRange(b: TripBasicInput): TripBasicInput {
    if (DateUtils.isValidIsoDate(b.startDate) && DateUtils.isValidIsoDate(b.endDate) &&
      b.endDate < b.startDate) {
      const fixed: TripBasicInput = {
        destination: b.destination, startDate: b.startDate,
        endDate: b.startDate, people: b.people, budget: b.budget
      };
      return fixed;
    }
    return b;
  }

  /**
   * 行程天数——**屏2 的显示与屏5/屏6/生成请求必须用同一个口径**。
   *
   * 为什么不能直接 `DateUtils.spanDays(b.startDate, b.endDate)`：草稿的日期默认是空串
   * （写死字面量会让新装用户的出发日在过去），而屏2 按「今天起算 3 天」填自己的页面 state。
   * 用户没点过「开始规划」就直进屏5（小艺 / 深链是受支持的入口）时，
   * `spanDays('', '')` 取到 **1 天**、上限 4 个，屏2 却写着 **3天2晚**（2026-11-04 真机实拍）——
   * 空串被当成了答案。这里把"没填"如实折算成屏2 那个默认档，草稿本身继续留空。
   */
  static days(b: TripBasicInput): number {
    return TripLength.days(b);
  }

  /**
   * 开一段新规划时丢弃旧草稿。
   * 之前只有一个实例方法 reset() 且从未被调用：连着规划第二次时，
   * 上一次的 selectedSpots / selectedArea / 节奏会静默带进来（真机连做三条行程时复现）。
   */
  static fresh(): void {
    PlanDraft.instance = null;
    // 草稿作废即无可续：dirty 标志同步清，否则根页「续草稿」入口指向空草稿
    markDraftDirty(false);
    // 防抖里可能还挂着一笔旧草稿的写盘：先撤掉，再把盘上那份清掉，
    // 否则「新建」之后杀进程重进会复活上一段草稿
    if (PlanDraft.persistTimer >= 0) {
      clearTimeout(PlanDraft.persistTimer);
      PlanDraft.persistTimer = -1;
    }
    const prefs: preferences.Preferences | null = PlanDraft.prefs;
    if (prefs !== null) {
      try {
        prefs.deleteSync(DRAFT_KEY);
        prefs.flush().catch((err: Error): void => {
          Logger.warn(TAG, `草稿清盘失败: ${err.message}`);
        });
      } catch (err) {
        Logger.warn(TAG, `草稿清盘失败: ${(err as Error).message}`);
      }
    }
  }

  // ——— 本机落盘（IMP-01）：杀进程/返回上一页不再丢未提交输入 ———
  // 口径：只落本机 preferences，不上云、不进 RDB（隐私口径不变）；
  // 生命周期与内存草稿完全一致——生成成功后不清（现状如此），fresh() 才清。
  private static ctx: common.Context | null = null;
  private static prefs: preferences.Preferences | null = null;
  private static persistTimer: number = -1;
  /** 冷启 Want 预填先于水合写过草稿时置位：外部意图优先，水合不得用盘上旧快照覆盖 */
  private static externalWrite: boolean = false;

  static markExternalWrite(): void {
    PlanDraft.externalWrite = true;
  }

  /**
   * 冷启水合：EntryAbility.bootstrap 调用，必须先于深链/小艺预填写草稿。
   * 返回 true = 盘上有草稿且已恢复（调用方据此广播 dirty，让根页「续草稿」入口活过来）。
   */
  static async hydrate(context: common.Context): Promise<boolean> {
    PlanDraft.ctx = context;
    try {
      PlanDraft.prefs = await preferences.getPreferences(context, DRAFT_STORE);
      if (PlanDraft.externalWrite) {
        // applyWant 在 onCreate 已写草稿（早于 bootstrap）：保留外部预填并补落盘
        PlanDraft.flush();
        return false;
      }
      const stored: preferences.ValueType = PlanDraft.prefs.getSync(DRAFT_KEY, '');
      const raw: string = typeof stored === 'string' ? stored as string : '';
      if (raw.length === 0) {
        return false;
      }
      const snap: PlanDraftSnapshot = JSON.parse(raw) as PlanDraftSnapshot;
      if (!PlanDraft.validSnapshot(snap)) {
        Logger.warn(TAG, '盘上草稿形态不合，按默认档起');
        return false;
      }
      const d: PlanDraft = PlanDraft.get();
      d.basic = snap.basic;
      d.style = snap.style;
      d.stayTier = snap.stayTier;
      d.transit = snap.transit;
      d.paces = snap.paces;
      d.selectedSpots = snap.selectedSpots;
      d.selectedArea = snap.selectedArea;
      Logger.info(TAG, `草稿水合 ${d.basic.destination} spots=${d.selectedSpots.length}`);
      return true;
    } catch (err) {
      // 读不到就按默认档起：草稿丢一档只是重填，不能挡住冷启
      Logger.warn(TAG, `草稿水合失败，按默认档起: ${(err as Error).message}`);
      return false;
    }
  }

  /** 纯函数：草稿 → 落盘快照（hypium 往返用例钉形态） */
  static toSnapshot(d: PlanDraft): PlanDraftSnapshot {
    const snap: PlanDraftSnapshot = {
      basic: d.basic, style: d.style, stayTier: d.stayTier, transit: d.transit,
      paces: d.paces, selectedSpots: d.selectedSpots, selectedArea: d.selectedArea
    };
    return snap;
  }

  static validSnapshot(s: PlanDraftSnapshot): boolean {
    return s !== null && s !== undefined
      && s.basic !== null && s.basic !== undefined
      && typeof s.basic.destination === 'string'
      && typeof s.basic.startDate === 'string'
      && typeof s.basic.endDate === 'string'
      && typeof s.basic.people === 'number'
      && typeof s.basic.budget === 'number'
      && typeof s.stayTier === 'string'
      && Array.isArray(s.paces)
      && Array.isArray(s.selectedSpots)
      && s.selectedArea !== null && s.selectedArea !== undefined;
  }

  /** 防抖写盘（500ms）：字段级改动随改随存，杀进程最多丢最后半秒 */
  static persist(): void {
    if (PlanDraft.persistTimer >= 0) {
      clearTimeout(PlanDraft.persistTimer);
    }
    PlanDraft.persistTimer = setTimeout((): void => {
      PlanDraft.persistTimer = -1;
      PlanDraft.flush();
    }, 500);
  }

  /** 立即写盘：CTA/识别成功等提交点用 */
  static flush(): void {
    const context: common.Context | null = PlanDraft.ctx;
    if (context === null) {
      return; // 水合前的极早期写入不落盘（深链/预填随后会带着同一批参数再来一次）
    }
    const prefs: preferences.Preferences | null = PlanDraft.prefs;
    if (prefs === null) {
      preferences.getPreferences(context, DRAFT_STORE).then((p: preferences.Preferences): void => {
        PlanDraft.prefs = p;
        PlanDraft.writeSnapshot(p);
      }).catch((err: Error): void => {
        Logger.warn(TAG, `草稿存储打开失败: ${err.message}`);
      });
      return;
    }
    PlanDraft.writeSnapshot(prefs);
  }

  private static writeSnapshot(prefs: preferences.Preferences): void {
    try {
      const d: PlanDraft = PlanDraft.get();
      prefs.putSync(DRAFT_KEY, JSON.stringify(PlanDraft.toSnapshot(d)));
      prefs.flush().catch((err: Error): void => {
        Logger.warn(TAG, `草稿写盘失败: ${err.message}`);
      });
    } catch (err) {
      Logger.warn(TAG, `草稿写盘失败: ${(err as Error).message}`);
    }
  }
}
