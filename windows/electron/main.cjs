'use strict';
const { app, BrowserWindow, dialog, ipcMain, nativeImage, protocol, session, Menu } = require('electron');
const path = require('node:path');
const fs = require('node:fs/promises');
const exifr = require('exifr');
const { FileService, sanitizeStem } = require('./files.cjs');
const { SessionStore } = require('./session.cjs');

const APP_URL = 'app://bundle/index.html';
const DIST = path.join(__dirname, '..', 'dist');
const smokeArgument = process.argv.find(arg => arg.startsWith('--smoke-test='));
const testMode = !app.isPackaged || Boolean(smokeArgument) || process.argv.includes('--test-mode');
app.setName('FrameStudioWindows');
app.setPath('userData', testMode && process.env.FRAME_STUDIO_USER_DATA ? path.resolve(process.env.FRAME_STUDIO_USER_DATA) : path.join(app.getPath('appData'), 'FrameStudioWindows'));
protocol.registerSchemesAsPrivileged([{ scheme: 'app', privileges: { standard: true, secure: true, supportFetchAPI: true } }]);
app.enableSandbox();
app.commandLine.appendSwitch('disable-features', 'AutofillServerCommunication,OptimizationHints,MediaRouter');

const files = new FileService({
  processImage: async (buffer, info, format) => {
    if (!format && ['image/webp', 'image/bmp'].includes(info.mime)) {
      await decodeBrowserImport(buffer, info);
      return undefined;
    }
    const decoded = nativeImage.createFromBuffer(buffer);
    if (decoded.isEmpty()) throw new Error('图片内容损坏或当前系统无法解码此格式。');
    const { width, height } = decoded.getSize();
    if (!width || !height || width * height > 40_000_000 || width > 16000 || height > 16000) throw new Error('解码后的图片尺寸超过限制。');
    return format ? (format === 'png' ? decoded.toPNG() : decoded.toJPEG(95)) : undefined;
  },
  parseExif: buffer => exifr.parse(buffer, {
    pick: ['Make', 'Model', 'FocalLength', 'FNumber', 'ExposureTime', 'ISO', 'DateTimeOriginal'],
    gps: false, exif: true, tiff: true, iptc: false, xmp: false, icc: false, jfif: false,
    reviveValues: false,
  }),
});
const sessions = new SessionStore(app.getPath('userData'));
const inFlight = new Set();
let mainWindow = null, closeApproved = false, rendererReady = false, sessionLoaded = false;

async function decodeBrowserImport(buffer, info) {
  if (!mainWindow || mainWindow.isDestroyed()) throw new Error('图片解码窗口不可用，请重试。');
  // NativeImage only guarantees PNG/JPEG. Chromium decodes these import-only formats
  // in the existing sandbox, using the same decoder as the eventual canvas renderer.
  // The only interpolated value is a generated raster data URL, never renderer code or a path.
  const dataUrl = `data:${info.mime};base64,${buffer.toString('base64')}`;
  const code = `new Promise((resolve, reject) => {
    const image = new Image();
    const dispose = () => { clearTimeout(timer); image.onload = null; image.onerror = null; image.src = ''; };
    const timer = setTimeout(() => { dispose(); reject(new Error('图片解码超时。')); }, 15000);
    image.onload = () => {
      const dimensions = { width: image.naturalWidth, height: image.naturalHeight };
      dispose(); resolve(dimensions);
    };
    image.onerror = () => { dispose(); reject(new Error('图片内容损坏或当前系统无法解码此格式。')); };
    image.src = ${JSON.stringify(dataUrl)};
  })`;
  const result = await mainWindow.webContents.executeJavaScriptInIsolatedWorld(1001, [{ code }]);
  if (!result || !Number.isSafeInteger(result.width) || !Number.isSafeInteger(result.height) || result.width <= 0 || result.height <= 0 || result.width > 16000 || result.height > 16000 || result.width * result.height > 40_000_000) throw new Error('解码后的图片尺寸超过限制。');
}

function assertSender(event) {
  if (!mainWindow || mainWindow.isDestroyed() || event.sender !== mainWindow.webContents || event.senderFrame !== mainWindow.webContents.mainFrame || event.senderFrame.url !== APP_URL) throw new Error('拒绝来自未授权页面的请求。');
}
function handle(name, handler) {
  ipcMain.handle(`frame-studio:${name}`, async (event, payload) => {
    assertSender(event);
    const operation = Promise.resolve().then(() => handler(payload));
    if (name !== 'confirm-close') inFlight.add(operation);
    try { return await operation; }
    catch (error) { console.error(`[${name}] ${error.message}`); throw new Error(error.message || '操作失败，请重试。'); }
    finally { inFlight.delete(operation); }
  });
}
function assertExportRequest(request) {
  if (!request || typeof request !== 'object' || typeof request.photoId !== 'string' || !['png', 'jpeg'].includes(request.format)) throw new Error('导出请求无效。');
  const photo = files.photos.get(request.photoId);
  if (!photo || photo.missing) throw new Error('照片未导入或原文件不可用。');
  return photo;
}
function registerHandlers() {
  handle('import-photos', async () => {
    const result = await dialog.showOpenDialog(mainWindow, { title: '选择照片', properties: ['openFile', 'multiSelections'], filters: [{ name: '照片（JPEG / PNG / WebP / BMP）', extensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp'] }] });
    return result.canceled ? { photos: [], errors: [] } : files.importPaths(result.filePaths);
  });
  handle('import-dropped', paths => files.importPaths(paths));
  handle('load-sample', () => files.importPaths([path.join(__dirname, '..', 'assets', 'sample.jpg')], { records: [{ id: 'sample' }] }));
  handle('load-session', async () => {
    // Restoration grants are sourced solely from the app-owned session, never renderer-provided paths.
    const { session: saved, errors } = await sessions.load();
    sessionLoaded = true;
    if (!saved) return { state: null, photos: [], errors };
    const sources = saved.sources.map(source => source.id === 'sample' ? { ...source, path: path.join(__dirname, '..', 'assets', 'sample.jpg') } : source);
    files.registerRestoredSources(sources);
    const result = await files.importPaths(sources.map(source => source.path), { records: sources });
    return { state: saved.state, photos: result.photos, errors: [...errors, ...result.errors] };
  });
  handle('save-session', state => {
    if (!sessionLoaded) throw new Error('请等待会话恢复完成后再保存。');
    return sessions.save(state, files.recordsForState(state));
  });
  handle('choose-export-folder', async () => {
    const result = await dialog.showOpenDialog(mainWindow, { title: '选择导出文件夹', properties: ['openDirectory', 'createDirectory'] });
    return result.canceled ? null : files.registerFolder(result.filePaths[0]);
  });
  handle('export-photo', async request => {
    const photo = assertExportRequest(request);
    const extension = request.format === 'png' ? 'png' : 'jpg';
    const result = await dialog.showSaveDialog(mainWindow, { title: '导出照片（已有文件会自动追加编号）', defaultPath: `${sanitizeStem(path.parse(photo.name).name)}_映框.${extension}`, filters: [{ name: request.format === 'png' ? 'PNG 图片' : 'JPEG 图片', extensions: [extension] }], properties: ['createDirectory'] });
    if (result.canceled || !result.filePath) return { canceled: true };
    return files.exportImage(request, { path: result.filePath });
  });
  handle('export-to-folder', request => { assertExportRequest(request); return files.exportImage(request, { folderToken: request.folder }); });
  handle('confirm-close', async () => {
    // A quit cannot cut an exclusive output file off while its write/fsync is in progress.
    while (inFlight.size) await Promise.allSettled([...inFlight]);
    await sessions.queue; closeApproved = true; mainWindow.close();
  });
}

const CSP = "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'none'; object-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'";
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.svg': 'image/svg+xml', '.woff': 'font/woff', '.woff2': 'font/woff2', '.ttf': 'font/ttf', '.otf': 'font/otf', '.ico': 'image/x-icon' };
async function configureSession() {
  const ses = session.defaultSession;
  ses.setPermissionRequestHandler((_webContents, _permission, callback) => callback(false));
  ses.setPermissionCheckHandler(() => false);
  ses.on('will-download', event => event.preventDefault());
  ses.webRequest.onBeforeRequest({ urls: ['<all_urls>'] }, (details, callback) => {
    let allowed = false;
    try { const url = new URL(details.url); allowed = (url.protocol === 'app:' && url.hostname === 'bundle') || ['data:', 'blob:'].includes(url.protocol); } catch {}
    callback({ cancel: !allowed });
  });
  protocol.handle('app', async request => {
    try {
      const url = new URL(request.url);
      if (url.hostname !== 'bundle' || request.method !== 'GET' || url.username || url.password || url.port) return new Response('Forbidden', { status: 403 });
      const pathname = decodeURIComponent(url.pathname);
      const resource = pathname === '/sample.jpg' ? path.join(__dirname, '..', 'assets', 'sample.jpg') : path.resolve(DIST, `.${pathname}`);
      const relative = path.relative(DIST, resource);
      if (pathname !== '/sample.jpg' && (!relative || relative.startsWith('..') || path.isAbsolute(relative))) return new Response('Forbidden', { status: 403 });
      const mime = MIME[path.extname(resource).toLowerCase()];
      if (!mime) return new Response('Forbidden', { status: 403 });
      return new Response(await fs.readFile(resource), { headers: { 'Content-Type': mime, 'Content-Security-Policy': CSP, 'X-Content-Type-Options': 'nosniff', 'Cache-Control': 'no-store' } });
    } catch { return new Response('Not found', { status: 404 }); }
  });
}
async function createWindow() {
  closeApproved = false; rendererReady = false;
  mainWindow = new BrowserWindow({
    width: 1440, height: 940, minWidth: 1050, minHeight: 720, title: '映框 · Frame Studio', backgroundColor: '#f5f2ec', icon: path.join(__dirname, '..', 'assets', 'icon.png'), show: !smokeArgument,
    webPreferences: { preload: path.join(__dirname, 'preload.cjs'), sandbox: true, contextIsolation: true, nodeIntegration: false, nodeIntegrationInWorker: false, nodeIntegrationInSubFrames: false, webSecurity: true, allowRunningInsecureContent: false, webviewTag: false, devTools: !app.isPackaged, spellcheck: false, navigateOnDragDrop: false },
  });
  mainWindow.removeMenu();
  mainWindow.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  mainWindow.webContents.on('will-navigate', event => event.preventDefault());
  mainWindow.webContents.on('will-redirect', event => event.preventDefault());
  mainWindow.webContents.on('will-attach-webview', event => event.preventDefault());
  mainWindow.webContents.on('render-process-gone', (_event, detail) => { rendererReady = false; console.error(`Renderer stopped: ${detail.reason}`); });
  mainWindow.webContents.on('console-message', details => { if (details.level === 'error' || details.level === 'warning') console.error(`Renderer ${details.level}: ${details.message}`); });
  mainWindow.on('close', event => {
    if (!closeApproved && rendererReady && !smokeArgument) { event.preventDefault(); mainWindow.webContents.send('frame-studio:before-close'); }
  });
  mainWindow.on('closed', () => { mainWindow = null; });
  await mainWindow.loadURL(APP_URL);
  rendererReady = true;
  if (smokeArgument) {
    const resultPath = path.resolve(smokeArgument.slice('--smoke-test='.length));
    try {
      // The packaged smoke confirms the actual local renderer, isolation and bridge startup.
      const result = await mainWindow.webContents.executeJavaScript(`new Promise((resolve, reject) => {
        const deadline = Date.now() + 20000;
        function check() {
          if (document.body?.dataset.ready === 'error') return reject(new Error('Renderer initialization failed.'));
          if (document.body?.dataset.ready === 'true') {
            const canvas = document.querySelector('#preview canvas');
            if (!canvas || canvas.width < 1 || canvas.height < 1 || document.querySelectorAll('#templates button').length !== 15) return reject(new Error('Initial sample preview or templates are missing.'));
            return resolve({ title: document.title, ready: document.readyState, appReady: true, previewWidth: canvas.width, previewHeight: canvas.height, bridge: typeof window.frameStudio?.importPhotos === 'function', nodeDisabled: typeof window.require === 'undefined', url: location.href });
          }
          if (Date.now() > deadline) return reject(new Error('Renderer initialization timed out.'));
          setTimeout(check, 50);
        }
        check();
      })`);
      if (!result.bridge || !result.nodeDisabled || result.url !== APP_URL) throw new Error('Renderer security/startup smoke failed.');
      await fs.writeFile(resultPath, JSON.stringify({ ok: true, platform: process.platform, arch: process.arch, ...result }, null, 2));
      closeApproved = true; app.exit(0);
    } catch (error) { await fs.writeFile(resultPath, JSON.stringify({ ok: false, error: error.message })); app.exit(1); }
  }
}
if (!app.requestSingleInstanceLock()) app.quit();
else {
  app.on('second-instance', () => { if (mainWindow) { if (mainWindow.isMinimized()) mainWindow.restore(); mainWindow.focus(); } });
  app.whenReady().then(async () => { Menu.setApplicationMenu(null); await configureSession(); registerHandlers(); await createWindow(); }).catch(error => { console.error(error); app.exit(1); });
  app.on('window-all-closed', () => app.quit());
}
