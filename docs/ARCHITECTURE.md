# Architecture

## Data flow
```
 Web (Angular)        ┐
 Android (Kotlin)     │  Embrace SDK (no-account)  ─┐
 iOS (Swift)          │  OR plain OpenTelemetry SDK │  OTLP (traces + logs)
 Flutter              ┘                             │  HTTP :4318 / gRPC :4317
                                                    ▼
                                  grafana/otel-lgtm (all-in-one)
                                  ├─ OTel Collector (+ spanmetrics connector)
                                  ├─ Tempo       (traces)
                                  ├─ Loki        (logs)
                                  └─ Prometheus  (metrics derived from spans)
                                                    ▼
                                          Grafana  :3000 → host :3939
```

Embrace has **no self-hostable backend** (the `embrace-io` GitHub org ships client SDKs only; the
dashboard is SaaS at `dash.embrace.io`). "Embrace self-host with Grafana" therefore means:
**Embrace SDK → OTLP export → any OTLP backend → Grafana.** The Embrace SDK exports **traces + logs
only — no metrics**; numeric values (RAM/storage/network) ride as span/log attributes and are turned
into metrics by the collector's **spanmetrics** connector.

## Why otel-lgtm (and the prod-shaped alternative)
`grafana/otel-lgtm` is a single image bundling Collector + Tempo + Loki + Prometheus + Grafana — the
fastest documented "any OTLP backend" PoC. Grafana labels it **DEV/DEMO only**. The production-shaped
deployment splits these into separate services (otel-collector-contrib + tempo + loki + mimir +
grafana), modeled on `grafana/intro-to-mltp`. For FnB, the collector would also fan in from Kafka and
could route to the **existing ClickHouse** via the Grafana ClickHouse datasource (O2 — feasibility TBD).

## Dual-export design
Each client can export to **both** targets simultaneously:
- **Grafana (self-host)** — always on; the primary subject of this spike. Works with **no Embrace account**.
- **Embrace cloud** — optional; needs a (free) Embrace App ID. Required ONLY to produce the
  Embrace-dashboard screenshots in the getting-started AC. The side-by-side "rich Embrace dashboard vs
  raw data surviving to Grafana" is itself the strongest evidence for findings F1/F2.

## plain-OTel comparison arm
Every client ships a second telemetry implementation using vanilla `@opentelemetry/*` (web / Kotlin /
Swift / Dart), selectable by a build flag or query param, tagged `telemetry.tool=otel`. This isolates
"what does Embrace actually add over bare OpenTelemetry when the target is Grafana?" (finding F1).
Observed: the OTel arm honors the schema contract exactly, whereas the Embrace SDK overrides
`service.name` and emits its own `emb.*` resource schema — a real integration gotcha for a shared dashboard.

## Self-tracing loop guard
The OTLP export is itself a network call the SDK would auto-instrument → infinite loop. Each client
excludes the collector endpoint from network capture: Android `disabled_url_patterns`,
Web `network.ignoreUrls`, iOS ignored-URLs. (Reproduced and fixed during the Flutter/iOS spike.)

## Per-platform OTLP endpoint
| Client | Endpoint to the collector |
|---|---|
| Web (browser) | `http://localhost:4318` |
| iOS simulator | `http://localhost:4318` |
| Flutter on iOS simulator | `http://localhost:4318` |
| **Android emulator** | **`http://10.0.2.2:4318`** (host alias; cleartext must be allowed) |

## The three findings the demo validates
- **F1** Embrace ≈ plain OTel for the Grafana path (extra value = client auto-instrumentation, not backend).
- **F2** crash/ANR symbolication + grouping are server-side → **lost** on the OTLP→self-host path.
- **F3** Sentry (not built here per decision D4) covers more but emits no OTLP — its data lives in its
  own backend, visible in Grafana only via the Sentry datasource plugin.
