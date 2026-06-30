/** Drill into an Exception (Exceptions list -> exception detail: stack + session) for one app.
 *  Used for platforms where the "crash" is a handled/runtime exception, not a native crash
 *  (Flutter Dart errors, Web JS errors). */
import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';
const APP = process.argv[2] || 'tzb7f';
const PLAT = process.argv[3] || 'flutter';
const OUT = `/Users/ductx/Projects/pula/EmbraceGrafanaDemo/screenshots/embrace/${PLAT}/deep`;
mkdirSync(OUT, { recursive: true });
const BASE = `https://dash.embrace.io/app/${APP}`;
const b = await chromium.connectOverCDP('http://127.0.0.1:18800');
const ctx = b.contexts()[0];
let page = ctx.pages().find(p => { try { return p.url().includes('dash.embrace.io'); } catch { return false; } });
await page.bringToFront().catch(()=>{});
const cdp = await page.context().newCDPSession(page);
await cdp.send('Emulation.setDeviceMetricsOverride', { width:1920, height:1080, deviceScaleFactor:1, mobile:false });
const shot = async n => { await page.screenshot({ path:`${OUT}/${n}.png`, fullPage:false }); console.log('shot', n); };
const click = async sels => { for(const s of sels){ try{ await page.locator(s).first().click({timeout:2500}); return true; }catch{} } return false; };

await page.goto(`${BASE}/v/top_versions/session/hour/exception`, { waitUntil:'domcontentloaded', timeout:30000 });
await page.getByRole('button',{name:'Got it'}).click({timeout:1200}).catch(()=>{});
await page.waitForTimeout(5500);
await shot('exceptions');
// open the first exception group
if (await click(['a[href*="exception/"]','a[href*="_exception/"]','tbody tr:first-child a','tbody tr:first-child'])) {
  await page.waitForTimeout(5000);
  console.log('exc url=', page.url());
  await shot('exception-detail');
  // expand an affected session + Timeline/Logs tabs if present
  await click(['tbody tr:first-child button','tbody tr:first-child td:first-child']);
  await page.waitForTimeout(1500);
  for (const [t,n] of [['Timeline','exception-detail-timeline'],['Logs','exception-detail-logs']]) {
    if (await click([`text="${t}"`])) { await page.waitForTimeout(3000); await shot(n); }
  }
} else { console.log('no exception row to open'); }
await b.close();
console.log('done exc', PLAT);
