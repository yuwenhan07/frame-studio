const { test, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createCanvas, Image } = require('@napi-rs/canvas');
const { normalizeStyle, templates } = require('../.test-build/core/model');
const { hex } = require('../.test-build/core/palette');
const { boundedLayout, validateDimensions, renderPhoto, analyzePhoto, clearImageCache } = require('../.test-build/imaging');

const savedImage = global.Image, savedDocument = global.document;
global.Image = Image;
global.document = { createElement: tag => { assert.equal(tag, 'canvas'); return createCanvas(1, 1); } };
after(() => { global.Image = savedImage; global.document = savedDocument; clearImageCache(); });
const pixel = (canvas, x, y) => [...canvas.getContext('2d').getImageData(Math.round(x), Math.round(y), 1, 1).data].slice(0, 3);
function fixture(width = 300, height = 200) {
  const canvas = createCanvas(width, height), ctx = canvas.getContext('2d');
  ctx.fillStyle = '#00FF00'; ctx.fillRect(0, 0, width, height);
  for (const [x, y, color] of [[0, 0, '#FF0000'], [.9, 0, '#0000FF'], [0, .9, '#FFFF00'], [.9, .9, '#00FFFF']]) {
    ctx.fillStyle = color; ctx.fillRect(width * x, height * y, width * .1, height * .1);
  }
  return canvas;
}

test('the 40 megapixel guard accepts its boundary and rejects invalid dimensions', () => {
  validateDimensions(10000, 4000);
  for (const [w, h] of [[10000, 4001], [16001, 1], [Infinity, 1], [0, 1], [1, NaN], [1.5, 1]]) {
    assert.throws(() => validateDimensions(w, h));
  }
});

test('bounded output never enlarges foreground for all fifteen templates, tiny photos, and fill mode', () => {
  for (const { id: template } of templates) for (const [iw, ih] of [[300, 200], [200, 300], [31, 27], [6000, 4000]]) {
    for (const longEdge of [256, 1920, 4096, 10000]) {
      const style = normalizeStyle({ template });
      const result = boundedLayout(iw, ih, style, longEdge);
      assert.ok(result.photo.w <= iw + 1e-8, template);
      assert.ok(result.photo.h <= ih + 1e-8, template);
      assert.ok(Math.max(result.width, result.height) <= Math.min(longEdge, 4096), template);
    }
  }
  const fill = boundedLayout(300, 200, normalizeStyle({ template: 'walkTicket', walkTicket: { photoMode: 'fill' } }), 4096);
  assert.ok(fill.photo.w <= 300 && fill.photo.h <= 200);
  const walk = boundedLayout(300, 200, normalizeStyle({}), 1920);
  assert.deepEqual({ width: walk.width, height: walk.height, photoWidth: walk.photo.w, photoHeight: walk.photo.h },
    { width: 300, height: 376, photoWidth: 300, photoHeight: 200 });
  assert.throws(() => boundedLayout(300, 200, normalizeStyle({}), NaN));
});

test('browser image analysis has exact independent red/blue proportions and clears failed cache entries', async () => {
  const canvas = createCanvas(4, 1), ctx = canvas.getContext('2d');
  ctx.fillStyle = '#FF0000'; ctx.fillRect(0, 0, 3, 1); ctx.fillStyle = '#0000FF'; ctx.fillRect(3, 0, 1, 1);
  const uri = canvas.toDataURL('image/png');
  const result = await analyzePhoto(uri, 2, 'dominance');
  assert.deepEqual(result.palette.map(c => [hex(c), c.fraction]), [['#FF0000', .75], ['#0000FF', .25]]);
  assert.equal(result.width, 4); assert.equal(result.height, 1);
  result.palette[0].r = 3;
  assert.equal(hex((await analyzePhoto(uri, 2, 'dominance')).palette[0]), '#FF0000');
  await assert.rejects(analyzePhoto('https://example.invalid/photo.jpg', 2, 'dominance'), /请选择/);
  await assert.rejects(analyzePhoto('data:image/png;base64,bm90LWEtcG5n', 2, 'dominance'), /无法解码/);
  assert.equal((await analyzePhoto(uri, 2, 'dominance')).width, 4);
});

test('actual browser adapter preserves four landmarks in every template and honors manual color', async () => {
  const uri = fixture().toDataURL('image/png'), manualWalk = { r: 169, g: 105, b: 107, fraction: 1 };
  for (const { id: template } of templates) {
    const style = normalizeStyle({ template, walkStamp: '' });
    const result = await renderPhoto(uri, style, 1920, false, { manualWalk });
    const bounds = boundedLayout(300, 200, style, 1920), p = bounds.photo;
    for (const [x, y, want] of [[.05, .05, [255, 0, 0]], [.95, .05, [0, 0, 255]], [.05, .95, [255, 255, 0]], [.95, .95, [0, 255, 255]]]) {
      assert.deepEqual(pixel(result, p.x + p.w * x, p.y + p.h * y), want, template);
    }
    if (template === 'colorWalk') assert.deepEqual(pixel(result, 3, 3), [169, 105, 107]);
  }
  const empty = await renderPhoto(uri, normalizeStyle({ walkBackground: 'horizontalStripes', walkStamp: '' }), 1920, false, { manualPalette: [] });
  assert.deepEqual(pixel(empty, 3, 3), [255, 255, 255]);
});

test('BMP imports match their independently specified bottom-up corner pixels', async () => {
  // A two-row 24-bit BMP uses BGR bytes, row padding, and stores its bottom row first.
  const bytes = Buffer.alloc(70);
  bytes.write('BM'); bytes.writeUInt32LE(70, 2); bytes.writeUInt32LE(54, 10); bytes.writeUInt32LE(40, 14);
  bytes.writeInt32LE(2, 18); bytes.writeInt32LE(2, 22); bytes.writeUInt16LE(1, 26); bytes.writeUInt16LE(24, 28);
  bytes.writeUInt32LE(16, 34);
  Buffer.from([0, 255, 255, 255, 255, 0, 0, 0, 0, 0, 255, 255, 0, 0, 0, 0]).copy(bytes, 54);
  const analysis = await analyzePhoto('data:image/bmp;base64,' + bytes.toString('base64'), 4, 'dominance');
  assert.equal(analysis.width, 2); assert.equal(analysis.height, 2);
  assert.deepEqual(analysis.palette.map(hex).sort(), ['#0000FF', '#00FFFF', '#FF0000', '#FFFF00']);
});

test('background blur changes the background while the foreground remains sharp', async () => {
  const image = createCanvas(300, 200), ctx = image.getContext('2d');
  ctx.fillStyle = '#FFFFFF'; ctx.fillRect(0, 0, 300, 200); ctx.fillStyle = '#000000'; ctx.fillRect(140, 0, 20, 200);
  const uri = image.toDataURL('image/png');
  const zero = await renderPhoto(uri, normalizeStyle({ template: 'softFrame', softFrame: { blur: 0, brightness: 0 } }), 1920, false);
  const high = await renderPhoto(uri, normalizeStyle({ template: 'softFrame', softFrame: { blur: .085, brightness: 0 } }), 1920, false);
  assert.deepEqual(pixel(zero, zero.width / 2, 3), [0, 0, 0]);
  assert.ok(pixel(high, high.width / 2, 3)[0] > 100);
  assert.deepEqual(pixel(high, high.width / 2, 80), [0, 0, 0]);
});

test('small photo barcode export reports inadequate physical resolution instead of upscaling', async () => {
  const uri = fixture().toDataURL('image/png');
  await assert.rejects(renderPhoto(uri, normalizeStyle({ template: 'tickets', ticketMark: 'barcode' }), 4096), /条码/);
  const preview = await renderPhoto(uri, normalizeStyle({ template: 'tickets', ticketMark: 'barcode' }), 4096, false);
  assert.ok(preview.width > 0);
});

test('all fifteen templates produce a local visual inspection sheet from a procedural test photo', async () => {
  const source = fixture(900, 600), sc = source.getContext('2d');
  const gradient = sc.createLinearGradient(0, 70, 900, 530);
  gradient.addColorStop(0, '#8BA4C0'); gradient.addColorStop(.5, '#D1C09B'); gradient.addColorStop(1, '#4A7257');
  sc.fillStyle = gradient; sc.fillRect(90, 60, 720, 480);
  const uri = source.toDataURL('image/png'), sheet = createCanvas(1500, 1900), ctx = sheet.getContext('2d');
  ctx.fillStyle = '#E7E6E0'; ctx.fillRect(0, 0, sheet.width, sheet.height);
  for (const [i, template] of templates.entries()) {
    const style = normalizeStyle({ template: template.id, ticketTitle: 'FRAME STUDIO', signature: 'Frame Studio' });
    const output = await renderPhoto(uri, style, 1200, false);
    const ratio = Math.min(450 / output.width, 320 / output.height), x = i % 3 * 500, y = Math.floor(i / 3) * 380;
    ctx.drawImage(output, x + (500 - output.width * ratio) / 2, y + 15, output.width * ratio, output.height * ratio);
    ctx.fillStyle = '#333333'; ctx.font = '18px sans-serif'; ctx.textAlign = 'center'; ctx.fillText(template.id, x + 250, y + 355);
  }
  fs.mkdirSync('.artifacts', { recursive: true });
  fs.writeFileSync(path.resolve('.artifacts/windows-template-contact-sheet.png'), sheet.toBuffer('image/png'));
});
