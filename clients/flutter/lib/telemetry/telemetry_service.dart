import 'device_context.dart';

/// Severity for log records (maps to OTel SeverityNumber / Embrace Severity).
enum LogSeverity { info, warning, error }

/// A handle to an in-flight span. Arm-specific; the UI never touches the
/// concrete type. `data` on workflow steps rides as `step.data`.
abstract class TelemetrySpan {
  /// Add/overwrite a string attribute.
  Future<void> setAttribute(String key, String value);

  /// Record a timestamped event (workflow "started"/"captured"/"synced"...).
  Future<void> addEvent(String name, {Map<String, String>? attributes});

  /// Mark this span as failed: sets status=ERROR + exception.* attributes.
  Future<void> recordError(Object error, {StackTrace? stackTrace});

  /// End the span. If [errored] the span is closed in an error state.
  Future<void> end({bool errored = false});
}

/// The single telemetry seam the UI depends on. Two implementations:
///   * EmbraceTelemetryService  (telemetry.tool = embrace)
///   * OtelTelemetryService     (telemetry.tool = otel)
abstract class TelemetryService {
  /// telemetry.tool value this arm stamps on every signal.
  String get tool;

  /// Whether telemetry is actually flowing to the collector. (E1: the Embrace
  /// arm reports false on iOS when the native SDK was not set up — the Dart
  /// exporter calls are no-ops there.)
  bool get isExporting;

  /// Initialise the SDK + wire OTLP export to the collector, then run [appRunner]
  /// (inside a guarded zone for the Embrace arm so uncaught Dart errors are
  /// captured). Must be called from main().
  Future<void> initialize(Future<void> Function() appRunner);

  /// Start a span. Pass [parent] to build the workflow parent/child tree.
  Future<TelemetrySpan> startSpan(
    String name, {
    TelemetrySpan? parent,
    String? actionName,
    Map<String, String>? attributes,
  });

  /// Emit a log record (B3 breadcrumb-ish + caught errors).
  Future<void> log(
    String message, {
    LogSeverity severity = LogSeverity.info,
    Map<String, String>? attributes,
  });

  /// Session/user timeline breadcrumb (B3).
  Future<void> addBreadcrumb(String message);

  /// Report a handled/caught error (action.name=caught_error).
  Future<void> recordCaughtError(Object error, StackTrace stack);

  /// Set the fixed demo user id (user.id).
  Future<void> setUser(String userId);

  /// Best-effort flush before the process may die (used right before crash).
  Future<void> flush();
}

/// The SCHEMA_CONTRACT common resource attributes as a plain map, shared by
/// both arms so they stamp identical keys/values.
Map<String, String> commonResourceAttributes(
  DeviceContext device,
  String tool,
) {
  return {
    'service.name': 'embrace-demo-flutter',
    'telemetry.tool': tool,
    'user.id': 'demo-user-001',
    'device.model': device.deviceModel,
    'device.manufacturer': device.deviceManufacturer,
    'app.version': device.appVersion,
    'os.version': device.osVersion,
  };
}
