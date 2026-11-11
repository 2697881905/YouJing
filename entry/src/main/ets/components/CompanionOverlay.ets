/**
 * 伴随助手 · 全局浮层（叠加在五 tab 与二级页之上，不重组导航）。
 *
 * 挂载：Index build 的 Navigation 同级 Stack 兄弟（盖住二级页）。默认休眠（无提示、触点收起），
 * 不扰现有 UI。容器 hitTestBehavior=None 让空白处触摸穿透到下层，仅交互件（卡/触点/短语/输入）收命中
 * ——与 dock 覆盖层同形态（Index.mainTabs）。
 *
 * 组成：① 常驻触点（玻璃胶囊，拇指区）② 快捷短语面板（SoftChip，上下文意图一键表达）
 * ③ 文字兜底（GlowInput）④ 请示卡（CompanionCard，有提示时浮出）。
 * 返回键走 overlayBackGuard（Index.onBackPress 优先关本层）。
 *
 * Phase 2 只搭浮层骨架与渲染；点选意图的执行/偏好 recording 由 Phase 3 接 CompanionEngine + SkipPlanner。
 */

import { ColorTokens } from '../design/ColorTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { GlassPillButton } from '../design/GlassPillButton';
import { BOTTOM_BAR_INSET_KEY } from '../utils/navMode';
import { registerOverlayBackGuard, unregisterOverlayBackGuard } from '../utils/overlayBackGuard';
import { CompanionCard } from './CompanionCard';
import { SoftChip, SoftChipTone } from './SoftChip';
import { GlowInput } from './GlowInput';
import { COMPANION_PROMPT_KEY, CompanionStore } from '../companion/CompanionStore';
import { CompanionPrompt } from '../companion/CompanionTypes';

const GUARD_ID: string = 'companionOverlay';
/** 快捷短语（上下文意图，Phase 3 按场景动态化） */
const QUICK_PHRASES: string[] = ['我累了', '附近有啥吃的', '跳过这站', '换个地方', '时间够吗'];

@Component
export struct CompanionOverlay {
  @StorageLink(COMPANION_PROMPT_KEY) promptJson: string = '';
  @StorageProp(BOTTOM_BAR_INSET_KEY) bottomBarInset: number = 0;
  @State private touchOpen: boolean = false;
  @State private inputText: string = '';

  aboutToAppear(): void {
    registerOverlayBackGuard(GUARD_ID, (): boolean => {
      return this.prompt() !== null || this.touchOpen;
    }, (): void => {
      CompanionStore.dismiss();
      this.touchOpen = false;
    });
  }

  aboutToDisappear(): void {
    unregisterOverlayBackGuard(GUARD_ID);
  }

  private prompt(): CompanionPrompt | null {
    if (this.promptJson.length === 0) {
      return null;
    }
    try {
      return JSON.parse(this.promptJson) as CompanionPrompt;
    } catch (err) {
      return null;
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // ④ 请示卡（有提示时浮出，底部让出触点高度）
      if (this.prompt() !== null) {
        Column() {
          CompanionCard({
            prompt: this.prompt()!,
            onSelect: (idx: number): void => {
              // 偏好闭环：记录这次选择（共享 prefs），连续选推荐项会把后续同类决定降为通知
              const p: CompanionPrompt | null = this.prompt();
              if (p !== null && idx >= 0 && idx < p.options.length) {
                const decisionKey: string =
                  p.kind === 'unplanned_arrival' ? 'unplanned_move_tomorrow' : p.kind;
                CompanionStore.prefs.recordChoice(
                  decisionKey, p.options[idx].key, p.options[p.recommendedIndex].key);
                // 执行选项意图（OnTrip 注册的执行器：跨天挪移+撤销）；其余选项确认即可
                CompanionStore.execute(p.options[idx].action);
              }
              CompanionStore.dismiss();
            },
            onDismiss: (): void => {
              CompanionStore.dismiss();
            }
          })
        }
        .width('100%')
        .padding({ left: SpaceTokens.base, right: SpaceTokens.base,
          bottom: this.bottomBarInset + 64 })
        .hitTestBehavior(HitTestMode.None)
      }

      // ②③ 快捷短语面板 + 文字兜底（触点展开时）
      if (this.touchOpen) {
        Column({ space: SpaceTokens.sm }) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(QUICK_PHRASES, (phrase: string) => {
              SoftChip({
                label: phrase,
                tone: SoftChipTone.NEUTRAL,
                action: (): void => {
                  // Phase 3：把短语作为意图接 CompanionEngine；Phase 2 先收起面板
                  this.touchOpen = false;
                }
              })
                .margin({ right: SpaceTokens.xs, bottom: SpaceTokens.xs })
            }, (phrase: string): string => phrase)
          }
          .width('100%')
          GlowInput({
            text: $inputText,
            placeholder: '或直接说/写你想怎样…',
            // fillWidth:false——GlowInput 的 fillWidth 会置 layoutWeight(1)，
            // 在纵向 Column 里会填满剩余高度把面板撑爆；此处要宽 100% 但不纵扩
            fillWidth: false
          })
        }
        .width('100%')
        .padding({ left: SpaceTokens.base, right: SpaceTokens.base,
          bottom: this.bottomBarInset + 64 })
        .hitTestBehavior(HitTestMode.None)
      }

      // ① 常驻触点（右下角拇指区）
      Row() {
        GlassPillButton({
          label: '助手',
          useSystemMaterial: true,
          action: (): void => {
            // 卡与面板互斥：开面板先收卡（避免两层叠在一起）
            if (!this.touchOpen) {
              CompanionStore.dismiss();
            }
            this.touchOpen = !this.touchOpen;
          }
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .padding({ right: SpaceTokens.base, bottom: this.bottomBarInset + SpaceTokens.base })
      .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }
}