import { Injectable } from '@angular/core';
import type { Attributes } from '@opentelemetry/api';

import {
  actionAttributes,
  primeStorageEstimate,
  type ActionName,
  type TelemetryTool,
} from './schema';
import type { TelemetryProvider } from './telemetry.types';
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
   * Action 1 — delay: a traced async action with an artificial delay (a performance span).
   * Emits a B4 custom event ("delay.tick") partway through.
   */
  async delay(ms = 750): Promise<void> {
    this.provider.breadcrumb('action:delay');
    await this.provider.startActiveSpan('delay', this.attrs('delay', { 'delay.ms': ms }), async (span) => {
      span.addEvent('delay.started', { 'delay.ms': ms });
      await new Promise((r) => setTimeout(r, ms / 2));
      span.addEvent('delay.tick', { 'delay.elapsed_ms': ms / 2 });
      await new Promise((r) => setTimeout(r, ms / 2));
      span.addEvent('delay.completed', { 'delay.ms': ms });
    });
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
