/// Central configuration for the demo's telemetry.
///
/// All attribute KEYS here must match `docs/SCHEMA_CONTRACT.md` exactly so the
/// shared Grafana dashboard works across every client (Web / Android / iOS /
/// Flutter / plain-OTel).
library;

class TelemetryConfig {
  TelemetryConfig._();

  /// service.name for this client (per the spike brief).
  static const String serviceName = 'embrace-demo-flutter';

  /// Fixed demo user (SCHEMA_CONTRACT: user.id).
  static const String demoUserId = 'demo-user-001';

  /// Self-hosted grafana/otel-lgtm OTLP/HTTP ingest.
  ///
  /// NOTE: an iOS *simulator* shares the host network, so `localhost` resolves
  /// to the Mac running the collector. (A physical device would need the LAN
  /// IP; Android emulator would need 10.0.2.2 — but Android is out of scope.)
  static const String otlpHttpBase = 'http://localhost:4318';
  static const String otlpTracesEndpoint = '$otlpHttpBase/v1/traces';
  static const String otlpLogsEndpoint = '$otlpHttpBase/v1/logs';

  /// Which SDK arm is compiled in. Selected at build time via
  /// `--dart-define=TELEMETRY_TOOL=embrace|otel` (defaults to otel, the arm
  /// that is guaranteed to reach Grafana with no Embrace account — see E1).
  static const String tool = String.fromEnvironment(
    'TELEMETRY_TOOL',
    defaultValue: 'otel',
  );

  static bool get isEmbrace => tool == 'embrace';
  static bool get isOtel => tool == 'otel';

  /// When set via `--dart-define=AUTOFIRE=delay,workflow,workflow,caught` the
  /// app fires those actions automatically after launch (no UI taps needed —
  /// `simctl` has no coordinate-tap on this toolchain). `crash` / `anr` are
  /// honored too. Empty = manual mode.
  static const String autofire =
      String.fromEnvironment('AUTOFIRE', defaultValue: '');
}

/// SCHEMA_CONTRACT attribute keys. Centralised so the two arms stay in lockstep.
class Attr {
  Attr._();

  // Resource / common
  static const userId = 'user.id';
  static const deviceModel = 'device.model';
  static const deviceManufacturer = 'device.manufacturer';
  static const appVersion = 'app.version';
  static const osVersion = 'os.version';
  static const serviceName = 'service.name';
  static const telemetryTool = 'telemetry.tool';

  // Per-action
  static const actionName = 'action.name';
  static const freeRamMb = 'system.free_ram_mb';
  static const freeStorageMb = 'system.free_storage_mb';
  static const networkSpeedMbps = 'network.speed_mbps';
  static const networkType = 'network.type';

  // Workflow child-span shape
  static const stepName = 'step.name';
  static const stepStatus = 'step.status';
  static const stepData = 'step.data';

  // Exception (on error spans)
  static const exceptionType = 'exception.type';
  static const exceptionMessage = 'exception.message';
}
