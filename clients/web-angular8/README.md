# web-angular8 — Embrace Web SDK feasibility spike (FNB-96526, E8)

**Question:** Can `@embrace-io/web-sdk` be installed and built into an **Angular 8 (EOL)** project on
its native **Node 14** toolchain? (FnB's real "WebPOS" stack: Angular 8 + Electron 8 + Node 14.)

**Verdict: ❌ NO.** `npm install` succeeds, but `ng build` fails with **49 TypeScript parse errors**
(`import type` / `export type` is TS 3.8 syntax; Angular 8 pins TypeScript `<3.6`). The realistic
fallback for WebPOS is a **pinned plain-`@opentelemetry/*@1.x` web setup**, not Embrace.

Full evidence + the cross-cut verdict are in
[`docs/_verdicts/angular8.md`](../../docs/_verdicts/angular8.md).

## Contents
```
web-angular8/
├── README.md                         (this file)
├── webpos8/                          minimal Angular 8 app (node_modules pruned; reproducible from lockfile)
│   ├── package.json                  @angular/* 8.2.14, typescript 3.5.3, + @embrace-io/web-sdk 2.22.0
│   ├── package-lock.json
│   └── src/main.ts                   minimal Embrace initSDK() wiring (no-account OTLP export)
└── evidence/
    ├── versions.txt                  toolchain + every version tried + result summary
    └── ng-build-embrace-FAIL.log     verbatim ANSI-stripped `ng build --prod` failure (49 TS errors, exit 1)
```

## Reproduce (everything runs in a `node:14` container — the host's Node 22 will NOT reproduce the constraint)

All commands assume cwd = this directory (`clients/web-angular8`).

### 0. One-time: pull the legacy toolchain
```bash
docker pull node:14   # node v14.21.3 / npm 6.14.18
```

### 1. Re-scaffold the app from scratch (optional — `webpos8/` is already here)
```bash
docker run --rm -v "$PWD":/work -w /work node:14 bash -c '
  npm i -g @angular/cli@8 &&
  ng new webpos8 --skip-git --defaults --skip-tests --style=css --routing=false --minimal'
```

### 2. Install deps (incl. Embrace) into `webpos8/`
```bash
docker run --rm -v "$PWD":/work -w /work/webpos8 node:14 bash -c '
  npm ci || npm install'
# ^ install SUCCEEDS. Engine mismatches for @opentelemetry/*@2.x (node "^18.19.0 || >=20.6.0")
#   are emitted only as `npm WARN notsup` under npm 6 — non-fatal.
```

### 3. Baseline build — confirm Angular 8 builds WITHOUT Embrace
Temporarily comment out the spike block in `src/main.ts`, then:
```bash
docker run --rm -v "$PWD":/work -w /work/webpos8 node:14 bash -c 'node_modules/.bin/ng build --prod'
# => SUCCEEDS, exit 0. Differential loading emits ES2015 + ES5 bundles.
```

### 4. Build WITH Embrace — the actual test
```bash
docker run --rm -v "$PWD":/work -w /work/webpos8 node:14 bash -c 'node_modules/.bin/ng build --prod'
# => FAILS, exit 1, 49 TS errors (TS1005 / TS1128 / TS1109), no dist bundle.
#    All in @opentelemetry/{exporter-trace-otlp-http,otlp-exporter-base}/build/src/*.d.ts
#    on `import type {...}` / `export type {...}` lines.
```

### 5. Workaround attempt (also fails)
Adding `"skipLibCheck": true` to `tsconfig.json` produces the **same 49 errors**: they are *syntax*
(parse) errors, which `skipLibCheck` (a *semantic* lib-check toggle) cannot suppress. Upgrading
TypeScript to `>=3.8` is blocked by `@angular/compiler-cli@8.2.14` (peer `typescript: >=3.4 <3.6`).

## Root cause (one line)
Modern `@opentelemetry/*` ship `.d.ts` using `import type` / `export type` (**TS 3.8**, Feb 2020);
Angular 8 caps TypeScript at **`<3.6`**, whose parser cannot tokenize that syntax.
