'use strict';

const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');

const MAX_FILE_BYTES = 40 * 1024 * 1024;
const MAX_OUTPUT_BYTES = 100 * 1024 * 1024;
const MAX_PIXELS = 40_000_000;
const MAX_PHOTOS = 50;
const MAX_BATCH_BYTES = 160 * 1024 * 1024;
const EXTENSIONS = new Set(['.jpg', '.jpeg', '.png', '.webp', '.bmp']);

function imageInfo(buffer, maxBytes = MAX_FILE_BYTES) {
  if (!Buffer.isBuffer(buffer) || buffer.length < 12 || buffer.length > maxBytes) throw new Error('图片为空、无效或超过 40 MiB 限制。');
  let width = 0, height = 0, mime = '';
  if (buffer.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) {
    if (buffer.length < 33 || buffer.toString('ascii', 12, 16) !== 'IHDR') throw new Error('PNG 文件头损坏。');
    width = buffer.readUInt32BE(16); height = buffer.readUInt32BE(20); mime = 'image/png';
  } else if (buffer[0] === 255 && buffer[1] === 216 && buffer[2] === 255) {
    let offset = 2;
    while (offset < buffer.length) {
      if (buffer[offset++] !== 255) throw new Error('JPEG 文件结构损坏。');
      while (buffer[offset] === 255) offset++;
      const marker = buffer[offset++];
      if (marker === 0xd9 || marker === 0xda) break;
      if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
      if (offset + 2 > buffer.length) break;
      const length = buffer.readUInt16BE(offset);
      if (length < 2 || offset + length > buffer.length) throw new Error('JPEG 文件结构损坏。');
      if ([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf].includes(marker)) {
        if (length < 8) throw new Error('JPEG 尺寸信息损坏。');
        height = buffer.readUInt16BE(offset + 3); width = buffer.readUInt16BE(offset + 5); break;
      }
      offset += length;
    }
    mime = 'image/jpeg';
  } else if (buffer.toString('ascii', 0, 4) === 'RIFF' && buffer.toString('ascii', 8, 12) === 'WEBP') {
    if (buffer.length < 30) throw new Error('WebP 文件头损坏。');
    const kind = buffer.toString('ascii', 12, 16);
    if (kind === 'VP8X') { width = 1 + buffer.readUIntLE(24, 3); height = 1 + buffer.readUIntLE(27, 3); }
    else if (kind === 'VP8 ' && buffer[23] === 0x9d && buffer[24] === 0x01 && buffer[25] === 0x2a) {
      width = buffer.readUInt16LE(26) & 0x3fff; height = buffer.readUInt16LE(28) & 0x3fff;
    } else if (kind === 'VP8L' && buffer[20] === 0x2f) {
      const bits = buffer.readUInt32LE(21); width = (bits & 0x3fff) + 1; height = ((bits >>> 14) & 0x3fff) + 1;
    }
    mime = 'image/webp';
  } else if (buffer.toString('ascii', 0, 2) === 'BM') {
    if (buffer.length < 26) throw new Error('BMP 文件头损坏。');
    const dibSize = buffer.readUInt32LE(14);
    if (dibSize === 12) { width = buffer.readUInt16LE(18); height = buffer.readUInt16LE(20); }
    else if (dibSize >= 40) { width = buffer.readInt32LE(18); height = Math.abs(buffer.readInt32LE(22)); }
    mime = 'image/bmp';
  }
  if (!mime || !Number.isSafeInteger(width) || !Number.isSafeInteger(height) || width <= 0 || height <= 0) throw new Error('无法识别图片。支持 JPEG、PNG、WebP、BMP。');
  if (width > 16000 || height > 16000 || width * height > MAX_PIXELS) throw new Error('图片尺寸超过限制（最长边 16000 像素、总计 4000 万像素）。');
  return { mime, width, height };
}

function sanitizeStem(value) {
  let stem = String(value).normalize('NFC').replace(/[<>:"/\\|?*\x00-\x1f]/g, '_').replace(/[. ]+$/g, '').trim();
  stem = Array.from(stem).slice(0, 100).join('');
  if (!stem) stem = '映框照片';
  if (/^(con|prn|aux|nul|com[1-9¹²³]|lpt[1-9¹²³])(?:\.|$)/i.test(stem)) stem = `_${stem}`;
  return stem;
}

function pathKey(value) { const result = path.resolve(value); return process.platform === 'win32' ? result.toLowerCase() : result; }
function idKey(stat) { return `${stat.dev}:${stat.ino}`; }
function cleanText(value, max = 250) { return typeof value === 'string' ? value.replace(/[\x00-\x1f]/g, ' ').trim().slice(0, max) : ''; }
function metadataFromExif(tags) {
  if (!tags || typeof tags !== 'object') return { brand: '', camera: '', parameters: '', date: '' };
  const focal = Number(tags.FocalLength), f = Number(tags.FNumber), exposure = Number(tags.ExposureTime), iso = Number(tags.ISO);
  const parts = [];
  if (Number.isFinite(focal) && focal > 0) parts.push(`${Number(focal.toFixed(1))}mm`);
  if (Number.isFinite(f) && f > 0) parts.push(`f/${Number(f.toFixed(1))}`);
  if (Number.isFinite(exposure) && exposure > 0) parts.push(exposure < 1 ? `1/${Math.round(1 / exposure)}s` : `${Number(exposure.toFixed(2))}s`);
  if (Number.isFinite(iso) && iso > 0) parts.push(`ISO ${Math.round(iso)}`);
  const date = tags.DateTimeOriginal;
  return { brand: cleanText(tags.Make), camera: cleanText(tags.Model), parameters: parts.join(' · '), date: date instanceof Date && !Number.isNaN(date.getTime()) ? `${date.getFullYear()}.${String(date.getMonth() + 1).padStart(2, '0')}.${String(date.getDate()).padStart(2, '0')}` : cleanText(date, 40).replace(/^(\d{4}):(\d{2}):(\d{2}).*/, '$1.$2.$3') };
}

class FileService {
  constructor({ processImage, parseExif = async () => null }) {
    if (typeof processImage !== 'function') throw new Error('Image decoder is required.');
    this.processImage = processImage;
    this.parseExif = parseExif;
    this.photos = new Map();
    this.activeIds = new Set();
    this.originalPaths = new Set();
    this.originalIdentities = new Set();
    this.folders = new Map();
  }

  async importPaths(paths, { records = null } = {}) {
    if (!Array.isArray(paths) || paths.length > MAX_PHOTOS) throw new Error('一次最多导入 50 张照片。');
    const photos = [], errors = [];
    let batchBytes = 0;
    for (let index = 0; index < paths.length; index++) {
      const sourcePath = paths[index];
      try {
        if (typeof sourcePath !== 'string' || !path.isAbsolute(sourcePath) || sourcePath.includes('\0')) throw new Error('来源必须是用户选择的本机图片。');
        if (!EXTENSIONS.has(path.extname(sourcePath).toLowerCase())) throw new Error('暂不支持此格式，请先转换为 JPEG、PNG、WebP 或 BMP。');
        const realPath = await fs.realpath(sourcePath);
        const handle = await fs.open(realPath, 'r');
        let buffer, stat, previous;
        try {
          stat = await handle.stat();
          if (!stat.isFile() || stat.size <= 0 || stat.size > MAX_FILE_BYTES) throw new Error('图片为空、不是普通文件或超过 40 MiB。');
          const restoredId = records?.[index]?.id;
          previous = (restoredId && this.photos.get(restoredId)) || [...this.photos.values()].find(photo => pathKey(photo.realPath || photo.path) === pathKey(realPath));
          if ((!previous || !this.activeIds.has(previous.id)) && this.activeIds.size >= MAX_PHOTOS) throw new Error('列表最多保留 50 张照片，请先移除部分照片。');
          const activeBytes = [...this.activeIds].reduce((sum, id) => sum + (id === previous?.id ? 0 : (this.photos.get(id)?.size || 0)), 0);
          if (activeBytes + stat.size > MAX_BATCH_BYTES) throw new Error('列表中图片总大小超过 160 MiB，请先移除部分照片。');
          batchBytes += stat.size;
          if (batchBytes > MAX_BATCH_BYTES) throw new Error('本批图片总大小超过 160 MiB，请分批导入。');
          buffer = Buffer.alloc(stat.size);
          let read = 0;
          while (read < buffer.length) {
            const result = await handle.read(buffer, read, buffer.length - read, read);
            if (!result.bytesRead) throw new Error('读取期间文件发生变化，请重试。');
            read += result.bytesRead;
          }
          const finalStat = await handle.stat();
          if ((await handle.read(Buffer.alloc(1), 0, 1, read)).bytesRead || finalStat.size !== stat.size || finalStat.mtimeMs !== stat.mtimeMs) throw new Error('读取期间文件发生变化，请重试。');
        } finally { await handle.close(); }
        const info = imageInfo(buffer);
        await this.processImage(buffer, info, null);
        let metadata = metadataFromExif(null);
        try { metadata = metadataFromExif(await this.parseExif(buffer)); } catch { /* EXIF is optional; a valid image remains usable. */ }
        const savedId = records?.[index]?.id;
        const id = typeof savedId === 'string' && /^[a-zA-Z0-9_-]{1,80}$/.test(savedId) ? savedId : (previous?.id || crypto.randomUUID());
        const changed = Boolean(previous && (previous.size !== stat.size || previous.modified !== stat.mtimeMs));
        const photo = { id, name: path.basename(sourcePath), path: sourcePath, dataUrl: `data:${info.mime};base64,${buffer.toString('base64')}`, width: info.width, height: info.height, metadata, changed };
        this.photos.set(id, { id, name: photo.name, path: sourcePath, realPath, identity: idKey(stat), size: stat.size, modified: stat.mtimeMs });
        this.activeIds.add(id);
        this.originalPaths.add(pathKey(sourcePath)); this.originalPaths.add(pathKey(realPath)); this.originalIdentities.add(idKey(stat));
        photos.push(photo);
      } catch (error) { errors.push(`${typeof sourcePath === 'string' ? path.basename(sourcePath) : '图片'}：${error.message}`); }
    }
    return { photos, errors };
  }

  async registerFolder(folder) {
    const realPath = await fs.realpath(folder);
    if (!(await fs.stat(realPath)).isDirectory()) throw new Error('请选择有效的输出文件夹。');
    const token = crypto.randomUUID(); this.folders.set(token, realPath); return token;
  }

  registerRestoredSources(records) {
    for (const record of records) {
      this.photos.set(record.id, { id: record.id, name: path.basename(record.path), path: record.path, size: record.size, modified: record.modified, missing: true });
      this.activeIds.add(record.id);
      this.originalPaths.add(pathKey(record.path));
    }
  }

  recordsForState(state) {
    if (!state || typeof state !== 'object' || Array.isArray(state) || !Array.isArray(state.photos) || state.photos.length > MAX_PHOTOS) throw new Error('会话照片列表无效。');
    const seen = new Set();
    const sources = state.photos.map(item => {
      if (!item || typeof item.id !== 'string' || seen.has(item.id) || !this.photos.has(item.id)) throw new Error('会话包含未导入或重复的照片。');
      seen.add(item.id); const photo = this.photos.get(item.id); return { id: photo.id, path: photo.path, ...(Number.isFinite(photo.size) && Number.isFinite(photo.modified) ? { size: photo.size, modified: photo.modified } : {}) };
    });
    this.activeIds = new Set(sources.map(source => source.id));
    return sources;
  }

  async assertNotOriginal(target) {
    if (this.originalPaths.has(pathKey(target))) throw new Error('不能覆盖任何已导入的原片，请更换文件名或输出位置。');
    try {
      const realPath = await fs.realpath(target), stat = await fs.stat(realPath);
      if (this.originalPaths.has(pathKey(realPath)) || this.originalIdentities.has(idKey(stat))) throw new Error('目标是已导入原片的别名，不能覆盖。');
    } catch (error) { if (error.code !== 'ENOENT') throw error; }
  }

  async exportImage({ dataUrl, photoId, format }, destination) {
    if (!this.photos.has(photoId) || this.photos.get(photoId).missing) throw new Error('请先导入要导出的照片。');
    if (!['png', 'jpeg'].includes(format)) throw new Error('输出格式无效。');
    const mime = format === 'png' ? 'image/png' : 'image/jpeg';
    const prefix = `data:${mime};base64,`;
    if (typeof dataUrl !== 'string' || !dataUrl.startsWith(prefix) || dataUrl.length > Math.ceil(MAX_OUTPUT_BYTES * 4 / 3) + 100) throw new Error('输出图片数据无效或超过 100 MiB。');
    const encoded = dataUrl.slice(prefix.length);
    if (!encoded.length || encoded.length % 4 !== 0 || !/^[A-Za-z0-9+/]*={0,2}$/.test(encoded)) throw new Error('输出图片编码无效。');
    const bytes = Buffer.from(encoded, 'base64'), info = imageInfo(bytes, MAX_OUTPUT_BYTES);
    if (info.mime !== mime) throw new Error('输出图片的格式与内容不匹配。');
    // Decode and re-encode pixels to exclude source EXIF/GPS and any non-image payload.
    const output = await this.processImage(bytes, info, format);
    const checked = imageInfo(output, MAX_OUTPUT_BYTES);
    if (checked.mime !== mime) throw new Error('输出图片编码失败。');
    const ext = format === 'png' ? '.png' : '.jpg';
    let folder, stem;
    if (destination.folderToken) {
      folder = this.folders.get(destination.folderToken);
      if (!folder) throw new Error('输出文件夹授权已过期，请重新选择。');
      const selectedPhoto = this.photos.get(photoId);
      stem = `${sanitizeStem(path.parse(selectedPhoto.name).name)}_映框`;
    } else {
      if (typeof destination.path !== 'string' || !path.isAbsolute(destination.path)) throw new Error('输出路径无效。');
      await this.assertNotOriginal(destination.path);
      folder = await fs.realpath(path.dirname(destination.path));
      stem = sanitizeStem(path.parse(destination.path).name);
    }
    // Resolve again: if a selected directory is replaced with a link, preserve the approved destination.
    if (pathKey(await fs.realpath(folder)) !== pathKey(folder)) throw new Error('输出文件夹位置已变化，请重新选择。');
    for (let suffix = 0; suffix < 10000; suffix++) {
      const target = path.join(folder, `${stem}${suffix ? ` (${suffix + 1})` : ''}${ext}`);
      await this.assertNotOriginal(target);
      let handle;
      try { handle = await fs.open(target, 'wx', 0o600); }
      catch (error) { if (error.code === 'EEXIST') continue; throw error; }
      try { await handle.writeFile(output); await handle.sync(); }
      catch (error) { await handle.close(); await fs.unlink(target).catch(() => {}); throw error; }
      await handle.close(); return { path: target };
    }
    throw new Error('同名文件过多，请更换输出名称。');
  }
}

module.exports = { FileService, imageInfo, sanitizeStem, metadataFromExif, MAX_FILE_BYTES, MAX_OUTPUT_BYTES, MAX_PIXELS, MAX_PHOTOS, MAX_BATCH_BYTES };
