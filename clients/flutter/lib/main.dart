import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'demo_actions.dart';
import 'telemetry/device_context.dart';
import 'telemetry/embrace_telemetry_service.dart';
import 'telemetry/otel_telemetry_service.dart';
import 'telemetry/telemetry_config.dart';
import 'telemetry/telemetry_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final device = await DeviceContext.load();

  final TelemetryService telemetry = TelemetryConfig.isEmbrace
      ? EmbraceTelemetryService(device)
      : OtelTelemetryService(device);

  // The OTel arm must install its own uncaught-error handlers (the Embrace arm
  // does this inside start(action:)). We route Flutter framework errors to the
  // telemetry log and run the app in a guarded zone so the "crash" action's
  // unhandled error is exported before propagating.
  if (TelemetryConfig.isOtel) {
    runZonedGuarded(() async {
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        telemetry.log(
          details.exceptionAsString(),
          severity: LogSeverity.error,
          attributes: {
            'exception.type': details.exception.runtimeType.toString(),
            'exception.message': details.exceptionAsString(),
            if (details.stack != null)
              'exception.stacktrace': details.stack.toString(),
          },
        );
      };
      await telemetry.initialize(() async {
        runApp(DemoApp(telemetry: telemetry));
      });
    }, (Object error, StackTrace stack) {
      telemetry.recordCaughtError(error, stack);
      // Surface in console too.
      FlutterError.dumpErrorToConsole(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    });
  } else {
    await telemetry.initialize(() async {
      runApp(DemoApp(telemetry: telemetry));
    });
  }
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key, required this.telemetry});
  final TelemetryService telemetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Embrace/OTel Demo (Flutter)',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: DemoHomePage(actions: DemoActions(telemetry)),
    );
  }
}

class DemoHomePage extends StatefulWidget {
  const DemoHomePage({super.key, required this.actions});
  final DemoActions actions;

  @override
  State<DemoHomePage> createState() => _DemoHomePageState();
}

class _DemoHomePageState extends State<DemoHomePage> {
  final List<String> _log = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (TelemetryConfig.autofire.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autofire());
    }
  }

  Future<void> _autofire() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    final a = widget.actions;
    for (final step in TelemetryConfig.autofire.split(',')) {
      switch (step.trim()) {
        case 'delay':
          await _run('delay', a.delay);
        case 'workflow':
          await _run('workflow', a.workflow);
        case 'anr':
          await _run('anr', a.anr);
        case 'caught':
          await _run('caught', a.caughtError);
        case 'crash':
          await _run('crash', a.crash);
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    _append('autofire complete');
  }

  void _append(String line) {
    if (!mounted) return;
    setState(() => _log.insert(
        0, '${DateTime.now().toIso8601String().substring(11, 19)}  $line'));
  }

  Future<void> _run(String label, Future<void> Function() body) async {
    if (_busy) return;
    setState(() => _busy = true);
    _append('-> $label');
    try {
      await body();
      _append('   done: $label');
    } catch (e) {
      _append('   error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.actions;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Embrace/OTel Flutter Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('service.name: ${TelemetryConfig.serviceName}'),
                    Text('telemetry.tool: ${a.toolLabel}'),
                    Text('collector: ${TelemetryConfig.otlpHttpBase}'),
                    Text('exporting (native started): ${a.isExporting}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ActionButton(
                  label: 'delay',
                  icon: Icons.timer,
                  onTap: _busy ? null : () => _run('delay', a.delay),
                ),
                _ActionButton(
                  label: 'workflow',
                  icon: Icons.account_tree,
                  onTap: _busy ? null : () => _run('workflow', a.workflow),
                ),
                _ActionButton(
                  label: 'ANR (6s hang)',
                  icon: Icons.hourglass_bottom,
                  onTap: _busy ? null : () => _run('anr', a.anr),
                ),
                _ActionButton(
                  label: 'caught error',
                  icon: Icons.report_problem,
                  onTap: _busy ? null : () => _run('caught', a.caughtError),
                ),
                _ActionButton(
                  label: 'CRASH',
                  icon: Icons.dangerous,
                  color: Colors.red,
                  onTap: _busy ? null : () => _run('crash', a.crash),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Activity log',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _log.length,
                itemBuilder: (_, i) => Text(
                  _log[i],
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
            if (kDebugMode)
              const Text(
                'Build with --dart-define=TELEMETRY_TOOL=embrace|otel',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.color,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
      style:
          color != null ? FilledButton.styleFrom(backgroundColor: color) : null,
    );
  }
}
