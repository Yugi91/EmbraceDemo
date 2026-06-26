import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Collects the SCHEMA_CONTRACT "resource / common" attributes plus the
/// per-action `system.*` / `network.*` samples.
///
/// Embrace captures device.model / os.version natively, but the contract asks
/// every client to set them *explicitly* "for parity", so we resolve them once
/// here and attach them to both arms.
class DeviceContext {
  DeviceContext._({
    required this.deviceModel,
    required this.deviceManufacturer,
    required this.osVersion,
    required this.appVersion,
  });

  final String deviceModel;
  final String deviceManufacturer;
  final String osVersion;
  final String appVersion;

  static DeviceContext? _cached;
  static DeviceContext get current =>
      _cached ?? (throw StateError('DeviceContext.load() not called'));

  static Future<DeviceContext> load() async {
    final pkg = await PackageInfo.fromPlatform();
    final appVersion = '${pkg.version}+${pkg.buildNumber}';

    String model = 'unknown';
    String manufacturer = 'unknown';
    String osVersion = 'unknown';

    final info = DeviceInfoPlugin();
    if (Platform.isIOS) {
      final ios = await info.iosInfo;
      // utsname.machine == hardware id, e.g. "iPhone15,2" (matches contract).
      model = ios.utsname.machine;
      manufacturer = 'Apple';
      osVersion = '${ios.systemName} ${ios.systemVersion}'; // "iOS 17.4"
    } else if (Platform.isAndroid) {
      final android = await info.androidInfo;
      model = android.model;
      manufacturer = android.manufacturer;
      osVersion = 'Android ${android.version.release}';
    }

    return _cached = DeviceContext._(
      deviceModel: model,
      deviceManufacturer: manufacturer,
      osVersion: osVersion,
      appVersion: appVersion,
    );
  }
}

/// A point-in-time sample of the numeric system/network signals the contract
/// wants on each action. Embrace does NOT auto-capture network speed, and on a
/// simulator real RAM/storage probing is unreliable, so these are best-effort
/// estimates carried as span/log attributes (the collector's spanmetrics
/// connector turns them into metrics — see SCHEMA_CONTRACT).
class SystemSample {
  const SystemSample({
    required this.freeRamMb,
    required this.freeStorageMb,
    required this.networkSpeedMbps,
    required this.networkType,
  });

  final double freeRamMb;
  final double freeStorageMb;
  final double networkSpeedMbps;
  final String networkType;

  static SystemSample take() {
    // Dart has no portable free-RAM API; report the process RSS headroom as a
    // coarse proxy so the attribute is present & non-zero for the demo.
    final rssMb = ProcessInfo.currentRss / (1024 * 1024);
    final freeRam = (512.0 - rssMb).clamp(1.0, 512.0);
    return SystemSample(
      freeRamMb: double.parse(freeRam.toStringAsFixed(1)),
      freeStorageMb: 4096.0, // simulator placeholder estimate
      networkSpeedMbps: 50.0, // estimate; not auto-captured by Embrace
      networkType: 'wifi',
    );
  }
}
