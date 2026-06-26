import Foundation
#if canImport(UIKit)
  import UIKit
#endif

/// Central configuration + SCHEMA_CONTRACT attribute keys for the native iOS client.
///
/// All keys here MUST match `docs/SCHEMA_CONTRACT.md` exactly so the shared Grafana
/// dashboard works across every client (Web / Android / iOS / Flutter / plain-OTel).
enum TelemetryConfig {
  /// service.name for this client (per the spike brief).
  static let serviceName = "embrace-demo-ios"

  /// Fixed demo user (SCHEMA_CONTRACT: user.id).
  static let demoUserId = "demo-user-001"

  /// Self-hosted grafana/otel-lgtm OTLP/HTTP ingest.
  /// An iOS *simulator* shares the host network, so `localhost` resolves to the Mac
  /// running the collector. (A physical device would need the LAN IP.)
  static let otlpHttpBase = "http://localhost:4318"
  static let otlpTracesEndpoint = "\(otlpHttpBase)/v1/traces"
  static let otlpLogsEndpoint = "\(otlpHttpBase)/v1/logs"

  /// Which SDK arm is active, chosen at launch:
  ///   xcrun simctl launch --setenv TELEMETRY_TOOL=embrace|otel ...
  /// Defaults to `otel` (the arm guaranteed to reach Grafana with no Embrace account).
  /// For backwards-compat with the Flutter spike convention, EMBRACE_ENABLED=1 also
  /// selects the embrace arm.
  static var tool: String {
    let env = ProcessInfo.processInfo.environment
    if let t = env["TELEMETRY_TOOL"], !t.isEmpty { return t }
    if env["EMBRACE_ENABLED"] == "1" { return "embrace" }
    return "otel"
  }

  static var isEmbrace: Bool { tool == "embrace" }
  static var isOtel: Bool { tool == "otel" }

  /// Comma-separated actions to fire automatically after launch (no UI taps —
  /// `simctl` has no coordinate-tap here). e.g.
  ///   --setenv AUTOFIRE=delay,workflow,workflow,caught,frames
  /// `crash` / `anr` are honored too. Empty = manual mode.
  static var autofire: [String] {
    let raw = ProcessInfo.processInfo.environment["AUTOFIRE"] ?? ""
    return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }
}

/// SCHEMA_CONTRACT attribute keys. Centralised so the two arms stay in lockstep.
enum Attr {
  // Resource / common
  static let userId = "user.id"
  static let deviceModel = "device.model"
  static let deviceManufacturer = "device.manufacturer"
  static let appVersion = "app.version"
  static let osVersion = "os.version"
  static let serviceName = "service.name"
  static let telemetryTool = "telemetry.tool"

  // Per-action
  static let actionName = "action.name"
  static let freeRamMb = "system.free_ram_mb"
  static let freeStorageMb = "system.free_storage_mb"
  static let networkSpeedMbps = "network.speed_mbps"
  static let networkType = "network.type"

  // Workflow child-span shape
  static let stepName = "step.name"
  static let stepStatus = "step.status"
  static let stepData = "step.data"

  // Exception (on error spans)
  static let exceptionType = "exception.type"
  static let exceptionMessage = "exception.message"
}

/// The SCHEMA_CONTRACT "resource / common" attributes, resolved once.
///
/// Embrace captures device.model / os.version natively, but the contract asks every
/// client to set them *explicitly* "for parity", so we attach them to both arms.
struct DeviceContext {
  let deviceModel: String
  let deviceManufacturer: String
  let osVersion: String
  let appVersion: String

  static let current = DeviceContext()

  init() {
    // utsname.machine == hardware id, e.g. "iPhone15,2" (matches contract).
    var sys = utsname()
    uname(&sys)
    let machine = withUnsafePointer(to: &sys.machine) {
      $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
    }
    self.deviceModel = machine.isEmpty ? "unknown" : machine
    self.deviceManufacturer = "Apple"

    #if canImport(UIKit)
      let osName = UIDevice.current.systemName  // "iOS"
      let osVer = UIDevice.current.systemVersion // "17.4"
      self.osVersion = "\(osName) \(osVer)"
    #else
      self.osVersion = "iOS unknown"
    #endif

    let info = Bundle.main.infoDictionary
    let short = (info?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    let build = (info?["CFBundleVersion"] as? String) ?? "1"
    self.appVersion = "\(short)+\(build)"
  }

  /// Common resource attributes as a plain [String:String], shared by both arms so
  /// they stamp identical keys/values.
  func commonResourceAttributes(tool: String) -> [String: String] {
    [
      Attr.serviceName: TelemetryConfig.serviceName,
      Attr.telemetryTool: tool,
      Attr.userId: TelemetryConfig.demoUserId,
      Attr.deviceModel: deviceModel,
      Attr.deviceManufacturer: deviceManufacturer,
      Attr.appVersion: appVersion,
      Attr.osVersion: osVersion,
    ]
  }
}

/// A point-in-time sample of the numeric system/network signals the contract wants
/// on each action. Embrace does NOT auto-capture network speed; on a simulator real
/// RAM/storage probing is unreliable, so these are best-effort estimates carried as
/// span/log attributes (the collector's spanmetrics connector turns them into metrics).
struct SystemSample {
  let freeRamMb: Double
  let freeStorageMb: Double
  let networkSpeedMbps: Double
  let networkType: String

  static func take() -> SystemSample {
    // Coarse free-RAM proxy: physical RAM minus this process's resident footprint.
    let physical = Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024)
    var used: Double = 0
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let kr = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
      }
    }
    if kr == KERN_SUCCESS {
      used = Double(info.resident_size) / (1024 * 1024)
    }
    let freeRam = max(1.0, physical - used)

    var freeStorage = 4096.0
    if let attrs = try? FileManager.default.attributesOfFileSystem(
      forPath: NSHomeDirectory()),
      let freeBytes = (attrs[.systemFreeSize] as? NSNumber)?.doubleValue {
      freeStorage = freeBytes / (1024 * 1024)
    }

    return SystemSample(
      freeRamMb: (freeRam * 10).rounded() / 10,
      freeStorageMb: (freeStorage * 10).rounded() / 10,
      networkSpeedMbps: 50.0,  // estimate; not auto-captured by Embrace
      networkType: "wifi"
    )
  }
}
