/** Fix the 2 weak drill-ins: trace waterfall (expand instance) + session/user timeline. */
import { chromium } from 'playwright';
const APP = process.argv[2] || '2tbxs';
const PLAT = process.argv[3] || 'android';
const OUT = `/Users/ductx/Projects/pula/EmbraceGrafanaDemo/screenshots/embrace/${PLAT}/deep`;
const BASE = `https://dash.embrace.io/app/${APP}`;
const b = await chromium.connectOverCDP('http://127.0.0.1:18800');
const ctx = b.contexts()[0];
let page = ctx.pages().find(p => { try { return p.url().includes('dash.embrace.io'); } catch { return false; } });
await page.bringToFront().catch(()=>{});
const cdp = await page.context().newCDPSession(page);
await cdp.send('Emulation.setDeviceMetricsOverride', { width:1920, height:1080, deviceScaleFactor:1, mobile:false });
const shot = async n => { await page.screenshot({ path:`${OUT}/${n}.png`, fullPage:false }); console.log('shot', n); };
const go = async s => { await page.goto(`${BASE}/${s}`, { waitUntil:'domcontentloaded', timeout:30000 });
  await page.getByRole('button',{name:'Got it'}).click({timeout:1200}).catch(()=>{}); await page.waitForTimeout(5500); };
const click = async sels => { for(const s of sels){ try{ await page.locator(s).first().click({timeout:2500}); return true; }catch{} } return false; };

// 1) Trace waterfall: workflow summary -> expand first instance row to reveal capture/save/sync tree
await go('v/top_versions/root_spans/hour');
if (await click(['a:has-text("workflow")','tr:has-text("workflow") a','text="workflow"'])) {
  await page.waitForTimeout(4500);
  // expand the first instance (chevron in the Root Span Instances List)
  await click(['tbody tr:first-child button','tbody tr:first-child svg','tbody tr:first-child td:first-child']);
  await page.waitForTimeout(3000);
  console.log('trace url=', page.url());
  await shot('trace-workflow-waterfall');
}

// 2) Session / user timeline: open a crash, expand its session, Timeline tab, "Open User Timeline"
await go('v/top_versions/session/hour/crash');
if (await click(['a[href*="/crash/"]','text=/DemoActions\\.crash/'])) {
  await page.waitForTimeout(5000);
  await click(['tbody tr:first-child button','tbody tr:first-child td:first-child svg','tbody tr:first-child']); // expand affected session
  await page.waitForTimeout(2000);
  await click(['text="Timeline"']); await page.waitForTimeout(2000);
  if (await click(['text="Open User Timeline"','a:has-text("User Timeline")'])) {
    await page.waitForTimeout(5000);
    console.log('session url=', page.url());
    await shot('session-timeline');
  } else { console.log('no Open User Timeline link'); }
}
await b.close();
console.log('done fix', PLAT);
