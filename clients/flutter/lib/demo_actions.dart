import 'dart:math';

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

  /// ACTION 1 — `delay`: a traced async action with an artificial delay (B2
  /// performance span).
  Future<void> delay() async {
    await _t.addBreadcrumb('tapped: delay');
    final span = await _t.startSpan('delay', actionName: 'delay');
    await _attachSystemSample(span);
    await span.addEvent('delay.start');
    final ms = 800 + _rng.nextInt(1200);
    await span.setAttribute('delay.ms', ms.toString());
    await Future<void>.delayed(Duration(milliseconds: ms));
    await span.addEvent('delay.end');
    await span.end();
    await _t.log('delay completed in ${ms}ms');
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

  String get toolLabel => _t.tool;
  bool get isExporting => _t.isExporting;
}
