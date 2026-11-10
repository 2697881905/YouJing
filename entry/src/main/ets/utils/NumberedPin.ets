/**
 * 编号落点图钉：把动线序号画进 marker 图标（Map Kit 默认图钉没有序号，
 * 一屏多站时看不出先后，只能靠点选信息窗）。
 *
 * 画法是官方 OffscreenCanvas（ArkUI 自带），产出 image.PixelMap 交给
 * MarkerOptions.icon——不是自绘一套 UI 组件，只是给官方图钉槽位供素材。
 * 结果按「序号 + 颜色」缓存：同一条行程来回切 Day 不重画。
 * 画失败就退回默认图钉，不能让地图整片没点。
 * 本 SDK 的 OffscreenCanvasRenderingContext2D 没有 renderSync()，getPixelMap 直接取绘制结果。
 *
 * 2026-11-10 重绘（用户「图钉太丑」）：弃大水滴（72×92、头 r28），改 Apple Maps
 * 风格白底数字小徽章——白胶囊 + 品牌色描边 + 细尖角，序号直接印在徽章上。
 * 画布按位数自适应：单位数 38×52、双位数 46×52（Map Kit 实测把 icon 放大
 * ~1.9 倍渲染，单位数显示约 24vp 宽，多站相邻不再糊成一坨蓝）。
 * 数字固定深蓝（白底 6.4:1），描边/尖角跟档位 brand：深色档浅蓝描边在夜图同样醒目。
 */

import { image } from '@kit.ImageKit';
import { Logger } from '../common/logger/Logger';

const TAG: string = 'Ui.MapPin';
const PIN_H: number = 52;
/** 徽章（圆角 = 半高，两端全圆）；宽度按位数给，单位数不撑宽 */
const BADGE_H: number = 30;
const BADGE_Y: number = 2;
const BADGE_W_SINGLE: number = 30;
const BADGE_W_DOUBLE: number = 38;
/** 尖角半宽：细尾，落点精度比旧图钉好 */
const TAIL_HALF: number = 6;
/** 数字固定深蓝：白底上 6.4:1（AAA），两档通用 */
const NUM_COLOR: string = '#FF0050A0';

export class NumberedPin {
  private static readonly cache: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();

  /** brand 用 '#AARRGGBB' 串，与动线同色（描边/尖角用） */
  static of(index: number, brand: string): image.PixelMap | undefined {
    const key: string = `${index}-${brand}`;
    const hit: image.PixelMap | undefined = NumberedPin.cache.get(key);
    if (hit !== undefined) {
      return hit;
    }
    try {
      const badgeW: number = index >= 10 ? BADGE_W_DOUBLE : BADGE_W_SINGLE;
      const pinW: number = badgeW + 8;
      const canvas: OffscreenCanvas = new OffscreenCanvas(pinW, PIN_H);
      const ctx: OffscreenCanvasRenderingContext2D = canvas.getContext('2d');
      ctx.clearRect(0, 0, pinW, PIN_H);
      const cx: number = pinW / 2;
      const badgeX: number = (pinW - badgeW) / 2;
      const cy: number = BADGE_Y + BADGE_H / 2;
      const r: number = BADGE_H / 2;
      // 尖角（先画，顶边被胶囊盖住）：实心 brand，与描边同色
      ctx.beginPath();
      ctx.moveTo(cx - TAIL_HALF, cy + r - 3);
      ctx.lineTo(cx, PIN_H - 2);
      ctx.lineTo(cx + TAIL_HALF, cy + r - 3);
      ctx.closePath();
      ctx.fillStyle = brand;
      ctx.fill();
      // 白底胶囊：两个半圆 + 两条直边（r = 半高，两端全圆）
      const halfStraight: number = badgeW / 2 - r;
      ctx.beginPath();
      ctx.arc(badgeX + r, cy, r, Math.PI / 2, Math.PI * 1.5);
      ctx.arc(badgeX + r + halfStraight * 2, cy, r, Math.PI * 1.5, Math.PI * 2.5);
      ctx.closePath();
      ctx.fillStyle = '#FFFFFFFF';
      ctx.fill();
      ctx.lineWidth = 2;
      ctx.strokeStyle = brand;
      ctx.stroke();
      // 序号直接印在胶囊上，18px 占徽章高 60%，白底不空
      ctx.fillStyle = NUM_COLOR;
      ctx.font = 'bold 18px sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(`${index}`, cx, cy + 1);
      const pm: image.PixelMap = ctx.getPixelMap(0, 0, pinW, PIN_H);
      NumberedPin.cache.set(key, pm);
      return pm;
    } catch (err) {
      Logger.warn(TAG, `编号图钉生成失败，退回默认图钉: ${(err as Error).message}`);
      return undefined;
    }
  }
}
