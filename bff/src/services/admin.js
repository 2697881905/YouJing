/**
 * 管理员账号白名单（仅本机/联调测试）。
 *
 * 只从环境变量读：`ADMIN_ACCOUNT_IDS=1,2`（account.id，逗号分隔）。
 * 不写数据库、不下发端侧配置，**未设置该变量时功能完全关闭**。
 *
 * 作用范围只有生成额度（`/v1/trip/generate`）：管理员不走 402、端侧权益带 `unlimited`。
 * 导出付费墙、IAP、限流仍按原规则——这里只解决「本机反复生成被额度拦住」。
 */
export function adminAccountIds() {
  return (process.env.ADMIN_ACCOUNT_IDS || '')
    .split(',')
    .map((item) => item.trim())
    .filter((item) => /^\d+$/.test(item))
    .map(Number);
}

export function isAdminAccount(accountId) {
  const id = Number(accountId);
  if (!Number.isInteger(id)) {
    return false;
  }
  return adminAccountIds().includes(id);
}
