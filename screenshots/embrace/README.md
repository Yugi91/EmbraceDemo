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
| **Android** (Kotlin) | DemoAndroid (`2tbxs`) | emulator screen + buttons | `traces` (delay/workflow/capture/save/sync/caught_error/frames by name + `emb-app-startup-cold`) · `issues` (**Crash** java.lang.RuntimeException *grouped* + **ANR 100%**) · `overview`/`sessions`/`exceptions` |
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
- **All four clients** route their custom demo spans THROUGH the Embrace SDK → so those spans appear on the
  Embrace dashboard **and** Grafana. On Android this is done by also recording each action via the Embrace
  TracingApi (`Embrace.getInstance().recordCompletedSpan(name, startMs, endMs)`) in the `embrace` arm, in
  addition to the OTel-Java span that feeds Grafana — see `android/traces.png` (delay/workflow/capture/save/
  sync/caught_error/frames all listed). On Android these are recorded as flat root spans (one row per case)
  rather than the nested `workflow → capture → save → sync` waterfall the web/iOS Embrace SDKs build.
- On **mobile**, Embrace additionally adds **crash grouping + ANR detection** server-side (Android `issues.png`
  shows both) — its strength that the Grafana self-host path does NOT have (finding F2).

## Deep drill-in captures (Performance + Troubleshooting) — `<platform>/deep/`
"All the way inside" — drilled into the detail views, not just the summary lists.

| Platform | `deep/` contents |
|---|---|
| **Android** (`2tbxs`) | `crashes` (crash-free % + trend + grouped RuntimeException) · `crash-detail-stack` (full stack **DemoActions.kt:130**, "Most relevant" frame) · `crash-detail-timeline` (session: startup→foreground→activity→network) · `crash-detail-logs` · `anr` + `anr-detail` (`java.lang.Thread.sleep`, ANR-free 95.83%) · `app-startup` · `network` · `release-health` · `trace-workflow-waterfall` · `user-flows` |
| **iOS** (`gq23k`) | `crashes` + `crash-detail-stack`/`-timeline`/`-logs` (Swift-mangled `$s…Actions…crash` — debug build, no dSYM upload = F2) · `app-startup` · `network` · `release-health` · `trace-workflow-waterfall` (**nested**, Total Spans 4) · `user-flows` |
| **Flutter** (`tzb7f`) | `exceptions` (Dart crash is an **Exception**, not a native Crash) · `app-startup` (cold/warm/TTFR) · `network` · `release-health` · `trace-workflow-waterfall` (**nested**) · `user-flows` |
| **Web** (`ctac2`) | `exceptions` (DemoHandledError + DemoUnhandledError JS errors) · `network` (**real business endpoint** `GET jsonplaceholder.typicode.com/todos/«number»`, auto-captured) · `web-vitals` · `release-health` · `trace-workflow-waterfall` · `exception-detail` |

Platform-honest differences (captured, not hidden):
- **Flutter crash → Exceptions, not Crashes** — a Dart guarded-zone error; the native Crashes view shows the empty state.
- **iOS has no ANR view** — the iOS analogue is app-hang; ANR is Android-specific.
- **Android records flat root spans** (each action a separate row) while **iOS / Flutter** nest `workflow → capture → save → sync` into a true waterfall.
- **Real-endpoint network**: a `network` action (real HTTP GET to jsonplaceholder.typicode.com) is wired on all 4 clients; captured for **web** so far (`web/deep/network.png`). Android/iOS/Flutter native re-runs to refresh their Network view with the real endpoint are pending.
- **Out Of Memory** + **Compare** (2-version) views are not yet populated (need an OOM trigger + a 2nd build — Level 3).

Grafana-side screenshots of the same telemetry: `../20_grafana_overview.png`, `../21_grafana_all_platforms.png`.
