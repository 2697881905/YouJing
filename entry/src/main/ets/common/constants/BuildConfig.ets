/**
 * 构建环境开关 · 全工程唯一定义点（IS_DEBUG / BUILD_MODE_NAME 不得在他处重复定义）。
 *
 * 纪律一：禁止通过 hvigor -p 构建参数透传运行时开关——已验证不可靠
 *（「有据」项目 BUILD_MODE_NAME 教训），环境开关一律以本文件源码常量为准。
 * 纪律二：发布 release 前必须手动翻转 IS_DEBUG 为 false，
 * 并逐项核对 Docs/INIT_REPORT.md 的发布前 checklist。
 */

export interface BuildConfigType {
  IS_DEBUG: boolean;
  BUILD_MODE_NAME: string;
}

export const BuildConfig: BuildConfigType = {
  IS_DEBUG: true,
  BUILD_MODE_NAME: 'debug'
};
