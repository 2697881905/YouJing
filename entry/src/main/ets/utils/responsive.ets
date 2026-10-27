import { BP_MD_MIN_VP } from './breakpointCenter';

/**
 * 响应式档位映射（照「有据」utils/responsive.ets 移植，档位按有径的列表形态重定）。
 *
 * 断点源唯一：窗口尺寸监听只在 breakpointCenter.ets 注册一处，
 * 本文件只做「断点 → 档位」的纯映射；消费方用 @StorageProp + @Watch 读，
 * 不允许再各自挂 windowSizeChange。
 *
 * 有径的卡片全是单列 List（全仓零 Grid / 零 lanes），宽屏下会被整屏拉宽、
 * 行长失控，所以这里给的是 List.lanes 的列数，不是 Grid 的列数。
 *
 *   手机竖屏 sm (<600vp)             → 1 列
 *   折叠屏展开 / 平板竖屏 md (600-839) → 2 列
 *   平板横屏 / 2in1 lg (>=840vp)      → 3 列
 */

export function listLanesForBreakpoint(bp: string): number {
  if (bp === 'lg') {
    return 3;
  }
  if (bp === 'md') {
    return 2;
  }
  return 1;
}

/**
 * 单列长文（表单、时间轴、协议正文、分享纸）在宽屏下的最大宽度。
 *
 * 手机竖屏返回 `'100%'`，即不收窄。
 * 上限值刻意由消费方从 `design/LayoutTokens.contentMaxWidth` 传入——
 * ARCHITECTURE §分层规定 `utils/` 只能依赖 `common/`，不得引用 `design/`。
 *
 * 为什么需要它：`List.lanes` 只解决"卡片并几列"，不解决"一行散文有多长"。
 * 折叠屏展开 / 平板上，时间轴与表单没有上限就会被整屏拉宽、行长失控。
 *
 * **md 档单独收成 600vp（= md 下限本身），不是沿用调用方传的 720。**
 * 真机实测（Mate X7 展开，窗口 707vp）：720 这个数比整块屏还宽，
 * `maxWidth: 720` 在整个 md 档（600–720vp）里永远不触发——契约那条
 * "Reading column max 720" 在折叠屏展开态是一句空话，协议正文实测被拉到
 * 658vp（14fp 下约 47 个汉字一行）。md 档用 600 之后，600vp 窗口不受影响
 * （恰好等于档位下限），707vp 窗口收到 600、两侧各留 53vp，读起来是"居中的一栏"
 * 而不是"被整屏拉宽的卡片"。`contentMaxWidth` 保持契约原值不动：它是 lg 及以上的上限。
 */
export function longFormMaxWidth(bp: string, capVp: number): Length {
  if (bp === 'lg') {
    return capVp;
  }
  if (bp === 'md') {
    return BP_MD_MIN_VP;
  }
  return '100%';
}
