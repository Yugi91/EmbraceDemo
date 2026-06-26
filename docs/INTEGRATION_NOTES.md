# Integration Notes — EmbraceGrafanaDemo

Per-client integration steps, gotchas, measured bundle/footprint, and perf impact for the
FNB-96526 observability spike. One section per client.

## Web (Angular 20 + Embrace Web SDK)

**Client dir:** `clients/web` · **service.name:** `embrace-demo-web` · **target:** self-hosted
`grafana/otel-lgtm` (OTLP HTTP `http://localhost:4318`), no Embrace cloud account.

### Packages

- `@embrace-io/web-sdk@2.22.0` — the official Embrace Web SDK. (Its `react` dependency is a
  **peerDependency only**, so it installs and runs in a non-React Angular app without React.)
- OTel peers used for the custom exporters and the plain-OTel arm:
  `@opentelemetry/exporter-trace-otlp-http`, `@opentelemetry/exporter-logs-otlp-http`,
  `@opentelemetry/sdk-trace-web@2.8`, `@opentelemetry/sdk-logs@0.219`,
  `@opentelemetry/api@1.9`, `@opentelemetry/api-logs@0.219`, `@opentelemetry/resources@2.8`.
  (The Embrace SDK pins these same OTel 2.x / 0.219 versions internally, so no duplication.)

### Integration steps

1. `ng new` (Angular 20, standalone, zoneful default). Add the packages above.
2. **Telemetry layer separated from UI** (`src/app/telemetry/`): a `TelemetryProvider`
   interface with two implementations — `EmbraceProvider` (SDK arm) and `OtelProvider`
   (plain-OTel arm). `TelemetryService` (`@Injectable`) picks the arm from `?exporter=` and
   exposes the four demo actions. The UI imports only the service.
3. **No-account init** — call `initSDK` **without `appID`**; supply custom exporters instead:

   ```ts
   initSDK({
     appVersion: '1.0.0+1',
     resource: resourceFromAttributes({ 'service.name': 'embrace-demo-web', /* + schema attrs */ }),
     spanExporters: [new OTLPTraceExporter({ url: 'http://localhost:4318/v1/traces' })],
     logExporters:  [new OTLPLogExporter({  url: 'http://localhost:4318/v1/logs' })],
     defaultInstrumentationConfig: {
       network: { ignoreUrls: ['http://localhost:4318'] }, // self-tracing-loop guard
     },
   });
   ```

   `initSDK` returns `SDKControl | false`; the returned control exposes `trace`, `log`,
   `session`, `user`, `page`, `flush`.
4. Run `initTelemetry()` in `main.ts` **before** `bootstrapApplication` so the unhandled-error
   and Web-Vitals instrumentation is installed before any app code paints/throws.
5. Spans: `trace.startSpan(name, { attributes, parentSpan })`; child spans nest via the
   `parentSpan` option (Embrace's `ExtendedSpanOptions`). Failure: `span.recordException(e)` +
   `span.setStatus({ code: ERROR })` (the SDK's `span.fail()` is a convenience wrapper).
   Logs: `log.message(msg, 'info'|'warning'|'error', { attributes })`,
   `log.logException(err, { handled: true, attributes })`. Breadcrumbs:
   `session.addBreadcrumb(name)`. Custom event = an INFO log with an `event.name` attribute.

### Gotchas (cost us time / worth knowing)

- **Auto-instrumentation is genuinely React-coupled** in marketing, but the **core SDK is
  framework-agnostic** and embeds fine in Angular — the React `react-instrumentation`
  sub-export is optional and we never import it. This is the E8 answer: ✅ it runs.
- **No documented `service.name` option** in the getting-started; it is the `resource` option
  (`resource?: Resource`, merged with the SDK's own resource). Found only by reading the
  shipped `dist/sdk/types.d.ts`. User-supplied resource values take precedence.
- The package `exports` map only exposes `.` and `./react-instrumentation`, so **deep-importing
  internal types** (e.g. `…/dist/sdk/types.js`) fails the Angular/esbuild resolver. Derive the
  control type from the public API instead: `type SDKControl = Exclude<ReturnType<typeof initSDK>, false>`.
- **`network.ignoreUrls` is mandatory** for the collector URL — without it the OTLP export
  `fetch` is auto-traced, producing a span that triggers another export → loop.
- **Breadcrumbs/session need foreground engagement.** `session.addBreadcrumb` is dropped if no
  session *part* is active; a part only starts on real user input (visibility/focus/click). In
  the headless verifier we issue a `mouse.click` before firing actions so B3 is captured.
- **Unhandled crash + headless:** Embrace's global handler consumes the `window` error, so
  Playwright's `pageerror` event stays empty — that is expected; the telemetry (a
  `sys.exception` log with `emb_exception_handling=unhandled_error`) is the real proof, not the
  browser event.
- **Exception type normalization:** Embrace reports `exception.type = "Error"` (the JS base
  class) and puts the original subclass name in `exception_name`. Plain OTel preserves the exact
  thrown class name in `exception.type`. Minor, but matters for Grafana grouping/filters.

### Measured bundle size (production `ng build`)

This single build contains **both** the Embrace and the plain-OTel arms (the `?exporter=`
runtime toggle statically imports both):

```
main          328.78 kB raw  /  84.84 kB gzip
polyfills      34.59 kB raw  /  11.33 kB gzip
styles          0.14 kB
Initial total  363.51 kB raw  /  96.32 kB transfer (gzip)
```

For reference, a bare Angular 20 hello-world is ~220–230 kB raw / ~70 kB gzip, so the Embrace +
OTel stack adds roughly **~135 kB raw / ~26 kB gzip** here (with both arms bundled). A
production app would tree-shake to a single arm, trimming this further.

### Perf impact

Negligible for the demo. SDK init is synchronous and completes before bootstrap; in the
verifier the page reaches `ready=true` immediately and the `documentLoad` span measured a ~36 ms
load. Exporters batch over OTLP/HTTP, so action latency is unaffected (the `delay` action's
own span measured 756 ms for its 750 ms artificial sleep — i.e. ~6 ms overhead). Embrace adds
continuous lightweight instrumentation (Web Vitals, user-timing, LoAF, clicks); none was
perceptible in the headless run.

## Flutter (Embrace Flutter SDK)

**Client dir:** `clients/flutter` · **service.name:** `embrace-demo-flutter` (OTel arm) ·
**target:** self-hosted `grafana/otel-lgtm` (OTLP HTTP `http://localhost:4318`), no Embrace account.

**SDK:** `embrace` **4.7.0** (pub.dev). On iOS it pulls native **EmbraceIO 6.20.0** (open-source
Apple SDK, built on OpenTelemetry-Swift) via CocoaPods. Tracing API arrived in v3.0.0 (Sep 2024);
the Dart OTLP exporter API (`addSpanExporter`/`addLogRecordExporter`) + OTel API compliance in v4.6.0.

**Toolchain:** Flutter 3.44.2, Dart 3.12.2, Xcode iOS sim (iOS 26.5), CocoaPods 1.16.2. Verified on
**iOS simulator**. **Android not built** (no JDK/AVD in env).

### Integration steps that worked (iOS, no Embrace account)

1. `flutter pub add embrace opentelemetry device_info_plus package_info_plus http fixnum`.
2. **Telemetry layer separated from UI** (`lib/telemetry/`): a `TelemetryService` interface +
   `TelemetrySpan` handle, two impls — `EmbraceTelemetryService` and `OtelTelemetryService`. The
   UI (`main.dart`) and demo logic (`demo_actions.dart`) depend only on the interface; the arm is
   chosen at build time via `--dart-define=TELEMETRY_TOOL=embrace|otel`.
3. Register OTLP exporters from Dart **before** `start()` (correct on Android, **no-op on iOS** —
   see gotcha #1):
   ```dart
   Embrace.instance.addSpanExporter(endpoint: 'http://localhost:4318/v1/traces');
   Embrace.instance.addLogRecordExporter(endpoint: 'http://localhost:4318/v1/logs');
   await Embrace.instance.start(action: () => runApp(MyApp())); // guarded zone captures crashes
   ```
4. **iOS native setup is mandatory** — `ios/Runner/AppDelegate.swift`, appId-less initializer:
   ```swift
   import EmbraceIO
   let export = OpenTelemetryExport(spanExporter: OtlpJsonSpanExporter(),
                                    logExporter: OtlpJsonLogExporter())
   let captureServices = CaptureServiceBuilder().addDefaults()
     .remove(ofType: URLSessionCaptureService.self)
     .add(.urlSession(options: URLSessionCaptureService.Options(
        ignoredURLs: ["localhost:4318", "127.0.0.1:4318"])))           // loop guard (#3)
     .build()
   try Embrace.setup(options: Embrace.Options(
        export: export, platform: .flutter,
        captureServices: captureServices, crashReporter: KSCrashReporter())).start()
   ```
5. **No off-the-shelf OTLP-HTTP exporter pod** ships in the dep tree (only
   `OpenTelemetry-Swift-Api` + `…-Sdk`). We hand-rolled a ~120-line
   `OtlpJsonSpanExporter`/`OtlpJsonLogExporter` (`ios/Runner/OtlpJsonExporter.swift`) POSTing
   OTLP/JSON — avoids gRPC/protobuf pods that could clash with Embrace's pinned OTel version.
6. Add `OtlpJsonExporter.swift` to the Runner Xcode target (patch `project.pbxproj`;
   `flutter create` doesn't auto-add files).
7. ATS exception in `ios/Runner/Info.plist` for cleartext `http://localhost:4318`.

### E1 — no-account / no-appId init: works (source-confirmed + runtime-confirmed)

- `Embrace.Options.appId` is `String?`; `validateAppId()` only fails on a non-nil, non-5-char
  value. A **second designated init** takes `export: OpenTelemetryExport` and sets `appId=nil`;
  validation throws `"OpenTelemetryExport must be provided when not using an appId"` only if BOTH
  are nil. So no-account works **iff** a custom exporter is supplied.
- Runtime: `EMBRACE-DEMO: native setup OK (no-account, custom OTLP export)`; app status line
  `exporting (native started): true`; demo spans + Embrace's own startup/session spans reached
  Grafana with **no Embrace cloud account**.

### Gotchas

1. **Dart `addSpanExporter`/`addLogRecordExporter` are no-ops on iOS.** The `embrace_ios` plugin
   returns `result(nil)` for both, and its Dart `start()` only **attaches** to an already-started
   native client (it does not call `Embrace.setup`). On iOS the SDK setup AND the OTLP export
   must be configured natively in AppDelegate. (On **Android** the Dart exporter calls DO work —
   so the cross-platform story differs by OS.)
2. **Embrace overrides `service.name` + the whole resource schema.** Its data lands under
   `service.name = io.embrace.demo.embraceDemoFlutter:Runner` with Embrace's keys (`emb.app.*`,
   `emb.device.*`, `emb.sdk.version`, `telemetry.sdk.language`) and **drops** SCHEMA_CONTRACT keys
   (`telemetry.tool`, `user.id`, `device.model` were absent). Dart `addSessionProperty` did not
   override the OTel resource. Shared dashboards need collector-side relabeling for the
   Embrace-iOS arm; the **OTel arm honors the contract keys exactly**.
3. **Self-tracing loop is real.** Exporter POSTs over `URLSession`, auto-instrumented by Embrace's
   `URLSessionCaptureService` → ~200 runaway `POST /v1/traces` spans. Fixed with
   `URLSessionCaptureService.Options(ignoredURLs:[...])`; after the guard, **zero** new self-trace
   spans (verified by timestamp).
4. **Embrace flushes per session, not per span** (export on background / next launch). The OTel
   arm's `BatchSpanProcessor` flushes near-immediately.
5. **Span duplication** — each Embrace span appears twice in Tempo (open + completed record).
6. Plugin **does not support Swift Package Manager** (CocoaPods only) — will break in a future Flutter.

### Plain-OTel arm (telemetry.tool=otel) — the F1 baseline

- `opentelemetry` (workiva) **0.18.11**: traces via `CollectorExporter` + `BatchSpanProcessor` +
  `TracerProviderBase(resource: Resource([...contract attrs...]))`. **Logs are Unimplemented** in
  that package → ~40-line manual OTLP/JSON POST to `/v1/logs`. No native code, no account, runs on
  the simulator. Honors **all** SCHEMA_CONTRACT keys. Minor "Zone mismatch" warning if the binding
  is touched before the guarded zone — harmless.

### App size / perf impact (iOS)

- Embedded frameworks (simulator **debug**, unstripped — NOT release figures): `EmbraceIO`
  **≈11 MB**, `OpenTelemetrySdk` ≈6.3 MB, `OpenTelemetryApi` ≈7.3 MB, `embrace_ios` ≈0.7 MB.
  Release/stripped device builds are materially smaller, but Embrace + its OTel deps are the
  largest single native chunk among the SDKs evaluated. Pod source: EmbraceIO 1.8 MB + OTel ~2 MB.
- Perf: no measurable startup regression on the simulator. Embrace auto-instruments startup itself
  (E5). Init ordering matters: exporters before `start()`; native `Embrace.setup` as early as
  possible in `didFinishLaunchingWithOptions`.
