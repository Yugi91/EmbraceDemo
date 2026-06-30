# Self-host (Grafana-only) gap analysis — what you LOSE without the Embrace cloud backend

**Decision context (FNB-96526):** if FnB integrates ONLY the self-hosted Grafana/LGTM stack
(client SDK → OTLP → Tempo/Loki/Prometheus) and does NOT use the Embrace **cloud** backend, which
capabilities are lost? Every row below is grounded in the spike (E1–E8, F1, F2) — **observed behaviour
on the running demo**, not vendor docs. Cross-refs point at the verdict rows in `SPIKE_RESULTS.md`.

Two "Grafana-only" variants matter — the answer differs:
- **(A) Embrace SDK → OTLP → Grafana** (SDK used, but no Embrace account / no cloud): you KEEP Embrace's
  client-side auto-RUM signals as **raw** data (Web Vitals, startup, session spans) because the SDK emits
  them over OTLP. You lose only the **server-side** processing.
- **(B) Bare OpenTelemetry SDK → Grafana** (no Embrace SDK at all): you ALSO lose the auto-RUM signals —
  you only get what you hand-instrument (plus a manual `window.onerror`/zone shim for crashes).

Legend: ✅ full · ⚠️ partial / raw only / manual · ❌ absent

## Capability comparison

| Capability | Embrace **cloud** | Grafana self-host **(A) Embrace SDK** | Grafana self-host **(B) bare OTel** | Finding |
|---|:--:|:--:|:--:|:--:|
| Custom spans / traces (delay · workflow · capture/save/sync) | ✅ | ✅ identical | ✅ identical | F1a |
| Logs · custom events · breadcrumbs | ✅ | ✅ | ✅ | B4 / F1a |
| Performance span durations (e.g. `delay`) | ✅ | ✅ | ✅ | B2 |
| Metrics — request rate / latency / error % (spanmetrics) | ✅ | ✅ | ✅ | infra |
| Crash **recorded at all** | ✅ | ✅ (raw) | ✅ (raw, via manual shim) | E2 |
| **Crash symbolication / de-obfuscation** (dSYM, R8/ProGuard) | ✅ | ❌ raw / obfuscated | ❌ | **F2** |
| **Crash grouping / dedup / issue management** | ✅ | ❌ flat events | ❌ | **F2 · E2** |
| **ANR / app-hang as a managed signal + rate** | ✅ native detector | ⚠️ manual span only | ⚠️ manual span only | E3 |
| Slow / frozen frames **metric** | ⚠️ manual span | ⚠️ manual span | ⚠️ manual span | E4 |
| App startup cold/warm **auto** (`emb-app-startup-*`) | ✅ auto | ✅ raw spans reach Grafana | ❌ (none) | E5 |
| Web Vitals / browser RUM **auto** (`ux.web_vital`, LoAF, user-timing) | ✅ | ✅ raw only | ❌ | F1b |
| Session timeline / **user flows** / release-health dashboards | ✅ curated UI | ⚠️ raw `emb-session` spans only, no curated UI | ❌ | B3 · F1b |
| Session **replay** | ❌ (no client-SDK API) | ❌ | ❌ | E6 |
| Network-request monitoring UI | ✅ | ⚠️ raw spans only | ❌ | — |
| Built-in alerting on crash-free % / ANR rate | ✅ | ⚠️ build-your-own in Grafana | ⚠️ build-your-own | F2 |
| Crash-free users · adoption · retention (release health) | ✅ | ❌ | ❌ | F2 |

## Bottom line

1. **Transport + raw telemetry are EQUIVALENT on self-host** — traces, logs, metrics, custom events and
   performance spans look the same whether they land in Embrace cloud or our Grafana (finding **F1**). For
   custom instrumentation + dev-build debugging, Grafana-only is fully sufficient.

2. **What you actually lose is the mobile crash-intelligence backend** (finding **F2**): symbolication,
   de-obfuscation, crash **grouping**, managed ANR, crash-free %, release health and out-of-the-box
   alerting — all **server-side** Embrace features. On a real PRODUCTION build (R8/ProGuard on Android,
   dSYM on iOS) the self-host crash stacks arrive **obfuscated/raw and ungrouped** → production triage is
   painful. This is the single biggest gap.

3. **Auto-RUM is an SDK-choice axis, not a backend axis.** Web Vitals, startup spans and the session
   timeline are KEPT (as raw data) if you keep the **Embrace SDK** and just point it at Grafana (variant A);
   they vanish with **bare OTel** (variant B). But the *curated* Embrace product UI (user flows, release
   health) is cloud-only either way.

4. **Not real differentiators:** session replay (absent from every client SDK — E6) and a frozen-frames
   *metric* (manual on both sides — E4).

## Recommendation

- **Self-hosted Grafana is enough** for custom traces/logs/metrics, performance spans and **non-production
  (debug) crash inspection**.
- For **production mobile crash & ANR triage** you need either (a) the **Embrace cloud** backend, or (b) a
  self-hostable crash backend that does symbolication + grouping — e.g. **Sentry self-host** (heavier
  footprint, see `SPIKE_RESULTS.md` O1: ~72 services, 4 vCPU / 16 GB+, FSL license).
- Pragmatic hybrid: **Embrace SDK → dual-export** (Embrace cloud for crash intelligence + Grafana for the
  unified custom-telemetry dashboard). This demo runs exactly that dual-export setup on all four clients.

---
_Grounded in the 2026-06-26 spike runs (E1–E8 / F1 / F2) + the dual-export Embrace-cloud capture
(2026-06-29). See `SPIKE_RESULTS.md` for per-platform evidence and `screenshots/embrace/` + `screenshots/`
for the Embrace-cloud vs Grafana dashboards._
