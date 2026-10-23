import { templates, normalizeStyle, defaultStyle, Style, RGB, activePaletteCount } from './core/model';
import { collectionFields, isCollection, visibleFields, Field, brandValues } from './core/collection-style';
import { hex, parseHex } from './core/palette';
import { renderPhoto, analyzePhoto, clearImageCache } from './imaging';

type Metadata = { brand: string; camera: string; parameters: string; date: string };
type ImportedPhoto = { id: string; name: string; path: string; dataUrl: string; width: number; height: number; metadata: Metadata; changed?: boolean };
type Photo = Partial<ImportedPhoto> & { id: string; selected: boolean; manualPalette?: RGB[]; manualWalk?: RGB; edits?: Metadata };
type State = { photos: Photo[]; currentId: string; style: Style; format: 'jpeg' | 'png'; longEdge: number };
type ImportResult = { photos: ImportedPhoto[]; errors: string[] };
interface FrameAPI {
  importPhotos(): Promise<ImportResult>;
  importDropped(files: File[]): Promise<ImportResult>;
  loadSession(): Promise<{ state: State | null; photos: ImportedPhoto[]; errors: string[] }>;
  loadSample(): Promise<ImportResult>;
  saveSession(state: unknown): Promise<void>;
  chooseExportFolder(): Promise<string | null>;
  exportPhoto(input: { dataUrl: string; photoId: string; format: string }): Promise<{ path?: string; canceled?: boolean }>;
  exportToFolder(input: { dataUrl: string; photoId: string; format: string; folder: string }): Promise<{ path: string }>;
  onBeforeClose(callback: () => void): void;
  confirmClose(): void;
}
declare global { interface Window { frameStudio: FrameAPI } }
const api = window.frameStudio;
const el = <T extends HTMLElement = HTMLElement>(id: string): T => document.getElementById(id) as T;
const status = (message: string, error = false): void => { el('status').textContent = message; el('status').classList.toggle('error', error); el('status').title = message; };
const errorText = (e: unknown): string => e instanceof Error ? e.message : String(e);
let state: State = { photos: [], currentId: '', style: normalizeStyle({}), format: 'jpeg', longEdge: 3840 };
let ready = false, working = false, cancelled = false, previewTicket = 0;
let closing = false;
const idleWaiters: (() => void)[] = [];
function finishWork(): void { working = false; updateActions(); idleWaiters.splice(0).forEach(resolve => resolve()); }
let saveQueue: Promise<void> = Promise.resolve();
let pendingSaveError: unknown = null;
const current = (): Photo | undefined => state.photos.find(p => p.id === state.currentId);
function snapshot(): unknown {
  return { ...state, photos: state.photos.map(({ id, selected, manualPalette, manualWalk, edits, name }) => ({ id, selected, manualPalette, manualWalk, edits, name })) };
}
function save(): Promise<void> {
  if (!ready) return Promise.resolve();
  const data = snapshot();
  el('save-status').textContent = '正在保存…';
  const result = saveQueue.catch(() => undefined).then(() => api.saveSession(data));
  saveQueue = result;
  void result.then(() => { pendingSaveError = null; el('save-status').textContent = '已自动保存'; }, e => {
    pendingSaveError = e; el('save-status').textContent = '保存失败'; status(`无法保存编辑记录：${errorText(e)}`, true);
  });
  return result;
}
function changed(): void { void save().catch(() => undefined); void preview(); }
function button(text: string, action: () => void, className = ''): HTMLButtonElement {
  const b = document.createElement('button'); b.textContent = text; b.className = className; b.onclick = action; return b;
}
function rebuildPhotos(): void {
  el('photos').replaceChildren();
  for (const photo of state.photos) {
    const row = document.createElement('div'); row.className = 'photo-row' + (photo.id === state.currentId ? ' active' : '');
    row.tabIndex = 0; row.setAttribute('role', 'button'); row.setAttribute('aria-label', photo.name || '照片暂时失联');
    const check = document.createElement('input'); check.type = 'checkbox'; check.checked = photo.selected;
    check.setAttribute('aria-label', `选择 ${photo.name || '照片'}`);
    check.onclick = e => e.stopPropagation(); check.onchange = () => { photo.selected = check.checked; void save().catch(() => undefined); updateActions(); };
    const img = document.createElement('img'); img.loading = 'lazy'; img.decoding = 'async'; if (photo.dataUrl) img.src = photo.dataUrl; img.alt = '';
    const name = document.createElement('span'); name.className = 'name'; name.textContent = (photo.name || '照片') + (photo.dataUrl ? '' : '（原片失联）');
    row.append(check, img, name);
    const select = (): void => { if (working) return; state.currentId = photo.id; rebuildPhotos(); rebuildMetadata(); changed(); };
    row.onclick = select; row.onkeydown = e => { if (e.target === row && (e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); select(); } };
    el('photos').append(row);
  }
  el('photo-count').textContent = `${state.photos.length} 张`; updateActions();
}
function updateActions(): void {
  for (const id of ['import', 'remove', 'select-all', 'invert', 'reset']) el<HTMLButtonElement>(id).disabled = working || !ready || closing;
  el<HTMLButtonElement>('export').disabled = working || !ready || !current()?.dataUrl;
  const count = state.photos.filter(p => p.selected).length;
  el<HTMLButtonElement>('batch').disabled = working || !ready || count === 0;
  el('batch').textContent = count ? `导出已选 · ${count} 张` : '导出已选';
  el('cancel').hidden = !working;
  for (const node of document.querySelectorAll<HTMLInputElement | HTMLButtonElement | HTMLSelectElement>('.inspector input,.inspector button,.inspector select,.photo-row input')) node.disabled = working || !ready;
}
function rebuildTemplates(): void {
  el('templates').replaceChildren(...templates.map(t => {
    const b = button(t.name, () => { state.style.template = t.id; rebuildTemplates(); rebuildFields(); changed(); }, state.style.template === t.id ? 'active' : '');
    b.dataset.template = t.id; b.title = t.note; return b;
  }));
  el('template-note').textContent = templates.find(t => t.id === state.style.template)?.note || '';
}
const field = (key: string, title: string, type: Field['type'], extra: Partial<Field> = {}): Field => ({ key, title, type, ...extra });
const number = (key: string, title: string, min: number, max: number, step = .01): Field => field(key, title, 'number', { min, max, step });
const choice = (key: string, title: string, options: string[], labels: string[]): Field => field(key, title, 'choice', { options, labels });
function topFields(): Field[] {
  const s = state.style;
  if (s.template === 'colorWalk') return [field('walkStamp', '主文字', 'text'), field('walkDetail', '第二行（空白时使用拍摄日期）', 'text'),
    choice('walkBackground', '色面', ['solid', 'horizontalStripes'], ['纯色', '主色条纹']), number('walkStripeCount', '条纹数量', 2, 8, 1),
    number('walkHeader', '色面高度', .25, .9), number('walkTextPosition', '文字上下位置', .15, .85), number('walkTextScale', '盖章字号', .5, 2, .05),
    choice('walkInk', '文字颜色', ['white', 'black', 'auto'], ['白色', '黑色', '自动对比'])];
  if (s.template === 'tickets') return [field('ticketTitle', '主标题', 'text'), field('ticketSubtitle', '地点或副标题', 'text'), field('ticketDate', '日期（空白时使用拍摄日期）', 'text'),
    choice('ticketMark', '贴印', ['stamp', 'barcode', 'none'], ['邮戳', 'Code 128 条码', '无']), field('barcode', '条码文字（英文与数字）', 'text'), number('ticketMargin', '留白', .08, .24), number('ticketFooter', '票尾高度', .13, .3)];
  return [number('paletteCount', '取色数量', 2, 8, 1), choice('paletteOrder', '颜色顺序', ['lightness', 'dominance'], ['明暗', '面积占比']),
    field('showHex', '显示 HEX 色号', 'flag'), ...(s.template === 'colorSquares' ? [field('diamond', '菱形色块', 'flag')] : []),
    number('margin', '照片白边', 0, .08, .001), number('footer', '底栏高度', .1, .3), number('swatch', '色块大小', .03, .12, .005)];
}
function makeField(f: Field, value: unknown, onChange: (value: string | number | boolean) => void, resetValue?: unknown): HTMLLabelElement {
  const label = document.createElement('label');
  const heading = document.createElement('span'); heading.textContent = f.title; heading.className = 'field-heading'; label.append(heading);
  if (f.type === 'choice') {
    const input = document.createElement('select'); input.setAttribute('aria-label', f.title);
    f.options!.forEach((v, i) => { const o = document.createElement('option'); o.value = v; o.textContent = f.labels?.[i] || v; input.append(o); });
    input.value = String(value); input.onchange = () => onChange(input.value); label.append(input);
  } else {
    const input = document.createElement('input'); input.setAttribute('aria-label', f.title);
    input.type = f.type === 'flag' ? 'checkbox' : f.type === 'number' ? 'range' : 'text';
    if (f.type === 'flag') { label.className = 'toggle'; input.checked = Boolean(value); input.onchange = () => onChange(input.checked); }
    else if (f.type === 'number') {
      input.min = String(f.min); input.max = String(f.max); input.step = String(f.step || .01); input.value = String(value);
      const output = document.createElement('output'); output.textContent = Number(value).toFixed(f.step && f.step < .001 ? 4 : 3).replace(/\.?0+$/, '');
      output.title = '双击恢复默认'; heading.append(output);
      input.oninput = () => { output.textContent = input.value; onChange(Number(input.value)); };
      output.ondblclick = () => { if (resetValue !== undefined) { input.value = String(resetValue); output.textContent = input.value; onChange(Number(resetValue)); } };
    } else {
      input.maxLength = 200; input.value = typeof value === 'string' ? value : '';
      const apply = (): void => { if (f.type === 'hex' && !/^#?[0-9a-f]{6}$/i.test(input.value.trim())) return; onChange(input.value); };
      input.oninput = apply;
      input.onchange = () => { if (f.type === 'hex' && !/^#?[0-9a-f]{6}$/i.test(input.value.trim())) { status('请输入六位 HEX 色号，例如 #8B7565', true); input.value = String(value); return; } apply(); };
    }
    label.append(input);
  }
  return label;
}
function rebuildFields(): void {
  const s = state.style, id = s.template;
  const shared = [field('signature', '个人落款', 'text'), number('signatureScale', '落款字号', .5, 2, .05),
    choice('chineseFont', '中文字体', ['sans-serif', 'serif', 'monospace'], ['系统黑体', '系统宋体', '等宽字体']),
    choice('englishFont', '英文字体', ['sans-serif', 'serif', 'monospace'], ['无衬线', '衬线', '等宽'])];
  const fields = el('fields'); fields.replaceChildren();
  const add = (f: Field, nested: boolean): void => {
    const obj = (nested ? s[id as keyof Style] : s) as unknown as Record<string, unknown>;
    const defaults = (nested ? defaultStyle[id as keyof Style] : defaultStyle) as unknown as Record<string, unknown>;
    fields.append(makeField(f, obj[f.key], value => {
      obj[f.key] = value; state.style = normalizeStyle(s);
      if (f.type === 'flag' || f.type === 'choice') rebuildFields();
      changed();
    }, defaults[f.key]));
  };
  if (isCollection(id)) for (const f of visibleFields(id, s[id])) {
    // EXIF values and per-photo corrections live in their own panel.
    if (['camera', 'parameters', 'brand', 'brandText'].includes(f.key)) continue;
    add(f, true);
  } else for (const f of topFields()) add(f, false);
  for (const f of shared) add(f, false);
}
function rebuildMetadata(): void {
  const p = current(); el('metadata').replaceChildren(); if (!p) return;
  const data = p.edits || p.metadata || { brand: '', camera: '', parameters: '', date: '' };
  for (const [key, title] of [['brand', '相机品牌'], ['camera', '相机型号'], ['parameters', '焦距 / 光圈 / 快门 / ISO'], ['date', '拍摄日期']] as const) {
    el('metadata').append(makeField(field(key, title, 'text'), data[key], value => { p.edits = { ...data, ...(p.edits || {}), [key]: String(value) }; changed(); }));
  }
}
function photoStyle(photo: Photo, input = state.style): Style {
  const s = normalizeStyle(input), m = photo.edits || photo.metadata || { brand: '', camera: '', parameters: '', date: '' };
  const normalized = m.brand.toLowerCase().replace(/[^a-z0-9]/g, '');
  let brand = brandValues.find(b => b !== 'custom' && normalized.includes(b.toLowerCase())) || 'custom';
  if (normalized.includes('panasonic')) brand = 'lumix';
  for (const id of ['softFrame', 'classic'] as const) { s[id].brand = brand; s[id].brandText = m.brand; s[id].camera = m.camera; s[id].parameters = m.parameters; }
  for (const id of Object.keys(collectionFields)) {
    const settings = s[id as keyof Style] as unknown as Record<string, unknown>;
    if ('customDate' in settings && !settings.customDate) settings.customDate = m.date;
  }
  if (!s.walkDetail) s.walkDetail = m.date;
  if (!s.ticketDate) s.ticketDate = m.date;
  return s;
}
async function paletteControls(photo: Photo, ticket: number): Promise<void> {
  const s = state.style;
  const visible = ['colorWalk', 'colorCircles', 'colorSquares', 'walkTicket', 'editorial'].includes(s.template);
  el('palette-section').hidden = !visible; if (!visible || !photo.dataUrl) return;
  const result = await analyzePhoto(photo.dataUrl, activePaletteCount(s), s.paletteOrder);
  if (ticket !== previewTicket || current()?.id !== photo.id) return;
  const solid = s.template === 'colorWalk' && s.walkBackground === 'solid';
  const colors = solid ? [photo.manualWalk || result.walk] : photo.manualPalette ?? result.palette;
  el('palette').replaceChildren();
  colors.forEach((color, i) => {
    const row = document.createElement('div'); row.className = 'swatch';
    const picker = document.createElement('input'); picker.type = 'color'; picker.value = hex(color); picker.setAttribute('aria-label', `颜色 ${i + 1}`);
    const text = document.createElement('input'); text.type = 'text'; text.value = hex(color); text.maxLength = 7; text.setAttribute('aria-label', `HEX ${i + 1}`);
    const change = (value: string): void => {
      const parsed = parseHex(value); if (!parsed) { status('请输入六位 HEX 色号', true); text.value = hex(color); return; }
      if (solid) photo.manualWalk = parsed; else { photo.manualPalette = colors.map(c => ({ ...c })); photo.manualPalette[i] = parsed; }
      changed();
    };
    picker.onchange = () => change(picker.value); text.onchange = () => change(text.value); row.append(picker, text);
    if (!solid) row.append(button('×', () => { photo.manualPalette = colors.filter((_, j) => j !== i).map(c => ({ ...c })); changed(); }));
    el('palette').append(row);
  });
  if (!colors.length) { const p = document.createElement('p'); p.className = 'hint'; p.textContent = '色卡已清空；恢复自动取色可重新填入。'; el('palette').append(p); }
}
async function preview(): Promise<void> {
  const ticket = ++previewTicket, photo = current();
  if (!photo?.dataUrl) {
    const empty = document.createElement('div'); empty.className = 'empty';
    const title = document.createElement('strong'); title.textContent = photo ? '原片暂时无法读取' : '把照片拖到这里';
    const detail = document.createElement('p'); detail.textContent = photo ? '请找回原路径文件后重启映框，编辑记录已保留。' : '或点击右上角「导入照片」';
    empty.append(title, detail); el('preview').replaceChildren(empty); el('dimensions').textContent = ''; el('palette').replaceChildren(); return;
  }
  try {
    const canvas = await renderPhoto(photo.dataUrl, photoStyle(photo), 1000, false, photo);
    if (ticket !== previewTicket) return;
    canvas.setAttribute('aria-label', '画框预览'); el('preview').replaceChildren(canvas);
    el('preview-title').textContent = photo.name || '照片';
    const analysis = await analyzePhoto(photo.dataUrl, activePaletteCount(state.style), state.style.paletteOrder);
    if (ticket !== previewTicket) return;
    el('dimensions').textContent = `${analysis.width} × ${analysis.height}`;
    await paletteControls(photo, ticket);
  } catch (e) { if (ticket === previewTicket) status(`预览失败：${errorText(e)}`, true); }
}
async function importResult(result: ImportResult): Promise<void> {
  let first = '', skipped = 0, oversized = 0;
  let retainedBytes = state.photos.reduce((sum, p) => sum + Math.ceil((p.dataUrl?.split(',')[1].length || 0) * .75), 0);
  for (const photo of result.photos) {
    const existing = state.photos.find(p => p.id === photo.id);
    const nextBytes = retainedBytes - Math.ceil((existing?.dataUrl?.split(',')[1].length || 0) * .75) + Math.ceil(photo.dataUrl.split(',')[1].length * .75);
    if (nextBytes > 160 * 1024 * 1024) { oversized++; continue; }
    if (existing) { if (photo.changed) { delete existing.edits; delete existing.manualPalette; delete existing.manualWalk; } Object.assign(existing, photo); }
    else if (state.photos.length < 50) state.photos.push({ ...photo, selected: true });
    else { skipped++; continue; }
    retainedBytes = nextBytes;
    if (!first) first = photo.id;
  }
  if (first) state.currentId = first;
  rebuildPhotos(); rebuildMetadata(); await save(); await preview();
  if (skipped) result.errors.push(`列表最多保留 50 张照片，已跳过 ${skipped} 张；可先移除已完成的照片`);
  if (oversized) result.errors.push(`会话原片合计上限 160 MiB，已跳过 ${oversized} 张；请分批处理`);
  status(result.errors.length ? `导入 ${result.photos.length - skipped - oversized} 张；${result.errors.join('；')}` : `已载入 ${result.photos.length} 张照片`, !!result.errors.length);
}
async function importPhotos(): Promise<void> {
  if (working || !ready || closing) return; working = true; updateActions();
  try { await importResult(await api.importPhotos()); } catch (e) { status(errorText(e), true); } finally { finishWork(); }
}
async function exportPhotos(batch: boolean): Promise<void> {
  if (working || !ready || closing) return;
  const photos = (batch ? state.photos.filter(p => p.selected) : [current()].filter(Boolean) as Photo[]).map(p => ({ ...p }));
  if (!photos.length) return;
  working = true; cancelled = false; updateActions();
  const style = normalizeStyle(state.style), format = state.format, longEdge = state.longEdge;
  let success = 0, failed = 0, done = 0; const errors: string[] = [];
  try {
    const folder = batch ? await api.chooseExportFolder() : null;
    if (batch && !folder) { status('已取消选择导出文件夹'); return; }
    for (const photo of photos) {
      if (cancelled) break;
      status(`正在导出 ${done + 1} / ${photos.length} · ${photo.name || '照片'}`);
      try {
        if (!photo.dataUrl) throw new Error('原片失联');
        const canvas = await renderPhoto(photo.dataUrl, photoStyle(photo, style), longEdge, true, photo);
        const dataUrl = canvas.toDataURL(`image/${format}`, .95);
        const result = batch ? await api.exportToFolder({ dataUrl, photoId: photo.id, format, folder: folder! }) : await api.exportPhoto({ dataUrl, photoId: photo.id, format });
        canvas.width = 1; canvas.height = 1;
        if ('canceled' in result && result.canceled) { cancelled = true; break; }
        success++;
      } catch (e) { failed++; errors.push(`${photo.name || '照片'}：${errorText(e)}`); }
      done++;
    }
    status(`导出完成：成功 ${success}，失败 ${failed}，未处理 ${photos.length - done}${errors.length ? '；' + errors.join('；') : ''}`, failed > 0);
  } catch (e) { status(errorText(e), true); } finally { finishWork(); }
}
el('import').onclick = () => { void importPhotos(); };
el('export').onclick = () => { void exportPhotos(false); };
el('batch').onclick = () => { void exportPhotos(true); };
el('cancel').onclick = () => { cancelled = true; status('将在当前照片导出后停止'); };
el('select-all').onclick = () => { state.photos.forEach(p => p.selected = true); rebuildPhotos(); void save().catch(() => undefined); };
el('invert').onclick = () => { state.photos.forEach(p => p.selected = !p.selected); rebuildPhotos(); void save().catch(() => undefined); };
el('remove').onclick = () => { state.photos = state.photos.filter(p => !p.selected); if (!current()) state.currentId = state.photos[0]?.id || ''; if (!state.photos.length) clearImageCache(); rebuildPhotos(); rebuildMetadata(); changed(); status('已从列表移除，磁盘原片和导出文件保留'); };
el('auto-colors').onclick = () => { const p = current(); if (p) { delete p.manualPalette; delete p.manualWalk; changed(); } };
el('reset').onclick = () => { const id = state.style.template; if (isCollection(id)) Object.assign(state.style, { [id]: normalizeStyle({})[id] }); else { for (const f of topFields()) (state.style as unknown as Record<string, unknown>)[f.key] = defaultStyle[f.key as keyof Style]; } rebuildFields(); changed(); };
el<HTMLSelectElement>('format').onchange = () => { state.format = el<HTMLSelectElement>('format').value as State['format']; void save().catch(() => undefined); };
el<HTMLSelectElement>('size').onchange = () => { state.longEdge = Number(el<HTMLSelectElement>('size').value); void save().catch(() => undefined); };
document.addEventListener('keydown', e => { if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'o') { e.preventDefault(); void importPhotos(); } if ((e.ctrlKey || e.metaKey) && e.shiftKey && e.key.toLowerCase() === 'e') { e.preventDefault(); void exportPhotos(false); } });
document.addEventListener('dragover', e => { e.preventDefault(); el('drop-zone').classList.add('dragging'); });
document.addEventListener('dragleave', e => { if (!e.relatedTarget) el('drop-zone').classList.remove('dragging'); });
document.addEventListener('drop', e => {
  e.preventDefault(); el('drop-zone').classList.remove('dragging'); if (working || !ready || closing) return;
  const files = Array.from(e.dataTransfer?.files || []); if (!files.length) return;
  working = true; updateActions();
  void api.importDropped(files).then(importResult).catch(e => status(errorText(e), true)).finally(finishWork);
});
api.onBeforeClose(() => {
  if (closing) return;
  closing = true; cancelled = true;
  if (document.activeElement instanceof HTMLInputElement) document.activeElement.dispatchEvent(new Event('change'));
  const idle = working ? new Promise<void>(resolve => idleWaiters.push(resolve)) : Promise.resolve();
  updateActions();
  void idle.then(save).then(() => { if (!pendingSaveError) api.confirmClose(); }).catch(e => { closing = false; updateActions(); status(`保存失败，窗口保持打开：${errorText(e)}`, true); });
});
function cleanMetadata(value: unknown): Metadata | undefined {
  if (!value || typeof value !== 'object') return undefined;
  const input = value as Record<string, unknown>;
  return Object.fromEntries(['brand', 'camera', 'parameters', 'date'].map(k => [k, typeof input[k] === 'string' ? input[k].slice(0, 200) : ''])) as Metadata;
}
function cleanColor(value: unknown): RGB | undefined {
  if (!value || typeof value !== 'object') return undefined;
  const c = value as RGB;
  return [c.r, c.g, c.b].every(n => Number.isInteger(n) && n >= 0 && n <= 255) ? { r: c.r, g: c.g, b: c.b, fraction: 0 } : undefined;
}
async function initialize(): Promise<void> {
  try {
    const result = await api.loadSession();
    if (result.state) {
      const saved = result.state;
      state = { photos: [], currentId: typeof saved.currentId === 'string' ? saved.currentId : '', style: normalizeStyle(saved.style || {}), format: saved.format === 'png' ? 'png' : 'jpeg', longEdge: [1920, 2560, 3840, 4096].includes(saved.longEdge) ? saved.longEdge : 3840 };
      for (const item of Array.isArray(saved.photos) ? saved.photos : []) {
        const loaded = result.photos.find(p => p.id === item.id);
        const manual = Array.isArray(item.manualPalette) ? item.manualPalette.slice(0, 8).map(cleanColor).filter(Boolean) as RGB[] : undefined;
        state.photos.push({ id: item.id, name: typeof item.name === 'string' ? item.name : '照片', ...loaded, selected: item.selected === true,
          edits: loaded?.changed ? undefined : cleanMetadata(item.edits), manualPalette: loaded?.changed ? undefined : manual, manualWalk: loaded?.changed ? undefined : cleanColor(item.manualWalk) });
      }
    } else if (!result.errors.length) {
      const sample = await api.loadSample(); state.photos = sample.photos.map(photo => ({ ...photo, selected: true })); state.currentId = state.photos[0]?.id || '';
      result.errors.push(...sample.errors);
    }
    if (!current()) state.currentId = state.photos[0]?.id || '';
    ready = true; rebuildPhotos(); rebuildTemplates(); rebuildFields(); rebuildMetadata();
    el<HTMLSelectElement>('format').value = state.format; el<HTMLSelectElement>('size').value = String(state.longEdge);
    await preview();
    status(result.errors.length ? result.errors.join('；') : '全部处理在本机完成。拖入照片开始创作。', !!result.errors.length);
    el('save-status').textContent = result.state ? '已恢复上次编辑' : 'Windows 预览版';
    document.body.dataset.ready = 'true';
  } catch (e) { status(`启动失败：${errorText(e)}`, true); document.body.dataset.ready = 'error'; }
}
updateActions();
void initialize();
