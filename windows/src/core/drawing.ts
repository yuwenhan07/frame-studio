import { RGB, Style } from './model';
import { Rect } from './layout';

// The renderer depends on drawing operations, never on wx, DOM or Apple frameworks.
export interface DrawingContext {
  fillStyle: string; strokeStyle: string; font: string; textAlign: string; textBaseline: string;
  lineWidth: number; globalAlpha: number; shadowBlur: number; shadowOffsetY: number; shadowColor: string;
  imageSmoothingEnabled: boolean; lineCap: string;
  save(): void; restore(): void; beginPath(): void; closePath(): void; clip(): void;
  moveTo(x: number, y: number): void; lineTo(x: number, y: number): void;
  quadraticCurveTo(cpx: number, cpy: number, x: number, y: number): void;
  bezierCurveTo(a: number, b: number, c: number, d: number, x: number, y: number): void;
  arc(x: number, y: number, r: number, start: number, end: number, ccw?: boolean): void;
  rect(x: number, y: number, w: number, h: number): void;
  fill(rule?: 'nonzero' | 'evenodd'): void; stroke(): void; fillRect(x: number, y: number, w: number, h: number): void;
  clearRect(x: number, y: number, w: number, h: number): void;
  scale(x: number, y: number): void; translate(x: number, y: number): void; rotate(angle: number): void; setLineDash(dash: number[]): void;
  drawImage(image: unknown, ...args: number[]): void;
  fillText(text: string, x: number, y: number): void; measureText(text: string): { width: number };
}
export interface RenderInput {
  image: unknown; imageWidth: number; imageHeight: number; background?: unknown;
  backgroundWidth?: number; backgroundHeight?: number; palette: RGB[]; walk: RGB;
}
function fontRuns(text: string, s: Style): { text: string; family: string }[] {
  const runs: { text: string; family: string }[] = [];
  for (const char of text) {
    const chinese = /[\u2e80-\u9fff\uf900-\ufaff\uff01-\uff60]/.test(char) || (char.codePointAt(0) || 0) >= 0x20000;
    const family = chinese ? s.chineseFont : s.englishFont;
    const last = runs[runs.length - 1];
    if (last && last.family === family) last.text += char; else runs.push({ text: char, family });
  }
  return runs;
}
export function text(ctx: DrawingContext, value: string, x: number, y: number, maxWidth: number, size: number,
  s: Style, color = '#262927', align = 'left', bold = false): void {
  if (!(maxWidth > 0 && size > 0)) return;
  const runs = fontRuns(value.replace(/[\r\n]+/g, ' '), s);
  const measure = (fontSize: number) => runs.reduce((sum, run) => {
    ctx.font = `${bold ? '600' : '400'} ${fontSize}px ${run.family}`;
    return sum + ctx.measureText(run.text).width;
  }, 0);
  const measured = measure(size);
  if (measured > maxWidth) size *= maxWidth / measured;
  const total = measure(size);
  let cursor = align === 'center' ? x - total / 2 : align === 'right' ? x - total : x;
  ctx.textAlign = 'left'; ctx.textBaseline = 'middle'; ctx.fillStyle = color;
  for (const run of runs) {
    ctx.font = `${bold ? '600' : '400'} ${size}px ${run.family}`;
    ctx.fillText(run.text, cursor, y); cursor += ctx.measureText(run.text).width;
  }
}
export function cover(ctx: DrawingContext, image: unknown, iw: number, ih: number, rect: Rect): void {
  const scale = Math.max(rect.w / iw, rect.h / ih), w = iw * scale, h = ih * scale;
  ctx.drawImage(image, rect.x + (rect.w - w) / 2, rect.y + (rect.h - h) / 2, w, h);
}
export function roundedRect(ctx: DrawingContext, r: Rect, radius: number): void {
  const d = Math.max(0, Math.min(radius, r.w / 2, r.h / 2)), right = r.x + r.w, bottom = r.y + r.h;
  ctx.beginPath(); ctx.moveTo(r.x + d, r.y); ctx.lineTo(right - d, r.y);
  ctx.quadraticCurveTo(right, r.y, right, r.y + d); ctx.lineTo(right, bottom - d);
  ctx.quadraticCurveTo(right, bottom, right - d, bottom); ctx.lineTo(r.x + d, bottom);
  ctx.quadraticCurveTo(r.x, bottom, r.x, bottom - d); ctx.lineTo(r.x, r.y + d);
  ctx.quadraticCurveTo(r.x, r.y, r.x + d, r.y); ctx.closePath();
}
// Keep every text run inside its allocated area, including oversized or mixed-language titles.
export function textBox(ctx: DrawingContext, value: string, r: Rect, size: number, s: Style,
  color: string, align = 'left', bold = false, family?: string): void {
  if (!(r.w > 0 && r.h > 0) || !value.trim()) return;
  ctx.save(); ctx.beginPath(); ctx.rect(r.x, r.y, r.w, r.h); ctx.clip();
  const x = align === 'center' ? r.x + r.w / 2 : align === 'right' ? r.x + r.w : r.x;
  text(ctx, value, x, r.y + r.h / 2, r.w, Math.min(size, r.h * .82), family ? { ...s, englishFont: family } : s, color, align, bold);
  ctx.restore();
}
