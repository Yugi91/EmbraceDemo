import type { Attributes, TimeInput } from '@opentelemetry/api';
import type { TelemetryTool } from './schema';

/**
 * Provider-agnostic span handle. Both the Embrace arm and the plain-OTel arm
 * return objects that satisfy this, so the UI/service layer never imports an SDK directly.
 */
export interface DemoSpan {
  setAttributes(attrs: Attributes): void;
  addEvent(name: string, attrs?: Attributes, timestamp?: TimeInput): void;
  /** Mark the span failed: status ERROR + record the exception attributes. */
  fail(error: Error, attrs?: Attributes): void;
  end(): void;
  /** Run `fn` as a child span named `name`, parented to this span. */
  child<T>(name: string, attrs: Attributes, fn: (span: DemoSpan) => Promise<T> | T): Promise<T>;
}

/** Severity levels accepted by log.message (mirrors Embrace's LogSeverity). */
export type LogLevel = 'info' | 'warning' | 'error';

/**
 * The capability surface the app needs. Implemented by EmbraceProvider and OtelProvider.
 * Keeping it minimal (start span / log / breadcrumb / flush) is enough for the 4 demo
 * actions and the B1–B4 baseline captures.
 */
export interface TelemetryProvider {
  readonly tool: TelemetryTool;
  /** True once init succeeded; false means init threw (recorded as the E8 verdict). */
  readonly ready: boolean;
  /** The error thrown during init, if any (E8 evidence). */
  readonly initError?: unknown;

  /** Start a root span, run `fn`, end it. Errors propagate after the span is failed+ended. */
  startActiveSpan<T>(
    name: string,
    attrs: Attributes,
    fn: (span: DemoSpan) => Promise<T> | T
  ): Promise<T>;

  /** Emit a standalone log record. */
  logMessage(message: string, level: LogLevel, attrs?: Attributes): void;

  /** Emit a handled-exception log record (E7). */
  logException(error: Error, attrs?: Attributes): void;

  /** Add a session/user-journey breadcrumb (B3). */
  breadcrumb(name: string): void;

  /** Force-flush exporters (used by the headless verifier before exit). */
  flush(): Promise<void>;
}
