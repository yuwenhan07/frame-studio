import { execFileSync } from 'node:child_process';
import { readdirSync } from 'node:fs';
execFileSync(process.execPath, ['node_modules/typescript/bin/tsc', '-p', 'tsconfig.json'], { stdio: 'inherit' });
const files = readdirSync('tests').filter(f => f.endsWith('.cjs')).map(f => `tests/${f}`);
execFileSync(process.execPath, ['--test', ...files], { stdio: 'inherit' });
