// 家族件探针页：ohosTest 编译图 emit 通道（评审 R29 修法）｜ 状态：不注册成用例、零 app 侧影响 ｜ 契约锚点：3fcc3a62

/**
 * FamilyProbePage —— ohosTest 下的「测试页」：在 build() 里**实例化**全部 8 个家族件
 * （Pressable / EmptyState / Skeleton / Separator / Avatar / StatRow / ChipRow / SoftChip），
 * 唯一目的是把 8 个件文件拉进 ohosTest 编译图的 **emit**（filesInfo.txt +
 * compiler.cache/modules/），让 ArkUI 装饰器/语法判据对它们真跑。
 *
 * 为什么必须「真挂出来」而不是 import（评审 R29 实测）：
 * - 未挂载的 @Component 连 entry@default 编译图都不进（R24，hvigor 按引用可达性收文件）；
 * - 「只按类型引用」（`const holder: Xxx | null = null`）只进 tsc 层、**不进 emit**——
 *   ArkUI 装饰器判据根本不跑：往 EmptyState/Skeleton/Separator/StatRow/ChipRow 这 5 个件
 *   注入被明令禁止的函数型 `@Prop xxx: () => void` → BUILD SUCCESSFUL（静默通过），
 *   同一注入打在 Pressable（有值级引用、在 emit 里）→ 当场报 V1 装饰器错。
 * - ⇒ 只有件在某个被 emit 的模块的 build() 里被真的构造，它才进 emit、受装饰器检查。
 *
 * 边界（本轮硬约束逐条落在这里）：
 * - 不注册进 List.test.ets、不新增任何 `it`——用例口径保持 194；
 * - 不碰 pages/**、本文件只在 ohosTest 模块，app 侧（entry@default）编译图对它零感知，
 *   「已落地未挂载」的像素承诺不破；
 * - ArkTS V1 的坑顺手做成正面示范：
 *   ① `@Prop` 不能装饰函数类型成员——Pressable 的 `action`、ChipRow 的 `onSelect`、
 *      SoftChip 的 `action` 都是**未装饰的普通函数成员**，这里按普通成员传参；
 *   ② 「组件传 UI」的唯一正解是 `@BuilderParam`——本页给 Pressable 的 `content`
 *      传 `this.probeContent`（本文件的 @Builder 方法）；
 *   ③ `@Link` 子件不能有默认值、父侧必须用 `$变量` 绑 @State——ChipRow 的
 *      `selectedIndex: $selectedIndex` 就是这条通道。
 */

import { Pressable } from '../../../main/ets/components/Pressable';
import { EmptyState } from '../../../main/ets/components/EmptyState';
import { Skeleton } from '../../../main/ets/components/Skeleton';
import { Separator } from '../../../main/ets/components/Separator';
import { Avatar, AvatarSizes } from '../../../main/ets/components/Avatar';
import { StatRow, StatItem } from '../../../main/ets/components/StatRow';
import { ChipRow, ChipItem } from '../../../main/ets/components/ChipRow';
import { SoftChip, SoftChipTone } from '../../../main/ets/components/SoftChip';
import { SpaceTokens } from '../../../main/ets/design/SpaceTokens';
import { RadiusTokens } from '../../../main/ets/design/RadiusTokens';
import { TypeTokens } from '../../../main/ets/design/TypeTokens';

/**
 * 探针页实例化的家族件个数。
 * StyleConfig.test.ets 的既有 `it` 值级引用这个常量——这是把本文件（连同它 build()
 * 里值级引用的 8 个件）拉进 emit 的最小合规通道；不新增用例、不改 194 口径。
 */
export const FAMILY_PROBE_COMPONENT_COUNT: number = 8;

const PROBE_CHIPS: ChipItem[] = [
  { key: 'sight', label: '景点' },
  { key: 'food', label: '餐饮' }
];

const PROBE_STATS: StatItem[] = [
  { key: 'trips', value: '12', label: '行程' },
  { key: 'spots', value: '48', label: '站点' }
];

@Component
export struct FamilyProbePage {
  /** ChipRow 的 @Link 另一半：@Link 必须由父侧 @State 经 `$变量` 绑定 */
  @State selectedIndex: number = 0;
  /** 按下计数：证明 Pressable/SoftChip 的函数成员（非 @Prop）通路真的可传 */
  @State pressedCount: number = 0;

  /** @BuilderParam 传参的正解形态：@Builder 方法引用喂给 Pressable.content */
  @Builder
  probeContent(): void {
    Text(`probe ${this.pressedCount}`)
      .fontSize(TypeTokens.small.size)
      .fontWeight(TypeTokens.small.weight)
      .fontFamily(TypeTokens.small.family)
  }

  build() {
    Column({ space: SpaceTokens.md }) {
      // 1/8 Pressable —— @BuilderParam content + 普通函数成员 action
      Pressable({
        content: this.probeContent,
        action: () => {
          this.pressedCount += 1;
        }
      })

      // 2/8 EmptyState —— R28 校正后的落点（muted 图标 + serif title）也一并受检
      EmptyState({
        title: '还没有行程',
        message: '空态探针：图标/主句/解释/出口四段全排一遍',
        actionLabel: '去规划',
        onAction: () => {
          this.pressedCount += 1;
        }
      })

      // 3/8 Skeleton —— 显式传满三个 @Prop，让件内装饰器组合全走一遍
      Skeleton({
        skeletonWidth: '100%',
        skeletonHeight: SpaceTokens.lg,
        radius: RadiusTokens.reason
      })

      // 4/8 Separator —— 无 props，裸构造同样进 emit
      Separator()

      // 5/8 Avatar —— symbol 分支（sys.symbol 资源直收），avatarSize 走封闭三档
      Avatar({
        name: '探针',
        symbol: $r('sys.symbol.info_circle'),
        avatarSize: AvatarSizes.MD
      })

      // 6/8 StatRow —— @Prop items: StatItem[]
      StatRow({ items: PROBE_STATS })

      // 7/8 ChipRow —— @Link（$selectedIndex）+ onSelect 普通函数成员
      ChipRow({
        items: PROBE_CHIPS,
        selectedIndex: $selectedIndex,
        onSelect: (index: number) => {
          this.selectedIndex = index;
        }
      })

      // 8/8 SoftChip —— tone enum + action 普通函数成员
      SoftChip({
        label: '重试',
        tone: SoftChipTone.BRAND,
        action: () => {
          this.pressedCount += 1;
        }
      })
    }
    .width('100%')
  }
}
