/**
 * 金额文案（屏11/屏12/屏15 底稿一律带千分位：`¥16,000`、`¥12,840`、`¥6,400`）。
 *
 * 实现里原来各处都是 `¥${n}` 直拼，四位以上就少一个量级的可读性；
 * 而且六个渲染点各拼各的，改一处漏五处。统一到这里。
 * 不用 `Intl.NumberFormat`：本机未验证它在 ArkTS 严格模式下对 `number` 的行为，
 * 手写分组零依赖。
 */

export class MoneyText {
  /** 分组：1234567 → 1,234,567（负号留在最前，小数部分不分组） */
  static group(n: number): string {
    const neg: boolean = n < 0;
    const text: string = `${Math.abs(Math.trunc(n))}`;
    let out: string = '';
    for (let i = 0; i < text.length; i++) {
      if (i > 0 && (text.length - i) % 3 === 0) {
        out += ',';
      }
      out += text.charAt(i);
    }
    return neg ? `-${out}` : out;
  }

  /** `¥` + 千分位；0 也照样出 `¥0`（空态要能读出"确实没花"，不是缺字段） */
  static yuan(n: number): string {
    return `¥${MoneyText.group(n)}`;
  }
}
