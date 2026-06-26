import 'dart:convert';

import 'package:fixnum/fixnum.dart';
import 'package:http/http.dart' as http;
import 'package:opentelemetry/api.dart' as otel_api;
import 'package:opentelemetry/sdk.dart' as otel_sdk;

import 'device_context.dart';
import 'telemetry_config.dart';
import 'telemetry_service.dart';

/// Plain-OpenTelemetry arm (telemetry.tool=otel).
///
/// This is the F1 comparison baseline and the guaranteed Grafana path: it needs
/// no Embrace account and works on a simulator. Traces go through the workiva
/// `opentelemetry` SDK -> OTLP/HTTP. Logs are sent via a hand-rolled OTLP/HTTP
/// JSON POST because that package's logs pipeline is Unimplemented.
class OtelTelemetryService implements TelemetryService {
  OtelTelemetryService(this._device);

  final DeviceContext _device;
  late final otel_api.Tracer _tracer;
  late final List<otel_api.Attribute> _resourceAttrs;
  bool _exporting = false;

  @override
  String get tool => 'otel';

  @override
  bool get isExporting => _exporting;

  @override
  Future<void> initialize(Future<void> Function() appRunner) async {
    final common = commonResourceAttributes(_device, tool);
    _resourceAttrs = common.entries
        .map((e) => otel_api.Attribute.fromString(e.key, e.value))
        .toList();

    final exporter = otel_sdk.CollectorExporter(
      Uri.parse(TelemetryConfig.otlpTracesEndpoint),
    );
    final provider = otel_sdk.TracerProviderBase(
      processors: [otel_sdk.BatchSpanProcessor(exporter)],
      resource: otel_sdk.Resource(_resourceAttrs),
    );
    otel_api.registerGlobalTracerProvider(provider);
    _tracer = provider.getTracer('embrace-demo-flutter-otel');
    _exporting = true;

    await appRunner();
  }

  @override
  Future<TelemetrySpan> startSpan(
    String name, {
    TelemetrySpan? parent,
    String? actionName,
    Map<String, String>? attributes,
  }) async {
    final context = parent is _OtelSpan
        ? otel_api.contextWithSpan(otel_api.Context.current, parent.span)
        : otel_api.Context.current;

    final span = _tracer.startSpan(name, context: context);
    if (actionName != null) {
      span.setAttribute(otel_api.Attribute.fromString(Attr.actionName, actionName));
    }
    attributes?.forEach(
      (k, v) => span.setAttribute(otel_api.Attribute.fromString(k, v)),
    );
    return _OtelSpan(span);
  }

  @override
  Future<void> log(
    String message, {
    LogSeverity severity = LogSeverity.info,
    Map<String, String>? attributes,
  }) async {
    await _postLog(message, severity, attributes ?? const {});
  }

  @override
  Future<void> addBreadcrumb(String message) =>
      log('breadcrumb: $message', severity: LogSeverity.info, attributes: {
        'event.kind': 'breadcrumb',
      });

  @override
  Future<void> recordCaughtError(Object error, StackTrace stack) => log(
        error.toString(),
        severity: LogSeverity.error,
        attributes: {
          Attr.actionName: 'caught_error',
          Attr.exceptionType: error.runtimeType.toString(),
          Attr.exceptionMessage: error.toString(),
          'exception.stacktrace': stack.toString(),
        },
      );

  @override
  Future<void> setUser(String userId) async {
    // user.id is already a resource attribute; nothing extra to do for OTel.
  }

  @override
  Future<void> flush() async {
    // BatchSpanProcessor has no public sync flush; allow the batch timer to fire.
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  /// Minimal OTLP/HTTP logs payload (the SDK doesn't implement logs export).
  Future<void> _postLog(
    String body,
    LogSeverity severity,
    Map<String, String> attrs,
  ) async {
    final nowNanos = (Int64(DateTime.now().millisecondsSinceEpoch) * 1000000)
        .toString();
    final severityNumber = switch (severity) {
      LogSeverity.info => 9, // INFO
      LogSeverity.warning => 13, // WARN
      LogSeverity.error => 17, // ERROR
    };
    final common = commonResourceAttributes(_device, tool);

    Map<String, dynamic> kv(String k, String v) => {
          'key': k,
          'value': {'stringValue': v},
        };

    final payload = {
      'resourceLogs': [
        {
          'resource': {
            'attributes': common.entries.map((e) => kv(e.key, e.value)).toList(),
          },
          'scopeLogs': [
            {
              'scope': {'name': 'embrace-demo-flutter-otel'},
              'logRecords': [
                {
                  'timeUnixNano': nowNanos,
                  'severityNumber': severityNumber,
                  'severityText': severity.name.toUpperCase(),
                  'body': {'stringValue': body},
                  'attributes':
                      attrs.entries.map((e) => kv(e.key, e.value)).toList(),
                }
              ],
            }
          ],
        }
      ],
    };

    try {
      await http
          .post(
            Uri.parse(TelemetryConfig.otlpLogsEndpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Never let telemetry export break the app / demo.
    }
  }
}

class _OtelSpan implements TelemetrySpan {
  _OtelSpan(this.span);
  final otel_api.Span span;

  @override
  Future<void> setAttribute(String key, String value) async {
    span.setAttribute(otel_api.Attribute.fromString(key, value));
  }

  @override
  Future<void> addEvent(String name, {Map<String, String>? attributes}) async {
    final attrs = (attributes ?? const {})
        .entries
        .map((e) => otel_api.Attribute.fromString(e.key, e.value))
        .toList();
    span.addEvent(name, attributes: attrs);
  }

  @override
  Future<void> recordError(Object error, {StackTrace? stackTrace}) async {
    span.setStatus(otel_api.StatusCode.error, error.toString());
    span.setAttribute(
        otel_api.Attribute.fromString(Attr.exceptionType, error.runtimeType.toString()));
    span.setAttribute(
        otel_api.Attribute.fromString(Attr.exceptionMessage, error.toString()));
    span.recordException(error, stackTrace: stackTrace ?? StackTrace.current);
  }

  @override
  Future<void> end({bool errored = false}) async {
    span.end();
  }
}
