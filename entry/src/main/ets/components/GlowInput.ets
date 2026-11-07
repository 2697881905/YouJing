/**
 * 统一输入框 · 2026-11-07 按有据 `design/components/GlowInput.ets:52-97` 移植。
 *
 * 默认分支是**官方原生样式**：实色 subtle + 无描边 + 无模糊 + 20 圆角胶囊 + 40vp 高
 * （YU 2026-10-04 改版后的定稿）；`segmentStyle=true` 才走「分段栏同款」玻璃
 * （半透明底 + backdropBlur 20 + 1vp 高光边框），有据当前 0 调用方，本仓保留该档备用。
 *
 * 三条避让：材质生效归零 / 内容区 systemMaterial 不渲染 / API 门禁只住 utils/immersiveMaterial.ets。
 */

import { ColorTokens } from '../design/ColorTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { TypeTokens } from '../design/TypeTokens';
import { GlassTokens } from './GlassTokens';

@Component
export struct GlowInput {
  /** 受控文本：外部 @State 变量经 $ 双向绑定 */
  @Link text: string;
  @Prop placeholder: string = '';
  /** true = 根 Stack 参与 flex 拉伸（Row 内并排）；false = 占满父容器宽 */
  @Prop fillWidth: boolean = true;
  /** 不叫 height：避开 CustomComponent 基类同名成员 */
  @Prop inputHeight: number = LayoutTokens.minTouchTarget - SpaceTokens.xxs;
  @Prop radius: number = RadiusTokens.card;
  @Prop segmentStyle: boolean = false;
  @Prop maxLength: number = 0;
  onChange?: (value: string) => void = undefined;
  onEnter?: () => void = undefined;
  onFocusChanged?: (focused: boolean) => void = undefined;

  private notifyFocus(focused: boolean): void {
    if (this.onFocusChanged !== undefined) {
      this.onFocusChanged(focused);
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      TextInput({ placeholder: this.placeholder, text: this.text })
        .fontFamily(TypeTokens.body.family)
        .direction(Direction.Ltr)
        .fontSize(TypeTokens.body.size)
        .lineHeight(TypeTokens.body.lineHeight)
        .fontColor(ColorTokens.ink)
        .placeholderColor(ColorTokens.muted)
        .width('100%')
        .height(this.inputHeight)
        .backdropBlur(this.segmentStyle ? GlassTokens.SEGMENT_BLUR : 0)
        .backgroundColor(this.segmentStyle ? GlassTokens.SEGMENT_BG : ColorTokens.surfaceSubtle)
        .border({
          width: this.segmentStyle ? LayoutTokens.glassBorderWidth : 0,
          color: GlassTokens.SEGMENT_BORDER,
          style: BorderStyle.Solid
        })
        .borderRadius(this.segmentStyle ? RadiusTokens.card : this.radius)
        .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm, top: 0, bottom: 0 })
        .maxLength(this.maxLength > 0 ? this.maxLength : 2147483647)
        .onChange((value: string): void => {
          this.text = value;
          if (this.onChange !== undefined) {
            this.onChange(value);
          }
        })
        .onSubmit((): void => {
          if (this.onEnter !== undefined) {
            this.onEnter();
          }
        })
        .onFocus((): void => {
          this.notifyFocus(true);
        })
        .onBlur((): void => {
          this.notifyFocus(false);
        })
    }
    .layoutWeight(this.fillWidth ? 1 : 0)
    .width(this.fillWidth ? 'auto' : '100%')
    .height(this.inputHeight)
  }
}
