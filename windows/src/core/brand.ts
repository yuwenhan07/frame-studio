import { brandMarks } from './brand-marks';
import { brandNames, brandValues } from './collection-style';
import { DrawingContext, textBox } from './drawing';
import { Rect } from './layout';
import { Style } from './model';

const commands = new Map<string, (string | number)[][]>();
function paths(value: string): (string | number)[][] {
  const cached = commands.get(value); if (cached) return cached;
  const tokens = value.split(' '), result: (string | number)[][] = [];
  for (let i = 0; i < tokens.length;) {
    const op = tokens[i++], count = op === 'C' ? 6 : op === 'Q' ? 4 : op === 'Z' ? 0 : 2;
    result.push([op, ...tokens.slice(i, i + count).map(Number)]); i += count;
  }
  commands.set(value, result); return result;
}
export function brandLabel(brand: string, custom: string): string {
  return brand === 'custom' ? custom.trim() : brandNames[brandValues.indexOf(brand)] || '';
}
export function brandAspect(brand: string, custom: string): number {
  const mark = brandMarks[brand];
  return mark ? mark.bounds[2] / mark.bounds[3] : Math.max(1, brandLabel(brand, custom).length * .68);
}
// Vector fills keep their counters and original layering, without runtime SVG or fonts.
export function drawBrand(ctx: DrawingContext, rect: Rect, brand: string, custom: string, style: Style,
  mode: 'color' | 'black' | 'white' = 'color'): void {
  if (!(rect.w > 0 && rect.h > 0)) return;
  const mark = brandMarks[brand];
  if (!mark) { textBox(ctx, brandLabel(brand, custom), rect, rect.h * .95, style, mode === 'white' ? '#FFFFFF' : '#111111', 'center', true); return; }
  const [x, y, width, height] = mark.bounds, scale = Math.min(rect.w / width, rect.h / height);
  ctx.save(); ctx.translate(rect.x + (rect.w - width * scale) / 2, rect.y + (rect.h - height * scale) / 2);
  ctx.scale(scale, scale); ctx.translate(-x, -y);
  for (const layer of mark.layers) {
    ctx.beginPath();
    for (const command of paths(layer.path)) {
      const [op, ...args] = command, n = args as number[];
      if (op === 'M') ctx.moveTo(n[0], n[1]);
      else if (op === 'L') ctx.lineTo(n[0], n[1]);
      else if (op === 'C') ctx.bezierCurveTo(n[0], n[1], n[2], n[3], n[4], n[5]);
      else if (op === 'Q') ctx.quadraticCurveTo(n[0], n[1], n[2], n[3]);
      else ctx.closePath();
    }
    const isWhite = layer.fill === '#FFFFFF';
    ctx.fillStyle = mode === 'color' ? layer.fill : mode === 'white' ? (isWhite ? '#222222' : '#FFFFFF') : (isWhite ? '#FFFFFF' : '#111111');
    ctx.fill(layer.evenOdd ? 'evenodd' : 'nonzero');
  }
  ctx.restore();
}
