# Android native (Kotlin/Compose) — verdicts (FNB-96526 spike)

Emulator `emulator-5554`, Android 15 (API 35) arm64. JDK 17 (Homebrew openjdk@17). AGP 8.7.3, Kotlin
2.0.21, Gradle 8.13. minSdk 21. OTLP endpoint from emulator = `http://10.0.2.2:4318` (cleartext allowed
via network-security-config). service.name = `embrace-demo-android`.

## Build
- **OTel arm: ✅** `./gradlew :app:assembleDebug -PtelemetryTool=otel -Pautofire=true` → BUILD SUCCESSFUL,
  installed + ran on emulator, telemetry verified in Grafana.
- **Toolchain gotcha (real finding):** Embrace 9.0.0 + its `io.opentelemetry.kotlin:0.4.0` exporter
  transitively drag **kotlin-stdlib 2.3.0** + an okhttp built with Kotlin 2.2 onto the classpath, which
  the project's **Kotlin 2.0.21** compiler rejects ("incompatible metadata" → internal compiler error).
  Fix used: gate the Embrace/OTel-Kotlin deps to the `embrace` arm only; the OTel arm reaches Embrace via
  reflection (no compile dep). The `embrace` arm therefore needs a Kotlin toolchain bump (≥2.2) — see E1.

## Verified in Grafana (OTel arm, service.name=embrace-demo-android)
- Tempo traces: `anr` 6001ms · `frames` 1481ms · `workflow` ×2 (223/213ms) · `delay` 761ms.
- Loki logs: "anr: blocked main thread 6s" · "demo handled exception (action.name=caught_error)" ·
  "EmbraceGrafanaDemo intentional unhandled crash (action.name=crash)" · "delay completed ok (760ms)" ·
  "frames jank burst done (12x120ms)" · "workflow failed at sync (HTTP 503)" · "workflow completed ok".

## Baseline / spikes
- **B1 (real error): ✅** — unhandled `RuntimeException` (crash action) reached Grafana (Tempo `crash`
  span STATUS_ERROR + Loki ERROR log) after a pre-throw `forceFlush()`.
- **B2 (performance): ✅** — `delay` 761ms span; `workflow` timing spans.
- **B3 (session/user timeline): ⚠️ (OTel arm)** — action logs form a timeline, but no Embrace session
  grouping/breadcrumbs in the OTel arm (that is an Embrace-SDK feature → embrace arm).
- **B4 (custom event): ✅** — `workflow` parent + `capture`/`save`/`sync` children with step.name/status/
  data + events; failed sync → ERROR + http.status=503 + exception.* attrs.
- **E2 (crash → Grafana, raw vs symbolicated): ✅ recorded, RAW, no grouping.** Debug build is
  unminified so the stack is readable as-is; a release/R8 build would be obfuscated and—on the
  OTLP→self-host path—would arrive WITHOUT de-obfuscation (mapping upload + symbolication are
  Embrace-backend features). Feeds **F2 (lost on self-host)**, consistent with iOS/Flutter.
- **E3 (ANR / app-hang): ✅ (behaviour + signal reach Grafana).** The `anr` action blocks the main
  thread 6s (a real ANR condition); the `anr` span (6001ms) + log reach Grafana. NB: Embrace's *native
  ANR detector* (`automatic_data_capture.anr_info=true`) is an embrace-arm feature, documented ✅ for
  Embrace Android. The self-host pipeline captures the hang as an OTel span/log either way.
- **E4 (slow/frozen frames): ⚠️** — the `frames` action (12×120ms main-thread jank) is captured as a
  manual span; no AUTO slow/frozen-frames metric without explicit instrumentation (matches iOS/report).
- **E6 (session replay): ❌** — no session-replay API in the Embrace Android SDK (confirmed cross-SDK).

## E1 — Embrace Android 9.0 no-account (no app_id)? — ⚠️ CONDITIONAL (runtime-verified)
Embrace arm built with **Kotlin 2.3.0** (BUILD SUCCESSFUL; the Embrace Gradle plugin applied with NO
app_id, so the *build* tolerates a missing app_id), installed + launched on emulator. At RUNTIME,
`Embrace.start()` with no app_id THROWS and the SDK does not init. Verbatim logcat:
> `W Embrace: Failed to initialize Embrace SDK`
> `java.lang.IllegalArgumentException: No appId supplied in embrace-config.json. This is required if you`
> `want to send data to Embrace, unless you configure an OTel exporter and add`
> `embrace.disableMappingFileUpload=true to gradle.properties.`

**Verdict: app_id is REQUIRED by default; no-account is possible ONLY by (a) registering an OTel
exporter AND (b) setting `embrace.disableMappingFileUpload=true` in gradle.properties.** This mirrors the
iOS path (Embrace inits appId-less once an `OpenTelemetryExport` is supplied — proven working there). So
cross-platform the rule is "no-account = supply your own OTel exporter", not merely "omit app_id".

NB the Android app still streamed ALL demo telemetry to Grafana in this arm via the OTel-Java pipeline
(`telemetry.tool=embrace`: crash / delay / workflow-ok / workflow-failed-503 logs verified in Loki) — the
app is functional; only Embrace's OWN auto-capture is gated behind the exporter + flag.

## Build toolchain note
- OTel arm: Kotlin 2.0.21 OK. Embrace arm: required bumping Kotlin → **2.3.0** (Embrace 9.0 / OTel-Kotlin
  0.4.0 are compiled with newer Kotlin) AND migrating `kotlinOptions.jvmTarget` → the `compilerOptions`
  DSL. Real integration cost for adopting Embrace 9.0 in an older-Kotlin Android codebase.

## APK size
debug `app-debug.apk` ≈ 10.8 MB (embrace arm, incl. `libembrace-native.so`). See
`clients/android/app/build/outputs/apk/debug/`.
