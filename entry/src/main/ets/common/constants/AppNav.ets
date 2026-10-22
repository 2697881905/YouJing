/**
 * 全局导航栈单例（§12 路由表）。
 * @Provide/@Consumer 仅 @ComponentV2 可用，V1 工程统一经本单例取栈；
 * 页面路由名以 handoff §12 路由表为准。
 */

export const APP_NAV: NavPathStack = new NavPathStack();
