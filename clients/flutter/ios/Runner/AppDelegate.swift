import Flutter
import UIKit
import EmbraceIO

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // E1 spike — Embrace no-account OTLP init.
    //
    // The iOS Flutter plugin's Dart-side addSpanExporter()/addLogRecordExporter()
    // are NO-OPS (the native SDK only accepts exporters at setup). So to make the
    // Embrace arm export to our self-hosted collector WITHOUT an Embrace account,
    // we set up the native EmbraceIO SDK here using the appId-less initializer
    //   Embrace.Options(export: OpenTelemetryExport(...))
    // which is only valid when a custom OpenTelemetryExport is supplied.
    //
    // Gated on a launch env var so the plain-OTel arm stays clean:
    //   xcrun simctl launch --setenv EMBRACE_ENABLED=1 ...
    if ProcessInfo.processInfo.environment["EMBRACE_ENABLED"] == "1" {
      let export = OpenTelemetryExport(
        spanExporter: OtlpJsonSpanExporter(),
        logExporter: OtlpJsonLogExporter()
      )
      do {
        // SCHEMA_CONTRACT self-tracing-loop guard: our OTLP export POSTs to
        // localhost:4318 via URLSession, which Embrace's URLSessionCaptureService
        // would auto-instrument -> infinite span loop. Build the default capture
        // services but swap URLSession for one that ignores the collector URL.
        let captureServices = CaptureServiceBuilder()
          .addDefaults()
          .remove(ofType: URLSessionCaptureService.self)
          .add(.urlSession(
            options: URLSessionCaptureService.Options(ignoredURLs: ["localhost:4318", "127.0.0.1:4318"])
          ))
          .build()

        // appId-less designated initializer: only valid because a custom
        // OpenTelemetryExport is supplied. platform: .flutter so the Flutter
        // plugin attaches correctly. KSCrash gives crash + app-hang capture
        // for E2/E3.
        let options = Embrace.Options(
          export: export,
          platform: .flutter,
          captureServices: captureServices,
          crashReporter: KSCrashReporter()
        )
        try Embrace.setup(options: options).start()
        NSLog("EMBRACE-DEMO: native setup OK (no-account, custom OTLP export)")
      } catch {
        NSLog("EMBRACE-DEMO: native setup FAILED: \(error)")
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
