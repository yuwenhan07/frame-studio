import { RGB, clamp } from './model';

export interface HSV { h: number; s: number; v: number }
export interface TouchRect { left: number; top: number; width: number; height: number }
export function rgbToHsv(color: RGB, previousHue = 0): HSV {
  const r = clamp(color.r, 0, 255) / 255, g = clamp(color.g, 0, 255) / 255, b = clamp(color.b, 0, 255) / 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b), delta = max - min;
  let h = clamp(previousHue, 0, 360);
  if (delta > 0) {
    h = max === r ? (g - b) / delta : max === g ? (b - r) / delta + 2 : (r - g) / delta + 4;
    h = (h * 60 + 360) % 360;
  }
  return { h, s: max ? delta / max : 0, v: max };
}
export function hsvToRgb(value: HSV): RGB {
  const h = clamp(value.h, 0, 360) % 360 / 60, s = clamp(value.s, 0, 1), v = clamp(value.v, 0, 1);
  const chroma = v * s, x = chroma * (1 - Math.abs(h % 2 - 1)), m = v - chroma;
  const channels = h < 1 ? [chroma, x, 0] : h < 2 ? [x, chroma, 0] : h < 3 ? [0, chroma, x]
    : h < 4 ? [0, x, chroma] : h < 5 ? [x, 0, chroma] : [chroma, 0, x];
  const [r, g, b] = channels.map(n => Math.round((n + m) * 255));
  return { r, g, b, fraction: 0 };
}
// Both WeChat clientX/clientY and boundingClientRect use viewport coordinates.
export function positionInPalette(x: number, y: number, rect: TouchRect): { x: number; y: number } | undefined {
  if (![x, y, rect.left, rect.top, rect.width, rect.height].every(Number.isFinite) || rect.width <= 0 || rect.height <= 0) return undefined;
  return { x: clamp((x - rect.left) / rect.width, 0, 1), y: clamp((y - rect.top) / rect.height, 0, 1) };
}
