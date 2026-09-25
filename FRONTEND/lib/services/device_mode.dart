import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Set to true by passing `--dart-define=TV_SIMULATION=true` at build/run time.
/// When enabled, this machine acts as a simulated Android TV display — the full
/// TV pairing, WebSocket, and video playback UI is shown regardless of platform.
const bool _tvSimulation =
    bool.fromEnvironment('TV_SIMULATION', defaultValue: false);

class DeviceMode {
  static const _channel = MethodChannel('cm.smartads/device');

  static Future<bool> isAndroidTv() async {
    if (_tvSimulation) return true;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _channel.invokeMethod<bool>('isAndroidTv') ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<Map<String, dynamic>> tvInfo() async {
    if (_tvSimulation) {
      return {
        'model': 'Desktop Simulator',
        'brand': 'SMARTADS',
        'osVersion': 'macOS Desktop',
        'resolution': '1920x1080',
        'androidId': null,
        'simulated': true,
      };
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return {};
    try {
      final value =
          await _channel.invokeMapMethod<String, dynamic>('getTvInfo');
      return Map<String, dynamic>.from(value ?? const {});
    } on PlatformException {
      return {};
    }
  }
}
