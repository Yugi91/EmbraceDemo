# Embrace vs Sentry — comparison table, refreshed with REAL spike results

This is the FNB-96526 §1.1 table, updated after running the demo. Cells marked **`*`** were
**spike-verified in this demo** (observed behaviour, not docs). Cells without `*` are carried over from
the FNB-96526 report (documented/inferred).

> ⚠️ **Honesty caveat — the Sentry (S) column was NOT built in this demo.** Decision D4 = no Sentry arm.
> So **every `S` verdict below is from the FNB-96526 report**, not re-verified here. Only the **Embrace
> (E)** side was actually spiked (all 4 SDKs + the Angular-8 build attempt). Treat `S` as research-grade,
> `E*` as demo-grade.

Legend: ✅ works · ⚠️ partial / caveat · ❌ does not / absent · `*` = spike-verified in this demo · — = N/A

### 1.1. Comparison (E = Embrace · S = Sentry)

| # | Feature (importance ↓) | iOS<br>(Swift 5 · iOS 13 · CocoaPods) | Android — Mobile/Touch<br>(Kotlin 2.1/2.0.21 · minSdk 21 · AGP 8.10/8.12) | Flutter — AppMAN<br>(Flutter 3.24.3 · Dart 3.5.3) | WebPOS<br>(Angular 8 EOL · Electron 8 · Node 14) | WebMan<br>(Angular 20 · Node 20) |
|---|---|:--|:--|:--|:--|:--|
| 1 | Native crash capture | E ✅\* · S ✅ | E ✅\* · S ✅ | E ✅\* · S ✅ | **E ❌\*** · S ✅ | — |
| 2 | ANR / App Hang | E ⚠️\* · S ✅ | E ✅\* · S ✅ | E ⚠️\* · S ✅ | — | — |
| 3 | Symbolication (dSYM / R8+NDK / Dart) | E ✅ · S ✅ | E ✅ · S ✅ | E ✅ · S ✅ | **E ❌\*** · S ✅ | E ✅ · S ✅ |
| 4 | Error / exception tracking | E ✅\* · S ✅ | E ✅\* · S ✅ | E ✅\* · S ✅ | **E ❌\*** · S ✅ | E ✅\* · S ✅ |
| 5 | **Session replay (visual)** | **E ❌\*** · S ✅ | **E ❌\*** · S ✅ | **E ❌\*** · S ✅ | **E ❌\*** · S ❌ | **E ❌\*** · S ✅ |
| 6 | App startup (cold / warm) | E ✅\* · S ✅ | E ✅\* · S ✅ | **E ✅\*** · S ✅ | — | — |
| 7 | Slow / frozen frames · Web Vitals | E ⚠️\* · S ✅ | E ⚠️\* · S ✅ | E ⚠️\* · S ✅ | **E ❌\*** · S ⚠️ | E ✅\* · S ✅ |
| 8 | Network request monitoring | E ✅ · S ✅ | E ✅ · S ✅ | E ✅ · S ✅ | **E ❌\*** · S ⚠️ | E ✅ · S ✅ |
| 9 | Performance tracing (spans) | E ✅\* · S ✅ | E ✅\* · S ✅ | E ✅\* · S ✅ | **E ❌\*** · S ⚠️ | E ✅\* · S ✅ |
| 10 | User journey / breadcrumbs | E ✅\* · S ✅ | E ✅\* · S ✅ | E ✅\* · S ✅ | **E ❌\*** · S ✅ | E ✅\* · S ✅ |
| 11 | Logs / custom events / spans (metrics: both ❌) | E ✅\* · S ✅ | E ✅\* · S ✅ | E ✅\* · S ✅ | **E ❌\*** · S ⚠️ | E ✅\* · S ✅ |
| 12 | Release / version + symbol upload | E ✅ · S ✅ | E ✅ · S ✅ | E ✅ · S ✅ | **E ❌\*** · S ⚠️ | E ✅ · S ✅ |
| 13 | **Framework fit (web)** | — | — | — | **E ❌\*** · S ⚠️ (Electron ✅) | **E ✅\*** · S ✅ |
| 14 | **Free / no license fee** | E ✅\* · S ✅ | **E ✅\*** · S ✅ | **E ✅\*** · S ✅ | E ✅ · S ✅ | E ✅\* · S ✅ |
| 15 | **Direct push to Grafana (OTLP)** | E ✅\* · S ❌ | E ✅\* · S ❌ | E ✅\* · S ❌ | E ✅ · S ❌ | E ✅\* · S ❌ |
| 16 | **Self-hostable backend (the tool's own)** | E ❌ · S ✅ | E ❌ · S ✅ | E ❌ · S ✅ | E ❌ · S ✅ | E ❌ · S ✅ |

## What changed vs the FNB-96526 report (Embrace side, evidence-backed)

**Resolved ⚠️ → ✅ (now proven):**
- **#4 Error tracking** iOS + WebMan: handled & unhandled exceptions captured identically (E7).
- **#6 App startup** Flutter: cold/warm auto-measured, no manual code — `emb-app-startup-cold/warm` (E5).
- **#13 Framework fit** WebMan/Angular 20: `@embrace-io/web-sdk@2.22.0` builds + streams real telemetry.
- **#14 Free tier** Android + Flutter: one free Embrace account (App IDs `2tbxs` / `tzb7f`) captured both.
- **#15 OTLP→Grafana**: confirmed on all 4 SDKs (the whole demo).

**Resolved ⚠️ → ❌ (proven absent / blocked):**
- **#5 Session replay** ALL platforms: no session-replay API in any Embrace client SDK (E6). Biggest "no".
- **WebPOS / Angular 8 entire Embrace column → ❌** (#1,3,4,7,8,9,10,11,12,13): the SDK **won't even compile**
  on Angular 8 — `ng build` fails with 49 TS errors (SDK's `import type` TS3.8 typings vs Angular 8's
  TS<3.6 cap; E8, evidence `clients/web-angular8/evidence/ng-build-embrace-FAIL.log`). Electron 8 / Node 14
  inherit the same ceiling. Realistic fallback = plain-OTel pinned to OTel 1.x (loses Embrace auto-RUM).

**Still ⚠️ after spiking (genuinely partial, not unknown):**
- **#2 ANR/App-Hang** iOS + Flutter: our manual `anr` span is captured, but the **native** discrete
  app-hang event was not surfaced in the run (Android's native ANR signal IS shown — E3). ANR is an
  Android-native concept; iOS = app-hang, Flutter = isolate block.
- **#7 Slow/frozen frames** mobile: captured only as a **manual** span; neither SDK auto-emitted a
  dedicated slow/frozen-frame **metric** (E4).

**Not spike-verified (kept as report values, no `*`):**
- **#3 Symbolication** + **#12 symbol upload**: the demo used **debug** builds (unminified) and did not
  upload a mapping/dSYM, so cloud symbolication wasn't exercised. NOTE: on the **self-host/Grafana** path
  symbolication + crash-grouping are **LOST** regardless (finding **F2**) — they are Embrace **cloud-backend**
  features. See `SELFHOST_GAP_ANALYSIS.md`.
- **#8 Network monitoring**: Embrace auto-network capture was configured (and the collector URL excluded to
  avoid a self-tracing loop) but not isolated as a demo case.
- **Entire Sentry (S) column**: D4 = Sentry arm not built.

## Bottom-line reading
- **Embrace is strong on mobile** (crash/ANR/startup auto, free tier, OTLP→Grafana) and **fine on Angular 20**.
- **Embrace's hard blockers:** no **session replay** (#5), no **self-host backend** (#16), and **cannot run on
  Angular 8 / Electron 8** (#13 — WebPOS). For WebPOS the only Embrace-ish path is plain-OTel (no Embrace RUM).
- **Sentry's structural trade-off (per report, unverified here):** richer replay + self-host backend, but
  **no OTLP** (#15) → can't feed Grafana directly; and on Angular 8 only the old `@sentry/angular@^6` line.
- For a **Grafana-unified** strategy, Embrace's OTLP path (#15) is the deciding advantage; for **production
  crash triage** you still need a symbolicating backend (Embrace cloud, or Sentry self-host — heavier).

---
_Refreshed 2026-06-30 from the demo spikes (E1–E8 / F1 / F2) + dual-export Embrace-cloud capture. Per-cell
evidence: `SPIKE_RESULTS.md`. Self-host gap: `SELFHOST_GAP_ANALYSIS.md`. Sentry not built (D4)._
