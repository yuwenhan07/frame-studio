'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const MAX_SESSION_BYTES = 2 * 1024 * 1024;

function serializeSession(state, sources) {
  const text = JSON.stringify({ version: 1, savedAt: new Date().toISOString(), state, sources }, (key, value) => ['dataUrl', 'realPath', 'identity', '__proto__', 'constructor', 'prototype'].includes(key) ? undefined : value);
  if (Buffer.byteLength(text) > MAX_SESSION_BYTES) throw new Error('会话设置超过 2 MiB，未保存。');
  validateSession(JSON.parse(text));
  return text;
}
function validateSession(value) {
  if (!value || value.version !== 1 || !value.state || typeof value.state !== 'object' || Array.isArray(value.state) || !Array.isArray(value.state.photos) || !Array.isArray(value.sources) || value.sources.length > 50 || value.state.photos.length !== value.sources.length) throw new Error('会话文件格式无效。');
  const seen = new Set();
  for (let i = 0; i < value.sources.length; i++) {
    const record = value.sources[i];
    if (!record || typeof record.id !== 'string' || !/^[a-zA-Z0-9_-]{1,80}$/.test(record.id) || seen.has(record.id) || typeof record.path !== 'string' || !path.isAbsolute(record.path) || record.path.includes('\0') || value.state.photos[i]?.id !== record.id) throw new Error('会话照片来源无效。');
    if ((record.size !== undefined && (!Number.isSafeInteger(record.size) || record.size < 0)) || (record.modified !== undefined && (!Number.isFinite(record.modified) || record.modified < 0))) throw new Error('会话照片文件属性无效。');
    seen.add(record.id);
  }
  return value;
}
class SessionStore {
  constructor(directory) { this.directory = directory; this.primary = path.join(directory, 'Session.json'); this.previous = path.join(directory, 'Session.previous.json'); this.queue = Promise.resolve(); }
  async readOne(file) {
    const stat = await fs.stat(file);
    if (!stat.isFile() || stat.size > MAX_SESSION_BYTES) throw new Error('会话文件超过大小限制或不是普通文件。');
    return validateSession(JSON.parse(await fs.readFile(file, 'utf8')));
  }
  async load() {
    await this.queue;
    const errors = [];
    try { return { session: await this.readOne(this.primary), errors }; }
    catch (error) { if (error.code !== 'ENOENT') errors.push(`主会话读取失败：${error.message}`); }
    try { const session = await this.readOne(this.previous); errors.push('已恢复上一份有效会话备份。'); return { session, errors }; }
    catch (error) { if (error.code !== 'ENOENT') errors.push(`会话备份读取失败：${error.message}`); }
    return { session: null, errors };
  }
  save(state, sources) {
    // Serialize before joining the queue so the caller cannot change this snapshot later.
    let text;
    try { text = serializeSession(state, sources); } catch (error) { return Promise.reject(error); }
    const pending = this.queue.then(() => this.write(text));
    this.queue = pending.catch(() => {});
    return pending;
  }
  async write(text) {
    await fs.mkdir(this.directory, { recursive: true, mode: 0o700 });
    const temporary = path.join(this.directory, `.Session-${crypto.randomUUID()}.tmp`);
    const backupTemporary = path.join(this.directory, `.Session-previous-${crypto.randomUUID()}.tmp`);
    try {
      const handle = await fs.open(temporary, 'wx', 0o600);
      try { await handle.writeFile(text, 'utf8'); await handle.sync(); } finally { await handle.close(); }
      let prior;
      try { prior = await this.readOne(this.primary); }
      catch (error) {
        if (error.code !== 'ENOENT') {
          // Preserve a corrupt primary for manual recovery; never replace a valid backup with it.
          const recovery = path.join(this.directory, 'Recovery');
          await fs.mkdir(recovery, { recursive: true, mode: 0o700 });
          await fs.copyFile(this.primary, path.join(recovery, `Session-${Date.now()}-${crypto.randomUUID()}.json`), require('node:fs').constants.COPYFILE_EXCL);
        }
      }
      if (prior) {
        try { await this.readOne(this.previous); }
        catch (error) {
          if (error.code !== 'ENOENT') {
            // A damaged previous snapshot is still recovery evidence; retain it before rotation.
            const recovery = path.join(this.directory, 'Recovery');
            await fs.mkdir(recovery, { recursive: true, mode: 0o700 });
            await fs.copyFile(this.previous, path.join(recovery, `Session.previous-${Date.now()}-${crypto.randomUUID()}.json`), require('node:fs').constants.COPYFILE_EXCL);
          }
        }
        await fs.writeFile(backupTemporary, JSON.stringify(prior), { flag: 'wx', mode: 0o600 });
        await fs.rename(backupTemporary, this.previous);
      }
      await fs.rename(temporary, this.primary);
    } finally {
      await fs.unlink(temporary).catch(() => {}); await fs.unlink(backupTemporary).catch(() => {});
    }
  }
}
module.exports = { SessionStore, serializeSession, validateSession, MAX_SESSION_BYTES };
