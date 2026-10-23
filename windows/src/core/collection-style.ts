// Mobile template settings. Nested defaults are normalized independently.
// Only generic system font families are used; no desktop fonts are bundled.
export const collectionDefaults = {
  softFrame: { margin: .028, portraitMargin: .08, top: .085, footer: .19, corner: .022,
    blur: .036, brightness: 0, shadow: .72, textScale: 1, whiteText: true, whiteBrand: false,
    showBrand: true, brand: 'nikon', brandText: '', showCamera: true, camera: '', showParameters: true,
    parameters: '', showSignature: true },
  postage: { variant: 'plain', margin: .105, border: .027, perforation: .0135, footer: .10,
    blur: .04, brightness: 0, shadow: .45, textScale: 1, place: '', customDate: '' },
  classic: { arrangement: 'centered', brand: 'nikon', brandText: '', footer: .12, margin: 0,
    brandScale: 1, infoScale: 1, brandColor: true, showCamera: false, camera: '', showParameters: true,
    parameters: '', showDate: false, customDate: '', showSignature: false },
  walkTicket: { theme: 'charcoal', customHex: '#494644', heading: '', title: 'COLOR WALK', subtitle: '漫步日志',
    notes: '', titleFont: 'serif', customDate: '', admission: 'ADMIT ONE · NO. 02', stubCaption: 'ROUTE WALK',
    showBarcode: true, showPalette: true, showHex: false, paletteCount: 4, photoMode: 'fit',
    margin: .09, aspect: .50, corner: .025, textScale: 1, shadow: .30 },
  film35: { label: 'FILM', number: '01', showSprockets: true, showSignature: true, customDate: '',
    margin: .065, rail: .085, textScale: 1 },
  gallery: { paper: 'ivory', title: '', subtitle: '', titleFont: 'serif', customDate: '',
    showSignature: true, showOutline: true, margin: .10, footer: .16, textScale: 1 },
  editorial: { paper: 'ivory', title: 'WANDER', subtitle: '旅行影像日志', edition: 'VOL. 01', notes: '',
    titleFont: 'serif', customDate: '', showSignature: true, showAccent: true, accent: 'photo',
    customHex: '#8B7565', margin: .055, header: .23, footer: .12, textScale: 1 },
  instant: { paper: 'white', caption: 'Keep this moment.', captionFont: 'serif', customDate: '',
    showSignature: true, margin: .065, border: .04, footer: .15, textScale: 1, shadow: .18 },
  cinema: { subtitle: '把日常，留给时间。', translation: 'Let the ordinary become a scene.', scene: 'SCENE 01',
    ink: 'ivory', showSignature: false, top: .065, bottom: .17, position: .50, textScale: 1 },
  receipt: { title: 'MEMORY RECEIPT', place: '', number: '001', note: 'THANK YOU FOR THIS MOMENT',
    paper: 'ivory', customDate: '', showSignature: true, margin: .10, footer: .26, textScale: 1 },
  tornPaper: { showCaptionArea: false, caption: 'A quiet moment.', captionFont: 'serif', paper: 'ivory',
    customDate: '', showSignature: true, margin: .07, border: .009, footer: .12, roughness: .0035,
    shadow: .18, textScale: 1 }
};
export type CollectionTemplate = keyof typeof collectionDefaults;
type Widen<T> = T extends number ? number : T extends boolean ? boolean : string;
export type CollectionStyles = { [K in CollectionTemplate]: { [F in keyof typeof collectionDefaults[K]]: Widen<typeof collectionDefaults[K][F]> } };
export interface Field {
  key: string; title: string; type: 'text' | 'number' | 'choice' | 'flag' | 'hex';
  min?: number; max?: number; step?: number; options?: string[]; labels?: string[];
}
const text = (key: string, title: string): Field => ({ key, title, type: 'text' });
const flag = (key: string, title: string): Field => ({ key, title, type: 'flag' });
const number = (key: string, title: string, min: number, max: number, step = .005): Field => ({ key, title, type: 'number', min, max, step });
const choice = (key: string, title: string, options: string[], labels: string[]): Field => ({ key, title, type: 'choice', options, labels });
const paper = () => choice('paper', '相纸颜色', ['ivory', 'white', 'charcoal'], ['暖白', '纯白', '炭黑']);
const font = (key: string) => choice(key, '标题英文字体', ['sans-serif', 'serif', 'monospace'], ['系统黑体', '系统宋体', '等宽字体']);
const signature = () => flag('showSignature', '显示个人落款');
const date = () => text('customDate', '日期（可选，手动填写）');
export const brandValues = ['nikon', 'canon', 'sony', 'fujifilm', 'leica', 'hasselblad', 'lumix', 'olympus', 'omSystem', 'pentax', 'ricoh', 'dji', 'insta360', 'custom'];
export const brandNames = ['Nikon', 'Canon', 'SONY', 'FUJIFILM', 'Leica', 'Hasselblad', 'LUMIX', 'OLYMPUS', 'OM SYSTEM', 'PENTAX', 'RICOH', 'DJI', 'Insta360', '自定义文字'];
const brand = () => choice('brand', '摄影品牌（手动选择）', brandValues, brandNames);
const camera = () => text('camera', '相机型号（可选，手动填写）');
const parameters = () => text('parameters', '拍摄参数（可选，手动填写）');
const scale = () => number('textScale', '文字大小', .65, 1.6, .05);
export const collectionFields: Record<CollectionTemplate, Field[]> = {
  softFrame: [flag('showBrand', '显示摄影品牌'), brand(), text('brandText', '自定义品牌文字'),
    flag('showCamera', '显示相机型号'), camera(), flag('showParameters', '显示拍摄参数'), parameters(), signature(),
    flag('whiteText', '浅色参数与型号'), flag('whiteBrand', '浅色品牌标志'),
    number('margin', '横版左右留白', .015, .15, .001), number('portraitMargin', '竖版左右留白', .015, .15, .001),
    number('top', '顶部留白', .025, .15, .001), number('footer', '底部留白', .13, .30, .005),
    number('blur', '背景虚化', 0, .085, .001), number('brightness', '背景明暗', -.5, .5, .01),
    number('corner', '照片圆角', 0, .05, .001), number('shadow', '悬浮阴影', 0, 1, .01), number('textScale', '文字大小', .65, 1.5, .05)],
  postage: [choice('variant', '邮票样式', ['plain', 'caption'], ['纯邮票画框', '地点与日期']),
    text('place', '地点或题字'), date(), number('margin', '画布留白', .035, .19, .005), number('border', '邮票白边', .014, .06, .001),
    number('perforation', '齿孔大小', .006, .022, .0005), number('footer', '题字区高度', .07, .18, .005),
    number('blur', '背景虚化', 0, .085, .001), number('brightness', '背景明暗', -.5, .5, .01),
    number('shadow', '悬浮阴影', 0, 1, .01), number('textScale', '题字大小', .5, 2, .05)],
  classic: [brand(), text('brandText', '自定义品牌文字'), choice('arrangement', '底栏排版', ['centered', 'split', 'inline'], ['品牌居中', '左文右标', '品牌与信息并列']),
    flag('brandColor', '使用品牌原色'), flag('showCamera', '显示相机型号'), camera(), flag('showParameters', '显示拍摄参数'), parameters(),
    flag('showDate', '显示日期'), date(), signature(), number('footer', '底栏高度', .06, .22, .005), number('margin', '照片白边', 0, .08, .001),
    number('brandScale', '品牌大小', .5, 2, .05), number('infoScale', '信息字号', .5, 2, .05)],
  walkTicket: [choice('theme', '票券配色', ['charcoal', 'cream', 'orange', 'brown', 'photo', 'custom'], ['炭灰', '奶油白', '橘色', '棕色', '照片主色', '自定义']),
    { key: 'customHex', title: '自定义票色 HEX', type: 'hex' }, text('heading', '上方小标题'), text('title', '主标题'), text('subtitle', '副标题'),
    text('notes', '补充文字'), font('titleFont'), date(), text('admission', '票根侧面文字'), text('stubCaption', '票根底部文字'),
    choice('photoMode', '照片适配', ['fit', 'fill'], ['完整照片', '填满（裁切）']), flag('showBarcode', '装饰条纹'), flag('showPalette', '显示主色色卡'), flag('showHex', '显示 HEX 色号'),
    number('paletteCount', '取色数量', 2, 8, 1), number('margin', '四周留白', .05, .16), number('aspect', '票券高宽比', .44, .64, .01),
    number('corner', '圆角大小', 0, .045, .001), number('textScale', '文字大小', .5, 2, .05), number('shadow', '阴影深度', 0, 1, .05)],
  film35: [text('label', '胶片标识'), text('number', '画幅编号'), date(), flag('showSprockets', '显示齿孔'), signature(),
    number('margin', '两侧留白', .035, .12), number('rail', '上下胶片边', .065, .14), scale()],
  gallery: [paper(), text('title', '作品标题'), text('subtitle', '作品说明'), font('titleFont'), date(), signature(), flag('showOutline', '细线画框'),
    number('margin', '四周留白', .045, .18), number('footer', '落款栏高度', .12, .26), scale()],
  editorial: [paper(), text('title', '主标题'), text('subtitle', '副标题'), text('edition', '期号'), text('notes', '页脚说明'), font('titleFont'), date(),
    signature(), flag('showAccent', '显示主色线'), choice('accent', '主色线颜色', ['photo', 'custom'], ['照片主色', '自定义']),
    { key: 'customHex', title: '主色线 HEX', type: 'hex' }, number('margin', '左右留白', .025, .12), number('header', '刊头高度', .17, .32), number('footer', '页脚高度', .09, .20), scale()],
  instant: [paper(), text('caption', '相纸题字'), font('captionFont'), date(), signature(), number('margin', '画布留白', .035, .12),
    number('border', '相纸白边', .025, .075), number('footer', '下边高度', .10, .24), scale(), number('shadow', '阴影深度', 0, .35, .01)],
  cinema: [text('subtitle', '主字幕'), text('translation', '第二行字幕'), text('scene', '场记文字'),
    choice('ink', '字幕颜色', ['ivory', 'amber'], ['米白', '暖金']), signature(), number('top', '上黑边', .025, .14), number('bottom', '下黑边', .12, .30),
    number('position', '字幕上下位置', 0, 1, .01), scale()],
  receipt: [paper(), text('title', '小票标题'), text('place', '地点'), text('number', '编号'), text('note', '底部致谢'), date(), signature(),
    number('margin', '画布留白', .06, .18), number('footer', '小票明细高度', .22, .38), scale()],
  tornPaper: [paper(), flag('showCaptionArea', '显示底部落款区'), text('caption', '相纸题字'), font('captionFont'), date(), signature(),
    number('margin', '画布留白', .035, .14), number('border', '相纸白边', .004, .08, .001), number('footer', '落款区高度', .09, .22),
    number('roughness', '撕裂程度', .001, .008, .0001), number('shadow', '阴影深度', 0, .35, .01), scale()]
};
export function isCollection(id: string): id is CollectionTemplate {
  return Object.prototype.hasOwnProperty.call(collectionDefaults, id);
}
export function normalizeCollections(value: unknown): CollectionStyles {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  const result = {} as CollectionStyles;
  for (const id of Object.keys(collectionDefaults) as CollectionTemplate[]) {
    const supplied = source[id];
    const input = supplied && typeof supplied === 'object' && !Array.isArray(supplied) ? supplied as Record<string, unknown> : {};
    const output: Record<string, string | number | boolean> = { ...collectionDefaults[id] };
    for (const f of collectionFields[id]) {
      const v = input[f.key];
      if (f.type === 'number' && typeof v === 'number' && Number.isFinite(v)) {
        output[f.key] = Math.min(f.max!, Math.max(f.min!, f.key === 'paletteCount' ? Math.round(v) : v));
      } else if (f.type === 'flag' && typeof v === 'boolean') output[f.key] = v;
      else if (f.type === 'choice' && typeof v === 'string' && f.options!.includes(v)) output[f.key] = v;
      else if (f.type === 'text' && typeof v === 'string') output[f.key] = v.replace(/[\r\n]+/g, ' ').slice(0, 200);
      else if (f.type === 'hex' && typeof v === 'string' && /^#?[0-9a-f]{6}$/i.test(v.trim())) output[f.key] = '#' + v.trim().replace('#', '').toUpperCase();
    }
    if (id === 'film35' && output.label === 'FRAME 35') output.label = 'FILM';
    // Matches the Mac migration: the old wide-paper preset now starts with a narrow torn edge.
    if (id === 'tornPaper' && input.showCaptionArea === undefined && input.border === .04) output.border = .009;
    (result as unknown as Record<string, unknown>)[id] = output;
  }
  return result;
}
export function visibleFields(id: CollectionTemplate, settings: CollectionStyles[CollectionTemplate]): Field[] {
  const s = settings as unknown as Record<string, string | number | boolean>;
  return collectionFields[id].filter(f => {
    if (id === 'postage' && s.variant === 'plain' && ['place', 'customDate', 'footer', 'textScale'].includes(f.key)) return false;
    if ((id === 'softFrame' || id === 'classic') && (
      f.key === 'brandText' && (s.brand !== 'custom' || s.showBrand === false)
      || f.key === 'brand' && s.showBrand === false
      || f.key === 'whiteBrand' && s.showBrand === false
      || f.key === 'camera' && !s.showCamera
      || f.key === 'parameters' && !s.showParameters
      || f.key === 'customDate' && !s.showDate)) return false;
    if (id === 'tornPaper' && !s.showCaptionArea && ['caption', 'captionFont', 'customDate', 'showSignature', 'footer', 'textScale'].includes(f.key)) return false;
    if (id === 'editorial' && (f.key === 'customHex' ? !s.showAccent || s.accent !== 'custom' : f.key === 'accent' && !s.showAccent)) return false;
    if (id === 'walkTicket' && (f.key === 'customHex' ? s.theme !== 'custom' : ['showHex', 'paletteCount'].includes(f.key) && !s.showPalette)) return false;
    return true;
  });
}
