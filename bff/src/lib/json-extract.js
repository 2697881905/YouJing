/**
 * 从模型输出里提取**第一个完整的 JSON 对象**。
 *
 * 为什么需要：json_object 模式下模型偶发在 JSON 后面再补一段说明（实测 2026-11-03：
 * `JSON.parse` 报 `Unexpected non-whitespace character after JSON at position 1963`）。
 * 生产此前直接 502 → 端侧整次重试，白烧一次模型调用。这里按**括号深度 + 字符串转义**
 * 扫出第一个可解析对象；解析失败继续找下一个 `{`。
 *
 * 安全边界：只接受**完整闭合**且能被 JSON.parse 的对象；数组、截断片段、坏 JSON 都返回 null，
 * 由调用方按原错误处理。解析出来的东西仍要过 validateTrip，不会因为兜底就放松校验。
 */

export function parseFirstJsonObject(text) {
  const source = typeof text === 'string' ? text : '';
  for (let start = source.indexOf('{'); start >= 0; start = source.indexOf('{', start + 1)) {
    let depth = 0;
    let inString = false;
    let escaped = false;
    for (let i = start; i < source.length; i += 1) {
      const ch = source[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch === '\\') {
          escaped = true;
        } else if (ch === '"') {
          inString = false;
        }
        continue;
      }
      if (ch === '"') {
        inString = true;
      } else if (ch === '{') {
        depth += 1;
      } else if (ch === '}') {
        depth -= 1;
        if (depth === 0) {
          try {
            return JSON.parse(source.slice(start, i + 1));
          } catch (e) {
            break;
          }
        }
      }
    }
  }
  return null;
}
