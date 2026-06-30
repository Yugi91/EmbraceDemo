/** Capture ONE Embrace view full-screen. Usage: capture-one.mjs <APP> <PLAT> <name> <urlSuffix> */
import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';
const [APP, PLAT, NAME, SUFFIX] = process.argv.slice(2);
if (!SUFFIX) { console.error('usage: capture-one.mjs APP PLAT name urlSuffix'); process.exit(1); }
const OUT = `/Users/ductx/Projects/pula/EmbraceGrafanaDemo/screenshots/embrace/${PLAT}/deep`;
mkdirSync(OUT, { recursive: true });
const b = await chromium.connectOverCDP('http://127.0.0.1:18800');
const ctx = b.contexts()[0];
let page = ctx.pages().find(p => { try { return p.url().includes('dash.embrace.io'); } catch { return false; } });
await page.bringToFront().catch(()=>{});
const cdp = await page.context().newCDPSession(page);
await cdp.send('Emulation.setDeviceMetricsOverride', { width:1920, height:1080, deviceScaleFactor:1, mobile:false });
await page.goto(`https://dash.embrace.io/app/${APP}/${SUFFIX}`, { waitUntil:'domcontentloaded', timeout:30000 });
await page.getByRole('button',{name:'Got it'}).click({timeout:1200}).catch(()=>{});
await page.waitForTimeout(6000);
await page.screenshot({ path:`${OUT}/${NAME}.png`, fullPage:false });
console.log('shot', `${PLAT}/${NAME}`, '->', page.url());
await b.close();
