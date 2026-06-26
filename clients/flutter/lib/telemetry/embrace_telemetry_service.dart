import 'dart:io';

import 'package:embrace/embrace.dart';
import 'package:embrace/embrace_api.dart';
import 'package:embrace_platform_interface/embrace_platform_interface.dart'
    show ErrorCode;

import 'device_context.dart';
import 'telemetry_config.dart';
import 'telemetry_service.dart';

/// Embrace Flutter SDK arm (telemetry.tool=embrace).
///
/// E1 / iOS gotcha baked in here: the iOS Flutter plugin's addSpanExporter /
/// addLogRecordExporter are NO-OPS (the native EmbraceIO 6.x SDK only accepts
/// exporters at `Embrace.setup` time, in AppDelegate). On Android those Dart
/// calls do wire the OTLP exporter. So whether telemetry actually reaches our
/// collector from this arm depends on the native config — we still register the
/// exporters from Dart (harmless, and correct on Android) and record the
/// session id to prove whether the native SDK started.
class EmbraceTelemetryService implements TelemetryService {
  EmbraceTelemetryService(this._device);

  final DeviceContext _device;
  bool _started = false;

  @override
  String get tool => 'embrace';

  @override
  bool get isExporting => _started;

  @override
  Future<void> initialize(Future<void> Function() appRunner) async {
    // Register OTLP exporters BEFORE start() (required ordering per the SDK).
    // No headers / no api-key: this is the no-account export path to our
    // self-hosted collector. On iOS these are no-ops (see class doc); the real
    // export is wired natively in AppDelegate.swift via OpenTelemetryExport.
    Embrace.instance.addSpanExporter(endpoint: TelemetryConfig.otlpTracesEndpoint);
    Embrace.instance
        .addLogRecordExporter(endpoint: TelemetryConfig.otlpLogsEndpoint);

    // start(action:) wraps the app in a guarded zone so uncaught Dart errors
    // (the "crash" action) are captured automatically.
    await Embrace.instance.start(action: () async {
      await _afterStart();
      await appRunner();
    });
  }

  Future<void> _afterStart() async {
    await setUser(TelemetryConfig.demoUserId);
    // getCurrentSessionId returns null if the native SDK never started
    // (e.g. iOS AppDelegate not configured) -> our isExporting signal.
    final sessionId = await Embrace.instance.getCurrentSessionId();
    _started = sessionId != null;
    // Stamp the common resource attrs Embrace doesn't set itself, as session
    // properties so they ride along on the session + are queryable.
    final common = commonResourceAttributes(_device, tool);
    common.forEach((k, v) {
      // Embrace session property keys can't contain dots in some backends, but
      // the OTLP exporter passes them through; keep the contract keys.
      Embrace.instance.addSessionProperty(k, v);
    });
  }

  @override
  Future<TelemetrySpan> startSpan(
    String name, {
    TelemetrySpan? parent,
    String? actionName,
    Map<String, String>? attributes,
  }) async {
    final parentSpan = parent is _EmbraceSpan ? parent.span : null;
    final span = await Embrace.instance.startSpan(name, parent: parentSpan);
    final wrapped = _EmbraceSpan(span);
    if (actionName != null) {
      await wrapped.setAttribute(Attr.actionName, actionName);
    }
    if (attributes != null) {
      for (final e in attributes.entries) {
        await wrapped.setAttribute(e.key, e.value);
      }
    }
    return wrapped;
  }

  @override
  Future<void> log(
    String message, {
    LogSeverity severity = LogSeverity.info,
    Map<String, String>? attributes,
  }) async {
    final sev = switch (severity) {
      LogSeverity.info => Severity.info,
      LogSeverity.warning => Severity.warning,
      LogSeverity.error => Severity.error,
    };
    Embrace.instance.logMessage(message, sev, properties: attributes);
  }

  @override
  Future<void> addBreadcrumb(String message) async {
    Embrace.instance.addBreadcrumb(message);
  }

  @override
  Future<void> recordCaughtError(Object error, StackTrace stack) async {
    Embrace.instance.logHandledDartError(error, stack);
  }

  @override
  Future<void> setUser(String userId) async {
    Embrace.instance.setUserIdentifier(userId);
  }

  @override
  Future<void> flush() async {
    // Embrace batches natively; give the exporter a moment before a crash.
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }
}

class _EmbraceSpan implements TelemetrySpan {
  _EmbraceSpan(this.span);
  final EmbraceSpan? span;

  @override
  Future<void> setAttribute(String key, String value) async {
    await span?.addAttribute(key, value);
  }

  @override
  Future<void> addEvent(String name, {Map<String, String>? attributes}) async {
    await span?.addEvent(name, attributes: attributes);
  }

  @override
  Future<void> recordError(Object error, {StackTrace? stackTrace}) async {
    await span?.addAttribute(Attr.exceptionType, error.runtimeType.toString());
    await span?.addAttribute(Attr.exceptionMessage, error.toString());
    // Also surface as a handled error so it shows on the timeline.
    if (Platform.isIOS || Platform.isAndroid) {
      Embrace.instance
          .logHandledDartError(error, stackTrace ?? StackTrace.current);
    }
  }

  @override
  Future<void> end({bool errored = false}) async {
    // EmbraceSpan marks failure via stop(errorCode:) — there is no setStatus.
    await span?.stop(errorCode: errored ? ErrorCode.failure : null);
  }
}
