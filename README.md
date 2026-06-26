# EmbraceGrafanaDemo

A runnable, multi-client **spike** that answers the open questions in **FNB-96526**
("Embrace vs Sentry for FnB, all clients, backend self-host"). Every client integrates the
**Embrace SDK** (with a parallel **plain-OpenTelemetry** arm for comparison), fires the same demo
actions, and exports telemetry to a **self-hosted Grafana stack**. The acceptance target is
[`docs/SPIKE_RESULTS.md`](docs/SPIKE_RESULTS.md): every ⚠️ ("docs silent → needs spike") cell from
the report resolved to a ✅/❌/⚠️ verdict backed by real evidence on the dashboard.

```
EmbraceGrafanaDemo/
├── backend/            grafana/otel-lgtm self-host stack (OTLP → Tempo/Loki/Prometheus → Grafana)
├── clients/
│   ├── web/            Angular 20 + Embrace Web SDK   (+ plain-OTel arm)   — FnB "WebMan"
│   ├── web-angular8/   Angular 8 EOL feasibility spike (Node 14)           — FnB "WebPOS"
│   ├── flutter/        Flutter + Embrace Flutter SDK  (+ plain-OTel arm)   — FnB "AppMAN"
│   ├── android/        Kotlin/Compose + Embrace Android SDK (+ OTel arm)   — FnB "Mobile/Touch"
│   └── ios/            Swift + Embrace Apple SDK      (+ plain-OTel arm)   — FnB "iOS"
├── docs/               ARCHITECTURE · SCHEMA_CONTRACT · SPIKE_RESULTS · INTEGRATION_NOTES
└── screenshots/        dashboard captures per action
```

## TL;DR findings (see docs/SPIKE_RESULTS.md for evidence)
- **F1 — Embrace ≈ plain OTel for the Grafana path.** Both deliver the same traces+logs to Grafana.
  Embrace's *extra* value is **client-side auto-instrumentation** (Web Vitals/RUM on web; cold/warm
  startup spans on mobile) — those survive. Its **backend** value (crash symbolication, grouping,
  flame-graphs) does **not** — it's server-side and there is no self-hostable Embrace backend.
- **F2 — crash/ANR symbolication is LOST on OTLP→self-host.** Grafana receives raw/unsymbolicated
  stacks with no grouping. Confirmed.
- **Demo proves the pipeline works end-to-end with NO Embrace account** (no-account OTLP export).
  An Embrace **cloud account is needed only for the Embrace *dashboard* screenshots** (the
  getting-started AC), not for the Grafana pipeline.

## Quickstart

### 1. Backend (Grafana self-host)
```bash
cd backend
docker compose up -d
# Grafana UI:  http://localhost:3939   (anonymous admin, no login)
# OTLP ingest: http://localhost:4318 (HTTP) · localhost:4317 (gRPC)
```
Smoke-test the pipeline:
```bash
curl -s "http://localhost:3939/api/datasources/proxy/uid/tempo/api/search?tags=service.name%3Dsmoke-test"
```

### 2. Clients
Each client has its own README with exact run steps:
- Web (Angular 20): [`clients/web/README.md`](clients/web/README.md)
- Flutter: [`clients/flutter/README.md`](clients/flutter/README.md)
- Android: [`clients/android/README.md`](clients/android/README.md)
- iOS: [`clients/ios/README.md`](clients/ios/README.md)
- Angular 8 spike: [`clients/web-angular8/README.md`](clients/web-angular8/README.md)

> **Networking note:** the Android emulator reaches the host via `10.0.2.2` (not `localhost`), so its
> OTLP endpoint is `http://10.0.2.2:4318`. Web/iOS-simulator/Flutter-on-simulator use `localhost`.

## Telemetry schema
All clients emit an identical attribute set (`user.id`, `device.*`, `app.version`,
`system.free_ram_mb/free_storage_mb`, `network.speed_mbps/type`, `action.name`, `telemetry.tool`) so
one Grafana dashboard works across platforms. See [`docs/SCHEMA_CONTRACT.md`](docs/SCHEMA_CONTRACT.md).
