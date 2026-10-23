import { Style, clamp } from './model';
import { isCollection } from './collection-style';
export interface Rect { x: number; y: number; w: number; h: number }
export interface Layout { width: number; height: number; photo: Rect; header?: Rect; footer?: Rect; card?: Rect; border: number;
  photoSlot?: Rect; body?: Rect; stub?: Rect; separatorX?: number; notch?: number; corner?: number; barcode?: Rect; ribbon?: Rect }
export function layout(imageWidth: number, imageHeight: number, s: Style, width = 1000): Layout {
  if (!(imageWidth > 0 && imageHeight > 0 && width >= 64)) throw new Error('图片尺寸无效');
  const w = Math.round(width);
  if (s.template === 'softFrame') {
    const v = s.softFrame, side = w * (imageHeight > imageWidth ? v.portraitMargin : v.margin), top = w * v.top;
    const pw = w - side * 2, ph = pw * imageHeight / imageWidth, fh = w * v.footer;
    return { width: w, height: Math.ceil(top + ph + fh), border: side,
      photo: { x: side, y: top, w: pw, h: ph }, footer: { x: 0, y: top + ph, w, h: fh } };
  }
  if (s.template === 'postage') {
    const v = s.postage, m = w * v.margin, b = w * v.border, fh = v.variant === 'caption' ? w * v.footer : 0;
    const pw = w - 2 * (m + b), ph = pw * imageHeight / imageWidth, ch = ph + 2 * b + fh;
    return { width: w, height: Math.ceil(ch + 2 * m), border: b,
      photo: { x: m + b, y: m + b, w: pw, h: ph }, card: { x: m, y: m, w: w - 2 * m, h: ch },
      footer: { x: m + b, y: m + b + ph, w: pw, h: fh }, notch: Math.min(w * v.perforation, b * .65, Math.min(w - 2 * m, ch) * .08) };
  }
  if (s.template === 'classic') {
    const m = w * s.classic.margin, pw = w - 2 * m, ph = pw * imageHeight / imageWidth, fh = w * s.classic.footer;
    return { width: w, height: Math.ceil(m + ph + fh), border: m,
      photo: { x: m, y: m, w: pw, h: ph }, footer: { x: 0, y: m + ph, w, h: fh } };
  }
  if (s.template === 'walkTicket') {
    const v = s.walkTicket, m = w * v.margin, cw = w - 2 * m, ch = cw * v.aspect, pad = cw * .04;
    const card = { x: m, y: m * .7, w: cw, h: ch };
    const slot = { x: m + pad, y: card.y + pad, w: cw * .305, h: ch - 2 * pad };
    const scale = Math.min(slot.w / imageWidth, slot.h / imageHeight);
    const photo = v.photoMode === 'fill' ? { ...slot } : { x: slot.x + (slot.w - imageWidth * scale) / 2,
      y: slot.y + (slot.h - imageHeight * scale) / 2, w: imageWidth * scale, h: imageHeight * scale };
    const separatorX = m + cw * .74, stub = { x: separatorX, y: card.y, w: m + cw - separatorX, h: ch };
    const barcode = { x: stub.x + stub.w * .63 - w * .0375, y: card.y + ch - pad * .85 - ch * .46, w: w * .075, h: ch * .46 };
    return { width: w, height: Math.ceil(ch + m * 1.4), border: pad, card, photo, photoSlot: slot,
      body: { x: slot.x + slot.w + cw * .035, y: card.y + pad, w: separatorX - slot.x - slot.w - cw * .07, h: ch - 2 * pad },
      stub, separatorX, notch: Math.min(w * .018, ch * .065), corner: Math.min(w * v.corner, pad), barcode,
      ribbon: { x: barcode.x, y: card.y + pad, w: barcode.w, h: ch * .25 } };
  }
  if (isCollection(s.template)) {
    let side = 0, top = 0, bottom = 0, outer = 0;
    switch (s.template) {
      case 'film35': side = w * s.film35.margin; top = bottom = w * s.film35.rail; break;
      case 'gallery': side = w * (s.gallery.margin + (imageHeight > imageWidth ? .02 : 0)); top = side; bottom = w * s.gallery.footer; break;
      case 'editorial': side = w * s.editorial.margin; top = w * s.editorial.header; bottom = w * s.editorial.footer; break;
      case 'instant': outer = w * s.instant.margin; side = outer + w * s.instant.border; top = side; bottom = outer + w * s.instant.footer; break;
      case 'cinema': top = w * s.cinema.top; bottom = w * s.cinema.bottom; break;
      case 'receipt': outer = w * s.receipt.margin; side = outer + w * .035; top = outer + w * .15; bottom = outer + w * s.receipt.footer; break;
      case 'tornPaper': outer = w * s.tornPaper.margin; side = outer + w * s.tornPaper.border; top = side;
        bottom = s.tornPaper.showCaptionArea ? outer + w * s.tornPaper.footer : side; break;
    }
    const pw = w - 2 * side, ph = pw * imageHeight / imageWidth, height = Math.ceil(top + ph + bottom);
    return { width: w, height, border: side - outer, photo: { x: side, y: top, w: pw, h: ph },
      card: { x: outer, y: outer, w: w - 2 * outer, h: height - 2 * outer },
      header: { x: side, y: outer, w: pw, h: top - outer },
      footer: { x: side, y: top + ph, w: pw, h: bottom - outer } };
  }
  if (s.template === 'colorWalk') {
    const h = w * s.walkHeader, photoH = w * imageHeight / imageWidth;
    return { width: w, height: Math.ceil(h + photoH), photo: { x: 0, y: h, w, h: photoH }, header: { x: 0, y: 0, w, h }, border: 0 };
  }
  if (s.template === 'tickets') {
    const m = w * s.ticketMargin, top = m * .7, border = w * .028, footer = w * s.ticketFooter;
    const pw = w - 2 * (m + border), ph = pw * imageHeight / imageWidth;
    return { width: w, height: Math.ceil(ph + border * 2 + footer + top * 2), border,
      photo: { x: m + border, y: top + border, w: pw, h: ph },
      card: { x: m, y: top, w: w - 2 * m, h: ph + border * 2 + footer },
      footer: { x: m + border, y: top + border + ph + border * .7, w: pw, h: footer - border * .7 } };
  }
  const border = w * s.margin, pw = w - border * 2, ph = pw * imageHeight / imageWidth;
  return { width: w, height: Math.ceil(border + ph + w * s.footer), border,
    photo: { x: border, y: border, w: pw, h: ph }, footer: { x: border, y: border + ph, w: pw, h: w * s.footer } };
}
export function layoutForLongEdge(iw: number, ih: number, s: Style, edge: number): Layout {
  const unit = layout(iw, ih, s);
  const width = Math.floor(unit.width * clamp(edge, 256, 4096) / Math.max(unit.width, unit.height));
  if (width < 64) throw new Error('当前图片比例过于狭长，请使用较大尺寸或先调整照片');
  return layout(iw, ih, s, width);
}
export function photoRectContains(layout: Layout, x: number, y: number): boolean {
  const p = layout.photo; return x >= p.x && x <= p.x + p.w && y >= p.y && y <= p.y + p.h;
}
