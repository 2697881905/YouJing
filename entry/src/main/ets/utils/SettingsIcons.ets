/**
 * 设置页图标映射 · 2026-11-10 自有据 `utils/settingsIcons.ets` 搬运（裁键版）。
 * 原样保留 Map + 字面量 $r() 结构；本轮只有 EditableProfilePreview 的
 * 「修改背景/修改头像」按钮用到 edit 一键，其余键照有据原表在共享资料
 * 落地时按需补（每键一张 svg，编译期校验存在）。
 */

const SETTINGS_ICONS: Map<string, Resource> = new Map<string, Resource>([
  ['edit', $r('app.media.set_edit')],
  ['chevronRight', $r('app.media.chevron_right')]
]);

// 按名称解析设置页图标资源；未命中回退 chevronRight（箭头），避免空白
export function resolveSettingsIcon(name: string): Resource {
  const found: Resource | undefined = SETTINGS_ICONS.get(name);
  if (found !== undefined) {
    return found;
  }
  return $r('app.media.chevron_right');
}
