/**
 * 编号落点图钉：把动线序号画进 marker 图标（Map Kit 默认图钉没有序号，
 * 一屏多站时看不出先后，只能靠点选信息窗）。
 *
 * 画法是官方 OffscreenCanvas（ArkUI 自带），产出 image.PixelMap 交给
 * MarkerOptions.icon——不是自绘一套 UI 组件，只是给官方图钉槽位供素材。
 * 结果按「序号 + 颜色」缓存：同一条行程来回切 Day 不重画。
 * 画失败就退回默认图钉，不能让地图整片没点。
 * 本 SDK 的 OffscreenCanvasRenderingContext2D 没有 renderSync()，getPixelMap 直接取绘制结果。
 */

import { image } from '@kit.ImageKit';
import { Logger } from '../common/logger/Logger';

const TAG: string = 'Ui.MapPin';
const PIN_W: number = 72;
const PIN_H: number = 92;
const HEAD_R: number = 28;
const DISC_R: number = 16;
const TAIL_HALF: number = 9;

export class NumberedPin {
  private static readonly cache: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();

  /** brand 用 '#AARRGGBB' 串，与动线同色 */
  static of(index: number, brand: string): image.PixelMap | undefined {
    const key: string = `${index}-${brand}`;
    const hit: image.PixelMap | undefined = NumberedPin.cache.get(key);
    if (hit !== undefined) {
      return hit;
    }
    try {
      const canvas: OffscreenCanvas = new OffscreenCanvas(PIN_W, PIN_H);
      const ctx: OffscreenCanvasRenderingContext2D = canvas.getContext('2d');
      ctx.clearRect(0, 0, PIN_W, PIN_H);
      const cx: number = PIN_W / 2;
      const cy: number = HEAD_R + 2;
      // 尖尾（先画，叠在圆头下面）
      ctx.beginPath();
      ctx.moveTo(cx - TAIL_HALF, cy + HEAD_R - 14);
      ctx.lineTo(cx, PIN_H - 2);
      ctx.lineTo(cx + TAIL_HALF, cy + HEAD_R - 14);
      ctx.closePath();
      ctx.fillStyle = brand;
      ctx.fill();
      // 圆头
      ctx.beginPath();
      ctx.arc(cx, cy, HEAD_R, 0, Math.PI * 2);
      ctx.fillStyle = brand;
      ctx.fill();
      // 白盘 + 序号
      ctx.beginPath();
      ctx.arc(cx, cy, DISC_R, 0, Math.PI * 2);
      ctx.fillStyle = '#FFFFFFFF';
      ctx.fill();
      ctx.fillStyle = brand;
      ctx.font = 'bold 20px sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(`${index}`, cx, cy + 1);
      const pm: image.PixelMap = ctx.getPixelMap(0, 0, PIN_W, PIN_H);
      NumberedPin.cache.set(key, pm);
      return pm;
    } catch (err) {
      Logger.warn(TAG, `编号图钉生成失败，退回默认图钉: ${(err as Error).message}`);
      return undefined;
    }
  }
}
