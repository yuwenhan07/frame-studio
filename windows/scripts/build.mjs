import { build } from 'esbuild';
import { mkdir, copyFile } from 'node:fs/promises';
await mkdir('dist', { recursive: true });
await build({ entryPoints: ['src/app.ts'], bundle: true, outfile: 'dist/app.js', platform: 'browser', target: 'chrome130', sourcemap: false, minify: true });
for (const name of ['index.html', 'style.css']) await copyFile(`src/${name}`, `dist/${name}`);
console.log('Built local renderer.');
