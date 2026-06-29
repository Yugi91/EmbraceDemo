/** Screenshot the WEB CLIENT APP UI (the demo screen with the action buttons).
 * Serves dist + opens it in a headless Chromium. Usage: node scripts/shot-app-ui.mjs <out.png> */
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { existsSync, mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DIST = path.join(path.resolve(__dirname, '..'), 'dist', 'embrace-demo-web', 'browser');
const OUT = process.argv[2] || path.join(path.resolve(__dirname, '../../..'), 'screenshots/embrace/web/app-ui.png');
mkdirSync(path.dirname(OUT), { recursive: true });
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.ico': 'image/x-icon', '.json': 'application/json', '.map': 'application/json' };

const server = http.createServer(async (req, res) => {
  try {
    const urlPath = decodeURIComponent((req.url || '/').split('?')[0]);
    let fp = path.join(DIST, urlPath === '/' ? 'index.html' : urlPath);
    if (!existsSync(fp)) fp = path.join(DIST, 'index.html');
    res.writeHead(200, { 'Content-Type': MIME[path.extname(fp)] || 'application/octet-stream' });
    res.end(await readFile(fp));
  } catch (e) { res.writeHead(500); res.end(String(e)); }
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const url = `http://127.0.0.1:${server.address().port}/`;
const browser = await chromium.launch({ args: ['--no-sandbox'] });
const page = await browser.newPage({ viewport: { width: 1366, height: 900 }, deviceScaleFactor: 2 });
await page.goto(url, { waitUntil: 'networkidle' });
await page.waitForTimeout(2500);
await page.screenshot({ path: OUT, fullPage: true });
console.log('app-ui ->', OUT);
await browser.close();
server.close();
