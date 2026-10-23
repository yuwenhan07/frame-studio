import { test, expect, _electron as electron, type ElectronApplication, type Page } from '@playwright/test';
import { createCanvas, loadImage } from '@napi-rs/canvas';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import * as os from 'node:os';

const root = path.resolve(__dirname, '..');
const running = new Set<ElectronApplication>();
const scratch = new Set<string>();
const templateIds = ['softFrame', 'postage', 'classic', 'colorWalk', 'colorCircles', 'colorSquares', 'tickets', 'walkTicket', 'film35', 'gallery', 'editorial', 'instant', 'cinema', 'receipt', 'tornPaper'];

// Independent synthetic source: a green foreground with four distinct corners.
function photoCanvas() {
  const canvas = createCanvas(900, 600), ctx = canvas.getContext('2d');
  ctx.fillStyle = '#00FF00'; ctx.fillRect(0, 0, 900, 600);
  for (const [x, y, color] of [[0, 0, '#FF0000'], [810, 0, '#0000FF'], [0, 540, '#FFFF00'], [810, 540, '#00FFFF']] as const) {
    ctx.fillStyle = color; ctx.fillRect(x, y, 90, 60);
  }
  return canvas;
}

// Add a minimal TIFF EXIF segment without relying on the app's EXIF implementation.
function jpegWithExif(jpeg: Buffer, camera: string, orientation = 1): Buffer {
  const make = Buffer.from('NIKON\0'), model = Buffer.from(camera + '\0'), date = Buffer.from('2026:10:23 10:30:00\0');
  const exifOffset = 62 + make.length + model.length, dateOffset = exifOffset + 18;
  const tiff = Buffer.alloc(dateOffset + date.length);
  tiff.write('II'); tiff.writeUInt16LE(42, 2); tiff.writeUInt32LE(8, 4); tiff.writeUInt16LE(4, 8);
  function entry(offset: number, tag: number, type: number, count: number, value: number) {
    tiff.writeUInt16LE(tag, offset); tiff.writeUInt16LE(type, offset + 2); tiff.writeUInt32LE(count, offset + 4); tiff.writeUInt32LE(value, offset + 8);
  }
  entry(10, 0x010f, 2, make.length, 62); entry(22, 0x0110, 2, model.length, 62 + make.length);
  entry(34, 0x0112, 3, 1, orientation); entry(46, 0x8769, 4, 1, exifOffset);
  make.copy(tiff, 62); model.copy(tiff, 62 + make.length);
  tiff.writeUInt16LE(1, exifOffset); entry(exifOffset + 2, 0x9003, 2, date.length, dateOffset); date.copy(tiff, dateOffset);
  const payload = Buffer.concat([Buffer.from('Exif\0\0'), tiff]), marker = Buffer.alloc(4);
  marker[0] = 255; marker[1] = 225; marker.writeUInt16BE(payload.length + 2, 2);
  return Buffer.concat([jpeg.subarray(0, 2), marker, payload, jpeg.subarray(2)]);
}

function bmpFixture(): Buffer {
  const canvas = photoCanvas(), rgba = canvas.getContext('2d').getImageData(0, 0, 900, 600).data;
  const stride = 2700, bytes = Buffer.alloc(54 + stride * 600);
  bytes.write('BM'); bytes.writeUInt32LE(bytes.length, 2); bytes.writeUInt32LE(54, 10); bytes.writeUInt32LE(40, 14);
  bytes.writeInt32LE(900, 18); bytes.writeInt32LE(600, 22); bytes.writeUInt16LE(1, 26); bytes.writeUInt16LE(24, 28); bytes.writeUInt32LE(stride * 600, 34);
  for (let y = 0; y < 600; y++) for (let x = 0; x < 900; x++) {
    const from = (y * 900 + x) * 4, to = 54 + (599 - y) * stride + x * 3;
    bytes[to] = rgba[from + 2]; bytes[to + 1] = rgba[from + 1]; bytes[to + 2] = rgba[from];
  }
  return bytes;
}

async function fixtures() {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), '映框 Windows smoke ')); scratch.add(directory);
  const source = photoCanvas(), jpg = source.toBuffer('image/jpeg', 95);
  const paths = {
    first: path.join(directory, '北京 旅行甲.jpg'), second: path.join(directory, '北京 旅行乙.jpg'),
    rotated: path.join(directory, '竖拍 EXIF.jpg'), webp: path.join(directory, '照片 WebP.webp'), bmp: path.join(directory, '照片 BMP.bmp'),
  };
  await Promise.all([
    fs.writeFile(paths.first, jpegWithExif(jpg, 'NIKON ALPHA')),
    fs.writeFile(paths.second, jpegWithExif(jpg, 'NIKON BETA')),
    fs.writeFile(paths.rotated, jpegWithExif(jpg, 'NIKON ROTATED', 6)),
    fs.writeFile(paths.webp, source.toBuffer('image/webp', 95)), fs.writeFile(paths.bmp, bmpFixture()),
  ]);
  return { directory, paths, userData: path.join(directory, '编辑会话') };
}

async function launch(userData: string) {
  const executable = process.env.FRAME_STUDIO_EXECUTABLE;
  const app = await electron.launch({
    ...(executable ? { executablePath: executable } : {}),
    args: executable ? ['--test-mode'] : [root, '--test-mode'],
    cwd: root,
    env: { ...process.env, FRAME_STUDIO_USER_DATA: userData },
    timeout: 45_000,
  });
  running.add(app);
  const page = await app.firstWindow();
  await expect(page.locator('body')).toHaveAttribute('data-ready', 'true');
  expect(await app.evaluate(({ app }) => app.getPath('userData'))).toBe(userData);
  return { app, page };
}

async function close(app: ElectronApplication) {
  const closed = app.waitForEvent('close');
  await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0]?.close());
  await closed; running.delete(app);
}

async function dialogs(app: ElectronApplication, photos: string[], folder?: string, single?: string) {
  await app.evaluate(({ dialog }, values) => {
    dialog.showOpenDialog = async (_window: unknown, options: { properties?: string[] }) => ({
      canceled: false, filePaths: options.properties?.includes('openDirectory') ? [values.folder!] : values.photos,
    }) as never;
    dialog.showSaveDialog = async () => ({ canceled: false, filePath: values.single! }) as never;
  }, { photos, folder, single });
}

async function removeAll(page: Page) {
  await page.locator('#select-all').click(); await page.locator('#remove').click();
  await expect(page.locator('#photos .photo-row')).toHaveCount(0);
  await expect(page.locator('#preview .empty')).toBeVisible();
  await expect(page.locator('#save-status')).toHaveText('已自动保存');
}

async function importPhotos(app: ElectronApplication, page: Page, paths: string[]) {
  await dialogs(app, paths); await page.locator('#import').click();
  await expect(page.locator('#photos .photo-row')).toHaveCount(paths.length);
  await expect(page.locator('#preview canvas')).toBeVisible();
  await expect(page.locator('#status')).toContainText(`已载入 ${paths.length} 张照片`);
  await expect(page.locator('#import')).toBeEnabled();
}

async function newPreview(page: Page, action: () => Promise<unknown>) {
  const old = await page.locator('#preview canvas').elementHandle();
  await action();
  if (old) await expect.poll(() => old.evaluate(canvas => canvas.isConnected)).toBe(false);
  await expect(page.locator('#preview canvas')).toBeVisible();
  expect(await page.locator('#status').getAttribute('class')).not.toBe('error');
}

async function selectTemplate(page: Page, id: string) {
  await newPreview(page, () => page.locator(`[data-template="${id}"]`).click());
  await expect(page.locator(`[data-template="${id}"]`)).toHaveClass('active');
}
async function selectPhoto(page: Page, name: string) {
  await newPreview(page, () => page.getByRole('button', { name, exact: true }).click());
}
async function edit(page: Page, label: string, value: string) {
  const input = page.getByRole('textbox', { name: label, exact: true });
  await newPreview(page, async () => { await input.fill(value); await input.press('Tab'); });
  await expect(page.locator('#save-status')).toHaveText('已自动保存');
}
async function previewData(page: Page) { return page.locator('#preview canvas').evaluate((canvas: HTMLCanvasElement) => canvas.toDataURL('image/png')); }

async function rgba(bytes: Buffer) {
  const image = await loadImage(bytes), canvas = createCanvas(image.width, image.height);
  canvas.getContext('2d').drawImage(image, 0, 0);
  return { width: image.width, height: image.height, bytes: Buffer.from(canvas.getContext('2d').getImageData(0, 0, image.width, image.height).data) };
}

test.afterEach(async ({}, info) => {
  for (const app of running) {
    try { const page = await app.firstWindow(); await page.screenshot({ path: info.outputPath('app-final.png') }); } catch {}
    await app.close().catch(() => undefined);
  }
  running.clear();
  for (const directory of scratch) await fs.rm(directory, { recursive: true, force: true }).catch(() => undefined);
  scratch.clear();
});

test('real Electron renders all 15 templates, imports WebP/BMP, and applies JPEG EXIF orientation once', async () => {
  const f = await fixtures(), { app, page } = await launch(f.userData);
  await expect(page.locator('#preview canvas')).toBeVisible();
  await fs.mkdir(path.join(root, '.artifacts'), { recursive: true });
  await page.screenshot({ path: path.join(root, '.artifacts', 'app.png') });
  expect(await page.evaluate(() => ({ node: typeof (window as unknown as { require?: unknown }).require, bridge: typeof window.frameStudio.importPhotos }))).toEqual({ node: 'undefined', bridge: 'function' });
  await removeAll(page); await importPhotos(app, page, [f.paths.first, f.paths.second, f.paths.rotated]);
  await expect(page.locator('#templates button')).toHaveCount(15);
  for (const id of templateIds) {
    await selectTemplate(page, id);
    const pixels = await page.locator('#preview canvas').evaluate((canvas: HTMLCanvasElement) => {
      const data = canvas.getContext('2d')!.getImageData(0, 0, canvas.width, canvas.height).data;
      const counts = { red: 0, blue: 0, yellow: 0, cyan: 0, green: 0 };
      for (let i = 0; i < data.length; i += 4) {
        const r = data[i], g = data[i + 1], b = data[i + 2];
        if (r > 240 && g < 15 && b < 15) counts.red++;
        if (r < 15 && g < 15 && b > 240) counts.blue++;
        if (r > 240 && g > 240 && b < 15) counts.yellow++;
        if (r < 15 && g > 240 && b > 240) counts.cyan++;
        if (r < 15 && g > 240 && b < 15) counts.green++;
      }
      return { ...counts, width: canvas.width, height: canvas.height };
    });
    expect(Math.max(pixels.width, pixels.height), id).toBeLessThanOrEqual(1000);
    for (const color of ['red', 'blue', 'yellow', 'cyan', 'green'] as const) expect(pixels[color], `${id}: ${color} landmark`).toBeGreaterThan(20);
  }
  await selectTemplate(page, 'colorCircles');
  await selectPhoto(page, path.basename(f.paths.rotated));
  await expect(page.locator('#dimensions')).toHaveText('600 × 900');
  const oriented = await page.locator('#preview canvas').evaluate((canvas: HTMLCanvasElement) => {
    const ctx = canvas.getContext('2d')!, pw = canvas.width * .96, ph = pw * 1.5, origin = canvas.width * .02;
    return [[.05, .05], [.95, .05], [.05, .95], [.95, .95]].map(([x, y]) => [...ctx.getImageData(Math.round(origin + pw * x), Math.round(origin + ph * y), 1, 1).data].slice(0, 3));
  });
  for (const [i, expected] of [[255, 255, 0], [255, 0, 0], [0, 255, 255], [0, 0, 255]].entries()) {
    expect(oriented[i].every((value, channel) => Math.abs(value - expected[channel]) <= 12)).toBe(true);
  }
  await dialogs(app, [f.paths.webp, f.paths.bmp]); await page.locator('#import').click();
  await expect(page.locator('#photos .photo-row')).toHaveCount(5);
  await expect(page.locator('#status')).toContainText('已载入 2 张照片');
  await expect(page.locator('#import')).toBeEnabled();
  for (const filename of [f.paths.webp, f.paths.bmp]) {
    await selectPhoto(page, path.basename(filename));
    await expect(page.locator('#dimensions')).toHaveText('900 × 600');
    const center = await page.locator('#preview canvas').evaluate((canvas: HTMLCanvasElement) =>
      [...canvas.getContext('2d')!.getImageData(Math.round(canvas.width * .5), Math.round(canvas.width * .34), 1, 1).data].slice(0, 3));
    expect(center[0]).toBeLessThan(12); expect(center[1]).toBeGreaterThan(243); expect(center[2]).toBeLessThan(12);
  }
  await selectTemplate(page, 'softFrame');
  await page.screenshot({ path: path.join(root, '.artifacts', 'app-test-fixture.png') });
});

test('photo edits, selected template, manual color and export settings survive restart; an empty session stays empty', async () => {
  const f = await fixtures(); let { app, page } = await launch(f.userData);
  await removeAll(page); await importPhotos(app, page, [f.paths.first, f.paths.second]);
  await selectTemplate(page, 'colorWalk');
  await edit(page, '主文字', '北京 · 留住此刻'); await edit(page, '个人落款', '摄影师 Test'); await edit(page, 'HEX 1', '#A9696B');
  await page.getByText('这张照片的拍摄信息', { exact: true }).click();
  await expect(page.getByRole('textbox', { name: '相机型号', exact: true })).toHaveValue('NIKON ALPHA');
  await edit(page, '相机型号', 'CUSTOM ALPHA');
  await page.locator('#format').selectOption('png'); await page.locator('#size').selectOption('1920');
  await page.getByRole('checkbox', { name: `选择 ${path.basename(f.paths.second)}`, exact: true }).uncheck();
  await expect(page.locator('#save-status')).toHaveText('已自动保存'); await close(app);
  ({ app, page } = await launch(f.userData));
  await expect(page.locator('#photos .photo-row')).toHaveCount(2);
  await expect(page.locator('[data-template="colorWalk"]')).toHaveClass('active');
  await expect(page.getByRole('textbox', { name: '主文字', exact: true })).toHaveValue('北京 · 留住此刻');
  await expect(page.getByRole('textbox', { name: '个人落款', exact: true })).toHaveValue('摄影师 Test');
  await expect(page.getByRole('textbox', { name: 'HEX 1', exact: true })).toHaveValue('#A9696B');
  await expect(page.locator('#format')).toHaveValue('png'); await expect(page.locator('#size')).toHaveValue('1920');
  await expect(page.getByRole('checkbox', { name: `选择 ${path.basename(f.paths.second)}`, exact: true })).not.toBeChecked();
  await page.getByText('这张照片的拍摄信息', { exact: true }).click();
  await expect(page.getByRole('textbox', { name: '相机型号', exact: true })).toHaveValue('CUSTOM ALPHA');
  await selectPhoto(page, path.basename(f.paths.second));
  await expect(page.getByRole('textbox', { name: '相机型号', exact: true })).toHaveValue('NIKON BETA');
  await removeAll(page); await close(app); ({ app, page } = await launch(f.userData));
  await expect(page.locator('#photos .photo-row')).toHaveCount(0); await expect(page.locator('#preview .empty')).toBeVisible();
  await expect(page.locator('#export')).toBeDisabled(); await expect(page.locator('#batch')).toBeDisabled();
});

test('batch and current exports write real Chinese-path files, preserve collisions and keep each photo metadata', async () => {
  const f = await fixtures(), { app, page } = await launch(f.userData), output = path.join(f.directory, '导出作品 空格');
  await fs.mkdir(output); const firstSource = await fs.readFile(f.paths.first), secondSource = await fs.readFile(f.paths.second);
  await removeAll(page); await importPhotos(app, page, [f.paths.first, f.paths.second]);
  await selectTemplate(page, 'classic');
  await newPreview(page, () => page.getByRole('checkbox', { name: '显示相机型号', exact: true }).check());
  await page.getByText('这张照片的拍摄信息', { exact: true }).click();
  await edit(page, '相机型号', 'CUSTOM ALPHA'); await edit(page, '焦距 / 光圈 / 快门 / ISO', '35mm · f/2 · 1/125s · ISO 100');
  const firstPreview = await previewData(page);
  await selectPhoto(page, path.basename(f.paths.second));
  await expect(page.getByRole('textbox', { name: '相机型号', exact: true })).toHaveValue('NIKON BETA');
  await expect(page.getByRole('textbox', { name: '焦距 / 光圈 / 快门 / ISO', exact: true })).toHaveValue('');
  const secondPreview = await previewData(page); expect(firstPreview).not.toBe(secondPreview);
  await page.locator('#format').selectOption('png'); await page.locator('#size').selectOption('1920');
  const firstName = '北京 旅行甲_映框.png', secondName = '北京 旅行乙_映框.png', collision = Buffer.from('existing user file');
  await fs.writeFile(path.join(output, firstName), collision);
  await dialogs(app, [], output, path.join(output, '当前 照片.png'));
  await page.locator('#batch').click(); await expect(page.locator('#status')).toHaveText('导出完成：成功 2，失败 0，未处理 0');
  await expect(page.locator('#batch')).toBeEnabled();
  expect(await fs.readFile(path.join(output, firstName))).toEqual(collision);
  const firstOutput = await fs.readFile(path.join(output, '北京 旅行甲_映框 (2).png')), secondOutput = await fs.readFile(path.join(output, secondName));
  for (const [bytes, preview] of [[firstOutput, firstPreview], [secondOutput, secondPreview]] as const) {
    const actual = await rgba(bytes), expected = await rgba(Buffer.from(preview.split(',')[1], 'base64'));
    expect(actual.width).toBe(900); expect(actual.height).toBe(708);
    expect(actual.bytes.equals(expected.bytes)).toBe(true);
    expect(bytes.includes(Buffer.from('Exif\0\0'))).toBe(false);
  }
  const firstPixels = await rgba(firstOutput), secondPixels = await rgba(secondOutput);
  expect(firstPixels.bytes.subarray(0, 900 * 600 * 4).equals(secondPixels.bytes.subarray(0, 900 * 600 * 4))).toBe(true);
  expect(firstPixels.bytes.subarray(900 * 600 * 4).equals(secondPixels.bytes.subarray(900 * 600 * 4))).toBe(false);
  await page.locator('#batch').click(); await expect(page.locator('#status')).toHaveText('导出完成：成功 2，失败 0，未处理 0');
  await expect(page.locator('#batch')).toBeEnabled();
  expect((await fs.readdir(output)).sort()).toEqual([firstName, '北京 旅行甲_映框 (2).png', '北京 旅行甲_映框 (3).png', secondName, '北京 旅行乙_映框 (2).png'].sort());
  await page.locator('#export').click(); await expect(page.locator('#status')).toHaveText('导出完成：成功 1，失败 0，未处理 0');
  expect((await rgba(await fs.readFile(path.join(output, '当前 照片.png')))).bytes.equals(secondPixels.bytes)).toBe(true);
  await page.locator('#format').selectOption('jpeg'); await dialogs(app, [], output, path.join(output, '当前 照片.jpg'));
  await page.locator('#export').click(); await expect(page.locator('#export')).toBeEnabled();
  await expect(page.locator('#status')).toHaveText('导出完成：成功 1，失败 0，未处理 0');
  const jpeg = await fs.readFile(path.join(output, '当前 照片.jpg')), jpegPixels = await rgba(jpeg);
  expect([...jpeg.subarray(0, 2)]).toEqual([255, 216]); expect(jpeg.includes(Buffer.from('Exif\0\0'))).toBe(false);
  expect([jpegPixels.width, jpegPixels.height]).toEqual([900, 708]);
  const center = (300 * 900 + 450) * 4;
  expect(jpegPixels.bytes[center]).toBeLessThan(12); expect(jpegPixels.bytes[center + 1]).toBeGreaterThan(243); expect(jpegPixels.bytes[center + 2]).toBeLessThan(12);
  expect(await fs.readFile(f.paths.first)).toEqual(firstSource); expect(await fs.readFile(f.paths.second)).toEqual(secondSource);
});
