import {
  context as otelContext,
  trace as otelTrace,
  SpanStatusCode,
  type Attributes,
  type Span,
  type TimeInput,
  type Tracer,
} from '@opentelemetry/api';
import { logs, SeverityNumber, type Logger } from '@opentelemetry/api-logs';
import { resourceFromAttributes } from '@opentelemetry/resources';
import {
  WebTracerProvider,
  BatchSpanProcessor,
  StackContextManager,
} from '@opentelemetry/sdk-trace-web';
import { LoggerProvider, BatchLogRecordProcessor } from '@opentelemetry/sdk-logs';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { OTLPLogExporter } from '@opentelemetry/exporter-logs-otlp-http';

import {
  ATTR,
  commonResourceAttributes,
  OTLP_LOGS_URL,
  OTLP_TRACES_URL,
} from './schema';
import type { DemoSpan, LogLevel, TelemetryProvider } from './telemetry.types';

const LEVEL_TO_SEVERITY: Record<LogLevel, { number: SeverityNumber; text: string }> = {
  info: { number: SeverityNumber.INFO, text: 'INFO' },
  warning: { number: SeverityNumber.WARN, text: 'WARN' },
  error: { number: SeverityNumber.ERROR, text: 'ERROR' },
};

/**
 * Plain-OpenTelemetry arm (F1 comparison). Same schema, same collector, telemetry.tool=otel.
 * This is the "bare OTel" baseline we compare Embrace against for the Grafana path.
 * Unlike Embrace there is no built-in unhandled-error / Web-Vitals / session capture, so we
 * wire a minimal global error handler here to keep B1 parity; B2/B3 are intentionally absent
 * (that gap IS the F1b finding).
 */
export class OtelProvider implements TelemetryProvider {
  readonly tool = 'otel' as const;
  ready = false;
  initError?: unknown;

  private tracer!: Tracer;
  private logger!: Logger;
  private tracerProvider!: WebTracerProvider;
  private loggerProvider!: LoggerProvider;

  init(): void {
    try {
      const resource = resourceFromAttributes(commonResourceAttributes('otel'));

      this.tracerProvider = new WebTracerProvider({
        resource,
        spanProcessors: [
          new BatchSpanProcessor(new OTLPTraceExporter({ url: OTLP_TRACES_URL })),
        ],
      });
      this.tracerProvider.register({ contextManager: new StackContextManager() });

      this.loggerProvider = new LoggerProvider({
        resource,
        processors: [
          new BatchLogRecordProcessor(new OTLPLogExporter({ url: OTLP_LOGS_URL })),
        ],
      });
      logs.setGlobalLoggerProvider(this.loggerProvider);

      this.tracer = otelTrace.getTracer('embrace-demo-web-otel');
      this.logger = logs.getLogger('embrace-demo-web-otel');

      this.installGlobalErrorHandlers();
      this.ready = true;
    } catch (err) {
      this.initError = err;
      this.ready = false;
      console.error('[OtelProvider] init failed:', err);
    }
  }

  /** B1 parity for the bare-OTel arm: capture unhandled errors as ERROR logs. */
  private installGlobalErrorHandlers(): void {
    window.addEventListener('error', (ev) => {
      const err = ev.error instanceof Error ? ev.error : new Error(ev.message);
      this.emitExceptionLog(err, { handled: false });
    });
    window.addEventListener('unhandledrejection', (ev) => {
      const reason = ev.reason;
      const err = reason instanceof Error ? reason : new Error(String(reason));
      this.emitExceptionLog(err, { handled: false });
    });
  }

  private emitExceptionLog(error: Error, extra: Attributes): void {
    this.logger.emit({
      severityNumber: SeverityNumber.ERROR,
      severityText: 'ERROR',
      body: error.message,
      attributes: {
        [ATTR.EXCEPTION_TYPE]: error.name,
        [ATTR.EXCEPTION_MESSAGE]: error.message,
        'exception.stacktrace': error.stack ?? '',
        ...extra,
      },
    });
  }

  private wrap(span: Span): DemoSpan {
    const self = this;
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
        const parentCtx = otelTrace.setSpan(otelContext.active(), span);
        return self.tracer.startActiveSpan(
          name,
          { attributes: attrs },
          parentCtx,
          async (childSpan) => {
            try {
              const result = await fn(self.wrap(childSpan));
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
          }
        );
      },
    };
  }

  async startActiveSpan<T>(
    name: string,
    attrs: Attributes,
    fn: (span: DemoSpan) => Promise<T> | T
  ): Promise<T> {
    return this.tracer.startActiveSpan(name, { attributes: attrs }, async (span) => {
      try {
        return await fn(this.wrap(span));
      } finally {
        span.end();
      }
    });
  }

  logMessage(message: string, level: LogLevel, attrs?: Attributes): void {
    const sev = LEVEL_TO_SEVERITY[level];
    this.logger.emit({
      severityNumber: sev.number,
      severityText: sev.text,
      body: message,
      attributes: attrs,
    });
  }

  logException(error: Error, attrs?: Attributes): void {
    this.emitExceptionLog(error, { handled: true, ...(attrs ?? {}) });
  }

  breadcrumb(name: string): void {
    // No native session timeline in bare OTel; emit an INFO log as the closest analogue.
    this.logMessage(`breadcrumb: ${name}`, 'info', { 'breadcrumb.name': name });
  }

  async flush(): Promise<void> {
    await this.tracerProvider.forceFlush();
    await this.loggerProvider.forceFlush();
  }
}
