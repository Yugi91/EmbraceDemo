# Demo Checklist — All Clients (FNB-96526)

Embrace + Grafana self-host observability demo. This is **what every client must demonstrate** plus the
**current verified status**. Source of truth for evidence: [`SPIKE_RESULTS.md`](SPIKE_RESULTS.md).

Backend: `grafana/otel-lgtm` — Grafana UI `http://localhost:3939`, OTLP ingest `:4318` (HTTP) / `:4317` (gRPC).
Every client ships **two arms**: the Embrace SDK and a plain **OpenTelemetry** arm (`telemetry.tool=otel`)
for the F1 comparison.

Clients = the real FnB stack: **Web Angular 20** (WebMan) · **Web Angular 8** (WebPOS) · **Android** Kotlin/Compose
(Mobile/Touch) · **iOS** Swift · **Flutter** (AppMAN).

---

## 1. Demo actions — every client (UI buttons / AUTOFIRE)
- [ ] **delay** — a performance span with an artificial delay
- [ ] **crash** — an UNHANDLED error/exception
- [ ] **ANR / app-hang** — block the main thread ~6 s
- [ ] **workflow** — parent span with child steps **capture → save → sync**, each timestamped; include one
      forced-fail run (sync → HTTP 503, span status = ERROR + exception attrs)
- [ ] **caught-error** — a caught (handled) exception that is logged

## 2. Baseline captures — every client (per Embrace getting-started) → must be visible in Grafana
- [ ] **B1** Real error (JS error / native unhandled crash)
- [ ] **B2** Performance / Web Vitals (mobile: perf span + cold/warm startup)
- [ ] **B3** Session / user timeline (breadcrumbs / session grouping)
- [ ] **B4** Custom event (workflow step events / custom log)

## 3. Telemetry schema — carried on every signal
```
user.id · device.model · device.manufacturer · app.version · os.version
system.free_ram_mb · system.free_storage_mb · network.type · network.speed_mbps
action.name · telemetry.tool (embrace | otel) · service.name
```

---

## 4. Per-client status (verified on Grafana, 2026-06-26)

| Client | delay | crash | ANR | workflow | caught | B1 | B2 | B3 | B4 | Notes |
|---|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|---|
| **Web Angular 20** (WebMan) | ✅ | ✅ | — | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | full; Embrace + OTel arms |
| **Web Angular 8** (WebPOS) | ❌ | ❌ | — | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | Embrace Web SDK **won't build** on Angular 8 (TS<3.6 vs SDK's TS 3.8 `import type`). Fallback: plain-OTel pinned to OTel 1.x, or migrate off Angular 8. |
| **Android** (Mobile/Touch) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ | ✅ | B3 via action logs (OTel arm has no Embrace session-grouping) |
| **iOS** (Swift) | ✅ | ✅ | ⚠️ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | app-hang ⚠️ (iOS has no "ANR"); Embrace auto startup/session |
| **Flutter** (AppMAN) | ✅ | ✅ | ⚠️ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | full; Embrace + OTel arms; ANR is Android-only |

Legend: ✅ verified on Grafana · ⚠️ partial/caveat · ❌ not possible (evidenced) · — not applicable

---

## 5. Spike verdicts (the FNB-96526 ⚠️ questions)

| # | Question | Verdict |
|---|---|---|
| **E1** | Embrace no-account init (no App ID)? | iOS/Flutter **✅** (must supply your own OTel exporter) · Android **⚠️** (also needs `embrace.disableMappingFileUpload=true`; else `Embrace.start` throws *No appId supplied*) |
| **E2** | Crash → Grafana: symbolicated? grouped? | **⚠️ RAW** — symbolication/grouping **lost** on self-host (all 3 mobile) → see F2 |
| **E3** | ANR / app-hang reported? | Android **✅** (real ANR span+log to Grafana) · iOS app-hang **⚠️** |
| **E4** | Slow/frozen frames metric? | **⚠️** — manual instrumentation only; Embrace emits no auto frames metric |
| **E5** | Startup cold/warm auto-measured? | **✅** auto (Moments removed in v3, Traces API auto-instruments) |
| **E6** | Session replay in the SDK? | **❌** — no session-replay API in any Embrace client SDK |
| **E7** | Handled exception captured like unhandled? | Web/iOS **✅** (same capture path, differs by one label) |
| **E8** | Web framework fit (SDK embeds & runs)? | Angular 20 **✅** · Angular 8 / Electron **❌** (TS ceiling) |
| **F1** | Embrace vs plain OTel on the Grafana path | **≈ equivalent**; Embrace's extra = client RUM auto-instrumentation (web vitals, startup), not the transport |
| **F2** | Is symbolication lost on OTLP→self-host? | **✅ lost** — symbolication + crash-grouping are Embrace cloud-backend features (not self-hostable) |

**Bottom line for FNB-96526:** if the backend is **Grafana/self-host**, Embrace is ≈ plain **OpenTelemetry**
(its mobile strength — symbolication/grouping — lives in a backend you can't self-host), and it has **no session
replay**. → For the Grafana path prefer **plain OTel SDK**; for replay/grouping/symbolication that's **Sentry
self-hosted** territory (not built here — decision D4).

---

## 6. How to run

```bash
# 1. Backend (Grafana self-host)
cd backend && docker compose up -d        # Grafana → http://localhost:3939

# 2. Clients (each README has details)
# Web (Angular 20):
cd clients/web && npm ci && npm run build && npm run verify      # ?exporter=otel for the OTel arm
# Android (JDK 17 + ANDROID_HOME):
cd clients/android && ./gradlew :app:assembleDebug -PtelemetryTool=otel -Pautofire=true   # embrace arm needs Kotlin 2.3.0
# iOS:
cd clients/ios && pod install && xcodebuild -workspace EmbraceDemo.xcworkspace -scheme EmbraceDemo -sdk iphonesimulator
# Flutter:
cd clients/flutter && flutter run --dart-define=TELEMETRY_TOOL=otel
# Angular 8 spike (reproduce the ❌):
cd clients/web-angular8   # see README (node:14 container)
```

> Note: "screenshot the **Embrace cloud dashboard**" was skipped by decision (Grafana-only). Telemetry is
> ephemeral in the otel-lgtm PoC (Tempo/Loki retention) — re-fire a client right before screenshotting.
