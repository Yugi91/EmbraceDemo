/**
 * Screenshot the Embrace cloud dashboard for one app (one PNG per "case" view) by attaching
 * (Playwright over CDP) to the already-logged-in OpenClaw-managed browser and REUSING its page.
 *
 * Usage: node scripts/shot-embrace-dash.mjs <APP_ID> <appName> [view1,view2,...]
 */
import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';

const APP_ID = process.argv[2];
const NAME = process.argv[3] || APP_ID;
if (!APP_ID) { console.error('usage: shot-embrace-dash.mjs <APP_ID> <name> [views]'); process.exit(1); }

const OUT = `/Users/ductx/Projects/pula/EmbraceGrafanaDemo/screenshots/embrace/${NAME}`;
mkdirSync(OUT, { recursive: true });

const ALL = {
  overview:   '/v/top_versions/session/hour/overview',
  sessions:   '/grouped_sessions/hour',
  issues:     '/v/top_versions/issue/hour/category',
  exceptions: '/v/top_versions/session/hour/exception',
  traces:     '/v/top_versions/root_spans/hour',
  'web-vitals': '/v/top_versions/vitals/hour',
  network:    '/v/top_versions/network/hour/summary',
};
const pick = process.argv[4]?.split(',');
const views = pick ? Object.fromEntries(pick.map((k) => [k, ALL[k]])) : ALL;

const browser = await chromium.connectOverCDP('http://127.0.0.1:18800');
const ctx = browser.contexts()[0];
const pages = ctx.pages();
console.log('existing pages:', pages.map((p) => { try { return p.url(); } catch { return '?'; } }));
let page = pages.find((p) => { try { return p.url().includes('dash.embrace.io'); } catch { return false; } }) || pages[0];
if (!page) { console.error('no usable page'); process.exit(1); }
await page.bringToFront().catch(() => {});
// Force full-screen render (CDP-attached real window ignores setViewportSize).
try {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Emulation.setDeviceMetricsOverride', { width: 1920, height: 1080, deviceScaleFactor: 1, mobile: false });
} catch (e) { console.log('viewport override failed:', e.message); }

for (const [name, suffix] of Object.entries(views)) {
  const url = `https://dash.embrace.io/app/${APP_ID}${suffix}`;
  try {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.getByRole('button', { name: 'Got it' }).click({ timeout: 2000 }).catch(() => {});
    await page.waitForTimeout(6500);
    const file = `${OUT}/${name}.png`;
    await page.screenshot({ path: file, fullPage: false });
    console.log('OK  ', name, '->', file);
  } catch (e) {
    console.log('FAIL', name, e.message.split('\n')[0]);
  }
}
await browser.close(); // disconnect only — does NOT close the OpenClaw browser
console.log('done:', NAME);
