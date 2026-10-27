/**
 * Mock 数据路由开关 · 单点定义。
 *
 * 说明：数据路由将在后续阶段（开发文档 §6 阶段 2「UI 占位 + Mock 数据」）
 * 接入 mock/MockTrip 时生效——data/ 层读取本开关决定走 RDB 还是 Mock。
 * 发布 release 前必须置为 false（列入 Docs/INIT_REPORT.md 发布 checklist）。
 */

export interface MockConfigType {
  USE_MOCK_DATA: boolean;
}

export const MockConfig: MockConfigType = {
  USE_MOCK_DATA: false
};
