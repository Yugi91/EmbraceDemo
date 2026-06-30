/** Web JS Exceptions: clear any stuck filter, shot the list, then drill into one exception. */
import { chromium } from 'playwright';
const APP = 'ctac2', PLAT = 'web';
const OUT = `/Users/ductx/Projects/pula/EmbraceGrafanaDemo/screenshots/embrace/${PLAT}/deep`;
const b = await chromium.connectOverCDP('http://127.0.0.1:18800');
const ctx = b.contexts()[0];
let page = ctx.pages().find(p => { try { return p.url().includes('dash.embrace.io'); } catch { return false; } });
await page.bringToFront().catch(()=>{});
const cdp = await page.context().newCDPSession(page);
await cdp.send('Emulation.setDeviceMetricsOverride', { width:1920, height:1080, deviceScaleFactor:1, mobile:false });
const shot = async n => { await page.screenshot({ path:`${OUT}/${n}.png`, fullPage:false }); console.log('shot', n); };
const click = async sels => { for(const s of sels){ try{ await page.locator(s).first().click({timeout:2500}); return true; }catch{} } return false; };

await page.goto(`https://dash.embrace.io/app/${APP}/v/top_versions/session/hour/exception`, { waitUntil:'domcontentloaded', timeout:30000 });
await page.getByRole('button',{name:'Got it'}).click({timeout:1200}).catch(()=>{});
await page.waitForTimeout(4000);
await click(['text="Clear all"']);            // drop the stuck is_handled filter
await page.waitForTimeout(4000);
await shot('exceptions');
// drill into the first exception by clicking its description (NOT the filter chip)
if (await click(['tbody tr:first-child td:nth-child(4)','tbody tr:first-child a','tbody tr:first-child'])) {
  await page.waitForTimeout(5000);
  console.log('exc url=', page.url());
  await shot('exception-detail');
}
await b.close();
console.log('done web-exc');
