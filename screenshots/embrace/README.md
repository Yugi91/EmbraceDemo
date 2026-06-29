# Embrace cloud dashboard screenshots (per app · per case)

Real telemetry captured on the **Embrace cloud dashboard** (dash.embrace.io) after wiring each client
to **dual-export** (Embrace cloud + self-hosted Grafana). One Embrace app per platform; all US region.

How these were produced: each client SDK was given its Embrace **App ID** at runtime (query param / env /
build flag — never committed), the app fired the demo actions, and the dashboard views were screenshotted
full-screen (1920×1080) by attaching to the logged-in browser. App IDs + tokens live OUTSIDE the repo.

| Platform | App (App ID) | `app-ui.png` | Dashboard per-case |
|---|---|---|---|
| **Web** (Angular 20) | DemoWeb (`ctac2`) | demo screen + action buttons | `case-index-traces` (delay/crash/caught_error/workflow by name) · `case-workflow` (capture→save→sync waterfall) · `exceptions` (crash *DemoUnhandledError*) · `web-vitals` · `overview`/`sessions`/`issues`/`network` |
| **iOS** (Swift) | DemoIOS (`gq23k`) | sim screen + buttons | `traces` (delay/anr/frames/workflow + `emb-app-startup-warm`, `emb-…time-to-first-render`) · `exceptions` · `overview`/`sessions`/`issues` |
| **Android** (Kotlin) | DemoAndroid (`2tbxs`) | emulator screen + buttons | `issues` (**Crash** java.lang.RuntimeException *grouped* + **ANR 100%**) · `traces` (`emb-app-startup-cold`) · `overview`/`sessions`/`exceptions` |
| **Flutter** | DemoFlutter (`tzb7f`) | sim screen + buttons | `traces`/`sessions`/`issues`/`overview`/`exceptions` |

## What the per-case views show
- **Traces → Root Spans List** = every demo action as a named row (delay · crash · caught_error · workflow)
  with Count / P90 / P95 — the clearest "which case" index.
- **Trace detail** (e.g. `case-workflow`) = the span waterfall: `workflow → capture → save → sync`.
- **Issues / Exceptions** = crash & handled errors by name; on **mobile**, Embrace adds **crash grouping +
  ANR detection** (Android `issues` shows both) — its server-side strength that the Grafana self-host path
  does NOT have (finding F2).
- **Embrace auto-instrumentation** (`emb-app-startup-*`, `time-to-first-render`, session timeline) appears on
  iOS/Android/Flutter without manual code — the value Embrace adds over plain OTel (finding F1).

## Note on the two export targets
- **iOS / Flutter / Web** route their custom demo spans THROUGH the Embrace SDK → so those spans appear on
  the Embrace dashboard **and** Grafana.
- **Android** emits the custom demo spans via plain OTel-Java (→ Grafana); the Embrace Android SDK on the
  cloud side shows its **native auto-capture** (startup, **crash grouping**, **ANR**) — see `android/issues.png`.

Grafana-side screenshots of the same telemetry: `../20_grafana_overview.png`, `../21_grafana_all_platforms.png`.
