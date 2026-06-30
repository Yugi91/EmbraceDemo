import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'telemetry/device_context.dart';
import 'telemetry/telemetry_config.dart';
import 'telemetry/telemetry_service.dart';

/// The four demo actions, each emitting telemetry per SCHEMA_CONTRACT.
/// Pure logic — no Flutter imports — so the UI stays a thin shell.
class DemoActions {
  DemoActions(this._t);
  final TelemetryService _t;
  final _rng = Random();

  /// Attach the per-action `system.*` / `network.*` sample to a span.
  Future<void> _attachSystemSample(TelemetrySpan span) async {
    final s = SystemSample.take();
    await span.setAttribute(Attr.freeRamMb, s.freeRamMb.toString());
    await span.setAttribute(Attr.freeStorageMb, s.freeStorageMb.toString());
    await span.setAttribute(Attr.networkSpeedMbps, s.networkSpeedMbps.toString());
    await span.setAttribute(Attr.networkType, s.networkType);
  }

  /// ACTION 1 — `metric`: build a concurrent + nested span tree (B2 performance
  /// span), capturing real wall-clock durations.
  ///
  ///   metric            (ROOT)
  ///   ├── A             (child of metric; runs CONCURRENTLY with B)
  ///   │   ├── C         (child of A; SEQUENTIAL — first)
  ///   │   └── D         (child of A; SEQUENTIAL — after C)
  ///   └── B             (child of metric; CONCURRENT with A)
  ///
  /// A and B are awaited together (`Future.wait`) so their spans overlap; inside
  /// A, C then D run sequentially. Children nest via `startSpan(parent:)`, the
  /// same mechanism `workflow()` uses. `metric` ends after both A and B finish.
  Future<void> metric() async {
    await _t.addBreadcrumb('tapped: metric');
    final metric = await _t.startSpan('metric', actionName: 'metric');
    await _attachSystemSample(metric);
    await metric.setAttribute(Attr.actionName, 'metric');
    await metric.setAttribute('task.name', 'metric');
    await metric.addEvent('started');

    // A — child of metric; runs C then D sequentially.
    Future<void> runA() async {
      final sw = Stopwatch()..start();
      final a = await _t.startSpan('A', parent: metric);
      await a.setAttribute(Attr.actionName, 'metric');
      await a.setAttribute('task.name', 'A');
      await a.addEvent('A.start');

      // C — child of A; SEQUENTIAL, first.
      final cSw = Stopwatch()..start();
      final c = await _t.startSpan('C', parent: a);
      await c.setAttribute(Attr.actionName, 'metric');
      await c.setAttribute('task.name', 'C');
      await c.addEvent('C.start');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      cSw.stop();
      await c.setAttribute('work_ms', cSw.elapsedMilliseconds.toString());
      await c.addEvent('C.end');
      await c.end();

      // D — child of A; SEQUENTIAL, after C.
      final dSw = Stopwatch()..start();
      final d = await _t.startSpan('D', parent: a);
      await d.setAttribute(Attr.actionName, 'metric');
      await d.setAttribute('task.name', 'D');
      await d.addEvent('D.start');
      await Future<void>.delayed(const Duration(milliseconds: 90));
      dSw.stop();
      await d.setAttribute('work_ms', dSw.elapsedMilliseconds.toString());
      await d.addEvent('D.end');
      await d.end();

      sw.stop();
      await a.setAttribute('work_ms', sw.elapsedMilliseconds.toString());
      await a.addEvent('A.end');
      await a.end();
    }

    // B — child of metric; runs CONCURRENTLY with A.
    Future<void> runB() async {
      final sw = Stopwatch()..start();
      final b = await _t.startSpan('B', parent: metric);
      await b.setAttribute(Attr.actionName, 'metric');
      await b.setAttribute('task.name', 'B');
      await b.addEvent('B.start');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      sw.stop();
      await b.setAttribute('work_ms', sw.elapsedMilliseconds.toString());
      await b.addEvent('B.end');
      await b.end();
    }

    final rootSw = Stopwatch()..start();
    // Single-isolate concurrency: A and B interleave on the event loop, so their
    // spans overlap on the timeline (metric ~= max(A, B)).
    await Future.wait([runA(), runB()]);
    rootSw.stop();
    await metric.setAttribute('work_ms', rootSw.elapsedMilliseconds.toString());
    await metric.addEvent('completed');
    await metric.end();
    await _t.log('metric perf tree done (A‖B, A→C→D)');
  }

  /// ACTION 2 — `crash`: an UNHANDLED Dart error (B1). Thrown off a microtask
  /// so it escapes the button callback and becomes a true unhandled error that
  /// the guarded zone (Embrace) / zone handler (OTel) reports.
  Future<void> crash() async {
    await _t.addBreadcrumb('tapped: crash');
    await _t.log(
      'about to crash (unhandled)',
      severity: LogSeverity.warning,
      attributes: {Attr.actionName: 'crash'},
    );
    await _t.flush(); // give the exporter a chance before the process dies
    Future<void>(() {
      throw StateError(
        'EmbraceGrafanaDemo intentional unhandled crash (action.name=crash)',
      );
    });
  }

  /// ACTION 3 — `anr`: block the UI isolate long enough to register as an
  /// app-hang / ANR (E3). 6s busy-loop on the main isolate.
  Future<void> anr() async {
    await _t.addBreadcrumb('tapped: anr');
    final span = await _t.startSpan('anr', actionName: 'anr');
    await _attachSystemSample(span);
    await span.addEvent('anr.block.start');
    // Synchronous busy-wait blocks the platform thread -> app hang.
    final stop = DateTime.now().add(const Duration(seconds: 6));
    var x = 0.0;
    while (DateTime.now().isBefore(stop)) {
      x += sqrt(_rng.nextDouble() * 1e6);
    }
    await span.setAttribute('anr.block_ms', '6000');
    await span.setAttribute('anr.sink', x.toStringAsFixed(0));
    await span.addEvent('anr.block.end');
    await span.end();
    await _t.log('anr block released (6s)');
  }

  /// ACTION 4 — `workflow`: parent span + capture->save->sync child spans with
  /// timestamped events. `sync` randomly fails -> child span ERROR + exception
  /// attrs (B4 custom-event shape, per SCHEMA_CONTRACT workflow diagram).
  Future<void> workflow() async {
    await _t.addBreadcrumb('tapped: workflow');
    final parent = await _t.startSpan('workflow', actionName: 'workflow');
    await _attachSystemSample(parent);
    await parent.addEvent('started');

    // capture
    final capture = await _t.startSpan('capture', parent: parent);
    final bytes = 1024 + _rng.nextInt(4096);
    await capture.setAttribute(Attr.stepName, 'capture');
    await capture.setAttribute(Attr.stepStatus, 'ok');
    await capture.setAttribute(Attr.stepData, '$bytes');
    await capture.addEvent('captured', attributes: {'bytes': '$bytes'});
    await capture.end();

    // save
    final save = await _t.startSpan('save', parent: parent);
    const path = '/tmp/demo/capture.bin';
    await save.setAttribute(Attr.stepName, 'save');
    await save.setAttribute(Attr.stepStatus, 'ok');
    await save.setAttribute(Attr.stepData, path);
    await save.addEvent('saved', attributes: {'path': path});
    await save.end();

    // sync — sometimes fails (~50%)
    final sync = await _t.startSpan('sync', parent: parent);
    const endpoint = 'https://api.example.test/sync';
    await sync.setAttribute(Attr.stepName, 'sync');
    await sync.setAttribute('endpoint', endpoint);
    final failed = _rng.nextBool();
    if (failed) {
      await sync.setAttribute('http.status', '503');
      await sync.setAttribute(Attr.stepStatus, 'failure');
      final err = Exception('sync failed: HTTP 503 from $endpoint');
      await sync.addEvent('failed', attributes: {'http.status': '503'});
      await sync.recordError(err, stackTrace: StackTrace.current);
      await sync.end(errored: true);
      await parent.addEvent('sync_failed');
      await parent.end(errored: true);
      await _t.log('workflow failed at sync (HTTP 503)',
          severity: LogSeverity.error);
    } else {
      await sync.setAttribute('http.status', '200');
      await sync.setAttribute(Attr.stepStatus, 'ok');
      await sync.addEvent('synced', attributes: {'http.status': '200'});
      await sync.end();
      await parent.addEvent('completed');
      await parent.end();
      await _t.log('workflow completed ok');
    }
  }

  /// Helper used by the UI's "caught error" demo (B1 handled variant / E7 feed).
  Future<void> caughtError() async {
    await _t.addBreadcrumb('tapped: caught_error');
    try {
      throw ArgumentError('demo handled exception (action.name=caught_error)');
    } catch (e, st) {
      await _t.recordCaughtError(e, st);
      await _t.log('caught & reported handled error',
          severity: LogSeverity.warning,
          attributes: {Attr.actionName: 'caught_error'});
    }
  }

  /// ACTION 5 — `network` [LEVEL 2]: a REAL HTTP GET. The Embrace SDK
  /// auto-captures outbound requests, so this external call surfaces in
  /// Embrace's Network view under jsonplaceholder.typicode.com. We also wrap it
  /// in a custom span carrying the http.* attrs for parity with the OTel arm.
  Future<void> network() async {
    await _t.addBreadcrumb('tapped: network');
    const url = 'https://jsonplaceholder.typicode.com/todos/1';
    final span = await _t.startSpan('network', actionName: 'network');
    await _attachSystemSample(span);
    await span.setAttribute('http.url', url);
    await span.setAttribute('http.method', 'GET');
    await span.addEvent('network.start');
    try {
      final res = await http.get(Uri.parse(url));
      await span.setAttribute('http.status_code', '${res.statusCode}');
      await span.addEvent('network.end',
          attributes: {'http.status_code': '${res.statusCode}'});
      await span.end();
      await _t.log('network GET $url -> ${res.statusCode}');
    } catch (e, st) {
      await span.recordError(e, stackTrace: st);
      await span.addEvent('network.failed');
      await span.end(errored: true);
      await _t.log('network GET $url failed: $e',
          severity: LogSeverity.error, attributes: {Attr.actionName: 'network'});
    }
  }

  /// ACTION 6 — `oom` [LEVEL 3]: allocate memory in an unbounded loop until the
  /// OS memory-kills the process. We retain references to ever-growing 8 MiB
  /// blocks so nothing is collected. This WILL terminate the app (intended).
  Future<void> oom() async {
    await _t.addBreadcrumb('tapped: oom');
    await _t.log('oom: allocating until killed',
        severity: LogSeverity.warning,
        attributes: {Attr.actionName: 'oom'});
    await _t.flush(); // give the exporter a chance before the process dies
    final blocks = <Uint8List>[];
    while (true) {
      blocks.add(Uint8List(8 * 1024 * 1024)); // 8 MiB, retained
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  String get toolLabel => _t.tool;
  bool get isExporting => _t.isExporting;
}
