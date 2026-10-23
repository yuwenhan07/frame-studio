import { RGB, PaletteOrder, clamp } from './model';

export function hex(c: RGB): string {
  return '#' + [c.r, c.g, c.b].map(v => Math.round(clamp(v, 0, 255)).toString(16).padStart(2, '0')).join('').toUpperCase();
}
export function parseHex(value: string, fraction = 0): RGB | undefined {
  const digits = value.trim().replace(/^#/, '');
  if (!/^[\da-f]{6}$/i.test(digits)) return undefined;
  const n = parseInt(digits, 16);
  return { r: n >> 16, g: n >> 8 & 255, b: n & 255, fraction };
}
export function lightness(c: RGB): number { return .2126 * c.r + .7152 * c.g + .0722 * c.b; }
export function contrastInk(c: RGB): string {
  const linear = (v: number) => v / 255 <= .04045 ? v / 255 / 12.92 : ((v / 255 + .055) / 1.055) ** 2.4;
  return .2126 * linear(c.r) + .7152 * linear(c.g) + .0722 * linear(c.b) > .179 ? '#232623' : '#FFFFFF';
}
interface Sample { r: number; g: number; b: number; weight: number }
function distance(a: Sample, b: Sample): number {
  return .30 * (a.r - b.r) ** 2 + .59 * (a.g - b.g) ** 2 + .11 * (a.b - b.b) ** 2;
}
// Keep first winner on ties, matching Swift's max(by:) traversal over sorted buckets.
function maxBy<T>(items: T[], score: (item: T) => number): T {
  return items.reduce((best, item) => score(item) > score(best) ? item : best);
}
export function extractPalette(rgba: ArrayLike<number>, count: number, order: PaletteOrder = 'lightness'): RGB[] {
  if (rgba.length % 4 !== 0) throw new Error('RGBA 数据长度无效');
  const histogram = new Map<number, { r: number; g: number; b: number; n: number }>();
  for (let i = 0; i < rgba.length; i += 4) {
    const alpha = rgba[i + 3] / 255;
    const r = Math.round(rgba[i] * alpha + 255 * (1 - alpha));
    const g = Math.round(rgba[i + 1] * alpha + 255 * (1 - alpha));
    const b = Math.round(rgba[i + 2] * alpha + 255 * (1 - alpha));
    const key = (r >> 3) << 10 | (g >> 3) << 5 | b >> 3;
    const bucket = histogram.get(key) || { r: 0, g: 0, b: 0, n: 0 };
    bucket.r += r; bucket.g += g; bucket.b += b; bucket.n++;
    histogram.set(key, bucket);
  }
  const samples: Sample[] = [...histogram.entries()].sort((a, b) => a[0] - b[0]).map(([, c]) => (
    { r: c.r / c.n / 255, g: c.g / c.n / 255, b: c.b / c.n / 255, weight: c.n }
  ));
  if (!samples.length) return [];
  const centers = [{ ...maxBy(samples, c => c.weight) }];
  const requested = Math.min(samples.length, Math.round(clamp(count, 1, 8)));
  while (centers.length < requested) {
    const next = maxBy(samples, c => Math.min(...centers.map(x => distance(c, x))) * Math.sqrt(c.weight));
    if (centers.some(c => distance(next, c) <= .000001)) break;
    centers.push({ ...next });
  }
  let weights: number[] = [];
  for (let pass = 0; pass < 18; pass++) {
    const sums = centers.map(() => ({ r: 0, g: 0, b: 0, n: 0 }));
    for (const sample of samples) {
      let index = 0;
      for (let i = 1; i < centers.length; i++) if (distance(sample, centers[i]) < distance(sample, centers[index])) index = i;
      const s = sums[index]; s.r += sample.r * sample.weight; s.g += sample.g * sample.weight;
      s.b += sample.b * sample.weight; s.n += sample.weight;
    }
    let movement = 0;
    for (let i = 0; i < centers.length; i++) if (sums[i].n) {
      const s = sums[i]; const next = { r: s.r / s.n, g: s.g / s.n, b: s.b / s.n, weight: s.n };
      movement = Math.max(movement, distance(centers[i], next)); centers[i] = next;
    }
    weights = sums.map(s => s.n);
    if (movement < .0000001) break;
  }
  const total = weights.reduce((a, b) => a + b, 0); const result: RGB[] = [];
  centers.forEach((c, i) => {
    if (!weights[i]) return;
    const color = { r: Math.round(c.r * 255), g: Math.round(c.g * 255), b: Math.round(c.b * 255), fraction: weights[i] / total };
    const old = result.find(x => hex(x) === hex(color));
    if (old) old.fraction += color.fraction; else result.push(color);
  });
  return result.sort((a, b) => {
    const delta = order === 'lightness' ? lightness(a) - lightness(b) : b.fraction - a.fraction;
    return delta || hex(a).localeCompare(hex(b));
  });
}
function hsv(c: RGB): { h: number; s: number; v: number } {
  const [r, g, b] = [c.r, c.g, c.b].map(v => v / 255);
  const max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min;
  let h = d === 0 ? 0 : max === r ? ((g - b) / d) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
  h = (h / 6 + 1) % 1;
  return { h, s: max === 0 ? 0 : d / max, v: max };
}
export function walkColor(colors: RGB[]): RGB {
  if (!colors.length) colors = [{ r: 128, g: 128, b: 128, fraction: 0 }];
  const dominant = [...colors].sort((a, b) => b.fraction - a.fraction || hex(a).localeCompare(hex(b)))[0];
  const tones = colors.map(c => ({ c, ...hsv(c) })).filter(t => t.s >= .12 && t.v >= .18 && lightness(t.c) < 242);
  let original = dominant;
  if (tones.reduce((a, t) => a + t.c.fraction, 0) >= .15) {
    const family = (t: typeof tones[number]) => tones.filter(x => Math.min(Math.abs(t.h - x.h), 1 - Math.abs(t.h - x.h)) <= .10);
    const score = (t: typeof tones[number]) => family(t).reduce((a, x) => a + x.c.fraction * (.6 + .4 * x.s), 0);
    const winner = tones.reduce((a, b) => score(b) > score(a) || (score(b) === score(a) && b.c.fraction > a.c.fraction) ? b : a);
    const group = family(winner); const total = group.reduce((a, t) => a + t.c.fraction, 0);
    const channel = (key: 'r' | 'g' | 'b') => Math.round(group.reduce((a, t) => a + t.c[key] * t.c.fraction, 0) / total);
    original = { r: channel('r'), g: channel('g'), b: channel('b'), fraction: total };
  }
  const c = [original.r, original.g, original.b].map(v => v / 255);
  const min = Math.min(...c), max = Math.max(...c), l = (min + max) / 2, spread = max - min;
  const lifted = l + Math.min(.035, (1 - l) * .07);
  const saturation = spread > 0 ? spread / (1 - Math.abs(2 * l - 1)) : 0;
  const newSpread = (1 - Math.abs(2 * lifted - 1)) * saturation * .9;
  const values = c.map(v => Math.round(255 * (spread ? lifted - newSpread / 2 + (v - min) / spread * newSpread : lifted)));
  return { r: values[0], g: values[1], b: values[2], fraction: original.fraction };
}
