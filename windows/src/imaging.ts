import { RGB, Style, PaletteOrder, activePaletteCount, normalizeStyle } from './core/model';
import { Layout, layout } from './core/layout';
import { extractPalette, walkColor } from './core/palette';
import { blurRGBA } from './core/blur';
import { backgroundBlur } from './core/photo-frames';
import { DrawingContext, RenderInput, render } from './core/render';

export const MAX_IMAGE_PIXELS = 40_000_000;
export const MAX_OUTPUT_LONG_EDGE = 4096;

export interface Analysis { palette: RGB[]; walk: RGB; width: number; height: number }
export interface RenderOptions { manualPalette?: RGB[]; manualWalk?: RGB }
interface Decoded { image: HTMLImageElement; width: number; height: number; sample: Uint8ClampedArray }

export function validateDimensions(width: number, height: number): void {
  if (!Number.isInteger(width) || !Number.isInteger(height) || width < 1 || height < 1) {
    throw new Error('图片尺寸无效');
  }
  if (width * height > MAX_IMAGE_PIXELS || width > 16000 || height > 16000) throw new Error('图片超过 4000 万像素或最长边 16000 像素，请先缩小图片');
}

function canvas(width: number, height: number): HTMLCanvasElement {
  validateDimensions(width, height);
  const result = document.createElement('canvas');
  result.width = width; result.height = height;
  return result;
}
function context(value: HTMLCanvasElement): CanvasRenderingContext2D {
  const result = value.getContext('2d', { willReadFrequently: true });
  if (!result) throw new Error('无法创建画布，请重启应用后重试');
  return result;
}

// Keep only the current decoded photo. Both preview and export use Chromium's
// EXIF-oriented natural dimensions and pixels; no second EXIF transform is applied.
let lastSource: string | undefined;
let lastDecoded: Promise<Decoded> | undefined;
function decode(dataUrl: string): Promise<Decoded> {
  if (!/^data:image\/(?:jpeg|png|webp|bmp);base64,/i.test(dataUrl)) {
    return Promise.reject(new Error('请选择 JPEG、PNG、WebP 或 BMP 图片'));
  }
  if (lastSource === dataUrl && lastDecoded) return lastDecoded;
  lastSource = dataUrl;
  const pending = new Promise<Decoded>((resolve, reject) => {
    const image = new Image();
    image.decoding = 'async';
    const timer = setTimeout(() => {
      image.onload = image.onerror = null; image.src = '';
      reject(new Error('图片读取超时，请换用较小的 JPEG 或 PNG 图片'));
    }, 30_000);
    image.onerror = () => { clearTimeout(timer); reject(new Error('无法解码图片，请确认文件完整且为 JPEG、PNG、WebP 或 BMP')); };
    image.onload = () => {
      clearTimeout(timer);
      try {
        const width = image.naturalWidth, height = image.naturalHeight;
        validateDimensions(width, height);
        const scale = Math.min(1, 192 / Math.max(width, height));
        const small = canvas(Math.max(1, Math.round(width * scale)), Math.max(1, Math.round(height * scale)));
        const ctx = context(small);
        ctx.fillStyle = '#FFFFFF'; ctx.fillRect(0, 0, small.width, small.height);
        ctx.drawImage(image, 0, 0, small.width, small.height);
        resolve({ image, width, height, sample: ctx.getImageData(0, 0, small.width, small.height).data });
      } catch (error) { reject(error); }
    };
    image.src = dataUrl;
  });
  lastDecoded = pending;
  void pending.catch(() => { if (lastDecoded === pending) { lastSource = undefined; lastDecoded = undefined; } });
  return pending;
}

/** Clear the only decoded-image cache, for example when all imported photos are removed. */
export function clearImageCache(): void { lastSource = undefined; lastDecoded = undefined; }

export async function analyzePhoto(dataUrl: string, count: number, order: PaletteOrder): Promise<Analysis> {
  const photo = await decode(dataUrl);
  return {
    palette: extractPalette(photo.sample, count, order),
    walk: walkColor(extractPalette(photo.sample, 8, 'dominance')),
    width: photo.width, height: photo.height
  };
}

/** The selected long edge is a maximum. The sharp foreground is never enlarged. */
export function boundedLayout(width: number, height: number, style: Style, longEdge: number): Layout {
  validateDimensions(width, height);
  if (!Number.isFinite(longEdge) || longEdge < 1) throw new Error('导出尺寸无效');
  const unit = layout(width, height, style, 1000);
  const edge = Math.min(MAX_OUTPUT_LONG_EDGE, Math.floor(longEdge));
  // For Walk Ticket's fill mode the cover scale is max(w/iw, h/ih),
  // so both constraints must be met even when the photo slot crops the source.
  const scale = Math.min(edge / Math.max(unit.width, unit.height),
    width / unit.photo.w, height / unit.photo.h,
    Math.sqrt(MAX_IMAGE_PIXELS / (unit.width * unit.height)));
  const targetWidth = Math.max(1, Math.floor(unit.width * scale));
  if (targetWidth >= 64) {
    const result = layout(width, height, style, targetWidth);
    validateDimensions(result.width, result.height);
    return result;
  }
  // A tiny source must stay tiny. Scale the layout below the shared core's
  // 64px authoring floor instead of silently enlarging its foreground.
  const base = layout(width, height, style, 64), ratio = targetWidth / 64;
  const result = Object.fromEntries(Object.entries(base).map(([key, value]) => [key,
    typeof value === 'number' ? value * ratio : Object.fromEntries(Object.entries(value).map(([name, n]) => [name, (n as number) * ratio]))
  ])) as unknown as Layout;
  result.width = targetWidth; result.height = Math.max(1, Math.ceil(result.height));
  validateDimensions(result.width, result.height);
  if (result.photo.w > width + 1e-8 || result.photo.h > height + 1e-8 || Math.max(result.width, result.height) > edge) {
    throw new Error('当前图片比例过于狭长，请先裁剪照片');
  }
  return result;
}

export async function renderPhoto(dataUrl: string, value: Style, longEdge: number, forExport = true,
  options: RenderOptions = {}): Promise<HTMLCanvasElement> {
  const style = normalizeStyle(value), photo = await decode(dataUrl);
  const bounds = boundedLayout(photo.width, photo.height, style, longEdge);
  const output = canvas(bounds.width, bounds.height);
  const input: RenderInput = {
    image: photo.image, imageWidth: photo.width, imageHeight: photo.height,
    palette: options.manualPalette === undefined ? extractPalette(photo.sample, activePaletteCount(style), style.paletteOrder) : options.manualPalette,
    walk: options.manualWalk ?? walkColor(extractPalette(photo.sample, 8, 'dominance'))
  };
  const strength = backgroundBlur(style);
  if (strength !== undefined) {
    const scale = Math.min(1, 512 / Math.max(photo.width, photo.height));
    const background = canvas(Math.max(1, Math.round(photo.width * scale)), Math.max(1, Math.round(photo.height * scale)));
    const ctx = context(background);
    ctx.fillStyle = '#FFFFFF'; ctx.fillRect(0, 0, background.width, background.height);
    ctx.drawImage(photo.image, 0, 0, background.width, background.height);
    const pixels = ctx.getImageData(0, 0, background.width, background.height);
    pixels.data.set(blurRGBA(pixels.data, background.width, background.height, Math.max(background.width, background.height) * strength));
    ctx.putImageData(pixels, 0, 0);
    input.background = background; input.backgroundWidth = background.width; input.backgroundHeight = background.height;
  }
  render(context(output) as unknown as DrawingContext, bounds, style, input, forExport);
  return output;
}
