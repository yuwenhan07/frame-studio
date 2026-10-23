'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const { FileService, imageInfo, sanitizeStem, metadataFromExif, MAX_FILE_BYTES } = require('../electron/files.cjs');
const { SessionStore, serializeSession, validateSession } = require('../electron/session.cjs');
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zt9sAAAAASUVORK5CYII=', 'base64');
const DATA = `data:image/png;base64,${PNG.toString('base64')}`;
async function setup(t) {
  const folder = await fs.mkdtemp(path.join(os.tmpdir(), 'frame-files-'));
  t.after(() => fs.rm(folder, { recursive: true, force: true }));
  const source = path.join(folder, 'original.png'); await fs.writeFile(source, PNG);
  // Production uses Electron's native decoder; unit tests isolate file/permission policy.
  const service = new FileService({ processImage: async (bytes, _info, format) => { assert.deepEqual(bytes, PNG); return format ? Buffer.from(PNG) : undefined; } });
  const imported = await service.importPaths([source]); assert.equal(imported.errors.length, 0);
  const request = { photoId: imported.photos[0].id, dataUrl: DATA, format: 'png' };
  return { folder, source, service, request, photo: imported.photos[0] };
}

test('identifies supported raster signatures and rejects malformed or oversized dimensions', () => {
  assert.deepEqual(imageInfo(PNG), { mime: 'image/png', width: 1, height: 1 });
  assert.throws(() => imageInfo(Buffer.from('<html>not an image</html>')), /无法识别/);
  const oversized = Buffer.from(PNG); oversized.writeUInt32BE(20000, 16);
  assert.throws(() => imageInfo(oversized), /尺寸超过限制/);
  assert.throws(() => imageInfo(Buffer.alloc(MAX_FILE_BYTES + 1)), /超过/);
});

test('rejects unsupported extensions, missing files and damaged pixel data explicitly', async t => {
  const { folder, service } = await setup(t);
  const invalid = path.join(folder, 'invalid.png'), heic = path.join(folder, 'phone.heic');
  await fs.writeFile(invalid, '<html>not an image</html>'); await fs.writeFile(heic, PNG);
  const result = await service.importPaths([invalid, heic, path.join(folder, 'missing.jpg')]);
  assert.equal(result.photos.length, 0); assert.equal(result.errors.length, 3);
  assert.match(result.errors[1], /暂不支持/);
  const decoderFailure = new FileService({ processImage: async () => { throw new Error('decode failed'); } });
  const failed = await decoderFailure.importPaths([(await setup(t)).source]);
  assert.equal(failed.photos.length, 0); assert.match(failed.errors[0], /decode failed/);
});

test('never overwrites any imported original, symlink alias or hardlink alias', async t => {
  const { folder, source, service, request } = await setup(t);
  const other = path.join(folder, 'other.png'); await fs.writeFile(other, PNG); await service.importPaths([other]);
  await assert.rejects(service.exportImage(request, { path: source }), /不能覆盖/);
  await assert.rejects(service.exportImage(request, { path: other }), /不能覆盖/);
  const hard = path.join(folder, 'hard.png'); await fs.link(source, hard);
  await assert.rejects(service.exportImage(request, { path: hard }), /别名/);
  const symbolic = path.join(folder, 'alias.png');
  try { await fs.symlink(source, symbolic); await assert.rejects(service.exportImage(request, { path: symbolic }), /别名/); }
  catch (error) { if (process.platform !== 'win32' || !['EPERM', 'EACCES'].includes(error.code)) throw error; t.diagnostic('Windows symlink privilege unavailable; hardlink preservation was still tested.'); }
  assert.deepEqual(await fs.readFile(source), PNG); assert.deepEqual(await fs.readFile(other), PNG);
});

test('exclusive exports preserve existing data and allocate unique suffixes under concurrency', async t => {
  const { folder, service, request } = await setup(t);
  const target = path.join(folder, 'result.png'); await fs.writeFile(target, 'existing-output');
  const results = await Promise.all(Array.from({ length: 3 }, () => service.exportImage(request, { path: target })));
  assert.equal(new Set(results.map(result => result.path)).size, 3);
  assert.deepEqual(results.map(result => path.basename(result.path)).sort(), ['result (2).png', 'result (3).png', 'result (4).png']);
  assert.equal(await fs.readFile(target, 'utf8'), 'existing-output');
  for (const result of results) assert.deepEqual(await fs.readFile(result.path), PNG);
});

test('folder tokens do not accept renderer paths, and output signatures must match format', async t => {
  const { folder, service, request } = await setup(t);
  await assert.rejects(service.exportImage(request, { folderToken: folder }), /授权已过期/);
  const token = await service.registerFolder(folder);
  assert.notEqual(token, folder);
  assert.equal(path.basename((await service.exportImage(request, { folderToken: token })).path), 'original_映框.png');
  await assert.rejects(service.exportImage({ ...request, photoId: 'not-approved' }, { folderToken: token }), /先导入/);
  await assert.rejects(service.exportImage({ ...request, format: 'jpeg', dataUrl: DATA.replace('image/png', 'image/jpeg') }, { folderToken: token }), /格式与内容/);
  await assert.rejects(service.exportImage({ ...request, dataUrl: 'data:image/png;base64,%%%' }, { folderToken: token }), /编码无效/);
});

test('Windows filenames and EXIF date fields are safe and deterministic', () => {
  assert.equal(sanitizeStem('CON'), '_CON'); assert.equal(sanitizeStem('COM1.photo'), '_COM1.photo');
  assert.equal(sanitizeStem(' ../photo:*? '), '.._photo___');
  assert.equal(sanitizeStem('...'), '映框照片'); assert.equal(sanitizeStem('holiday.'), 'holiday');
  const metadata = metadataFromExif({ Make: 'Canon', Model: 'EOS R', FocalLength: 50, FNumber: 1.8, ExposureTime: 0.005, ISO: 100, DateTimeOriginal: '2026:10:23 12:30:00', GPSLatitude: 30 });
  assert.deepEqual(metadata, { brand: 'Canon', camera: 'EOS R', parameters: '50mm · f/1.8 · 1/200s · ISO 100', date: '2026.10.23' });
  assert.equal('GPSLatitude' in metadata, false);
});

test('sessions accept only registry identities and preserve missing approved entries', async t => {
  const { source, service, photo, request, folder } = await setup(t);
  const sourceStat = await fs.stat(source);
  assert.deepEqual(service.recordsForState({ photos: [{ id: photo.id, path: '/renderer/path' }] }), [{ id: photo.id, path: source, size: PNG.length, modified: sourceStat.mtimeMs }]);
  assert.throws(() => service.recordsForState({ photos: [{ id: 'arbitrary', path: source }] }), /未导入/);
  assert.throws(() => service.recordsForState({ photos: [{ id: photo.id }, { id: photo.id }] }), /重复/);
  service.registerRestoredSources([{ id: 'missing', path: path.join(folder, 'missing.png') }]);
  assert.deepEqual(service.recordsForState({ photos: [{ id: 'missing' }] }), [{ id: 'missing', path: path.join(folder, 'missing.png') }]);
  await assert.rejects(service.exportImage({ ...request, photoId: 'missing' }, { path: path.join(folder, 'out.png') }), /先导入/);
});

test('session save is serialized, strips pixel blobs, rotates valid previous snapshot and keeps empty lists', async t => {
  const { folder, photo, source } = await setup(t); const store = new SessionStore(path.join(folder, 'state'));
  assert.deepEqual(await store.load(), { session: null, errors: [] });
  const sources = [{ id: photo.id, path: source }];
  await store.save({ photos: [{ id: photo.id, dataUrl: DATA }], currentId: photo.id }, sources);
  assert.equal((await store.load()).session.state.photos[0].dataUrl, undefined);
  await Promise.all([store.save({ photos: [], marker: 2 }, []), store.save({ photos: [], marker: 3 }, [])]);
  assert.equal((await store.load()).session.state.marker, 3);
  assert.equal((await store.readOne(store.previous)).state.marker, 2);
  assert.deepEqual((await store.load()).session.state.photos, []);
});

test('corrupt primary recovers valid backup without destroying recovery evidence', async t => {
  const { folder } = await setup(t); const store = new SessionStore(path.join(folder, 'state'));
  await store.save({ photos: [], marker: 'first' }, []); await store.save({ photos: [], marker: 'second' }, []);
  await fs.writeFile(store.primary, '{not-json');
  const loaded = await store.load(); assert.equal(loaded.session.state.marker, 'first'); assert.equal(loaded.errors.length, 2);
  await store.save({ photos: [], marker: 'third' }, []);
  assert.equal((await store.readOne(store.previous)).state.marker, 'first');
  const recovery = await fs.readdir(path.join(store.directory, 'Recovery')); assert.equal(recovery.length, 1);
  assert.equal(await fs.readFile(path.join(store.directory, 'Recovery', recovery[0]), 'utf8'), '{not-json');
});

test('malformed session schemas and oversized state fail without replacing the session', async t => {
  const { folder } = await setup(t); const store = new SessionStore(path.join(folder, 'state'));
  await store.save({ photos: [], marker: 'valid' }, []);
  assert.throws(() => validateSession({ version: 1, state: { photos: [{ id: 'x' }] }, sources: [{ id: 'x', path: '../secret.png' }] }), /来源无效/);
  assert.throws(() => serializeSession({ photos: [], huge: 'a'.repeat(2 * 1024 * 1024) }, []), /超过 2 MiB/);
  await assert.rejects(store.save({ photos: [{ id: 'x' }] }, []), /格式无效/);
  assert.equal((await store.load()).session.state.marker, 'valid');
});


test('reimport preserves IDs, detects source replacement and persists size/mtime restoration evidence', async t => {
  const { service, source, photo } = await setup(t);
  const duplicate = await service.importPaths([source]);
  assert.equal(duplicate.photos[0].id, photo.id); assert.equal(duplicate.photos[0].changed, false);
  const records = service.recordsForState({ photos: [{ id: photo.id }] });
  const changedTime = new Date(Date.now() + 60_000); await fs.utimes(source, changedTime, changedTime);
  const changed = await service.importPaths([source]);
  assert.equal(changed.photos[0].id, photo.id); assert.equal(changed.photos[0].changed, true);
  const restored = new FileService({ processImage: async () => undefined });
  restored.registerRestoredSources(records);
  const result = await restored.importPaths([source], { records });
  assert.equal(result.photos[0].id, photo.id); assert.equal(result.photos[0].changed, true);
});

test('cumulative active limits match restoration limits and release capacity when removed', async t => {
  const { folder, service, photo } = await setup(t);
  for (let i = 0; i < 49; i++) service.registerRestoredSources([{ id: `missing-${i}`, path: path.join(folder, `missing-${i}.png`), size: 1, modified: 1 }]);
  const another = path.join(folder, 'another.png'); await fs.writeFile(another, PNG);
  const full = await service.importPaths([another]); assert.equal(full.photos.length, 0); assert.match(full.errors[0], /最多保留 50/);
  service.recordsForState({ photos: [{ id: photo.id }] });
  service.registerRestoredSources([{ id: 'large', path: path.join(folder, 'large.png'), size: 160 * 1024 * 1024, modified: 1 }]);
  const tooBig = await service.importPaths([another]); assert.equal(tooBig.photos.length, 0); assert.match(tooBig.errors[0], /总大小超过 160/);
  service.recordsForState({ photos: [{ id: photo.id }] });
  const accepted = await service.importPaths([another]); assert.equal(accepted.photos.length, 1);
  assert.equal(service.photos.get(accepted.photos[0].id).dataUrl, undefined);
});


test('both corrupt session snapshots survive later saves as distinct recovery files', async t => {
  const { folder } = await setup(t); const store = new SessionStore(path.join(folder, 'state'));
  await store.save({ photos: [], marker: 'first' }, []); await store.save({ photos: [], marker: 'second' }, []);
  await fs.writeFile(store.primary, '{damaged-primary'); await fs.writeFile(store.previous, '{damaged-previous');
  const loaded = await store.load(); assert.equal(loaded.session, null); assert.equal(loaded.errors.length, 2);
  await store.save({ photos: [], marker: 'restart' }, []);
  assert.equal(await fs.readFile(store.previous, 'utf8'), '{damaged-previous');
  await store.save({ photos: [], marker: 'newest' }, []);
  assert.equal((await store.readOne(store.previous)).state.marker, 'restart');
  assert.equal((await store.load()).session.state.marker, 'newest');
  const recovery = path.join(store.directory, 'Recovery');
  const recovered = await Promise.all((await fs.readdir(recovery)).map(filename => fs.readFile(path.join(recovery, filename), 'utf8')));
  assert.deepEqual(recovered.sort(), ['{damaged-previous', '{damaged-primary']);
});
