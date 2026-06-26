import { enableProdMode } from '@angular/core';
import { platformBrowserDynamic } from '@angular/platform-browser-dynamic';

import { AppModule } from './app/app.module';
import { environment } from './environments/environment';

// --- Spike E8: minimal Embrace Web SDK init (no-account OTLP export) ---
// Mirrors the Angular 20 reference shape (clients/web/.../embrace.provider.ts).
// appID intentionally omitted -> no-account mode; a custom OTLP exporter targets a
// local collector. It does NOT need to actually send — we are testing BUILD feasibility
// on the Angular 8 / Node 14 toolchain. The import is what forces the bundler to pull
// the SDK (and its @opentelemetry/*@2.x transitive deps) into the build graph.
import { initSDK } from '@embrace-io/web-sdk';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';

const OTLP_TRACES_URL = 'http://localhost:4318/v1/traces';

try {
  initSDK({
    appVersion: '1.0.0+1',
    spanExporters: [new OTLPTraceExporter({ url: OTLP_TRACES_URL })],
    defaultInstrumentationConfig: {
      network: { ignoreUrls: ['http://localhost:4318'] },
    },
  });
} catch (e) {
  console.error('[spike] Embrace initSDK failed:', e);
}
// --- end spike init ---

if (environment.production) {
  enableProdMode();
}

platformBrowserDynamic().bootstrapModule(AppModule)
  .catch(err => console.error(err));
