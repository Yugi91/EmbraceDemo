# Verdict — E8 (Angular 8) + Web (Ng8) baseline · FNB-96526

Spike dir: `clients/web-angular8/` · raw evidence: `clients/web-angular8/evidence/`
Run on the **native legacy toolchain** in a `node:14` Docker container (host Node 22 cannot reproduce
the constraint). This covers FnB's real "WebPOS" stack target: **Angular 8 + Node 14** (+ Electron 8).

| ID | Cell | Verdict | One-line |
|----|------|:--:|---|
| **E8** | Web framework fit — Embrace SDK embeds & runs? (**Angular 8** column) | ❌ | `npm i` OK, but `ng build` fails — 49 TS parse errors; `import type` is TS 3.8, Angular 8 caps TS `<3.6`. |
| **B1–B4** | BASELINE captures, **Web (Ng8)** column | ❌ | Embrace cannot be built into Ng8, so none of B1–B4 can be demonstrated via Embrace on Ng8. The Ng8 app itself builds fine; the blocker is the SDK. |

> Note: the working **Web (Ng20)** E8 ✅ and B1–B4 ✅ (reference at `clients/web`, `@embrace-io/web-sdk@2.22.0`)
> are unaffected — this verdict only fills the **Ng8** sub-cells that were ⬜.

---

## E8 (Angular 8): ❌ confirmed not working

### Toolchain (exact, from `node:14` container)
- node **v14.21.3**, npm **6.14.18**
- `@angular/cli` **8.3.29**, `@angular/*` app **8.2.14**, `@angular-devkit/build-angular` **0.803.29**
- **typescript 3.5.3** — and Angular 8 *pins* it: `@angular/compiler-cli@8.2.14` peer = `typescript: >=3.4 <3.6`
- tsconfig `target: es2015` → differential loading also emits ES5

### Embrace versions tried
- **`@embrace-io/web-sdk@2.22.0`** — the latest, and the *same version that builds fine on the Angular 20
  reference*. No `engines` field of its own; `peerDependencies` is only `react` (peer-only, unused on the
  manual-wiring path). Pulls modern transitive deps: `@opentelemetry/*@2.8.0 / ^0.219.0`, `web-vitals@^5.3.0`.
- **`@opentelemetry/exporter-trace-otlp-http@0.219.0`** — imported directly by the minimal `initSDK()` in
  `src/main.ts` (mirrors the Ng20 reference shape: no appID → no-account mode, custom OTLP span exporter to
  `http://localhost:4318/v1/traces`; does not need to actually send — BUILD feasibility only).

### Step 1 — install: ✅ SUCCEEDS (so install is NOT the blocker)
Under npm 6, engine mismatches are **warnings, not errors**:
```
npm WARN notsup Unsupported engine for @opentelemetry/core@2.8.0:
  wanted: {"node":"^18.19.0 || >=20.6.0"} (current: {"node":"14.21.3","npm":"6.14.18"})
... (same WARN for sdk-trace-web, sdk-trace-base, sdk-metrics, resources, instrumentation,
     otlp-transformer, otlp-exporter-base, sdk-logs, exporter-trace-otlp-http,
     instrumentation-fetch/-xhr, web-common @ 0.219.0; import-in-the-middle@3.2.0 wants node>=18)
+ @embrace-io/web-sdk@2.22.0
added 25 packages ... in 7.845s        # exit 0
```
(npm 6 default is `engine-strict=false`. A consumer who set `engine-strict=true` WOULD get a hard
`EBADENGINE` install failure here — but even with the default lenient install, the build fails next.)

### Step 3 — `ng build --prod`: ❌ FAILS — exit 1, NO `dist` bundle, **49 TypeScript errors**
Error-code histogram (ANSI-stripped):
```
42  error TS1005   ("';' expected" / "'=' expected")
 6  error TS1128   ("Declaration or statement expected")
 1  error TS1109
```
Every error is in `@opentelemetry/{exporter-trace-otlp-http,otlp-exporter-base}/build/src/*.d.ts`,
on `import type` / `export type` lines. Verbatim (head of `evidence/ng-build-embrace-FAIL.log`):
```
ERROR in node_modules/@opentelemetry/exporter-trace-otlp-http/build/src/platform/node/OTLPTraceExporter.d.ts:1:13 - error TS1005: '=' expected.
1 import type { ReadableSpan, SpanExporter } from '@opentelemetry/sdk-trace-base';
              ~
node_modules/@opentelemetry/otlp-exporter-base/build/src/index.d.ts:8:1 - error TS1128: Declaration or statement expected.
8 export type { OTLPExporterNodeConfigBase } from './configuration/legacy-node-configuration';
  ~~~~~~
```

### Root cause
`import type` / `export type` is **TypeScript 3.8** syntax (released Feb 2020). Angular 8's compiler
hard-caps TypeScript at **`<3.6`**. TS 3.5's *parser* cannot tokenize the `type` modifier, so these
are **syntax (parse) errors**, raised before any type-checking. The modern OTel `.d.ts` files (shipped
by the deps Embrace pulls in) are simply unparseable by the only TypeScript version Angular 8 allows.

### Step 4 — workaround attempt (time-boxed): ❌ does not help
- **`skipLibCheck: true`** → **identical 49 errors**. `skipLibCheck` suppresses *semantic* checking of
  declaration files; it does not stop the parser from *reading* them. Syntax errors fire regardless.
- **Upgrade TypeScript to ≥3.8** → blocked: `@angular/compiler-cli@8.2.14` peer `typescript: >=3.4 <3.6`.
  You cannot satisfy both "Angular 8 compiler" and "TS that understands `import type`" simultaneously.
- Older Embrace web-sdk versions are not a viable escape: the package's modern `@opentelemetry/*@2.x /
  0.219.x` dependency tree (which carries the TS-3.8 `.d.ts`) is what breaks TS 3.5 — the incompatibility
  is structural to the OTel toolchain era, not specific to one Embrace release. (`@embrace-io/web-sdk`
  latest == 2.22.0; there is no older line that pairs with TS-3.5-parseable OTel `.d.ts`.)

**Conclusion (E8 / Angular 8): ❌.** Not a config tweak away — it's a hard TS-version incompatibility
between Angular 8 (TS `<3.6`) and the modern OpenTelemetry typings the Embrace Web SDK depends on.
(Electron 8 / Node 14 share the same toolchain ceiling, so the Electron sub-cell inherits this ❌.)

---

## Web (Ng8) baseline capture (B1–B4): ❌ via Embrace

Because Embrace cannot be **built** into Ng8 (above), the B1–B4 baseline captures (real error, Web
Vitals, session timeline, custom event) **cannot be demonstrated through Embrace on Angular 8**.

What WAS independently proven on Ng8: the **Angular 8 app builds fine on its own** —
`ng build --prod` with no Embrace import **succeeds, exit 0**, emitting differential ES2015 + ES5 bundles:
```
chunk {1} main-es2015.<hash>.js (main) 134 kB [initial] [rendered]
chunk {1} main-es5.<hash>.js   (main) 164 kB [initial] [rendered]
... Time: 9389ms        # exit 0
```
So the toolchain is healthy; the blocker is squarely the Embrace SDK's modern OTel dependency typings.

---

## Realistic WebPOS fallback: plain `@opentelemetry/*` — viable ONLY if pinned to the 1.x line

Plain OTel is the right fallback for WebPOS **but only with version discipline**:
- The OTel **`2.x` / `0.4x.x`+ (and 0.219.x)** packages carry the SAME TS-3.8 `.d.ts` (`import type`/
  `export type`) that broke the build above — so naively `npm i @opentelemetry/sdk-trace-web` (latest)
  on Angular 8 would fail **identically**.
- The viable path is to **pin the older OTel `1.x` web line** (e.g. `@opentelemetry/sdk-trace-web@^1.x`
  with matching `@opentelemetry/exporter-trace-otlp-http@^0.4x` from the 1.x era), whose `.d.ts` predate
  the `import type` syntax and parse under TS 3.5. That gives WebPOS the OTLP→Grafana transport (manual
  spans/logs) without Embrace's auto-RUM (Web Vitals, session timeline, click tracking — the Embrace
  value-add documented under F1b for Ng20).
- Not exhaustively build-verified in this time-boxed spike (the E8 question was the deliverable), but the
  mechanism is clear: the blocker is purely the OTel **typings era**, which 1.x avoids. Recommended next
  step if WebPOS observability is pursued: a 1-hour pinned-OTel-1.x build spike on this same `node:14`
  harness to confirm bundle output.

**Bottom line:** Embrace Web SDK → Angular 8 = ❌ (hard TS incompatibility). For WebPOS, use a
**version-pinned plain-OTel 1.x** web setup, accepting loss of Embrace's auto-RUM; the realistic strategic
fix is to migrate WebPOS off Angular 8 (then the Ng20 ✅ path applies).
