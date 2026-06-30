/**
 * Headless verifier for the Embrace Grafana Demo web client.
 *
 * Serves the production build (dist/embrace-demo-web/browser) over a tiny static server,
 * opens the page with Playwright/Chromium, fires every demo action (delay, caught-error,
 * workflow ok, workflow fail, custom event) via the window.__demo hooks, flushes exporters,
 * then triggers the UNHANDLED crash in its own fresh page load (so it is a genuine uncaught
 * error). Repeats the run for both arms: Embrace (default) and plain OTel (?exporter=otel).
 *
 * Usage: node scripts/verify.mjs            # both arms
 *        node scripts/verify.mjs embrace    # one arm
 *        node scripts/verify.mjs otel
 */
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');
const DIST = path.join(ROOT, 'dist', 'embrace-demo-web', 'browser');

if (!existsSync(DIST)) {
  console.error(`dist not found at ${DIST} — run "npm run build" first.`);
  process.exit(1);
}

const MIME = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.css': 'text/css',
  '.ico': 'image/x-icon',
  '.json': 'application/json',
  '.map': 'application/json',
};

function startServer() {
  const server = http.createServer(async (req, res) => {
    try {
      const urlPath = decodeURIComponent((req.url || '/').split('?')[0]);
      let filePath = path.join(DIST, urlPath === '/' ? 'index.html' : urlPath);
      if (!existsSync(filePath)) filePath = path.join(DIST, 'index.html'); // SPA fallback
      const body = await readFile(filePath);
      res.writeHead(200, { 'Content-Type': MIME[path.extname(filePath)] || 'application/octet-stream' });
      res.end(body);
    } catch (e) {
      res.writeHead(500);
      res.end(String(e));
    }
  });
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => {
      const { port } = server.address();
      resolve({ server, port });
    });
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function runArm(browser, baseUrl, tool) {
  const suffix = tool === 'otel' ? '?exporter=otel' : '';
  console.log(`\n=== ARM: ${tool} ===`);

  // --- Main page: fire all non-crashing actions ---
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  const consoleErrors = [];
  page.on('console', (m) => {
    if (m.type() === 'error') consoleErrors.push(m.text());
  });
  page.on('pageerror', (e) => consoleErrors.push(`pageerror: ${e.message}`));

  await page.goto(`${baseUrl}/${suffix}`, { waitUntil: 'networkidle' });
  await page.waitForFunction(() => window.__demo && window.__demo.ready() === true, { timeout: 10000 })
    .catch(() => console.warn('  (warning) SDK ready flag not true within timeout'));

  const ready = await page.evaluate(() => window.__demo?.ready?.());
  const armName = await page.evaluate(() => window.__demo?.tool?.());
  console.log(`  page loaded, tool=${armName}, ready=${ready}`);

  // Simulate a real user interaction so Embrace starts a session part (needed for breadcrumbs/B3).
  await page.mouse.move(200, 200);
  await page.mouse.click(200, 200);

  console.log('  firing: metric');
  await page.evaluate(() => window.__demo.metric());
  console.log('  firing: caught-error');
  await page.evaluate(() => window.__demo.caughtError());
  console.log('  firing: workflow (ok)');
  await page.evaluate(() => window.__demo.workflowOk());
  console.log('  firing: workflow (force fail)');
  await page.evaluate(() => window.__demo.workflowFail());
  console.log('  firing: custom event');
  await page.evaluate(() => window.__demo.customEvent());

  await sleep(1500);
  console.log('  flushing exporters');
  await page.evaluate(() => window.__demo.flush()).catch((e) => console.warn('  flush err', e));
  await sleep(1500);
  await ctx.close();

  // --- Crash page: genuine unhandled error in its own load (B1) ---
  const crashCtx = await browser.newContext();
  const crashPage = await crashCtx.newPage();
  const crashErrors = [];
  crashPage.on('pageerror', (e) => crashErrors.push(e.message));
  await crashPage.goto(`${baseUrl}/${suffix}`, { waitUntil: 'networkidle' });
  await crashPage.waitForFunction(() => window.__demo && window.__demo.ready() === true, { timeout: 10000 }).catch(() => {});
  await crashPage.mouse.click(200, 200);
  console.log('  firing: crash (unhandled)');
  await crashPage.evaluate(() => window.__demo.crash());
  await sleep(1500);
  // End session / flush so the crash + its session export are sent before close.
  await crashPage.evaluate(() => window.__demo.flush()).catch(() => {});
  await sleep(2000);
  console.log(`  observed unhandled pageerror(s): ${JSON.stringify(crashErrors)}`);
  await crashCtx.close();

  if (consoleErrors.length) {
    console.log(`  console errors during main run: ${JSON.stringify(consoleErrors.slice(0, 5))}`);
  }
}

(async () => {
  const arms = process.argv[2] ? [process.argv[2]] : ['embrace', 'otel'];
  const { server, port } = await startServer();
  const baseUrl = `http://127.0.0.1:${port}`;
  console.log(`static server on ${baseUrl} serving ${DIST}`);
  const browser = await chromium.launch({ args: ['--no-sandbox'] });
  try {
    for (const arm of arms) {
      await runArm(browser, baseUrl, arm);
    }
  } finally {
    await browser.close();
    server.close();
  }
  console.log('\nverify: done. Allow a few seconds for OTLP batches, then query Grafana.');
})();
