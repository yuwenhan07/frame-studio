import { CollectionStyles, CollectionTemplate, normalizeCollections } from './collection-style';
export type Template = 'colorWalk' | 'colorCircles' | 'colorSquares' | 'tickets' | CollectionTemplate;
export type PaletteOrder = 'lightness' | 'dominance';
export type Mark = 'stamp' | 'barcode' | 'none';
export interface RGB { r: number; g: number; b: number; fraction: number }
export interface Style extends CollectionStyles {
  template: Template; paletteCount: number; paletteOrder: PaletteOrder;
  margin: number; footer: number; swatch: number; showHex: boolean; diamond: boolean;
  signature: string; signatureScale: number; chineseFont: string; englishFont: string;
  walkHeader: number; walkTextPosition: number; walkTextScale: number;
  walkStamp: string; walkDetail: string; walkInk: 'white' | 'black' | 'auto';
  walkBackground: 'solid' | 'horizontalStripes'; walkStripeCount: number;
  ticketTitle: string; ticketSubtitle: string; ticketDate: string; ticketMark: Mark;
  barcode: string; ticketMargin: number; ticketFooter: number;
}
export interface Photo {
  id: string; path: string; width: number; height: number; orientation: string;
  palette: RGB[]; manualPalette?: RGB[]; walkColor: RGB; manualWalk?: RGB;
  selected: boolean;
}
export const templates: { id: Template; name: string; note: string }[] = [
  { id: 'softFrame', name: '柔焦画框', note: '同源虚化 · 悬浮照片' },
  { id: 'postage', name: '邮票画框', note: '四边齿孔 · 地点与日期' },
  { id: 'classic', name: '经典画框', note: '摄影品牌 · 经典底栏' },
  { id: 'colorWalk', name: 'Color Walk', note: '纯色 · 横向主色条纹' },
  { id: 'colorCircles', name: '圆形色卡', note: '留下照片里的颜色' },
  { id: 'colorSquares', name: '方形色卡', note: '方形与菱形色彩' },
  { id: 'tickets', name: 'Tickets', note: '把旅途收成一张票根' },
  { id: 'walkTicket', name: 'Walk Ticket', note: '漫步日志 · 主色票券' },
  { id: 'film35', name: '胶片相框', note: '齿孔 · 画幅与日期' },
  { id: 'gallery', name: 'Gallery', note: '作品留白 · 画廊装裱' },
  { id: 'editorial', name: 'Editorial', note: '旅行影像 · 杂志刊头' },
  { id: 'instant', name: 'Instant', note: '即时相纸 · 留住此刻' },
  { id: 'cinema', name: 'Cinema', note: '电影黑边 · 双行字幕' },
  { id: 'receipt', name: 'Receipt', note: '记忆小票 · 旅途明细' },
  { id: 'tornPaper', name: '手撕相纸', note: '不规则撕边 · 白色毛边' }
];
export const defaultStyle: Style = {
  ...normalizeCollections({}),
  template: 'colorWalk', paletteCount: 5, paletteOrder: 'lightness', margin: .02,
  footer: .16, swatch: .065, showHex: true, diamond: true,
  signature: '', signatureScale: 1, chineseFont: 'sans-serif', englishFont: 'sans-serif',
  walkHeader: .585, walkTextPosition: .5, walkTextScale: 1,
  walkStamp: 'Stay alive · keep trying', walkDetail: '', walkInk: 'white',
  walkBackground: 'solid', walkStripeCount: 4,
  ticketTitle: 'TICKETS', ticketSubtitle: '', ticketDate: '', ticketMark: 'stamp',
  barcode: 'FRAMESTUDIO', ticketMargin: .17, ticketFooter: .205
};
export function clamp(value: number, low: number, high: number): number {
  return Math.min(high, Math.max(low, Number.isFinite(value) ? value : low));
}
export function normalizeStyle(value: Partial<Style>): Style {
  const s = { ...defaultStyle, ...value, ...normalizeCollections(value) };
  if (String(s.template) === 'contactSheet') s.template = 'film35';
  if (!templates.some(t => t.id === s.template)) s.template = defaultStyle.template;
  s.paletteCount = Math.round(clamp(s.paletteCount, 2, 8));
  s.walkStripeCount = Math.round(clamp(s.walkStripeCount, 2, 8));
  if (!['solid', 'horizontalStripes'].includes(s.walkBackground)) s.walkBackground = 'solid';
  s.margin = clamp(s.margin, 0, .08); s.footer = clamp(s.footer, .10, .30);
  s.swatch = clamp(s.swatch, .03, .12); s.signatureScale = clamp(s.signatureScale, .5, 2);
  s.walkHeader = clamp(s.walkHeader, .25, .9); s.walkTextPosition = clamp(s.walkTextPosition, .15, .85);
  s.walkTextScale = clamp(s.walkTextScale, .5, 2); s.ticketMargin = clamp(s.ticketMargin, .08, .24);
  s.ticketFooter = clamp(s.ticketFooter, .13, .30);
  for (const key of ['signature', 'walkStamp', 'walkDetail', 'ticketTitle', 'ticketSubtitle', 'ticketDate', 'barcode'] as const) {
    s[key] = typeof s[key] === 'string' ? s[key].slice(0, 200) : defaultStyle[key];
  }
  if (!['lightness', 'dominance'].includes(s.paletteOrder)) s.paletteOrder = 'lightness';
  if (!['stamp', 'barcode', 'none'].includes(s.ticketMark)) s.ticketMark = 'stamp';
  if (!['white', 'black', 'auto'].includes(s.walkInk)) s.walkInk = 'white';
  for (const key of ['chineseFont', 'englishFont'] as const) {
    if (!['sans-serif', 'serif', 'monospace'].includes(s[key])) s[key] = 'sans-serif';
  }
  for (const key of ['showHex', 'diamond'] as const) s[key] = typeof s[key] === 'boolean' ? s[key] : defaultStyle[key];
  return s;
}
export function activePaletteCount(s: Style): number {
  return s.template === 'walkTicket' ? s.walkTicket.paletteCount
    : s.template === 'colorWalk' && s.walkBackground === 'horizontalStripes' ? s.walkStripeCount : s.paletteCount;
}
export function effectivePalette(photo: Photo): RGB[] {
  return photo.manualPalette === undefined ? photo.palette : photo.manualPalette;
}
