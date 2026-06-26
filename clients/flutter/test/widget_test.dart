// Smoke test for the Embrace/OTel Flutter demo.
//
// The real app boots a telemetry SDK in main() and reads device info via
// platform channels. Pure `flutter test` has no platform, so we mock the
// device_info/package_info channels, then verify the demo home page renders its
// action buttons against the OTel service. This keeps `flutter test` green
// without a simulator, the native SDK, or a live collector.

import 'package:embrace_demo_flutter/demo_actions.dart';
import 'package:embrace_demo_flutter/main.dart';
import 'package:embrace_demo_flutter/telemetry/device_context.dart';
import 'package:embrace_demo_flutter/telemetry/otel_telemetry_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    // device_info_plus
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/device_info'),
      (call) async => <String, dynamic>{
        'systemName': 'iOS',
        'systemVersion': '17.4',
        'utsname': <String, dynamic>{'machine': 'iPhone15,2'},
      },
    );

    // package_info_plus
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/package_info'),
      (call) async => <String, dynamic>{
        'appName': 'Embrace Demo Flutter',
        'packageName': 'io.embrace.demo.embraceDemoFlutter',
        'version': '1.0.0',
        'buildNumber': '1',
      },
    );
  });

  testWidgets('demo home renders action buttons', (WidgetTester tester) async {
    await DeviceContext.load();
    final service = OtelTelemetryService(DeviceContext.current);
    final actions = DemoActions(service);

    await tester.pumpWidget(MaterialApp(home: DemoHomePage(actions: actions)));

    expect(find.text('delay'), findsOneWidget);
    expect(find.text('workflow'), findsOneWidget);
    expect(find.text('CRASH'), findsOneWidget);
  });
}
