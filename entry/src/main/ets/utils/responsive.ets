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
 * 宽屏下的正文最大宽度（vp）。
 * 有径已有 LayoutTokens.contentMaxWidth 这一档，但列表页没消费它——
 * 多列之后仍要给单列长文（行程说明、协议正文）一个可读上限。
 */
export function contentMaxWidthForBreakpoint(bp: string, phoneWidth: number): number {
  if (bp === 'lg') {
    return 880;
  }
  if (bp === 'md') {
    return 680;
  }
  return phoneWidth;
}
