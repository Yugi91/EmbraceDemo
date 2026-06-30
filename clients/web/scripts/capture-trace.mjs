/** Capture a named root-span trace waterfall (summary + expanded instance tree).
 *  Usage: capture-trace.mjs <APP> <PLAT> <spanName> [outName] */
import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';
const [APP, PLAT, SPAN, OUTNAME] = process.argv.slice(2);
const OUT = `/Users/ductx/Projects/pula/EmbraceGrafanaDemo/screenshots/embrace/${PLAT}/deep`;
mkdirSync(OUT, { recursive: true });
const name = OUTNAME || `trace-${SPAN}-waterfall`;
const b = await chromium.connectOverCDP('http://127.0.0.1:18800');
const ctx = b.contexts()[0];
let page = ctx.pages().find(p => { try { return p.url().includes('dash.embrace.io'); } catch { return false; } });
await page.bringToFront().catch(()=>{});
const cdp = await page.context().newCDPSession(page);
await cdp.send('Emulation.setDeviceMetricsOverride', { width:1920, height:1080, deviceScaleFactor:1, mobile:false });
const click = async sels => { for(const s of sels){ try{ await page.locator(s).first().click({timeout:2500}); return true; }catch{} } return false; };

await page.goto(`https://dash.embrace.io/app/${APP}/v/top_versions/root_spans/hour`, { waitUntil:'domcontentloaded', timeout:30000 });
await page.getByRole('button',{name:'Got it'}).click({timeout:1200}).catch(()=>{});
await page.waitForTimeout(5500);
if (await click([`a:has-text("${SPAN}")`, `tr:has-text("${SPAN}") a`, `text="${SPAN}"`])) {
  await page.waitForTimeout(4500);
  // expand the first instance row to reveal the span tree
  await click(['tbody tr:first-child button','tbody tr:first-child svg','tbody tr:first-child td:first-child']);
  await page.waitForTimeout(3000);
  console.log('url=', page.url());
  await page.screenshot({ path:`${OUT}/${name}.png`, fullPage:false });
  console.log('shot', `${PLAT}/${name}`);
} else { console.log('span row not found:', SPAN); }
await b.close();
