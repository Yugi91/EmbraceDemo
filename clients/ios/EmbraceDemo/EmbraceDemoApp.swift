import UIKit
import SwiftUI

/// Native iOS (Swift) client of the EmbraceGrafanaDemo — FNB-96526 spike.
///
/// UIKit app lifecycle (AppDelegate + SceneDelegate) so the deploy target can stay
/// at **iOS 13** (the SwiftUI `App`/`Scene` lifecycle is iOS 14+). The UI itself is
/// SwiftUI, hosted in a `UIHostingController` (SwiftUI views ARE available on iOS 13).
/// Telemetry is set up as early as possible in `didFinishLaunchingWithOptions`,
/// matching the Flutter spike's AppDelegate timing.
///
/// Two telemetry arms, selected at launch via env var (no rebuild needed):
///   xcrun simctl launch --setenv TELEMETRY_TOOL=embrace ...   (Embrace, no-account OTLP)
///   xcrun simctl launch --setenv TELEMETRY_TOOL=otel    ...   (plain OpenTelemetry)
/// Defaults to `otel`. Optionally drive actions headlessly:
///   --setenv AUTOFIRE=delay,workflow,workflow,caught,frames

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
  /// Single shared telemetry arm + actions, built at launch.
  static let telemetry: TelemetryService =
    TelemetryConfig.isEmbrace ? EmbraceTelemetryService() : OtelTelemetryService()
  static let actions = DemoActions(telemetry)

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Set up the chosen telemetry arm as early as possible.
    AppDelegate.telemetry.bootstrap()
    return true
  }

  func application(
    _ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let config = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
    config.delegateClass = SceneDelegate.self
    return config
  }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene else { return }
    let window = UIWindow(windowScene: windowScene)
    window.rootViewController = UIHostingController(rootView: ContentView(actions: AppDelegate.actions))
    self.window = window
    window.makeKeyAndVisible()

    // Headless driver (simctl can't tap by coordinate on this toolchain).
    Autofire.runIfRequested(AppDelegate.actions)
  }
}

/// Fires the AUTOFIRE env list after launch. Sequences actions with gaps so each
/// exports; UI-blocking actions (anr/frames/crash) hop to the main thread.
enum Autofire {
  static func runIfRequested(_ actions: DemoActions) {
    let list = TelemetryConfig.autofire
    guard !list.isEmpty else { return }
    NSLog("EMBRACE-DEMO: AUTOFIRE = \(list.joined(separator: ","))")

    DispatchQueue.global(qos: .userInitiated).async {
      Thread.sleep(forTimeInterval: 1.5)  // let the SDK settle / first session span open
      for name in list {
        NSLog("EMBRACE-DEMO: AUTOFIRE -> \(name)")
        switch name {
        case "delay": actions.delay()
        case "workflow": actions.workflow()
        case "caught", "caught_error": actions.caughtError()
        case "anr", "hang", "app-hang": runOnMainSync { actions.appHang() }
        case "frames", "jank": runOnMainSync { actions.frames() }
        case "network": actions.network()
        case "crash":
          DispatchQueue.main.async { actions.crash() }  // terminates the process
          return
        case "oom":
          actions.oom()  // allocates until memory-killed (never returns)
          return
        default: NSLog("EMBRACE-DEMO: AUTOFIRE unknown action '\(name)'")
        }
        Thread.sleep(forTimeInterval: 1.2)
      }
      actions.flush()  // final flush so the last batch leaves before idle
      NSLog("EMBRACE-DEMO: AUTOFIRE complete")
    }
  }

  private static func runOnMainSync(_ block: @escaping () -> Void) {
    if Thread.isMainThread { block() } else { DispatchQueue.main.sync(execute: block) }
  }
}
