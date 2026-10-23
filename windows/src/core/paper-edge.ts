import { Rect } from './layout';
import { DrawingContext } from './drawing';
export interface Point { x: number; y: number }
function random(seed: number): () => number {
  let state = seed >>> 0;
  return () => { state ^= state << 13; state ^= state >>> 17; state ^= state << 5; return (state >>> 0) / 4294967295; };
}
// Seed and spacing depend on proportions, so preview and export retain the same torn silhouette.
export function tornPoints(rect: Rect, depth: number, step: number, seed = 7319): Point[] {
  const d = Math.min(Math.max(0, depth), Math.min(rect.w, rect.h) * .08), rnd = random(seed);
  const corners = [{ x: rect.x, y: rect.y }, { x: rect.x + rect.w, y: rect.y },
    { x: rect.x + rect.w, y: rect.y + rect.h }, { x: rect.x, y: rect.y + rect.h }];
  const normals = [{ x: 0, y: 1 }, { x: -1, y: 0 }, { x: 0, y: -1 }, { x: 1, y: 0 }];
  const points: Point[] = [];
  corners.forEach((a, edge) => {
    const b = corners[(edge + 1) % 4], n = normals[edge];
    const length = Math.hypot(b.x - a.x, b.y - a.y), count = Math.max(12, Math.min(4096, Math.ceil(length / Math.max(.1, step))));
    const anchors = [{ t: 0, inset: d * (.12 + rnd() * .15) }];
    let t = 0;
    while (t < 1) {
      t = Math.min(1, t + (3 + rnd() * 9) / count);
      const notch = rnd() < .14;
      anchors.push({ t, inset: d * (notch ? .78 + rnd() * .22 : .04 + rnd() * .43) });
    }
    let segment = 0;
    for (let i = 0; i < count; i++) {
      const position = i / count;
      while (segment < anchors.length - 2 && anchors[segment + 1].t < position) segment++;
      const from = anchors[segment], to = anchors[segment + 1];
      const mix = (position - from.t) / (to.t - from.t);
      const inset = Math.min(d, Math.max(0, from.inset + (to.inset - from.inset) * mix + (rnd() - .5) * d * .24));
      points.push({ x: a.x + (b.x - a.x) * position + n.x * inset, y: a.y + (b.y - a.y) * position + n.y * inset });
    }
  });
  return points;
}
export function polygon(ctx: DrawingContext, points: Point[]): void {
  ctx.beginPath(); points.forEach((p, i) => { if (i) ctx.lineTo(p.x, p.y); else ctx.moveTo(p.x, p.y); }); ctx.closePath();
}
export function paperFibers(ctx: DrawingContext, points: Point[], width: number, seed: number): void {
  const rnd = random(seed); ctx.save(); ctx.strokeStyle = '#FFFFFF'; ctx.lineCap = 'round';
  points.forEach((a, i) => {
    const b = points[(i + 1) % points.length];
    if (rnd() < .78) {
      ctx.globalAlpha = .38 + rnd() * .50; ctx.lineWidth = width * (.00055 + rnd() * .001);
      ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke();
    }
    if (rnd() < .40) {
      const dx = b.x - a.x, dy = b.y - a.y, length = Math.hypot(dx, dy) || 1, span = width * (.0005 + rnd() * .0019);
      ctx.lineWidth = width * (.00025 + rnd() * .0004); ctx.globalAlpha = .35 + rnd() * .4;
      ctx.beginPath(); ctx.moveTo(a.x + dy / length * span, a.y - dx / length * span);
      ctx.lineTo(a.x - dy / length * span, a.y + dx / length * span); ctx.stroke();
    }
  });
  ctx.restore();
}
