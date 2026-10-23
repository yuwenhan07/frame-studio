import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  testMatch: 'app.spec.ts',
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 180_000,
  expect: { timeout: 15_000 },
  reporter: [['list'], ['json', { outputFile: '.artifacts/app-test-results.json' }]],
  outputDir: '.artifacts/playwright',
  use: { trace: 'retain-on-failure' },
});
