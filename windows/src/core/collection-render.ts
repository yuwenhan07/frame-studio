import { renderPhotoFrame } from './photo-frames';
import { Style } from './model';
import { Layout, Rect } from './layout';
import { DrawingContext, RenderInput, cover, roundedRect, textBox } from './drawing';
import { contrastInk, hex, parseHex } from './palette';
import { paperFibers, polygon, tornPoints } from './paper-edge';

const paperColor = (value: string) => value === 'charcoal' ? '#292A29' : value === 'white' ? '#FFFEFC' : '#F7F3EA';
const paperInk = (value: string) => value === 'charcoal' ? '#F2EEE6' : '#34332F';
const box = (r: Rect, x: number, y: number, w: number, h: number): Rect => ({ x: r.x + r.w * x, y: r.y + r.h * y, w: r.w * w, h: r.h * h });
function fill(ctx: DrawingContext, r: Rect, color: string): void { ctx.fillStyle = color; ctx.fillRect(r.x, r.y, r.w, r.h); }
function rule(ctx: DrawingContext, x1: number, y: number, x2: number, color: string, weight: number, dashed = false): void {
  ctx.save(); ctx.strokeStyle = color; ctx.lineWidth = weight;
  if (dashed) ctx.setLineDash([weight * 4.3, weight * 4.3]);
  ctx.beginPath(); ctx.moveTo(x1, y); ctx.lineTo(x2, y); ctx.stroke(); ctx.restore();
}
function outline(ctx: DrawingContext, r: Rect, extra: number, ink: string, width: number): void {
  ctx.save(); ctx.strokeStyle = ink; ctx.lineWidth = width;
  ctx.beginPath(); ctx.rect(r.x - extra, r.y - extra, r.w + extra * 2, r.h + extra * 2); ctx.stroke(); ctx.restore();
}
export function walkTicketOutline(ctx: DrawingContext, l: Layout): void {
  const c = l.card!, x = c.x, y = c.y, right = x + c.w, bottom = y + c.h, r = l.corner!, n = l.notch!, sep = l.separatorX!;
  ctx.beginPath(); ctx.moveTo(x + r, y); ctx.lineTo(sep - n, y);
  ctx.arc(sep, y, n, Math.PI, 0, true); ctx.lineTo(right - r, y);
  ctx.quadraticCurveTo(right, y, right, y + r); ctx.lineTo(right, bottom - r);
  ctx.quadraticCurveTo(right, bottom, right - r, bottom); ctx.lineTo(sep + n, bottom);
  ctx.arc(sep, bottom, n, 0, Math.PI, true); ctx.lineTo(x + r, bottom);
  ctx.quadraticCurveTo(x, bottom, x, bottom - r); ctx.lineTo(x, y + r);
  ctx.quadraticCurveTo(x, y, x + r, y); ctx.closePath();
}
function walkTicket(ctx: DrawingContext, l: Layout, style: Style, input: RenderInput): void {
  const s = style.walkTicket, w = l.width, card = l.card!, body = l.body!, stub = l.stub!;
  const theme: Record<string, string> = { charcoal: '#494644', cream: '#FFFCF5', orange: '#FF884B', brown: '#593600', photo: hex(input.walk), custom: s.customHex };
  const color = theme[s.theme] || '#494644', ink = contrastInk(parseHex(color)!) === '#FFFFFF' ? '#FFFFFF' : '#302E29';
  const secondary = ink + '94';
  fill(ctx, { x: 0, y: 0, w, h: l.height }, '#F8F4EB');
  ctx.save(); ctx.shadowColor = `rgba(0,0,0,${s.shadow})`; ctx.shadowBlur = w * .028; ctx.shadowOffsetY = w * .012;
  walkTicketOutline(ctx, l); ctx.fillStyle = color; ctx.fill(); ctx.restore();
  ctx.save(); walkTicketOutline(ctx, l); ctx.clip();
  ctx.save(); roundedRect(ctx, l.photo, w * .012); ctx.clip(); fill(ctx, l.photo, '#FFFFFF');
  if (s.photoMode === 'fill') cover(ctx, input.image, input.imageWidth, input.imageHeight, l.photoSlot!);
  else ctx.drawImage(input.image, l.photo.x, l.photo.y, l.photo.w, l.photo.h);
  ctx.restore();
  const tb = (center: number, height: number) => ({ x: body.x, y: card.y + card.h * (1 - center - height / 2), w: body.w, h: card.h * height });
  const line = (value: string, r: Rect, size: number, color = ink, font?: string, bold = false) => textBox(ctx, value, r, w * size * s.textScale, style, color, 'left', bold, font);
  line(s.heading, tb(.90, .07), .021);
  line(s.title, tb(.74, .21), .067, ink, s.titleFont, true);
  line(s.subtitle, tb(.56, .10), .027);
  line(s.customDate, tb(.44, .055), .016, secondary, 'monospace');
  line(s.notes, tb(.375, .055), .014, secondary);
  const palette = input.palette.slice(0, 8);
  if (s.showPalette && palette.length) {
    const slot = body.w / palette.length, size = Math.min(w * .048, slot * .80, card.h * .14);
    palette.forEach((color, i) => {
      const r = { x: body.x + slot * i, y: card.y + card.h * .81 - size, w: size, h: size };
      roundedRect(ctx, r, w * .006); ctx.fillStyle = hex(color); ctx.fill(); ctx.strokeStyle = ink + '26'; ctx.lineWidth = w * .0006; ctx.stroke();
      if (s.showHex) textBox(ctx, hex(color), { x: r.x, y: r.y + size + w * .004, w: slot * .94, h: w * .012 }, w * .009, style, secondary, 'left', false, 'monospace');
      const rs = l.ribbon!.w / palette.length;
      fill(ctx, { x: l.ribbon!.x + rs * i, y: l.ribbon!.y, w: rs * .92, h: l.ribbon!.h }, hex(color));
    });
    textBox(ctx, `COLOR CARD · ${palette.length} TONES`, tb(.10, .035), w * .011, style, secondary, 'left', false, 'monospace');
  }
  const dot = w * .0034, first = card.y + l.notch! * 1.6, last = card.y + card.h - l.notch! * 1.6;
  const count = Math.max(2, Math.floor((last - first) / (dot * 3.2)));
  ctx.fillStyle = ink + '6E';
  for (let i = 0; i <= count; i++) { ctx.beginPath(); ctx.arc(l.separatorX!, first + (last - first) * i / count, dot, 0, Math.PI * 2); ctx.fill(); }
  ctx.save(); ctx.translate(stub.x + stub.w * .27, stub.y + stub.h / 2); ctx.rotate(-Math.PI / 2);
  textBox(ctx, s.admission, { x: -card.h * .35, y: -w * .012, w: card.h * .70, h: w * .024 }, w * .013, style, secondary, 'left', false, 'monospace'); ctx.restore();
  if (s.showBarcode) {
    // Deliberate decorative lines; no encoded payload, QR code or backing plate.
    const lengths = [.61,.82,.91,.72,.56,.44,.55,.75,.92,.98,.85,.68,.50,.44,.59,.79,.95,.99,.86,.69,.51,.43,.53,.74,.92,.97,.85,.66,.48,.42,.58,.78,.92,.81,.63,.47];
    const b = l.barcode!; ctx.save(); ctx.beginPath(); ctx.rect(b.x, b.y, b.w, b.h); ctx.clip();
    ctx.strokeStyle = secondary; ctx.lineWidth = Math.max(.5, w * .0016); ctx.lineCap = 'butt'; ctx.beginPath();
    lengths.forEach((length, i) => { const y = b.y + b.h * (i + .5) / lengths.length; ctx.moveTo(b.x, y); ctx.lineTo(b.x + b.w * length, y); });
    ctx.stroke(); ctx.restore();
  }
  textBox(ctx, s.stubCaption, { x: l.barcode!.x - w * .005, y: card.y + card.h * .937, w: stub.x + stub.w - l.barcode!.x - w * .015, h: card.h * .045 }, w * .0105, style, secondary, 'left', false, 'monospace');
  ctx.restore();
}
function receiptOutline(ctx: DrawingContext, r: Rect, tooth: number): void {
  ctx.beginPath(); ctx.moveTo(r.x, r.y); ctx.lineTo(r.x + r.w, r.y); ctx.lineTo(r.x + r.w, r.y + r.h);
  const count = Math.max(4, Math.round(r.w / tooth));
  for (let i = count; i > 0; i--) {
    ctx.lineTo(r.x + r.w * (i - .5) / count, r.y + r.h - tooth * .45);
    ctx.lineTo(r.x + r.w * (i - 1) / count, r.y + r.h);
  }
  ctx.closePath();
}
export function renderCollection(ctx: DrawingContext, l: Layout, style: Style, input: RenderInput): void {
  if (['softFrame', 'postage', 'classic'].includes(style.template)) { renderPhotoFrame(ctx, l, style, input); return; }
  if (style.template === 'walkTicket') { walkTicket(ctx, l, style, input); return; }
  const w = l.width, p = l.photo, f = l.footer!, h = l.header!, card = l.card!;
  const canvas = { x: 0, y: 0, w, h: l.height };
  const wholePhoto = () => { fill(ctx, p, '#FFFFFF'); ctx.drawImage(input.image, p.x, p.y, p.w, p.h); };
  switch (style.template) {
    case 'film35': fill(ctx, canvas, '#161716'); wholePhoto(); break;
    case 'gallery': fill(ctx, canvas, paperColor(style.gallery.paper)); wholePhoto(); break;
    case 'editorial': fill(ctx, canvas, paperColor(style.editorial.paper)); wholePhoto(); break;
    case 'cinema': fill(ctx, canvas, '#141514'); wholePhoto(); break;
    case 'instant':
      fill(ctx, canvas, '#EAE7E0'); ctx.save(); ctx.shadowColor = `rgba(0,0,0,${style.instant.shadow})`;
      ctx.shadowBlur = w * .021; ctx.shadowOffsetY = w * .008; fill(ctx, card, paperColor(style.instant.paper)); ctx.restore(); wholePhoto(); break;
    case 'receipt':
      fill(ctx, canvas, '#DCDAD3'); ctx.save(); ctx.shadowColor = '#0000001F'; ctx.shadowBlur = w * .014; ctx.shadowOffsetY = w * .004;
      receiptOutline(ctx, card, w * .014); ctx.fillStyle = paperColor(style.receipt.paper); ctx.fill(); ctx.restore(); wholePhoto(); break;
    case 'tornPaper': {
      const v = style.tornPaper, depth = w * v.roughness * 4;
      fill(ctx, canvas, '#6A655D');
      const outer = tornPoints(card, depth, w * .0028), inner = tornPoints(p, depth * .68, w * .0025, 3419);
      ctx.save(); ctx.shadowColor = `rgba(0,0,0,${v.shadow})`; ctx.shadowBlur = w * .014; ctx.shadowOffsetY = w * .006;
      polygon(ctx, outer); ctx.fillStyle = paperColor(v.paper); ctx.fill(); ctx.restore();
      paperFibers(ctx, outer, w, 2187);
      ctx.save(); polygon(ctx, outer); ctx.clip(); ctx.save(); polygon(ctx, inner); ctx.clip(); wholePhoto(); ctx.restore();
      paperFibers(ctx, inner, w, 8791); ctx.restore();
      break;
    }
  }
  const line = (value: string, rect: Rect, size: number, ink: string, align = 'left', font?: string) => textBox(ctx, value, rect, w * size, style, ink, align, false, font);
  switch (style.template) {
    case 'film35': {
      const s = style.film35, ink = '#D5A563', scale = s.textScale;
      if (s.showSprockets) {
        const count = Math.max(5, Math.floor(p.w / (w * .062))), slot = p.w / count;
        for (let i = 0; i < count; i++) for (const y of [w * .009, l.height - w * .022]) {
          roundedRect(ctx, { x: p.x + (i + .5) * slot - w * .018, y, w: w * .036, h: w * .013 }, w * .0025);
          ctx.fillStyle = '#E8E3D8'; ctx.fill();
        }
      }
      outline(ctx, p, w * .003, ink + '52', w * .0007);
      line(s.label, { x: p.x, y: p.y - w * .039, w: p.w * .7, h: w * .027 }, .014 * scale, ink, 'left', 'monospace');
      line(s.number ? `${s.number}  ▷` : '', { x: p.x + p.w * .75, y: p.y - w * .039, w: p.w * .25, h: w * .027 }, .014 * scale, ink, 'right', 'monospace');
      if (s.showSignature) line(style.signature, { x: p.x, y: l.height - w * .059, w: p.w * .65, h: w * .029 }, .011 * scale * style.signatureScale, ink);
      line(s.customDate, { x: p.x + p.w * .7, y: l.height - w * .057, w: p.w * .30, h: w * .025 }, .011 * scale, ink, 'right', 'monospace');
      break;
    }
    case 'gallery': {
      const s = style.gallery, ink = paperInk(s.paper), secondary = ink + '94', scale = s.textScale;
      if (s.showOutline) outline(ctx, p, w * .005, ink + '4D', w * .0006);
      line(s.title, box(f, 0, .19, .75, .24), .028 * scale, ink, 'left', s.titleFont);
      line(s.subtitle, box(f, 0, .49, .75, .15), .0125 * scale, secondary);
      line(s.customDate, box(f, 0, .69, .55, .13), .0105 * scale, secondary, 'left', 'monospace');
      if (s.showSignature) line(style.signature, box(f, .60, .64, .40, .18), .014 * scale * style.signatureScale, ink, 'right');
      break;
    }
    case 'editorial': {
      const s = style.editorial, ink = paperInk(s.paper), secondary = ink + '99', scale = s.textScale;
      line('TRAVEL JOURNAL', box(h, 0, .13, .65, .10), .010 * scale, secondary, 'left', 'monospace');
      line(s.edition, box(h, .72, .13, .28, .10), .010 * scale, secondary, 'right', 'monospace');
      line(s.title, box(h, 0, .30, 1, .43), .098 * scale, ink, 'left', s.titleFont);
      line(s.subtitle, box(h, 0, .80, 1, .10), .012 * scale, secondary);
      if (s.showAccent) rule(ctx, p.x, p.y - w * .006, p.x + p.w, s.accent === 'custom' ? s.customHex : hex(input.walk), w * .0025);
      line(s.notes, box(f, 0, .22, .72, .23), .014 * scale, ink);
      line(s.customDate, box(f, 0, .58, .57, .17), .0105 * scale, secondary, 'left', 'monospace');
      if (s.showSignature) line(style.signature, box(f, .66, .54, .34, .21), .013 * scale * style.signatureScale, ink, 'right');
      break;
    }
    case 'instant': {
      const s = style.instant, ink = paperInk(s.paper), scale = s.textScale;
      line(s.caption, box(f, 0, .19, 1, .30), .032 * scale, ink, 'center', s.captionFont);
      line(s.customDate, box(f, 0, .65, .62, .17), .0105 * scale, ink + '8C', 'left', 'monospace');
      if (s.showSignature) line(style.signature, box(f, .66, .63, .34, .20), .014 * scale * style.signatureScale, ink, 'right');
      break;
    }
    case 'cinema': {
      const s = style.cinema, ink = s.ink === 'amber' ? '#DEC992' : '#EEEAE1', scale = s.textScale;
      line(s.scene, box(h, .04, .30, .65, .42), .010 * scale, ink + '85', 'left', 'monospace');
      const signature = s.showSignature && !!style.signature.trim(), safeBottom = Math.max(f.h * .12, signature ? w * .035 : 0);
      const available = f.h * .88 - safeBottom, groupH = Math.min(f.h * .47, available), y = f.y + f.h * .12 + (available - groupH) * s.position;
      line(s.subtitle, { x: w * .065, y: y + groupH * .04, w: w * .87, h: groupH * .48 }, .026 * scale, ink, 'center');
      line(s.translation, { x: w * .065, y: y + groupH * .65, w: w * .87, h: groupH * .35 }, .015 * scale, ink + 'C7', 'center');
      if (s.showSignature) line(style.signature, { x: w * .70, y: l.height - w * .027, w: w * .26, h: w * .019 }, .009 * style.signatureScale, ink + '80', 'right');
      break;
    }
    case 'receipt': {
      const s = style.receipt, ink = paperInk(s.paper), secondary = ink + '9E', scale = s.textScale;
      line(s.title, box(h, 0, .18, 1, .28), .028 * scale, ink, 'center', 'monospace');
      line(s.place, box(h, 0, .61, 1, .17), .013 * scale, secondary, 'center');
      rule(ctx, f.x, f.y + w * .025, f.x + f.w, secondary, w * .0007, true);
      const rows = [['NO.', s.number]]; if (s.customDate) rows.push(['DATE', s.customDate]);
      const rh = Math.min(w * .029, f.h * .43 / rows.length);
      rows.forEach(([key, value], i) => {
        const y = f.y + w * .048 + rh * (i + .24);
        line(key, { x: f.x, y, w: f.w * .21, h: rh * .76 }, .011 * scale, secondary, 'left', 'monospace');
        line(value, { x: f.x + f.w * .24, y, w: f.w * .76, h: rh * .76 }, .012 * scale, ink, 'right', 'monospace');
      });
      rule(ctx, f.x, f.y + f.h * .71, f.x + f.w, secondary, w * .0007, true);
      line(s.note, box(f, 0, .77, 1, .09), .0105 * scale, secondary, 'center', 'monospace');
      if (s.showSignature) line(style.signature, box(f, 0, .88, 1, .075), .012 * scale * style.signatureScale, ink, 'center');
      break;
    }
    case 'tornPaper': {
      const s = style.tornPaper; if (!s.showCaptionArea) break;
      const ink = paperInk(s.paper), scale = s.textScale;
      // Clip captions to paper as well, including the most irregular edge setting.
      ctx.save(); polygon(ctx, tornPoints(card, w * s.roughness * 4, w * .0028)); ctx.clip();
      line(s.caption, box(f, 0, .19, 1, .29), .025 * scale, ink, 'left', s.captionFont);
      line(s.customDate, box(f, 0, .64, .57, .16), .010 * scale, ink + '8C', 'left', 'monospace');
      if (s.showSignature) line(style.signature, box(f, .63, .61, .37, .21), .013 * scale * style.signatureScale, ink, 'right');
      ctx.restore(); break;
    }
  }
}
