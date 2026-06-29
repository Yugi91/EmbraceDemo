import {
  context as otelContext,
  SpanStatusCode,
  type Attributes,
  type Span,
  type TimeInput,
} from '@opentelemetry/api';
import { resourceFromAttributes } from '@opentelemetry/resources';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { OTLPLogExporter } from '@opentelemetry/exporter-logs-otlp-http';
import { initSDK, trace, log, session } from '@embrace-io/web-sdk';

// initSDK returns `SDKControl | false`; derive the control type from the public export
// rather than deep-importing internal paths (the package `exports` map only exposes `.`).
type SDKControl = Exclude<ReturnType<typeof initSDK>, false>;

import {
  APP_VERSION,
  ATTR,
  commonResourceAttributes,
  OTLP_BASE,
  OTLP_LOGS_URL,
  OTLP_TRACES_URL,
} from './schema';
import type { DemoSpan, LogLevel, TelemetryProvider } from './telemetry.types';

/** Wrap an OTel Span (Embrace's ExtendedSpan is a superset) in the DemoSpan façade. */
function wrapSpan(span: Span): DemoSpan {
  return {
    setAttributes(attrs: Attributes) {
      span.setAttributes(attrs);
    },
    addEvent(name: string, attrs?: Attributes, timestamp?: TimeInput) {
      span.addEvent(name, attrs, timestamp);
    },
    fail(error: Error, attrs?: Attributes) {
      if (attrs) span.setAttributes(attrs);
      span.setAttribute(ATTR.EXCEPTION_TYPE, error.name);
      span.setAttribute(ATTR.EXCEPTION_MESSAGE, error.message);
      span.recordException(error);
      span.setStatus({ code: SpanStatusCode.ERROR, message: error.message });
    },
    end() {
      span.end();
    },
    async child<T>(
      name: string,
      attrs: Attributes,
      fn: (s: DemoSpan) => Promise<T> | T
    ): Promise<T> {
      // Parent via Embrace's ExtendedSpanOptions.parentSpan so the child nests under `workflow`.
      const childSpan = trace.startSpan(name, { parentSpan: span, attributes: attrs });
      try {
        const result = await fn(wrapSpan(childSpan));
        childSpan.end();
        return result;
      } catch (err) {
        const e = err instanceof Error ? err : new Error(String(err));
        childSpan.setAttribute(ATTR.EXCEPTION_TYPE, e.name);
        childSpan.setAttribute(ATTR.EXCEPTION_MESSAGE, e.message);
        childSpan.recordException(e);
        childSpan.setStatus({ code: SpanStatusCode.ERROR, message: e.message });
        childSpan.end();
        throw err;
      }
    },
  };
}

/**
 * Embrace Web SDK arm. Spike E8: the framework-agnostic core SDK is wired into Angular
 * MANUALLY (auto-instrumentation is React-only). No Embrace account → appID omitted and a
 * custom OTLP span+log exporter pair targets our local collector. The collector URL is added
 * to network.ignoreUrls to prevent the export fetch from being auto-traced (self-tracing loop).
 */
export class EmbraceProvider implements TelemetryProvider {
  readonly tool = 'embrace' as const;
  ready = false;
  initError?: unknown;

  private control: SDKControl | null = null;

  init(): void {
    try {
      // Optional Embrace-cloud DUAL-EXPORT: providing an appID makes the SDK send to the Embrace
      // dashboard IN ADDITION to the custom OTLP exporters (→ Grafana). Read at runtime from the
      // `embraceAppId` query param (or window.__EMBRACE_APP_ID__) so no account-specific ID is
      // committed to the repo. Omitted → no-account mode (Grafana-only).
      const appId =
        new URLSearchParams(globalThis.location?.search ?? '').get('embraceAppId') ||
        (globalThis as unknown as { __EMBRACE_APP_ID__?: string }).__EMBRACE_APP_ID__ ||
        undefined;
      const result = initSDK({
        ...(appId ? { appID: appId } : {}),
        // appID omitted → no-account mode; valid because custom OTLP exporters are set.
        appVersion: APP_VERSION,
        resource: resourceFromAttributes(commonResourceAttributes('embrace')),
        spanExporters: [new OTLPTraceExporter({ url: OTLP_TRACES_URL })],
        logExporters: [new OTLPLogExporter({ url: OTLP_LOGS_URL })],
        defaultInstrumentationConfig: {
          // Self-tracing loop guard: do not auto-instrument the OTLP export calls.
          network: { ignoreUrls: [OTLP_BASE] },
        },
      });
      if (result === false) {
        throw new Error('initSDK returned false (SDK refused to initialize)');
      }
      this.control = result;
      this.ready = true;
    } catch (err) {
      this.initError = err;
      this.ready = false;
      // Surface for the E8 verdict; do not rethrow so the app can still load.
      console.error('[EmbraceProvider] initSDK failed:', err);
    }
  }

  async startActiveSpan<T>(
    name: string,
    attrs: Attributes,
    fn: (span: DemoSpan) => Promise<T> | T
  ): Promise<T> {
    const span = trace.startSpan(name, { attributes: attrs });
    // Make the span active so any nested auto-instrumented work attaches to it.
    const ctx = trace.setSpan(otelContext.active(), span);
    try {
      return await otelContext.with(ctx, () => fn(wrapSpan(span)));
    } finally {
      span.end();
    }
  }

  logMessage(message: string, level: LogLevel, attrs?: Attributes): void {
    log.message(message, level, attrs ? { attributes: attrs } : undefined);
  }

  logException(error: Error, attrs?: Attributes): void {
    log.logException(error, { handled: true, attributes: attrs });
  }

  breadcrumb(name: string): void {
    session.addBreadcrumb(name);
  }

  async flush(): Promise<void> {
    // Ending the user session triggers a real export of buffered Embrace spans,
    // and flush() drains logs + the custom span exporter.
    try {
      session.endUserSession();
    } catch {
      /* no active session — ignore */
    }
    await this.control?.flush();
  }
}
