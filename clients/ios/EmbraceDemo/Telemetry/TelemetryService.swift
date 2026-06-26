import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import EmbraceIO

/// Log severity, mapped to OTel SeverityNumber / Embrace LogSeverity per arm.
enum DemoSeverity {
  case info, warning, error
}

/// A handle to an in-flight span. Arm-specific; the UI never touches the concrete
/// type. Both arms wrap an OpenTelemetry `Span` (Embrace's tracer also returns one).
final class TelemetrySpan {
  let span: Span
  init(_ span: Span) { self.span = span }

  func setAttribute(_ key: String, _ value: String) {
    span.setAttribute(key: key, value: .string(value))
  }

  func addEvent(_ name: String, attributes: [String: String] = [:]) {
    let attrs = attributes.mapValues { AttributeValue.string($0) }
    span.addEvent(name: name, attributes: attrs, timestamp: Date())
  }

  /// Mark this span as failed: status=ERROR + exception.* attributes (SCHEMA_CONTRACT).
  func recordError(_ error: Error) {
    span.status = .error(description: "\(error)")
    span.setAttribute(key: Attr.exceptionType, value: .string(String(describing: type(of: error))))
    span.setAttribute(key: Attr.exceptionMessage, value: .string("\(error)"))
  }

  func end(errored: Bool = false) {
    if errored, case .unset = span.status {
      span.status = .error(description: "span ended in error state")
    }
    span.end()
  }
}

/// The single telemetry seam the UI + demo logic depend on. Two implementations:
///   * EmbraceTelemetryService  (telemetry.tool = embrace)
///   * OtelTelemetryService     (telemetry.tool = otel)
protocol TelemetryService: AnyObject {
  /// telemetry.tool value this arm stamps on every signal.
  var tool: String { get }

  /// Whether telemetry is actually flowing to the collector.
  var isExporting: Bool { get }

  /// Set up the SDK + wire OTLP export. Called once, very early, from the App init.
  func bootstrap()

  func startSpan(_ name: String, parent: TelemetrySpan?, actionName: String?) -> TelemetrySpan

  func log(_ message: String, severity: DemoSeverity, attributes: [String: String])

  /// Session/user timeline breadcrumb (B3).
  func addBreadcrumb(_ message: String)

  /// Report a handled/caught error (action.name=caught_error) — E7 feed.
  func recordCaughtError(_ error: Error)

  /// Best-effort flush before the process may die (used right before crash).
  func flush()
}

extension TelemetryService {
  func startSpan(_ name: String, parent: TelemetrySpan? = nil, actionName: String? = nil)
    -> TelemetrySpan
  { startSpan(name, parent: parent, actionName: actionName) }

  func log(_ message: String, severity: DemoSeverity = .info, attributes: [String: String] = [:]) {
    log(message, severity: severity, attributes: attributes)
  }
}

// MARK: - Embrace arm (telemetry.tool=embrace)

/// EmbraceIO 6.20.0 no-account / OTLP-only arm.
///
/// E1: appId-less init — `Embrace.Options(export: OpenTelemetryExport(...))` is valid
/// only because a custom exporter is supplied (validation throws only if BOTH appId
/// and export are nil). Spans go through Embrace's own OTel `Tracer`; logs through
/// `Embrace.client?.log(...)`. Embrace overrides service.name → the bundle id and
/// emits its own emb.* resource schema, dropping our contract attrs (documented).
final class EmbraceTelemetryService: TelemetryService {
  let tool = "embrace"
  private(set) var isExporting = false
  private var tracer: Tracer?

  func bootstrap() {
    let export = OpenTelemetryExport(
      spanExporter: OtlpJsonSpanExporter(),
      logExporter: OtlpJsonLogExporter()
    )
    do {
      // SCHEMA_CONTRACT self-tracing-loop guard: our OTLP export POSTs to
      // localhost:4318 via URLSession, which Embrace's URLSessionCaptureService
      // would auto-instrument -> infinite span loop. Swap URLSession for one that
      // ignores the collector URL.
      let captureServices = CaptureServiceBuilder()
        .addDefaults()
        .remove(ofType: URLSessionCaptureService.self)
        .add(
          .urlSession(
            options: URLSessionCaptureService.Options(
              ignoredURLs: ["localhost:4318", "127.0.0.1:4318"])))
        .build()

      // appId-less designated initializer — valid only with a custom export.
      // platform: .default for a native iOS app. KSCrash gives crash + app-hang
      // capture (E2/E3).
      let options = Embrace.Options(
        export: export,
        platform: .default,
        captureServices: captureServices,
        crashReporter: KSCrashReporter()
      )
      try Embrace.setup(options: options).start()
      Embrace.client?.metadata.userIdentifier = TelemetryConfig.demoUserId
      tracer = Embrace.client?.tracer(instrumentationName: "embrace-demo-ios")
      isExporting = Embrace.client != nil
      NSLog("EMBRACE-DEMO: native setup OK (no-account, custom OTLP export), exporting=\(isExporting)")
    } catch {
      NSLog("EMBRACE-DEMO: native setup FAILED: \(error)")
    }
  }

  func startSpan(_ name: String, parent: TelemetrySpan?, actionName: String?) -> TelemetrySpan {
    // If Embrace never started, fall back to a no-op span via a detached tracer.
    let builder = tracer?.spanBuilder(spanName: name)
      ?? OpenTelemetry.instance.tracerProvider
      .get(instrumentationName: "embrace-demo-ios-fallback", instrumentationVersion: nil)
      .spanBuilder(spanName: name)
    if let parent = parent { builder.setParent(parent.span) }
    let span = builder.startSpan()
    if let actionName = actionName {
      span.setAttribute(key: Attr.actionName, value: .string(actionName))
    }
    return TelemetrySpan(span)
  }

  func log(_ message: String, severity: DemoSeverity, attributes: [String: String]) {
    let sev: LogSeverity
    switch severity {
    case .info: sev = .info
    case .warning: sev = .warn
    case .error: sev = .error
    }
    Embrace.client?.log(message, severity: sev, attributes: attributes)
  }

  func addBreadcrumb(_ message: String) {
    Embrace.client?.add(event: .breadcrumb(message))
  }

  func recordCaughtError(_ error: Error) {
    // E7: a handled exception captured via the SDK's error-severity log path,
    // carrying a stack trace + the same exception.* attrs as the unhandled path.
    Embrace.client?.log(
      "\(error)",
      severity: .error,
      attributes: [
        Attr.actionName: "caught_error",
        Attr.exceptionType: String(describing: type(of: error)),
        Attr.exceptionMessage: "\(error)",
        "exception.handled": "true",
      ],
      stackTraceBehavior: .default
    )
  }

  func flush() {
    // Embrace batches natively; give the exporter a moment before a crash.
    Thread.sleep(forTimeInterval: 0.6)
  }
}

// MARK: - Plain-OTel arm (telemetry.tool=otel) — the F1 baseline

/// Plain OpenTelemetry-Swift arm. No Embrace account, no native crash handler — the
/// guaranteed Grafana path that honors ALL SCHEMA_CONTRACT keys exactly. Traces via
/// a `TracerProviderSdk` + `BatchSpanProcessor`; logs via a `LoggerProviderSdk` +
/// `BatchLogRecordProcessor` (the Swift OTel SDK fully implements logs). Both feed
/// the SAME hand-rolled OTLP/JSON exporter used by the Embrace arm.
final class OtelTelemetryService: TelemetryService {
  let tool = "otel"
  private(set) var isExporting = false
  private var tracer: Tracer?
  private var logger: Logger?
  // Hold the concrete provider/processor so flush() can force a sync export
  // (the `TracerProvider`/`LoggerProvider` protocols don't expose forceFlush).
  private var tracerProvider: TracerProviderSdk?
  private var logProcessor: BatchLogRecordProcessor?

  func bootstrap() {
    let common = DeviceContext.current.commonResourceAttributes(tool: tool)
    let resource = Resource(attributes: common.mapValues { AttributeValue.string($0) })

    let tracerProvider = TracerProviderBuilder()
      .with(resource: resource)
      .add(spanProcessor: BatchSpanProcessor(spanExporter: OtlpJsonSpanExporter()))
      .build()
    self.tracerProvider = tracerProvider
    OpenTelemetry.registerTracerProvider(tracerProvider: tracerProvider)

    let logProcessor = BatchLogRecordProcessor(logRecordExporter: OtlpJsonLogExporter())
    self.logProcessor = logProcessor
    let loggerProvider = LoggerProviderBuilder()
      .with(resource: resource)
      .with(processors: [logProcessor])
      .build()
    OpenTelemetry.registerLoggerProvider(loggerProvider: loggerProvider)

    tracer = tracerProvider.get(
      instrumentationName: "embrace-demo-ios-otel", instrumentationVersion: "1.0.0")
    logger = loggerProvider.loggerBuilder(instrumentationScopeName: "embrace-demo-ios-otel")
      .setIncludeTraceContext(true)
      .build()
    isExporting = true
    NSLog("EMBRACE-DEMO: OTel arm setup OK (service.name=\(TelemetryConfig.serviceName))")
  }

  func startSpan(_ name: String, parent: TelemetrySpan?, actionName: String?) -> TelemetrySpan {
    let builder = tracer!.spanBuilder(spanName: name)
    if let parent = parent { builder.setParent(parent.span) }
    let span = builder.startSpan()
    if let actionName = actionName {
      span.setAttribute(key: Attr.actionName, value: .string(actionName))
    }
    return TelemetrySpan(span)
  }

  func log(_ message: String, severity: DemoSeverity, attributes: [String: String]) {
    let sev: Severity
    switch severity {
    case .info: sev = .info
    case .warning: sev = .warn
    case .error: sev = .error
    }
    logger?.logRecordBuilder()
      .setBody(.string(message))
      .setSeverity(sev)
      .setTimestamp(Date())
      .setAttributes(attributes.mapValues { AttributeValue.string($0) })
      .emit()
  }

  func addBreadcrumb(_ message: String) {
    log("breadcrumb: \(message)", severity: .info, attributes: ["event.kind": "breadcrumb"])
  }

  func recordCaughtError(_ error: Error) {
    log(
      "\(error)",
      severity: .error,
      attributes: [
        Attr.actionName: "caught_error",
        Attr.exceptionType: String(describing: type(of: error)),
        Attr.exceptionMessage: "\(error)",
        "exception.handled": "true",
      ])
  }

  func flush() {
    tracerProvider?.forceFlush()
    _ = logProcessor?.forceFlush()
    Thread.sleep(forTimeInterval: 0.4)
  }
}
