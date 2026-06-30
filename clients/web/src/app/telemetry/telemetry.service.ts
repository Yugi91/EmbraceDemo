import { Injectable } from '@angular/core';
import type { Attributes } from '@opentelemetry/api';

import {
  actionAttributes,
  primeStorageEstimate,
  type ActionName,
  type TelemetryTool,
} from './schema';
import type { DemoSpan, TelemetryProvider } from './telemetry.types';
import { EmbraceProvider } from './embrace.provider';
import { OtelProvider } from './otel.provider';

/** Decide which arm to use from the URL (?exporter=otel) — defaults to Embrace. */
export function resolveTool(): TelemetryTool {
  try {
    const params = new URLSearchParams(window.location.search);
    return params.get('exporter') === 'otel' ? 'otel' : 'embrace';
  } catch {
    return 'embrace';
  }
}

let singleton: TelemetryProvider | null = null;

/**
 * Initialize the telemetry provider exactly once, as early as possible (from main.ts,
 * before Angular bootstrap) so the unhandled-error instrumentation is installed before any
 * app code can throw. Safe to call repeatedly — returns the same instance.
 */
export function initTelemetry(): TelemetryProvider {
  if (singleton) return singleton;
  const tool = resolveTool();
  const provider: EmbraceProvider | OtelProvider =
    tool === 'otel' ? new OtelProvider() : new EmbraceProvider();
  provider.init();
  // Fire-and-forget: storage estimate primes the system.free_storage_mb attribute.
  void primeStorageEstimate();
  singleton = provider;
  return provider;
}

/**
 * Angular-facing telemetry service. Thin orchestration over the active provider; exposes the
 * four demo actions plus baseline-capture helpers. The provider is created in main.ts and read
 * here via the module singleton, so DI gets the already-initialized instance.
 */
@Injectable({ providedIn: 'root' })
export class TelemetryService {
  private readonly provider: TelemetryProvider = initTelemetry();

  get tool(): TelemetryTool {
    return this.provider.tool;
  }
  get ready(): boolean {
    return this.provider.ready;
  }
  get initError(): unknown {
    return this.provider.initError;
  }

  private attrs(action: ActionName, extra?: Attributes): Attributes {
    return { ...actionAttributes(action, this.provider.tool), ...(extra ?? {}) };
  }

  /**
   * Action 1 — metric: a CONCURRENT + NESTED span tree that captures REAL durations, to show
   * overlapping vs. sequential work in the trace/waterfall view:
   *
   *   metric            (ROOT span)
   *   ├── A             (child of metric; runs CONCURRENTLY with B)
   *   │   ├── C         (child of A; SEQUENTIAL — first,  ~120ms)
   *   │   └── D         (child of A; SEQUENTIAL — after C, ~90ms)
   *   └── B             (child of metric; CONCURRENT with A, ~150ms)
   *
   * JS is single-threaded, but `Promise.all([runA(), runB()])` lets A and B interleave at their
   * `await` points, so their spans OVERLAP in the timeline (A ≈ C+D ≈ 210ms, B ≈ 150ms, and the
   * `metric` root ≈ max(A, B) ≈ 210ms). C → D are strictly sequential inside A.
   *
   * IMPORTANT (nesting): the descendants use `parent.child(...)` rather than another bare
   * `startActiveSpan`. The active-context managers in BOTH arms (Embrace's bundled manager and
   * the OTel `StackContextManager`) are SYNCHRONOUS/stack-based and do NOT preserve the active
   * span across an `await`. A bare nested `startActiveSpan` for D would be created AFTER
   * `await runC()`, by which point the active context has unwound — so D would mis-parent. The
   * `.child()` façade parents EXPLICITLY (Embrace `parentSpan`, OTel explicit parent context),
   * which nests reliably regardless of the async-context limitation. Each child is still created
   * INSIDE its parent's callback, satisfying the parent/child contract.
   */
  async metric(): Promise<void> {
    this.provider.breadcrumb('action:metric');

    // Simulated work durations (ms). A overlaps B; A ≈ C+D so the root ≈ max(A, B).
    const C_MS = 120;
    const D_MS = 90;
    const B_MS = 150;
    const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

    // C — first sequential child of A.
    const runC = (a: DemoSpan): Promise<number> =>
      a.child('C', this.attrs('metric', { 'task.name': 'C', 'work.ms': C_MS }), async (c) => {
        const start = performance.now();
        c.addEvent('C.started', { 'work.ms': C_MS });
        await sleep(C_MS);
        const dur = Math.round(performance.now() - start);
        c.setAttributes({ 'work.actual_ms': dur });
        c.addEvent('C.completed', { 'work.actual_ms': dur });
        return dur;
      });

    // D — second sequential child of A (runs AFTER C resolves).
    const runD = (a: DemoSpan): Promise<number> =>
      a.child('D', this.attrs('metric', { 'task.name': 'D', 'work.ms': D_MS }), async (d) => {
        const start = performance.now();
        d.addEvent('D.started', { 'work.ms': D_MS });
        await sleep(D_MS);
        const dur = Math.round(performance.now() - start);
        d.setAttributes({ 'work.actual_ms': dur });
        d.addEvent('D.completed', { 'work.actual_ms': dur });
        return dur;
      });

    // A — child of metric; runs C then D SEQUENTIALLY. Concurrent with B.
    const runA = (parent: DemoSpan): Promise<number> =>
      parent.child('A', this.attrs('metric', { 'task.name': 'A' }), async (a) => {
        const start = performance.now();
        a.addEvent('A.started');
        const cMs = await runC(a);
        const dMs = await runD(a);
        const dur = Math.round(performance.now() - start);
        a.setAttributes({ 'work.actual_ms': dur, 'work.c_ms': cMs, 'work.d_ms': dMs });
        a.addEvent('A.completed', { 'work.actual_ms': dur });
        return dur;
      });

    // B — child of metric; runs CONCURRENTLY with A.
    const runB = (parent: DemoSpan): Promise<number> =>
      parent.child('B', this.attrs('metric', { 'task.name': 'B', 'work.ms': B_MS }), async (b) => {
        const start = performance.now();
        b.addEvent('B.started', { 'work.ms': B_MS });
        await sleep(B_MS);
        const dur = Math.round(performance.now() - start);
        b.setAttributes({ 'work.actual_ms': dur });
        b.addEvent('B.completed', { 'work.actual_ms': dur });
        return dur;
      });

    await this.provider.startActiveSpan(
      'metric',
      this.attrs('metric', { 'task.name': 'metric' }),
      async (root) => {
        const start = performance.now();
        root.addEvent('metric.started');
        // Concurrent: A (which itself sequences C → D) overlaps B.
        const [aMs, bMs] = await Promise.all([runA(root), runB(root)]);
        const dur = Math.round(performance.now() - start);
        root.setAttributes({ 'work.actual_ms': dur, 'work.a_ms': aMs, 'work.b_ms': bMs });
        root.addEvent('metric.completed', { 'work.actual_ms': dur });
      }
    );

    this.provider.logMessage('metric perf tree done (A‖B, A→C→D)', 'info', this.attrs('metric'));
  }

  /**
   * Action 2 — crash (B1): throw an UNHANDLED error. We start a span, mark it failed, end it,
   * then throw asynchronously so the error escapes to the global handler (Embrace's exception
   * instrumentation / our OTel window.onerror) rather than being swallowed by the promise chain.
   */
  triggerCrash(): void {
    this.provider.breadcrumb('action:crash');
    const error = new Error('Demo unhandled crash from web client');
    error.name = 'DemoUnhandledError';
    void this.provider.startActiveSpan('crash', this.attrs('crash'), (span) => {
      span.addEvent('crash.about_to_throw');
      span.fail(error);
    });
    // Escape the current task so it becomes a genuine uncaught error.
    setTimeout(() => {
      throw error;
    }, 0);
  }

  /**
   * Action 3 — caught_error (E7): try/catch then log the handled exception.
   * The same error shape as the crash, but routed through log.logException(handled:true).
   */
  async caughtError(): Promise<void> {
    this.provider.breadcrumb('action:caught_error');
    await this.provider.startActiveSpan('caught_error', this.attrs('caught_error'), (span) => {
      try {
        const error = new Error('Demo handled exception from web client');
        error.name = 'DemoHandledError';
        throw error;
      } catch (err) {
        const e = err instanceof Error ? err : new Error(String(err));
        span.addEvent('caught_error.handled', { 'exception.type': e.name });
        this.provider.logException(e, this.attrs('caught_error'));
      }
    });
  }

  /**
   * Action 4 — workflow (B4 custom events): parent span `workflow` with child spans
   * capture → save → sync, each carrying step.name/step.status/step.data + timestamped events.
   * The sync step fails ~50% of the time (span status ERROR + exception attrs).
   */
  async workflow(forceSyncFail?: boolean): Promise<{ syncFailed: boolean }> {
    this.provider.breadcrumb('action:workflow');
    const syncShouldFail = forceSyncFail ?? Math.random() < 0.5;

    await this.provider.startActiveSpan('workflow', this.attrs('workflow'), async (parent) => {
      parent.addEvent('started');

      // capture
      const bytes = await parent.child(
        'capture',
        { 'step.name': 'capture', 'step.status': 'ok' },
        async (s) => {
          await new Promise((r) => setTimeout(r, 80));
          const captured = 2048;
          s.setAttributes({ 'step.data': `${captured} bytes`, 'step.status': 'ok' });
          s.addEvent('captured', { 'step.data': captured });
          return captured;
        }
      );

      // save
      const path = await parent.child(
        'save',
        { 'step.name': 'save', 'step.status': 'ok' },
        async (s) => {
          await new Promise((r) => setTimeout(r, 60));
          const savedPath = `/local/cache/submission-${Date.now()}.bin`;
          s.setAttributes({ 'step.data': `${bytes} bytes`, 'step.status': 'ok', 'save.path': savedPath });
          s.addEvent('saved', { 'save.path': savedPath });
          return savedPath;
        }
      );

      // sync (may fail)
      try {
        await parent.child(
          'sync',
          { 'step.name': 'sync', 'step.status': 'ok', 'sync.endpoint': 'https://api.demo/submit' },
          async (s) => {
            await new Promise((r) => setTimeout(r, 100));
            if (syncShouldFail) {
              s.setAttributes({ 'step.status': 'failure', 'http.status': 503 });
              const err = new Error('sync failed: upstream 503 from https://api.demo/submit');
              err.name = 'SyncError';
              s.addEvent('failed', { 'http.status': 503, 'save.path': path });
              s.fail(err, { 'step.status': 'failure', 'http.status': 503 });
              throw err;
            }
            s.setAttributes({ 'step.status': 'ok', 'http.status': 200 });
            s.addEvent('synced', { 'http.status': 200, 'save.path': path });
          }
        );
      } catch {
        // Workflow records the failed sync but completes; the child already carries ERROR status.
        parent.addEvent('sync_failed_handled');
      }

      parent.addEvent('finished', { 'workflow.sync_failed': syncShouldFail });
    });

    return { syncFailed: syncShouldFail };
  }

  /**
   * Action 5 — network [LEVEL 2]: perform a REAL HTTP GET via fetch. The Embrace Web SDK
   * auto-captures fetch/XHR, so this request also surfaces in Embrace's Network view under the
   * jsonplaceholder.typicode.com domain. We additionally wrap it in a `network` span carrying
   * the http.* attributes and log success/failure like the other actions.
   */
  async network(): Promise<{ ok: boolean; status: number }> {
    this.provider.breadcrumb('action:network');
    const url = 'https://jsonplaceholder.typicode.com/todos/1';
    const method = 'GET';
    return this.provider.startActiveSpan(
      'network',
      this.attrs('network', { 'http.url': url, 'http.method': method }),
      async (span) => {
        span.addEvent('network.request', { 'http.url': url, 'http.method': method });
        try {
          const res = await fetch(url, { method });
          span.setAttributes({ 'http.status_code': res.status });
          if (!res.ok) {
            const err = new Error(`network request failed: HTTP ${res.status} from ${url}`);
            err.name = 'NetworkError';
            span.addEvent('network.failed', { 'http.status_code': res.status });
            span.fail(err, { 'http.status_code': res.status });
            this.provider.logMessage(
              `network: GET ${url} failed (HTTP ${res.status})`,
              'error',
              this.attrs('network', { 'http.url': url, 'http.status_code': res.status })
            );
            return { ok: false, status: res.status };
          }
          span.addEvent('network.succeeded', { 'http.status_code': res.status });
          this.provider.logMessage(
            `network: GET ${url} ok (HTTP ${res.status})`,
            'info',
            this.attrs('network', { 'http.url': url, 'http.status_code': res.status })
          );
          return { ok: true, status: res.status };
        } catch (err) {
          const e = err instanceof Error ? err : new Error(String(err));
          span.fail(e, { 'http.url': url, 'http.method': method });
          this.provider.logException(e, this.attrs('network', { 'http.url': url }));
          return { ok: false, status: 0 };
        }
      }
    );
  }

  /**
   * Action 6 — oom [LEVEL 3]: best-effort memory-pressure action.
   *
   * NOTE: a true OS OOM-kill is NOT applicable to a browser tab — browsers sandbox each tab's
   * memory and respond to exhaustion with a per-tab "Aw, Snap"/allocation failure, not an OS
   * OOM signal. So this demonstrates ALLOCATION PRESSURE, not an OS OOM-kill. We retain a
   * growing array of large typed arrays (32 MiB each), bounded to ~200 iterations so we don't
   * hard-freeze the dev machine, logging progress along the way.
   */
  async oom(): Promise<{ iterations: number; allocatedMb: number }> {
    this.provider.breadcrumb('action:oom');
    const CHUNK_BYTES = 32 * 1024 * 1024; // 32 MiB per allocation
    const MAX_ITERATIONS = 200; // bound so the dev machine doesn't hard-freeze
    return this.provider.startActiveSpan(
      'oom',
      this.attrs('oom', { 'oom.chunk_bytes': CHUNK_BYTES, 'oom.max_iterations': MAX_ITERATIONS }),
      async (span) => {
        // Retained so the allocations can't be garbage-collected mid-loop.
        const retained: Uint8Array[] = [];
        let i = 0;
        try {
          for (; i < MAX_ITERATIONS; i++) {
            // Touch the first byte so the engine actually commits the pages.
            const chunk = new Uint8Array(CHUNK_BYTES);
            chunk[0] = 1;
            retained.push(chunk);
            if (i % 25 === 0) {
              const allocatedMb = Math.round(((i + 1) * CHUNK_BYTES) / (1024 * 1024));
              span.addEvent('oom.progress', { 'oom.iteration': i, 'oom.allocated_mb': allocatedMb });
              this.provider.logMessage(
                `oom: allocated ~${allocatedMb} MB (iteration ${i})`,
                'warning',
                this.attrs('oom', { 'oom.iteration': i, 'oom.allocated_mb': allocatedMb })
              );
              // Yield so progress logs/spans can flush and the tab stays responsive.
              await new Promise((r) => setTimeout(r, 0));
            }
          }
        } catch (err) {
          // An allocation failure here is the browser's per-tab limit, NOT an OS OOM-kill.
          const e = err instanceof Error ? err : new Error(String(err));
          span.fail(e, { 'oom.iteration': i });
          this.provider.logException(e, this.attrs('oom', { 'oom.iteration': i }));
        }
        const allocatedMb = Math.round((retained.length * CHUNK_BYTES) / (1024 * 1024));
        span.setAttributes({ 'oom.iterations': retained.length, 'oom.allocated_mb': allocatedMb });
        span.addEvent('oom.heavy_allocation', { 'oom.allocated_mb': allocatedMb });
        this.provider.logMessage(
          'oom: heavy allocation (browser has no OS OOM-kill — see note)',
          'warning',
          this.attrs('oom', { 'oom.iterations': retained.length, 'oom.allocated_mb': allocatedMb })
        );
        // Drop the references so the heap can be reclaimed after the action completes.
        retained.length = 0;
        return { iterations: i, allocatedMb };
      }
    );
  }

  /** B3 helper — record a session/user-journey breadcrumb. */
  breadcrumb(name: string): void {
    this.provider.breadcrumb(name);
  }

  /** B4 helper — emit a standalone custom event as an INFO log with structured attrs. */
  customEvent(name: string, attrs?: Attributes): void {
    this.provider.logMessage(name, 'info', { 'event.name': name, ...(attrs ?? {}) });
  }

  flush(): Promise<void> {
    return this.provider.flush();
  }
}
