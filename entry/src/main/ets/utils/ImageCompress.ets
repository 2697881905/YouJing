/**
 * 图片压缩 · 2026-11-10 自有据 `utils/image.ets` 搬运（编辑资料页配套）。
 *
 * 选图后长边压缩 + 质量 80% 转 jpeg，同时返回 PixelMap（本地即时预览）与
 * bytes（ jpeg 二进制）。有据用 bytes 走 COS 直传；有径本轮无后端，bytes
 * 在页内直接转 base64 data URI 落本地（ProfileStore.avatar/profileBackground），
 * 共享后端落地时 bytes 原样交给上传链路，压缩这一层不动。
 *
 * photo:// URI 是沙箱受限 URI，必须经由文件描述符打开——直接
 * `image.createImageSource(uri)` 在某些 SDK 返回 undefined（createPixelMap 报错）。
 */

import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';

export interface CompressedImage {
  /** 本地即时预览用 */
  preview: image.PixelMap;
  /** jpeg 二进制（本轮转 base64 落本地；共享后端落地后转上传） */
  bytes: ArrayBuffer;
}

/** 头像专用压缩：最长边默认 512px，避免本地 base64 兜底时体积过大 */
export async function compressAvatar(uri: string, maxEdge: number = 512): Promise<CompressedImage> {
  const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
  let source: image.ImageSource;
  try {
    source = image.createImageSource(file.fd);
  } catch (e) {
    fileIo.closeSync(file);
    throw new Error((e as Error).message);
  }
  try {
    const pixelMap: image.PixelMap = await source.createPixelMap();
    const info = pixelMap.getImageInfoSync();
    const longEdge: number = Math.max(info.size.width, info.size.height);
    if (longEdge > maxEdge) {
      const ratio: number = maxEdge / longEdge;
      await pixelMap.scale(ratio, ratio);
    }
    const packer: image.ImagePacker = image.createImagePacker();
    try {
      const bytes: ArrayBuffer = await packer.packToData(pixelMap, {
        format: 'image/jpeg',
        quality: 80
      });
      return { preview: pixelMap, bytes };
    } finally {
      await packer.release();
    }
  } finally {
    source.release();
    fileIo.closeSync(file);
  }
}

/** base64 data URI（Image 组件可直接渲染，有据降级链路同款来源） */
export function toDataUri(bytes: ArrayBuffer): string {
  const u8: Uint8Array = new Uint8Array(bytes);
  let bin: string = '';
  const chunk: number = 0x8000;
  for (let i = 0; i < u8.length; i += chunk) {
    bin += String.fromCharCode(...u8.subarray(i, i + chunk));
  }
  return 'data:image/jpeg;base64,' + base64Encode(bin);
}

function base64Encode(bin: string): string {
  const table: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let out: string = '';
  for (let i = 0; i < bin.length; i += 3) {
    const b0: number = bin.charCodeAt(i);
    const b1: number = i + 1 < bin.length ? bin.charCodeAt(i + 1) : 0;
    const b2: number = i + 2 < bin.length ? bin.charCodeAt(i + 2) : 0;
    out += table[b0 >> 2];
    out += table[((b0 & 0x03) << 4) | (b1 >> 4)];
    out += i + 1 < bin.length ? table[((b1 & 0x0f) << 2) | (b2 >> 6)] : '=';
    out += i + 2 < bin.length ? table[b2 & 0x3f] : '=';
  }
  return out;
}
