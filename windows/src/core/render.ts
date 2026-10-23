import { RGB, Style } from './model';
import { Layout, Rect } from './layout';
import { hex, contrastInk } from './palette';
import { barcodeGeometry } from './barcode';
import { DrawingContext, RenderInput, text, cover, textBox } from './drawing';
import { isCollection } from './collection-style';
import { renderCollection } from './collection-render';
export { DrawingContext, RenderInput } from './drawing';

export function ticketOutline(ctx: DrawingContext, l: Layout): void {
  const c = l.card!, radius = Math.min(l.width * .0065, l.border * .48), notch = Math.min(l.width * .014, l.border * .8);
  const count = Math.min(127, Math.max(3, Math.floor(c.w / (radius * 4.4)) | 1));
  const xs = Array.from({ length: count }, (_, i) => c.x + c.w * (i + 1) / (count + 1));
  const separator = l.photo.y + l.photo.h + l.border * .5;
  ctx.beginPath(); ctx.moveTo(c.x, c.y);
  for (const x of xs) { ctx.lineTo(x - radius, c.y); ctx.arc(x, c.y, radius, Math.PI, 0, true); }
  ctx.lineTo(c.x + c.w, c.y); ctx.lineTo(c.x + c.w, separator - notch);
  ctx.arc(c.x + c.w, separator, notch, -Math.PI / 2, Math.PI / 2, true);
  ctx.lineTo(c.x + c.w, c.y + c.h);
  for (const x of [...xs].reverse()) { ctx.lineTo(x + radius, c.y + c.h); ctx.arc(x, c.y + c.h, radius, 0, Math.PI, true); }
  ctx.lineTo(c.x, c.y + c.h); ctx.lineTo(c.x, separator + notch);
  ctx.arc(c.x, separator, notch, Math.PI / 2, -Math.PI / 2, true);
  ctx.closePath();
}
function stamp(ctx: DrawingContext, x: number, y: number, radius: number, s: Style): void {
  ctx.save(); ctx.strokeStyle = '#94A6AC'; ctx.fillStyle = '#94A6AC'; ctx.globalAlpha = .78;
  ctx.lineWidth = Math.max(.7, radius * .018);
  ctx.beginPath(); ctx.arc(x, y, radius, 0, Math.PI * 2); ctx.stroke();
  ctx.beginPath(); ctx.arc(x, y, radius * .76, 0, Math.PI * 2); ctx.stroke();
  for (const [label, top] of [['WORLD POST', true], ['AIR MAIL', false]] as const) {
    Array.from(label).forEach((char, i) => {
      const a = (top ? -Math.PI / 2 : Math.PI / 2) + (i - (label.length - 1) / 2) * .16 * (top ? 1 : -1);
      ctx.save(); ctx.translate(x + Math.cos(a) * radius * .86, y + Math.sin(a) * radius * .86);
      ctx.rotate(a + (top ? Math.PI / 2 : -Math.PI / 2));
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.font = `${radius * .18}px sans-serif`;
      ctx.fillText(char, 0, 0); ctx.restore();
    });
  }
  // Vector airplane avoids dependence on platform-specific emoji fonts.
  ctx.beginPath(); ctx.moveTo(x, y - radius * .34); ctx.lineTo(x + radius * .08, y - radius * .03);
  ctx.lineTo(x + radius * .39, y + radius * .12); ctx.lineTo(x + radius * .39, y + radius * .20);
  ctx.lineTo(x + radius * .08, y + radius * .10); ctx.lineTo(x + radius * .05, y + radius * .30);
  ctx.lineTo(x + radius * .15, y + radius * .35); ctx.lineTo(x - radius * .15, y + radius * .35);
  ctx.lineTo(x - radius * .05, y + radius * .30); ctx.lineTo(x - radius * .08, y + radius * .10);
  ctx.lineTo(x - radius * .39, y + radius * .20); ctx.lineTo(x - radius * .39, y + radius * .12);
  ctx.lineTo(x - radius * .08, y - radius * .03); ctx.closePath(); ctx.fill();
  for (let row = 0; row < 4; row++) {
    ctx.beginPath();
    for (let i = 0; i <= 45; i++) {
      const px = x - radius * 2.5 + i / 45 * radius * 1.7;
      const py = y - radius * .3 + row * radius * .18 + Math.sin(i / 45 * Math.PI * 3) * radius * .11;
      if (!i) ctx.moveTo(px, py); else ctx.lineTo(px, py);
    }
    ctx.stroke();
  }
  ctx.restore();
}
export function render(ctx: DrawingContext, l: Layout, s: Style, input: RenderInput, forExport = false): void {
  const w = l.width, p = l.photo;
  ctx.save(); ctx.clearRect(0, 0, l.width, l.height); ctx.fillStyle = '#FFFFFF'; ctx.fillRect(0, 0, l.width, l.height);
  ctx.imageSmoothingEnabled = true;
  if (isCollection(s.template)) { renderCollection(ctx, l, s, input); ctx.restore(); return; }
  if (s.template === 'tickets') {
    cover(ctx, input.background || input.image, input.backgroundWidth || input.imageWidth,
      input.backgroundHeight || input.imageHeight, { x: 0, y: 0, w, h: l.height });
    ctx.fillStyle = '#000000'; ctx.globalAlpha = .08; ctx.fillRect(0, 0, w, l.height); ctx.globalAlpha = 1;
    ctx.save(); ctx.shadowBlur = w * .027; ctx.shadowOffsetY = w * .012; ctx.shadowColor = '#00000066';
    ticketOutline(ctx, l); ctx.fillStyle = '#FFFFFF'; ctx.fill(); ctx.restore();
    ctx.save(); ticketOutline(ctx, l); ctx.clip(); ctx.drawImage(input.image, p.x, p.y, p.w, p.h); ctx.restore();
    const f = l.footer!, sep = p.y + p.h + l.border * .5;
    ctx.strokeStyle = '#B7BBB8'; ctx.lineWidth = Math.max(1, w * .001); ctx.setLineDash([w * .005, w * .004]);
    ctx.beginPath(); ctx.moveTo(f.x, sep); ctx.lineTo(f.x + f.w, sep); ctx.stroke(); ctx.setLineDash([]);
    const titleW = s.ticketMark === 'none' ? f.w : f.w * .51;
    text(ctx, s.ticketTitle, f.x + w * .008, f.y + f.h * .25, titleW, w * .036, s);
    text(ctx, s.ticketSubtitle, f.x + w * .008, f.y + f.h * .50, titleW, w * .021, s, '#6C706C');
    text(ctx, s.ticketDate, f.x + w * .008, f.y + f.h * .76, titleW, w * .019, s, '#6C706C');
    if (s.ticketMark === 'stamp') stamp(ctx, f.x + f.w * .86, f.y + f.h * .48, Math.min(f.h * .40, f.w * .13), s);
    if (s.ticketMark === 'barcode' && s.barcode.trim()) {
      const available = f.w * .44;
      // Preview permits subpixel bars; export requires at least 2 physical pixels per module.
      const encoded = forExport ? barcodeGeometry(s.barcode, available, 2) : barcodeGeometry(s.barcode, Math.max(available, 2000), 1);
      const module = forExport ? encoded.module : available / encoded.bits.length;
      const bx = forExport ? Math.round(f.x + f.w - encoded.width) : f.x + f.w - available;
      ctx.fillStyle = '#1E211F';
      Array.from(encoded.bits).forEach((bit, i) => { if (bit === '1') ctx.fillRect(bx + i * module, f.y + f.h * .36, module, f.h * .43); });
    }
  } else {
    ctx.drawImage(input.image, p.x, p.y, p.w, p.h);
    if (s.template === 'colorWalk') {
      const h = l.header!, striped = s.walkBackground === 'horizontalStripes';
      const colors = striped ? input.palette.slice(0, 8) : [input.walk];
      // An explicitly emptied stripe palette stays empty; white is its neutral background.
      if (!colors.length) colors.push({ r: 255, g: 255, b: 255, fraction: 0 });
      const bands = colors.map((color, i) => {
        const y = Math.round(h.h * i / colors.length), bottom = i === colors.length - 1 ? h.h : Math.round(h.h * (i + 1) / colors.length);
        return { rect: { x: h.x, y: h.y + y, w: h.w, h: bottom - y }, color };
      });
      for (const band of bands) { ctx.fillStyle = hex(band.color); ctx.fillRect(band.rect.x, band.rect.y, band.rect.w, band.rect.h); }
      let size = w * .043 * s.walkTextScale;
      size *= Math.min(1, h.h * .70 / (size * (s.walkDetail ? 2.2 : 1.25)));
      const groupH = size * (s.walkDetail ? 2.2 : 1.25), half = groupH / 2, padding = h.h * .04;
      const center = Math.max(padding + half, Math.min(h.h - padding - half, h.h * s.walkTextPosition));
      // Clip and redraw the stamp per band: glyphs crossing a dark/light boundary follow both inks.
      for (const band of bands) {
        const ink = s.walkInk === 'auto' ? contrastInk(band.color) : s.walkInk === 'black' ? '#232623' : '#FFFFFF';
        ctx.save(); ctx.beginPath(); ctx.rect(band.rect.x, band.rect.y, band.rect.w, band.rect.h); ctx.clip();
        textBox(ctx, s.walkStamp, { x: w * .06, y: center - half, w: w * .88, h: size * 1.25 }, size, s, ink, 'center', true);
        if (s.walkDetail) textBox(ctx, s.walkDetail, { x: w * .06, y: center - half + size * 1.35, w: w * .88, h: size * .85 }, size * .73, s, ink, 'center');
        ctx.restore();
      }
    } else {
      const f = l.footer!, count = input.palette.length, slot = count ? f.w / count : f.w;
      const size = Math.min(w * s.swatch, slot * .65, f.h * (s.showHex ? .43 : .64));
      input.palette.forEach((color, i) => {
        const x = f.x + slot * (i + .5), y = f.y + f.h * (s.showHex ? .42 : .5);
        ctx.save(); ctx.fillStyle = hex(color); ctx.translate(x, y); ctx.beginPath();
        if (s.template === 'colorCircles') ctx.arc(0, 0, size / 2, 0, Math.PI * 2);
        else { if (s.diamond) ctx.rotate(Math.PI / 4); ctx.rect(-size / 2, -size / 2, size, size); }
        ctx.fill(); ctx.restore();
        if (s.showHex) text(ctx, hex(color), x, f.y + f.h * .80, slot * .88, Math.min(w * .017, slot * .12), s, '#262927', 'center');
      });
    }
  }
  if (s.signature) {
    ctx.save(); ctx.shadowColor = '#00000088'; ctx.shadowBlur = w * .004;
    text(ctx, s.signature, p.x + p.w / 2, p.y + p.h - w * .027, p.w * .9,
      Math.min(w * .018 * s.signatureScale, p.h * .12), s, '#FFFFFF', 'center'); ctx.restore();
  }
  ctx.restore();
}
