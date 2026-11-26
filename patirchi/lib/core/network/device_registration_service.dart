import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:patirchi/core/network/api_client.dart';
import 'package:patirchi/core/network/api_endpoints.dart';
import 'package:patirchi/core/storage/guest_buyer_storage.dart';

/// Qurilmani xavfsiz texnik maydonlar bilan backendda ro'yxatdan o'tkazadi.
class DeviceRegistrationService {
  DeviceRegistrationService._();

  static final _storage = GuestBuyerStorage();
  static bool _registeredThisRun = false;

  static Future<void> register({bool force = false}) async {
    if (_registeredThisRun && !force) return;
    try {
      final device = await DeviceInfoPlugin().deviceInfo;
      final app = await PackageInfo.fromPlatform();
      final data = device.data;
      final platform = switch (defaultTargetPlatform) {
        TargetPlatform.android => 'android',
        TargetPlatform.iOS => 'ios',
        _ => 'other',
      };

      final metadata = <String, dynamic>{};
      for (final key in const ['brand', 'device', 'sdkInt', 'systemName']) {
        final value = data[key];
        if (value != null && value is! List && value is! Map) {
          metadata[key] = value;
        }
      }

      await ApiClient.instance.post(
        ApiEndpoints.deviceRegister,
        body: {
          'device_id': await _storage.deviceId(),
          'platform': platform,
          'manufacturer': data['manufacturer']?.toString() ?? '',
          'model': data['model']?.toString() ?? '',
          'os_version': data['version'] is Map
              ? (data['version'] as Map)['release']?.toString() ?? ''
              : data['systemVersion']?.toString() ?? '',
          'app_version': app.version,
          'metadata': metadata,
        },
      );
      _registeredThisRun = true;
    } on Object {
      // Qurilma ro'yxati ishlamasa ham xaridor sahifasi ochiladi.
    }
  }
}
