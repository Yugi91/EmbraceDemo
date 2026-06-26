// Screenshot a Grafana dashboard (anonymous admin) to a PNG.
// Usage: node scripts/shot-grafana.mjs "<url>" "<out.png>"
import { chromium } from 'playwright';

const url = process.argv[2];
const out = process.argv[3];
const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 1600, height: 1100 }, deviceScaleFactor: 2 });
const page = await ctx.newPage();
await page.goto(url, { waitUntil: 'load', timeout: 60000 });
// Grafana is a live SPA — give panels time to run their queries and render.
await page.waitForTimeout(11000);
await page.screenshot({ path: out, fullPage: true });
await browser.close();
console.log('shot ->', out);
