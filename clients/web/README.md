# Embrace Grafana Demo — Web client (Angular 20)

Decision-support spike for **FNB-96526** (Embrace vs Sentry observability for FnB).
A working Angular 20 SPA that integrates the **Embrace Web SDK** (manually wired — the SDK's
auto-instrumentation is React-only) and exports telemetry to a **self-hosted Grafana
(`grafana/otel-lgtm`)** stack with **no Embrace cloud account** (no-account OTLP export).

It also ships a **plain-OpenTelemetry arm** behind a `?exporter=otel` toggle so we can compare
"what Embrace adds over bare OTel for the Grafana path" (spike F1).

`service.name` = `embrace-demo-web`. All telemetry uses the shared schema in
`../../docs/SCHEMA_CONTRACT.md`.

## Prerequisites

- Node ≥ 22, npm ≥ 10.
- The backend must be up. Grafana UI: http://localhost:3939 (anonymous admin).
  OTLP HTTP ingest: `http://localhost:4318` (`/v1/traces`, `/v1/logs`).

## Install

```bash
cd clients/web
npm install
```

## Run (dev server)

```bash
npm start            # ng serve → http://localhost:4200
```

- Default (Embrace arm): http://localhost:4200/
- Plain-OTel arm (F1):    http://localhost:4200/?exporter=otel

Click the demo-action buttons; the on-page activity log shows progress. Telemetry is exported
to the local collector and visible in Grafana within a few seconds (Tempo = traces, Loki = logs,
Prometheus = span metrics via the collector's spanmetrics connector).

## Demo actions

| Button | What it does | Spike |
|---|---|---|
| **delay** | Traced async span with a 750 ms artificial delay + timestamped events | perf / B2 |
| **crash** | Throws an **unhandled** JS error (caught by the global handler) | B1 |
| **caught-error** | `try/catch` then logs the handled exception | E7 |
| **workflow** | Parent span `workflow` → child spans `capture` → `save` → `sync`, each with `step.name/step.status/step.data` + events; `sync` fails ~50 % (span status ERROR + exception attrs) | B4 |
| **workflow (force sync fail)** | Same, but forces the sync failure | B4 |
| **custom event** | Emits a standalone custom-event log | B4 |

Baseline captures (B2 Web Vitals, B3 session/breadcrumbs) happen automatically via Embrace's
default instrumentation; in the OTel arm only B1/B4 + the action spans are present (that gap is
the F1b finding).

## Architecture (clean-ish: telemetry layer separated from UI)

```
src/app/telemetry/
  schema.ts            schema constants + per-action / resource attribute sampling
  telemetry.types.ts   provider-agnostic interfaces (TelemetryProvider, DemoSpan)
  embrace.provider.ts  Embrace Web SDK arm (initSDK, no-account OTLP export)
  otel.provider.ts     plain @opentelemetry/* arm (telemetry.tool=otel)
  telemetry.service.ts Angular @Injectable; picks the arm from ?exporter=, exposes the 4 actions
src/app/app.ts/.html   UI (buttons + activity log); exposes window.__demo for headless verify
src/main.ts            initTelemetry() runs BEFORE bootstrap (so error capture is installed early)
```

The UI never imports an SDK directly — it only talks to `TelemetryService`, which delegates to
the active provider. Swapping arms is a one-line factory decision in `initTelemetry()`.

### No-account OTLP + self-tracing-loop guard

`initSDK` is called **without `appID`**; this is valid because at least one custom exporter is
supplied (`@opentelemetry/exporter-trace-otlp-http` + `-logs-otlp-http`) pointing at
`http://localhost:4318`. The collector base URL is added to
`defaultInstrumentationConfig.network.ignoreUrls` so the OTLP export `fetch` is not itself
auto-traced (avoids the infinite self-tracing loop called out in the schema contract).

## Build (production)

```bash
npm run build
```

Output: `dist/embrace-demo-web/browser`. Measured production bundle (this build includes BOTH
the Embrace and OTel arms because the runtime toggle imports both):

```
main      328.78 kB raw  /  84.84 kB gzip
polyfills  34.59 kB raw  /  11.33 kB gzip
styles      0.14 kB
Initial total: 363.51 kB raw / 96.32 kB transfer (gzip)
```

## Headless verification

Fires every action (incl. the unhandled crash in its own page load) against the production
build with Playwright/Chromium, for both arms:

```bash
npm run build
npm i -D playwright && npx playwright install chromium   # once
npm run verify                # both arms
node scripts/verify.mjs otel  # single arm
```

Then confirm data in Grafana's backend API:

```bash
# traces
curl -s "http://localhost:3939/api/datasources/proxy/uid/tempo/api/search?tags=service.name%3Dembrace-demo-web"
# logs
curl -s "http://localhost:3939/api/datasources/proxy/uid/loki/loki/api/v1/query_range?query=%7Bservice_name%3D%22embrace-demo-web%22%7D"
```

See `../../docs/SPIKE_RESULTS.md` (Web Ng20 column) and `../../docs/INTEGRATION_NOTES.md` for the
recorded verdicts and gotchas.
