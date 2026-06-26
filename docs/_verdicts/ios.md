# iOS native (Swift) — verdicts

Build: ✅ `xcodebuild -workspace EmbraceDemo.xcworkspace -scheme EmbraceDemo -sdk iphonesimulator` →
**BUILD SUCCEEDED**. Stack: EmbraceIO pod (no-account `Embrace.Options(export: OpenTelemetryExport(...))`)
+ OpenTelemetry-Swift + a hand-written `OtlpJsonExporter.swift` (no off-the-shelf OTLP/HTTP pod in
Embrace's iOS dep tree). Arms switch via `TELEMETRY_TOOL=embrace|otel`; `AUTOFIRE=` env drives actions.
Run: ✅ both arms on iOS Simulator (UDID A14FF08C), telemetry verified in Grafana.

service.name: OTel arm = `embrace-demo-ios` (honors full SCHEMA_CONTRACT). Embrace arm = `io.pula.embracedemo.ios`
(Embrace overrides service.name to the bundle id + emits its own `emb.*` resource schema — same gotcha as Flutter).

## Baseline captures
- **B1 (real error): ✅** — `caught_error` captured as ERROR log (Loki, `action.name=caught_error`). Unhandled
  crash uses the same KSCrash path proven raw on Flutter-iOS (not re-fired this run; supported).
- **B2 (performance): ✅** — `delay` span (durationMs 1221) in Tempo; Embrace auto-emits startup spans (B2/E5).
- **B3 (session / user timeline): ✅** — Embrace arm auto-emits `emb-session`, `emb-screen-view`,
  `emb-process-launch`, `emb-UIKitNavigationController-time-to-first-render` (no manual code) + our breadcrumbs.
- **B4 (custom event): ✅** — `workflow` parent + `capture`/`save`/`sync` children w/ step attrs + events;
  failed `sync` → STATUS_CODE_ERROR + `http.status=503` + exception attrs (Tempo + Loki).

## Spikes
- **E2 (crash → Grafana): ⚠️ raw, no grouping** — consistent with Flutter-iOS; KSCrash captures, but
  symbolication/grouping are Embrace-backend (server-side) features → Grafana sees raw stacks. Feeds **F2 ✅**.
- **E4 (slow/frozen frames): ⚠️** — our `frames` action span IS emitted (Loki: "frames jank burst done
  (12x120ms)"), but the Embrace SDK did **not** auto-emit a dedicated slow/frozen-frames METRIC span in this run
  (only startup/session/screen-view auto). So frames must be instrumented manually → ⚠️ (matches report).
- **E6 (session replay): ❌** — no session-replay API present in the EmbraceIO pod (grep of
  `clients/ios/Pods/EmbraceIO` finds none) nor the Embrace Web SDK. Embrace exposes no session-replay API on
  these SDKs → ❌ (matches report's "almost certainly no").
- **E7 (handled exception): ✅** — handled try/catch error logged as an ERROR record (Loki
  `demo handled exception (action.name=caught_error)`), captured like an unhandled one (as on Web).

## F1 (Embrace vs plain-OTel on the Grafana path)
- OTel arm delivers the same demo signals to the same collector AND honors every SCHEMA_CONTRACT key
  (`service.name=embrace-demo-ios`, `telemetry.tool=otel`, `device.manufacturer=Apple`, …).
- Embrace arm adds client-side auto-instrumentation (cold-startup, session, screen-view, process-launch)
  that bare OTel does not — but overrides `service.name` and drops custom resource attrs.

## Evidence (Grafana, 2026-06-26)
- Tempo (OTel, service `embrace-demo-ios`): `anr` 6000ms, `frames` 1646ms, `workflow` (+19ms), `delay` 1221ms.
- Tempo (Embrace, service `io.pula.embracedemo.ios`): `emb-app-startup-cold`, `emb-process-launch`,
  `emb-UIKitNavigationController-time-to-first-render`, `emb-screen-view`, `emb-session`.
- Loki: `caught_error` (error+warn), breadcrumbs, workflow events, failed-sync HTTP 503.
- App: `clients/ios/` (EmbraceDemo.xcworkspace + Pods + Telemetry/*.swift). Run: see `clients/ios/README.md`.
