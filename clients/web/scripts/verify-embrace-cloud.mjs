/**
 * Dual-export verifier: fires the demo web actions with the Embrace Web SDK pointed at the Embrace
 * CLOUD dashboard (via ?embraceAppId=<id>) AND the local OTLP→Grafana exporters. Captures every
 * network call to Embrace's ingest hosts so we can confirm data is accepted (and see the region).
 *
 * Usage: node scripts/verify-embrace-cloud.mjs <APP_ID>     # APP_ID passed at runtime, never committed
 */
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const APP_ID = process.argv[2];
if (!APP_ID) { console.error('usage: node scripts/verify-embrace-cloud.mjs <APP_ID>'); process.exit(1); }

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DIST = path.join(path.resolve(__dirname, '..'), 'dist', 'embrace-demo-web', 'browser');
if (!existsSync(DIST)) { console.error(`dist not found at ${DIST} — run "npm run build" first.`); process.exit(1); }

const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.ico': 'image/x-icon', '.json': 'application/json', '.map': 'application/json' };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function startServer() {
  const server = http.createServer(async (req, res) => {
    try {
      const urlPath = decodeURIComponent((req.url || '/').split('?')[0]);
      let filePath = path.join(DIST, urlPath === '/' ? 'index.html' : urlPath);
      if (!existsSync(filePath)) filePath = path.join(DIST, 'index.html');
      const body = await readFile(filePath);
      res.writeHead(200, { 'Content-Type': MIME[path.extname(filePath)] || 'application/octet-stream' });
      res.end(body);
    } catch (e) { res.writeHead(500); res.end(String(e)); }
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve({ server, port: server.address().port })));
}

const isEmbrace = (u) => /emb-api\.com|embrace\.io|embrace\.com|\bemb(race)?[-.]/i.test(u);

(async () => {
  const { server, port } = await startServer();
  const baseUrl = `http://127.0.0.1:${port}`;
  const url = `${baseUrl}/?embraceAppId=${encodeURIComponent(APP_ID)}`;
  console.log(`serving ${DIST}\nopening ${url}`);
  const browser = await chromium.launch({ args: ['--no-sandbox'] });
  const embraceCalls = [];
  try {
    const ctx = await browser.newContext();
    const page = await ctx.newPage();
    page.on('response', (r) => { if (isEmbrace(r.url())) embraceCalls.push(`${r.status()}  ${r.request().method()}  ${r.url().slice(0, 110)}`); });
    page.on('requestfailed', (r) => { if (isEmbrace(r.url())) embraceCalls.push(`FAILED  ${r.url().slice(0, 110)}  (${r.failure()?.errorText})`); });

    await page.goto(url, { waitUntil: 'networkidle' });
    await page.waitForFunction(() => window.__demo && window.__demo.ready() === true, { timeout: 12000 }).catch(() => console.warn('  (warn) ready flag not true'));
    console.log(`  ready=${await page.evaluate(() => window.__demo?.ready?.())}, tool=${await page.evaluate(() => window.__demo?.tool?.())}`);
    await page.mouse.click(200, 200);
    for (const act of ['metric', 'network', 'caughtError', 'workflowOk', 'workflowFail', 'customEvent']) {
      console.log(`  firing: ${act}`);
      await page.evaluate((a) => window.__demo[a](), act);
      await sleep(act === 'network' || act === 'metric' ? 1500 : 300);   // network/metric take longer
    }
    await sleep(1500);
    await page.evaluate(() => window.__demo.flush()).catch(() => {});
    await sleep(2500);
    await ctx.close();

    // crash in its own load
    const cctx = await browser.newContext();
    const cpage = await cctx.newPage();
    cpage.on('response', (r) => { if (isEmbrace(r.url())) embraceCalls.push(`${r.status()}  ${r.request().method()}  ${r.url().slice(0, 110)}`); });
    await cpage.goto(url, { waitUntil: 'networkidle' });
    await cpage.waitForFunction(() => window.__demo && window.__demo.ready() === true, { timeout: 12000 }).catch(() => {});
    await cpage.mouse.click(200, 200);
    console.log('  firing: crash (unhandled)');
    await cpage.evaluate(() => window.__demo.crash());
    await sleep(1500);
    await cpage.evaluate(() => window.__demo.flush()).catch(() => {});
    await sleep(2500);
    await cctx.close();
  } finally {
    await browser.close();
    server.close();
  }
  console.log(`\n=== Embrace ingest network calls (${embraceCalls.length}) ===`);
  for (const c of embraceCalls) console.log('  ' + c);
  if (!embraceCalls.length) console.log('  (none — appId/region likely wrong, or SDK sent nothing)');
})();
