/** Deep-capture Performance + Troubleshooting views (incl. drill-ins) for one Embrace app. */
import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';
const APP = process.argv[2] || '2tbxs';
const PLAT = process.argv[3] || 'android';
const OUT = `/Users/ductx/Projects/pula/EmbraceGrafanaDemo/screenshots/embrace/${PLAT}/deep`;
mkdirSync(OUT, { recursive: true });
const BASE = `https://dash.embrace.io/app/${APP}`;

const b = await chromium.connectOverCDP('http://127.0.0.1:18800');
const ctx = b.contexts()[0];
let page = ctx.pages().find(p => { try { return p.url().includes('dash.embrace.io'); } catch { return false; } });
await page.bringToFront().catch(()=>{});
const cdp = await page.context().newCDPSession(page);
await cdp.send('Emulation.setDeviceMetricsOverride', { width:1920, height:1080, deviceScaleFactor:1, mobile:false });

async function shot(name){ await page.screenshot({ path:`${OUT}/${name}.png`, fullPage:false }); console.log('shot', name); }
async function go(suffix){ await page.goto(`${BASE}/${suffix}`, { waitUntil:'domcontentloaded', timeout:30000 });
  await page.getByRole('button',{name:'Got it'}).click({timeout:1200}).catch(()=>{});
  await page.waitForTimeout(5500); }
async function clickFirst(selectors){ for(const s of selectors){ try{ await page.locator(s).first().click({timeout:2500}); return true; }catch{} } return false; }

// ---- Direct views ----
await go('v/top_versions/session/hour/crash');            await shot('crashes');
await go('v/top_versions/anr/hour');                      await shot('anr');
await go('v/top_versions/root_spans/hour/summary/emb-app-startup-cold'); await shot('app-startup');
await go('v/top_versions/network/hour/summary');          await shot('network');
await go('release-health');                               await shot('release-health');
await go('v/top_versions/user_flows/hour');               await shot('user-flows');

// ---- Drill-in: crash detail (stack / timeline / logs tabs) ----
await go('v/top_versions/session/hour/crash');
if (await clickFirst(['a[href*="/crash/"]','text=/DemoActions\\.crash/','text=/RuntimeException/'])) {
  await page.waitForTimeout(5000); await shot('crash-detail-stack');
  for (const [tab,name] of [['Timeline','crash-detail-timeline'],['Logs','crash-detail-logs']]) {
    if (await clickFirst([`text="${tab}"`])) { await page.waitForTimeout(3500); await shot(name); }
  }
}

// ---- Drill-in: ANR detail ----
await go('v/top_versions/anr/hour');
if (await clickFirst(['a[href*="/anr/"]','text=/anr/','tbody tr'])) { await page.waitForTimeout(4500); await shot('anr-detail'); }

// ---- Drill-in: trace waterfall (workflow) ----
await go('v/top_versions/root_spans/hour');
if (await clickFirst(['a:has-text("workflow")','tr:has-text("workflow") a','text="workflow"'])) {
  await page.waitForTimeout(4500); await shot('trace-workflow-waterfall');
}

// ---- Drill-in: session timeline ----
await go('grouped_sessions/hour');
if (await clickFirst(['a[href*="grouped_sessions"]','tbody tr','[class*="session" i] a'])) {
  await page.waitForTimeout(3500);
  await clickFirst(['a[href*="/session"]','tbody tr']);   // group -> individual session
  await page.waitForTimeout(4500); await shot('session-timeline');
}
await b.close();
console.log('done', PLAT);
