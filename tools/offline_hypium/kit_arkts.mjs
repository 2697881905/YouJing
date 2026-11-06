/**
 * `@kit.ArkTS` 的**按名白名单**替身：只映射语义能一一对上的那部分。
 * ArkTS 的 `util.TextEncoder().encodeInto(s)` 返回 Uint8Array（带 byteLength），
 * WHATWG 同名方法是 `encodeInto(input, output)` 返回 {read, written}——语义不同，
 * 所以这里显式实现成 ArkTS 的形状，而不是直接把 node 的 util 透传出去。
 * 白名单之外的名字一律不映射（宁可让套件继续标 SKIP，也不给假信心）。
 */
import nodeUtil from 'node:util';

class ArktsTextEncoder {
  encodeInto(input) {
    return new nodeUtil.TextEncoder().encode(input);
  }

  encode(input) {
    return new nodeUtil.TextEncoder().encode(input);
  }
}

class ArktsTextDecoder {
  constructor(encoding = 'utf-8') {
    this.inner = new nodeUtil.TextDecoder(encoding);
  }

  decodeWithStream(input) {
    return this.inner.decode(input);
  }

  decode(input) {
    return this.inner.decode(input);
  }
}

export const util = {
  TextEncoder: ArktsTextEncoder,
  TextDecoder: ArktsTextDecoder,
  buffer: nodeUtil.buffer
};
