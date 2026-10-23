'use strict';
const { contextBridge, ipcRenderer, webUtils } = require('electron');

const invoke = (channel, payload) => ipcRenderer.invoke(`frame-studio:${channel}`, payload);
contextBridge.exposeInMainWorld('frameStudio', Object.freeze({
  importPhotos: () => invoke('import-photos'),
  importDropped: files => {
    if (!Array.isArray(files) || files.length > 50) return Promise.reject(new Error('一次最多导入 50 张照片。'));
    // Chromium supplies the backing path; renderer-created File objects produce an empty path.
    const paths = files.map(file => webUtils.getPathForFile(file)).filter(Boolean);
    return invoke('import-dropped', paths);
  },
  loadSample: () => invoke('load-sample'),
  loadSession: () => invoke('load-session'),
  saveSession: state => invoke('save-session', state),
  exportPhoto: request => invoke('export-photo', request),
  chooseExportFolder: () => invoke('choose-export-folder'),
  exportToFolder: request => invoke('export-to-folder', request),
  onBeforeClose: callback => {
    if (typeof callback !== 'function') throw new TypeError('Close handler must be a function.');
    const listener = () => callback();
    ipcRenderer.on('frame-studio:before-close', listener);
    return () => ipcRenderer.removeListener('frame-studio:before-close', listener);
  },
  confirmClose: () => invoke('confirm-close'),
}));
