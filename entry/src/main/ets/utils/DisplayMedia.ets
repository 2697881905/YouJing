/**
 * 存储图源 → 可渲染地址 · 2026-11-10 建立的适配层（对位有据 services/api
 * 的 resolveDisplayImageUrl）。
 *
 * 有据的存储 ref（COS key）要经后端换签名 URL 才能进 Image；有径本轮图源
 * 是 base64 data URI / 完整 URL（ProfileStore 本地落盘），本身就是可渲染
 * 地址——恒等返回。共享资料落地时把这里换成有据同款解析（存储 ref →
 * 共享服务端 URL），ProfileHeader/EditableProfilePreview 等搬运组件一行不动。
 */

export function resolveDisplayImageUrl(ref: string): string {
  return ref;
}
