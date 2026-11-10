/**
 * 动作名 → 线条图标资源映射 · 2026-11-10 自有据 `utils/actionIcons.ets` 搬运（裁键版）。
 *
 * 原样保留 Map + 字面量 $r() 的结构（规避 ArkTS 索引访问禁令、编译期校验资源存在）；
 * 只保留资料区搬运件实际引用的键（draftBox / trash）与兜底链（close_x），
 * 社交域键（like/comment/bookmark…）连同其 svg 未搬——有径没有这些域，键多了
 * 只会让「编译期校验资源存在」变成一句空话。共享资料落地扩键时照有据原表补。
 */

const ACTION_ICONS: Map<string, Resource> = new Map<string, Resource>([
  ['draftBox', $r('app.media.draft_box')],
  ['trash', $r('app.media.set_trash')],
  ['check', $r('app.media.set_edit')],
  ['chevronDown', $r('app.media.chevron_right')],
  ['chevronUp', $r('app.media.chevron_right')],
  ['chevronRight', $r('app.media.chevron_right')]
]);

// 按动作名解析线条图标资源；未命中回退 close（x）
export function resolveActionIcon(name: string): Resource {
  const found: Resource | undefined = ACTION_ICONS.get(name);
  if (found !== undefined) {
    return found;
  }
  return $r('app.media.close_x');
}
