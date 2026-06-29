/** Screenshot the CURRENT dash.embrace.io page (full page) to a file, via CDP to the OpenClaw browser.
 * Usage: node scripts/shot-current.mjs <out.png> */
import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';
import path from 'node:path';
const OUT = process.argv[2];
if (!OUT) { console.error('usage: shot-current.mjs <out.png>'); process.exit(1); }
mkdirSync(path.dirname(OUT), { recursive: true });
const b = await chromium.connectOverCDP('http://127.0.0.1:18800');
const ctx = b.contexts()[0];
const page = ctx.pages().find((p) => { try { return p.url().includes('dash.embrace.io'); } catch { return false; } }) || ctx.pages()[0];
console.log('page:', page.url());
// Force a full-screen render size (CDP-attached real window ignores setViewportSize).
try {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Emulation.setDeviceMetricsOverride', { width: 1920, height: 1080, deviceScaleFactor: 1, mobile: false });
} catch (e) { console.log('viewport override failed:', e.message); }
const NAV = process.argv[3];
if (NAV && NAV.startsWith('http')) {
  try { await page.goto(NAV, { waitUntil: 'domcontentloaded', timeout: 35000 }); }
  catch { await page.waitForTimeout(3000); }
  await page.waitForTimeout(4000);
}
await page.getByRole('button', { name: 'Got it' }).click({ timeout: 2500 }).catch(() => {});
await page.keyboard.press('Escape').catch(() => {});
await page.waitForTimeout(1200);
// Expand any inner vertical scroll containers so fullPage captures ALL rows (the timeline
// details table scrolls internally → otherwise only the first few rows are captured).
await page.evaluate(() => {
  for (const el of Array.from(document.querySelectorAll('*'))) {
    const s = getComputedStyle(el);
    if ((s.overflowY === 'auto' || s.overflowY === 'scroll') && el.scrollHeight > el.clientHeight + 40) {
      el.style.maxHeight = 'none';
      el.style.height = 'auto';
      el.style.overflow = 'visible';
    }
  }
}).catch(() => {});
await page.waitForTimeout(1200);
await page.screenshot({ path: OUT, fullPage: true });
console.log('shot ->', OUT);
await b.close();
