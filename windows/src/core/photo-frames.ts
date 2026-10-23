import { Style } from './model';
import { Layout, Rect } from './layout';
import { DrawingContext, RenderInput, cover, roundedRect, textBox } from './drawing';
import { brandAspect, brandLabel, drawBrand } from './brand';

export function backgroundBlur(style: Style): number | undefined {
  return style.template === 'tickets' ? .025 : style.template === 'softFrame' ? style.softFrame.blur
    : style.template === 'postage' ? style.postage.blur : undefined;
}
function background(ctx: DrawingContext, l: Layout, input: RenderInput, brightness: number): void {
  const r = { x: 0, y: 0, w: l.width, h: l.height };
  cover(ctx, input.background || input.image, input.backgroundWidth || input.imageWidth, input.backgroundHeight || input.imageHeight, r);
  if (brightness) { ctx.save(); ctx.globalAlpha = Math.abs(brightness); ctx.fillStyle = brightness > 0 ? '#FFFFFF' : '#000000'; ctx.fillRect(0, 0, r.w, r.h); ctx.restore(); }
}
function photo(ctx: DrawingContext, r: Rect, input: RenderInput): void {
  ctx.fillStyle = '#FFFFFF'; ctx.fillRect(r.x, r.y, r.w, r.h); ctx.drawImage(input.image, r.x, r.y, r.w, r.h);
}
// Clockwise paper outline with inward semicircles on all four edges and concave corners.
export function postageOutline(ctx: DrawingContext, card: Rect, radius: number): void {
  const x = card.x, y = card.y, right = x + card.w, bottom = y + card.h, corner = radius * 1.6;
  const centers = (length: number): number[] => {
    const available = length - corner * 2, count = Math.max(1, Math.floor(available / (radius * 4.1)));
    return Array.from({ length: count }, (_, i) => corner + available * (i + 1) / (count + 1));
  };
  const cx = centers(card.w), cy = centers(card.h);
  ctx.beginPath(); ctx.moveTo(x + corner, y);
  for (const c of cx) { ctx.lineTo(x + c - radius, y); ctx.arc(x + c, y, radius, Math.PI, 0, true); }
  ctx.lineTo(right - corner, y); ctx.arc(right, y, corner, Math.PI, Math.PI / 2, true);
  for (const c of cy) { ctx.lineTo(right, y + c - radius); ctx.arc(right, y + c, radius, -Math.PI / 2, Math.PI / 2, true); }
  ctx.lineTo(right, bottom - corner); ctx.arc(right, bottom, corner, -Math.PI / 2, -Math.PI, true);
  for (const c of [...cx].reverse()) { ctx.lineTo(x + c + radius, bottom); ctx.arc(x + c, bottom, radius, 0, Math.PI, true); }
  ctx.lineTo(x + corner, bottom); ctx.arc(x, bottom, corner, 0, -Math.PI / 2, true);
  for (const c of [...cy].reverse()) { ctx.lineTo(x, y + c + radius); ctx.arc(x, y + c, radius, Math.PI / 2, -Math.PI / 2, true); }
  ctx.lineTo(x, y + corner); ctx.arc(x, y, corner, Math.PI / 2, 0, true); ctx.closePath();
}
function softFrame(ctx: DrawingContext, l: Layout, style: Style, input: RenderInput): void {
  const s = style.softFrame, w = l.width, p = l.photo, f = l.footer!;
  background(ctx, l, input, s.brightness);
  ctx.save(); ctx.shadowColor = `rgba(0,0,0,${s.shadow})`; ctx.shadowBlur = w * .023; ctx.shadowOffsetY = w * .004;
  roundedRect(ctx, p, w * s.corner); ctx.fillStyle = '#FFFFFF'; ctx.fill(); ctx.restore();
  ctx.save(); roundedRect(ctx, p, w * s.corner); ctx.clip(); photo(ctx, p, input); ctx.restore();
  const ink = s.whiteText ? '#FFFFFF' : '#222222', camera = s.showCamera ? s.camera.trim() : '';
  const hasBrand = s.showBrand && !!brandLabel(s.brand, s.brandText), aspect = brandAspect(s.brand, s.brandText);
  const bh = hasBrand ? Math.min(w * .035 * s.textScale, w * .28 / aspect, f.h * .23) : 0, bw = bh * aspect;
  ctx.save(); ctx.font = `400 ${w * .027 * s.textScale}px ${style.englishFont}`;
  const cw = camera ? Math.min(ctx.measureText(camera).width, w * .86 - bw - (bw ? w * .012 : 0)) : 0;
  ctx.restore();
  const gap = bw && cw ? w * .012 : 0, start = (w - bw - gap - cw) / 2, titleY = f.y + f.h * .39;
  if (hasBrand) drawBrand(ctx, { x: start, y: titleY - bh / 2, w: bw, h: bh }, s.brand, s.brandText, style, s.whiteBrand ? 'white' : 'black');
  if (camera) textBox(ctx, camera, { x: start + bw + gap, y: titleY - f.h * .14, w: cw, h: f.h * .28 }, w * .027 * s.textScale, style, ink);
  if (s.showParameters) textBox(ctx, s.parameters, { x: w * .06, y: f.y + f.h * .60, w: w * .88, h: f.h * .18 }, w * .0205 * s.textScale, style, ink, 'center');
  if (s.showSignature) textBox(ctx, style.signature, { x: w * .06, y: f.y + f.h * .82, w: w * .88, h: f.h * .14 }, w * .012 * style.signatureScale, style, ink, 'center');
}
function postage(ctx: DrawingContext, l: Layout, style: Style, input: RenderInput): void {
  const s = style.postage, w = l.width;
  background(ctx, l, input, s.brightness);
  ctx.save(); ctx.shadowColor = `rgba(0,0,0,${s.shadow})`; ctx.shadowBlur = w * .023; ctx.shadowOffsetY = w * .008;
  postageOutline(ctx, l.card!, l.notch!); ctx.fillStyle = '#FFFEFC'; ctx.fill(); ctx.restore();
  ctx.save(); postageOutline(ctx, l.card!, l.notch!); ctx.clip(); photo(ctx, l.photo, input);
  if (s.variant === 'caption') {
    const f = l.footer!, both = !!s.place.trim() && !!s.customDate.trim();
    textBox(ctx, s.place, { x: f.x, y: f.y + f.h * .07, w: f.w * .97, h: f.h * (both ? .43 : .80) }, w * .037 * s.textScale, style, '#34332F', 'right', true);
    textBox(ctx, s.customDate, { x: f.x, y: f.y + f.h * (both ? .54 : .07), w: f.w * .97, h: f.h * (both ? .36 : .80) }, w * .027 * s.textScale, style, '#34332F', 'right');
  }
  ctx.restore();
}
interface Info { value: string; size: number; color: string; bold?: boolean }
function infoStack(ctx: DrawingContext, rect: Rect, info: Info[], style: Style, align: string): void {
  if (!info.length || rect.w <= 0) return;
  const nominal = info.reduce((n, row) => n + row.size * 1.45, 0), scale = Math.min(1, rect.h / nominal);
  let y = rect.y + (rect.h - nominal * scale) / 2;
  for (const row of info) { const h = row.size * 1.45 * scale; textBox(ctx, row.value, { x: rect.x, y, w: rect.w, h }, row.size * scale, style, row.color, align, row.bold); y += h; }
}
function classic(ctx: DrawingContext, l: Layout, style: Style, input: RenderInput): void {
  const s = style.classic, w = l.width, f = l.footer!, aspect = brandAspect(s.brand, s.brandText), hasBrand = !!brandLabel(s.brand, s.brandText);
  photo(ctx, l.photo, input);
  const rows: Info[] = [];
  const add = (enabled: boolean, value: string, size: number, color: string, bold = false) => { if (enabled && value.trim()) rows.push({ value, size: w * size * s.infoScale, color, bold }); };
  add(s.showCamera, s.camera, .019, '#242424', true); add(s.showParameters, s.parameters, .015, s.arrangement === 'centered' ? '#202020' : '#777777');
  add(s.showDate, s.customDate, .012, '#888888'); add(s.showSignature, style.signature, .012 * style.signatureScale, '#555555');
  const base = w * (s.brand === 'leica' ? .052 : s.arrangement === 'inline' ? .027 : .035) * s.brandScale;
  const mark = (r: Rect) => { if (hasBrand) drawBrand(ctx, r, s.brand, s.brandText, style, s.brandColor ? 'color' : 'black'); };
  ctx.save(); ctx.beginPath(); ctx.rect(f.x, f.y, f.w, f.h); ctx.clip();
  if (s.arrangement === 'centered') {
    let bh = hasBrand ? Math.min(base, w * .70 / aspect) : 0, bw = bh * aspect;
    const gap = bh && rows.length ? w * .014 : 0, rh = rows.reduce((n, row) => n + row.size * 1.45, 0);
    const scale = Math.min(1, f.h * .80 / (bh + gap + rh || 1)); bh *= scale; bw *= scale;
    const y = f.y + (f.h - (bh + gap * scale + rh * scale)) / 2;
    mark({ x: (w - bw) / 2, y, w: bw, h: bh });
    infoStack(ctx, { x: w * .05, y: y + bh + gap * scale, w: w * .90, h: rh * scale }, rows, style, 'center');
  } else if (s.arrangement === 'split') {
    const pad = w * .035, bh = hasBrand ? Math.min(base, f.h * .74, w * .28 / aspect) : 0, bw = bh * aspect;
    mark({ x: w - pad - bw, y: f.y + (f.h - bh) / 2, w: bw, h: bh });
    infoStack(ctx, { x: pad, y: f.y + f.h * .11, w: w - pad * 2 - bw - (bw ? w * .04 : 0), h: f.h * .78 }, rows, style, 'left');
  } else {
    const pad = w * .035, bh = hasBrand ? Math.min(base, f.h * .74, w * .22 / aspect) : 0, bw = bh * aspect;
    mark({ x: pad, y: f.y + (f.h - bh) / 2, w: bw, h: bh });
    const start = pad + bw + (bw && rows.length ? w * .04 : 0), available = w - pad - start;
    if (bw && rows.length) { ctx.strokeStyle = '#D8D8D8'; ctx.lineWidth = w * .0007; ctx.beginPath(); ctx.moveTo(start - w * .02, f.y + f.h * .25); ctx.lineTo(start - w * .02, f.y + f.h * .75); ctx.stroke(); }
    ctx.save();
    const widths = rows.map(row => { ctx.font = `400 ${row.size}px ${style.englishFont}`; return Math.max(row.size, ctx.measureText(row.value).width); });
    ctx.restore();
    const total = widths.reduce((a, b) => a + b, 0), gap = rows.length > 1 ? Math.min(w * .025, available * .06) : 0;
    const scale = Math.min(1, (available - gap * Math.max(0, rows.length - 1)) / (total || 1));
    let x = start;
    rows.forEach((row, i) => { const rw = widths[i] * scale; textBox(ctx, row.value, { x, y: f.y + f.h * .14, w: rw, h: f.h * .72 }, row.size * scale, style, row.color, 'left', row.bold); x += rw + gap; });
  }
  ctx.restore();
}
export function renderPhotoFrame(ctx: DrawingContext, l: Layout, style: Style, input: RenderInput): void {
  if (style.template === 'softFrame') softFrame(ctx, l, style, input);
  else if (style.template === 'postage') postage(ctx, l, style, input);
  else classic(ctx, l, style, input);
}
