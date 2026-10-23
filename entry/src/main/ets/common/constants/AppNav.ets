/**
 * 全局导航栈单例（§12 路由表）。
 * @Provide/@Consumer 仅 @ComponentV2 可用，V1 工程统一经本单例取栈；
 * 页面路由名以 handoff §12 路由表为准。
 */

export const APP_NAV: NavPathStack = new NavPathStack();

/**
 * 屏9 编辑页的路由参数（NavDestination 的 param 是 object，这里给一个显式形状，
 * 免得页面各自约定字符串前缀）。dayIndex 从 0 起，与屏8 当前展示的日一致。
 */
export interface EditTarget {
  tripId: string;
  dayIndex: number;
}

/**
 * 屏7 生成受阻的路由参数：把真实错误码与原始诊断带过去，
 * 页面不再念底稿里编造的「伏见稻荷与宇治步行超 90 分钟」。
 */
export interface FailInfo {
  code: number;
  detail: string;
}
