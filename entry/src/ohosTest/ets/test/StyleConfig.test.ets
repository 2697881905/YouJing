/**
 * 纯配置/口径回归：CategoryStyle 五映射、QuestionFlowConfig 四题与 MotionTokens 五档。
 * 拼错一个选项 value 即静默错档（屏3 与 PlanParams 枚举对不上时用户选了没反应），
 * 这两处必须离线可断言。
 * MotionTokens 一段是契约 v2 C4 的锁：五档时长与 pressScale 写死对表 DESIGN.md `motion:`，
 * 三条曲线的**控制点**用 ICurve.interpolate 的曲线指纹锁住（否则换一档贝塞尔今天全绿），
 * 顺带证明 §1 那条「自定义贝塞尔在 ArkTS 可用」不只是抄姊妹 App 的结论。
 * ShadowTokens 一段是 T10 前置半步的锁：契约 v2 四档新投影值 + contact/card 的别名关系
 * + `floating` 的 #18（T2′ 契约批已把 #17 校正为有据 9.4% 的 #18，与 §Elevation 九% 同批）。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { CategoryStyle } from '../../../main/ets/utils/CategoryStyle';
import { QuestionFlowConfig } from '../../../main/ets/common/constants/QuestionFlowConfig';
import { ActivityCategory } from '../../../main/ets/model/Trip';
import { PaceOption, TransitPreference, TravelStyle } from '../../../main/ets/model/PlanParams';
import { MotionTokens, MotionCurves } from '../../../main/ets/design/MotionTokens';
import { ShadowTokens } from '../../../main/ets/design/ShadowTokens';
import { Pressable } from '../../../main/ets/components/Pressable';
import { EmptyState } from '../../../main/ets/components/EmptyState';
import { Skeleton } from '../../../main/ets/components/Skeleton';
import { Separator } from '../../../main/ets/components/Separator';
import { Avatar, AvatarSizes } from '../../../main/ets/components/Avatar';
import { StatRow, StatItem } from '../../../main/ets/components/StatRow';
import { ChipRow, ChipItem } from '../../../main/ets/components/ChipRow';
import { SoftChip, SoftChipTone } from '../../../main/ets/components/SoftChip';
import { FAMILY_PROBE_COMPONENT_COUNT } from './FamilyProbePage';

export default function styleConfigTest(): void {
  describe('CategoryStyle', () => {
    it('five_type_mapping_closed', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 契约活动类型色点五对：景点 primary / 餐饮 bookmark / 住宿 accent_mention /
      // 交通 icon / 休息 faint；第六种用图标或文字，不许新色相
      expect(CategoryStyle.colorName(ActivityCategory.SIGHT)).assertEqual('primary');
      expect(CategoryStyle.colorName(ActivityCategory.FOOD)).assertEqual('bookmark');
      expect(CategoryStyle.colorName(ActivityCategory.HOTEL)).assertEqual('accent_mention');
      expect(CategoryStyle.colorName(ActivityCategory.TRANSPORT)).assertEqual('icon');
      expect(CategoryStyle.colorName(ActivityCategory.REST)).assertEqual('faint');
    });

    it('unknown_category_falls_back_to_sight', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 认不出的类别按景点蓝兜底（与屏8 时间线同一条口径）
      expect(CategoryStyle.colorName(ActivityCategory.SHOP)).assertEqual('primary');
      expect(CategoryStyle.colorName(ActivityCategory.OTHER)).assertEqual('primary');
    });
  });

  describe('QuestionFlowConfig', () => {
    it('four_questions_match_doc', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const qs = QuestionFlowConfig.QUESTIONS;
      expect(qs.length).assertEqual(4);
      expect(qs[0].id).assertEqual('style');
      expect(qs[0].options.length).assertEqual(5);
      expect(qs[1].id).assertEqual('stay');
      expect(qs[1].options.length).assertEqual(3);
      expect(qs[2].id).assertEqual('transit');
      expect(qs[2].options.length).assertEqual(3);
      expect(qs[3].id).assertEqual('pace');
      expect(qs[3].multiSelect).assertTrue();
    });

    it('option_values_hit_model_enums', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 选项 value 必须落在模型枚举里，否则屏3 选了但生成参数对不上
      const styleVals: string[] = [TravelStyle.LEISURE, TravelStyle.FAST_PACE, TravelStyle.FAMILY,
        TravelStyle.FOODIE, TravelStyle.CULTURE];
      for (const opt of QuestionFlowConfig.QUESTIONS[0].options) {
        expect(styleVals.indexOf(opt.value) >= 0).assertTrue();
      }
      const transitVals: string[] = [TransitPreference.PUBLIC, TransitPreference.TAXI_MAIN,
        TransitPreference.CHARTER];
      for (const opt of QuestionFlowConfig.QUESTIONS[2].options) {
        expect(transitVals.indexOf(opt.value) >= 0).assertTrue();
      }
      const paceVals: string[] = [PaceOption.RELAXED, PaceOption.STANDARD, PaceOption.PACKED];
      for (const opt of QuestionFlowConfig.QUESTIONS[3].options) {
        expect(paceVals.indexOf(opt.value) >= 0).assertTrue();
      }
    });

    it('default_values_are_valid_options', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 「用户不操作也能生成」的兜底：每题默认值必须是该题选项之一
      for (const q of QuestionFlowConfig.QUESTIONS) {
        expect(q.defaultValues.length > 0).assertTrue();
        for (const dv of q.defaultValues) {
          const hit = q.options.some((o) => o.value === dv);
          expect(hit).assertTrue();
        }
      }
    });
  });

  describe('MotionTokens', () => {
    it('motion_tiers_match_contract', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // DESIGN.md `motion:` 段逐字对表：press140 / control220 / container320 / shimmer1200 /
      // press-scale 0.97。改这里任一个值必须先改契约，否则 P2 的家族件跟着错档。
      expect(MotionTokens.press).assertEqual(140);
      expect(MotionTokens.control).assertEqual(220);
      expect(MotionTokens.container).assertEqual(320);
      expect(MotionTokens.shimmer).assertEqual(1200);
      expect(MotionTokens.pressScale).assertEqual(0.97);
      // 三条曲线是 curves.cubicBezierCurve 返回的 ICurve（非 Curve 枚举）：
      // 模块一加载就把静态成员算出来，取不到即 §1「自定义贝塞尔可用」这条前提在本机不成立。
      const curvesReady: boolean = MotionCurves.standard !== undefined
        && MotionCurves.decelerate !== undefined && MotionCurves.linear !== undefined;
      expect(curvesReady).assertTrue();
      // 控制点也锁死：只断言 !== undefined 时，把 standard 改成 (0.25, 0.1, 0.25, 1)（CSS ease）
      // 或整条换成 Curve 枚举，今天全绿。ICurve.interpolate(fraction) 把归一化时间打到该曲线上
      // （SDK 声明见 component/common.d.ts 的 `interface ICurve { interpolate(fraction: number): number }`），
      // 于是「曲线指纹」可断言。参考值按 cubic-bezier 逐字算出，与本机实测逐位对表：
      //   standard(0.2,0.8,0.2,1)  f=.25 → 0.767284 / 实测 0.7668588757514954
      //                            f=.50 → 0.946079 / 实测 0.9461418390274048
      //   decelerate(0,0,0.2,1)    f=.50 → 0.839245 / 实测 0.8393326997756958
      //   linear(0,0,1,1)          f=.50 → 0.500000 / 实测 0.5
      //   三档端点实测**不是** 0/1：f=0 → 0.002342033898457885 / 0.00286865234375 / 0.00072479248046875，
      //   f=1 → 0.9999999403953552 / 0.9999998211860657 / 0.9992752075195313——ArkUI 解算器的数值地板。
      //   所以端点判「落在 0/1 附近」而不是逐位等于；hypium 的 assertClose 是**相对**精度
      //   （|actual-expected|/|actual| < precision，见 @ohos/hypium assertClose.js），
      //   拿 0 当期望值时任何非 0 实测都会挂——本机首跑正是这样炸出 0.002342 这条真相的。
      expect(MotionCurves.standard.interpolate(0) <= 0.01).assertTrue();
      expect(MotionCurves.standard.interpolate(1) >= 0.99).assertTrue();
      expect(MotionCurves.linear.interpolate(0) <= 0.01).assertTrue();
      expect(MotionCurves.linear.interpolate(1) >= 0.99).assertTrue();
      // 契约 curve-standard 是快出曲线：中点必须已跑到 0.6 之后
      expect(MotionCurves.standard.interpolate(0.5)).assertLarger(0.6);
      // 指纹区间：precision 0.02 既盖住框架尾差（实测尾差 4e-4 量级），又远小于
      // 「换一档曲线」的量级差——ease(0.25,0.1,0.25,1) 中点 0.8024、decelerate 中点 0.8393，
      // 与 standard 的 0.9461 差 0.11~0.14，改控制点或换成 Curve 枚举必红。
      expect(MotionCurves.standard.interpolate(0.5)).assertClose(0.946079, 0.02);
      expect(MotionCurves.standard.interpolate(0.25)).assertClose(0.767284, 0.02);
      expect(MotionCurves.decelerate.interpolate(0.5)).assertClose(0.839245, 0.02);
      // linear 这条单独放宽 precision（0.001 → 0.005）。理由：assertClose 判的是
      // |actual-expected|/|actual| < precision（hypium 1.0.25 assertClose.js:21-29，分母是**实测值**），
      // 期望 0.5 时 0.001 折算成绝对窗只有 ±0.0005；另三条期望值在 0.77~0.95，0.02 折算成绝对窗
      // 是 ±0.015~±0.019 —— 线性档反而比其他三条紧 30 倍以上。本机 linear 实测恰好 0.5（尾差 0），
      // 但换设备/换 API 版本解算出 0.5006 就会因 0.0006 > 0.0005 判红，那是框架尾差不是缺陷
      // （同一现象在端点断言上已经付过学费，见上面 0.002342 那条真相）。
      // 0.005 → 绝对窗 ±0.0025，5 倍余量；仍比「换一档曲线」的量级差 0.11 小 40 倍以上，
      // 放宽的是噪声窗，没把指纹判据放松到测不出换曲线。
      expect(MotionCurves.linear.interpolate(0.5)).assertClose(0.5, 0.005);
    });
  });

  describe('ShadowTokens', () => {
    it('contract_v2_projection_tiers_locked', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // T10 §0.2 的前置半步：契约 v2 的投影档**先落在代码侧**，四档逐字取有据（shadow.ets）。
      // 简报 §5.3 要求的四条合起来先锁一次（写成一整条与简报逐字对齐的合取式）：
      expect(ShadowTokens.cardContact.radius === 1 && ShadowTokens.cardAmbient.offsetY === 3
        && ShadowTokens.pillFloat.color === '#26000000' && ShadowTokens.none.radius === 0).assertTrue();
      // 再逐字段钉死，防止「只改一个字段仍然满足上面那条合取式」：
      expect(ShadowTokens.none.radius).assertEqual(0);
      expect(ShadowTokens.none.offsetX).assertEqual(0);
      expect(ShadowTokens.none.offsetY).assertEqual(0);
      expect(ShadowTokens.none.color).assertEqual('#00000000');
      expect(ShadowTokens.cardContact.radius).assertEqual(1);
      expect(ShadowTokens.cardContact.offsetX).assertEqual(0);
      expect(ShadowTokens.cardContact.offsetY).assertEqual(0);
      expect(ShadowTokens.cardContact.color).assertEqual('#08000000');
      expect(ShadowTokens.cardAmbient.radius).assertEqual(10);
      expect(ShadowTokens.cardAmbient.offsetX).assertEqual(0);
      expect(ShadowTokens.cardAmbient.offsetY).assertEqual(3);
      expect(ShadowTokens.cardAmbient.color).assertEqual('#12000000');
      expect(ShadowTokens.pillFloat.radius).assertEqual(8);
      expect(ShadowTokens.pillFloat.offsetX).assertEqual(0);
      expect(ShadowTokens.pillFloat.offsetY).assertEqual(3);
      expect(ShadowTokens.pillFloat.color).assertEqual('#26000000');
      // 旧档 radius/offset 一个都没动（现存 4 个页面调用点还在用旧名）；
      // floating.color 是 T2′ 契约批唯一改值：#17→#18（有据 9.4%，对齐 §Elevation "9% black"）。
      expect(ShadowTokens.floating.radius).assertEqual(16);
      expect(ShadowTokens.floating.offsetY).assertEqual(6);
      expect(ShadowTokens.floating.color).assertEqual('#18000000');
      // 旧别名 contact/card 已在 T4 删除（它们与本条下面这两档同值）。
      // 原写法是「按四字段全等锁别名」，其注释自己写明：删别名时这条会编译失败，
      // 那是预期的删除信号而非回归 —— 信号已在 2026-11-03 T4 兑现，故改成直接钉新档的值。
      // 四字段仍逐条钉：tools/audit_elevation.py 的 tokens() 正则认 `名字: { radius: …`，
      // 两条 ElevationSpec 必须各自是内联字面量，不能互相引用。
      expect(ShadowTokens.cardContact.radius).assertEqual(1);
      expect(ShadowTokens.cardContact.offsetX).assertEqual(0);
      expect(ShadowTokens.cardContact.offsetY).assertEqual(0);
      expect(ShadowTokens.cardContact.color).assertEqual('#08000000');
      expect(ShadowTokens.cardAmbient.radius).assertEqual(10);
      expect(ShadowTokens.cardAmbient.offsetX).assertEqual(0);
      expect(ShadowTokens.cardAmbient.offsetY).assertEqual(3);
      expect(ShadowTokens.cardAmbient.color).assertEqual('#12000000');
      // segmented/popover 是「无偏移环境影」两档，elevation 尺也盯着 offsetY；一起钉住：
      expect(ShadowTokens.segmented.offsetY).assertEqual(0);
      expect(ShadowTokens.popover.offsetY).assertEqual(0);
    });
  });

  describe('FamilyComponents', () => {
    it('unmounted_family_pieces_compile_and_keep_contract_sizes',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // T10 的编译图陷阱（报告里取证）：hvigor 的 ArkTS 阶段按**引用可达性**收文件，
      // 一个都没挂载的 @Component 连 filesInfo.txt 都进不去（实测 entry@default 的
      // filesInfo.txt 里有 OptionCard.ets、没有 Pressable.ets/Skeleton.ets），
      // 于是「整仓构建零 error」这句**根本不覆盖这 8 个新文件**。
      // 这里把它们 import 进 ohosTest 的编译图，让 ArkTS 真的类型检查一遍；
      // 下面这些 `: Xxx | undefined = null` 的持有位就是为了不被当无用导入剪掉。
      // 不许反过来用它：件仍然是「已落地未挂载」，app 产物里不该有这些符号。
      const pressableHolder: Pressable | null = null;
      const emptyStateHolder: EmptyState | null = null;
      const skeletonHolder: Skeleton | null = null;
      const separatorHolder: Separator | null = null;
      const avatarHolder: Avatar | null = null;
      const statRowHolder: StatRow | null = null;
      const chipRowHolder: ChipRow | null = null;
      const softChipHolder: SoftChip | null = null;
      expect(pressableHolder === null).assertTrue();
      expect(emptyStateHolder === null).assertTrue();
      expect(skeletonHolder === null).assertTrue();
      expect(separatorHolder === null).assertTrue();
      expect(avatarHolder === null).assertTrue();
      expect(statRowHolder === null).assertTrue();
      expect(chipRowHolder === null).assertTrue();
      expect(softChipHolder === null).assertTrue();
      // 契约 avatar sizes "24px, 40px, 56px"（DESIGN.md:385）——三档封闭，不许长出第四档
      expect(AvatarSizes.SM).assertEqual(24);
      expect(AvatarSizes.MD).assertEqual(40);
      expect(AvatarSizes.LG).assertEqual(56);
      // tag-pill 两档 tone（有据的 danger 档本轮不建：色板没有 danger_tint，
      // 简报 §0.3 把两份 color.json 收在 52/52，加第 53 件属契约改动，随 T2）
      expect(SoftChipTone.NEUTRAL).assertEqual('neutral');
      expect(SoftChipTone.BRAND).assertEqual('brand');
      // 家族件入参形状（字段名写错要到 T2 挂载那一屏才发现，太晚了）
      const chip: ChipItem = { key: 'sight', label: '景点' };
      expect(chip.key).assertEqual('sight');
      expect(chip.label).assertEqual('景点');
      const stat: StatItem = { key: 'trips', value: '12', label: '行程' };
      expect(stat.value).assertEqual('12');
      expect(stat.label).assertEqual('行程');
      // R29 通道：上面那批「类型持有位」只进 tsc 层、不进 emit，ArkUI 装饰器判据对
      // 5 个件（EmptyState/Skeleton/Separator/StatRow/ChipRow）根本不跑。
      // FamilyProbePage 在 build() 里实例化全部 8 件，这里值级引用它导出的常量，
      // 把该页（连同 8 个件）拉进 ohosTest 的 emit——收口判据是 filesInfo.txt 8/8 命中。
      // 该页不注册成用例、不新增 `it`，194 口径不动。
      expect(FAMILY_PROBE_COMPONENT_COUNT).assertEqual(8);
    });
  });
}
