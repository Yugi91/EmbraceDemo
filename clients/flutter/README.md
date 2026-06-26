# EmbraceGrafanaDemo — Flutter client

Decision-support spike for **FNB-96526** (Embrace vs Sentry observability). This
is the Flutter arm ("AppMAN" equivalent). It demonstrates getting Flutter
telemetry into our **self-hosted Grafana** (`grafana/otel-lgtm`) over OTLP, via
two interchangeable arms:

| `--dart-define=TELEMETRY_TOOL=` | Arm | Account needed | iOS export path |
|---|---|---|---|
| `otel` *(default)* | Plain OpenTelemetry (workiva `opentelemetry` + manual OTLP logs) | none | pure Dart over host network |
| `embrace` | Embrace Flutter SDK 4.7.0 (native EmbraceIO 6.20.0) | **none** (no-account OTLP mode) | native `OpenTelemetryExport` in `AppDelegate.swift` |

`service.name = embrace-demo-flutter` (OTel arm). The Embrace arm reports under
its own resource (`io.embrace.demo.embraceDemoFlutter:Runner`) — see gotchas in
`docs/INTEGRATION_NOTES.md`.

## Architecture

```
lib/
  telemetry/
    telemetry_service.dart         # abstract seam the UI depends on (TelemetrySpan, TelemetryService)
    telemetry_config.dart          # endpoints, schema attr keys, --dart-define switches
    device_context.dart            # SCHEMA_CONTRACT resource + system/network samples
    embrace_telemetry_service.dart # Embrace arm
    otel_telemetry_service.dart    # plain-OTel arm (traces via SDK, logs via manual OTLP POST)
  demo_actions.dart                # delay / crash / anr / workflow / caught_error (pure logic)
  main.dart                        # service factory + guarded-zone wiring + UI shell
ios/Runner/
  AppDelegate.swift                # Embrace no-account native setup (gated on EMBRACE_ENABLED)
  OtlpJsonExporter.swift           # tiny OTLP/JSON SpanExporter + LogRecordExporter (no extra pods)
```

The UI only ever talks to the `TelemetryService` interface; the two SDK arms are
swapped at build time. Telemetry attribute keys come from
`docs/SCHEMA_CONTRACT.md`.

## Prerequisites

- Flutter 3.44.2 stable, Xcode + an iOS simulator (Android is out of scope for
  this spike — no JDK/AVD in the environment).
- Backend up: `grafana/otel-lgtm` with OTLP/HTTP on `http://localhost:4318`,
  Grafana on `http://localhost:3939`.

## Run

The OTel arm needs no native config (pure Dart, reaches `localhost:4318` over the
simulator's shared host network):

```bash
cd clients/flutter
flutter pub get
open -a Simulator                                   # boot any iPhone sim
flutter run --dart-define=TELEMETRY_TOOL=otel
```

The Embrace arm needs the native SDK started in `AppDelegate.swift`, which is
gated on an env var so the OTel arm stays clean:

```bash
SIMCTL_CHILD_EMBRACE_ENABLED=1 flutter run --dart-define=TELEMETRY_TOOL=embrace
```

### Headless action firing (no taps)

`simctl` on this toolchain has no coordinate-tap, so the app can auto-fire
actions after launch:

```bash
flutter build ios --simulator --debug \
  --dart-define=TELEMETRY_TOOL=otel \
  --dart-define=AUTOFIRE=delay,workflow,workflow,caught
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl launch booted io.embrace.demo.embraceDemoFlutter
```

`AUTOFIRE` accepts a comma list of: `delay,workflow,anr,caught,crash`.

For the Embrace arm, prefix the launch with the env var:

```bash
SIMCTL_CHILD_EMBRACE_ENABLED=1 xcrun simctl launch booted io.embrace.demo.embraceDemoFlutter
```

## Demo actions

| Button | Telemetry |
|---|---|
| **delay** | performance span `delay` with artificial 0.8–2.0s delay (B2) |
| **workflow** | parent span `workflow` + children `capture`→`save`→`sync`; `sync` fails ~50% → span ERROR + `exception.*` (B4) |
| **ANR (6s hang)** | blocks the UI isolate 6s → app-hang; span `anr` durationMs≈6000 (E3) |
| **caught error** | handled exception → `action.name=caught_error` log (B1 handled) |
| **CRASH** | unhandled Dart `StateError` (B1) |

## Verify telemetry reached Grafana

```bash
# OTel arm traces
curl -s "http://localhost:3939/api/datasources/proxy/uid/tempo/api/search?tags=service.name%3Dembrace-demo-flutter"
# Embrace arm traces (note Embrace's own service.name)
curl -s -G "http://localhost:3939/api/datasources/proxy/uid/tempo/api/search" \
  --data-urlencode 'q={resource.service.name="io.embrace.demo.embraceDemoFlutter:Runner"}'
# logs (either arm)
curl -s "http://localhost:3939/api/datasources/proxy/uid/loki/loki/api/v1/query_range?query=%7Bservice_name%3D%22embrace-demo-flutter%22%7D"
```

## Notes / limitations

- Android is intentionally not targeted (no toolchain). The `embrace_android`
  plugin DOES honor the Dart-side `addSpanExporter`/`addLogRecordExporter`; iOS
  does not (those are no-ops on iOS — that's why iOS export is wired natively).
- ATS exception for cleartext `localhost:4318` is in `ios/Runner/Info.plist`
  (demo only — never ship that).
- `device_info_plus`/`package_info_plus` supply the SCHEMA_CONTRACT resource
  attributes (`device.model`, `os.version`, `app.version`).
