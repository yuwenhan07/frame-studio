import { code128Patterns } from './barcode-patterns';

export function encodeCode128(value: string): string {
  const text = value.trim();
  if (!/^[\x20-\x7e]{1,48}$/.test(text)) throw new Error('条码请使用 1–48 个英文、数字或半角符号');
  const values = Array.from(text, c => c.charCodeAt(0) - 32);
  const checksum = (104 + values.reduce((sum, n, i) => sum + n * (i + 1), 0)) % 103;
  return '0'.repeat(10) + [104, ...values, checksum, 106].map(n => code128Patterns[n]).join('') + '0'.repeat(10);
}
export function barcodeGeometry(value: string, availableWidth: number, minModule = 1): { bits: string; module: number; width: number } {
  const bits = encodeCode128(value), module = Math.floor(availableWidth / bits.length);
  if (module < minModule) throw new Error('当前条码太密，请提高导出尺寸或缩短内容');
  return { bits, module, width: bits.length * module };
}
