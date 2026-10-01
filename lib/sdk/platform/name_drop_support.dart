import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'native_dpi_channel.dart';

class NameDropSupport {
  const NameDropSupport._();

  static const _channel = MethodChannel(NativeDpiChannel.channelName);

  static const _firstVersion = 17;

  static bool? _cached;

  @visibleForTesting
  static void reset() => _cached = null;

  @visibleForTesting
  static bool debugAlwaysSupported = kDebugMode;

  static Future<bool> onThisDevice() async {
    final cached = _cached;
    if (cached != null) return cached;
    return _cached = await _ask();
  }

  static Future<bool> _ask() async {
    if (kDebugMode && debugAlwaysSupported) return true;

    if (defaultTargetPlatform != TargetPlatform.iOS || kIsWeb) return false;

    try {
      final raw = await _channel.invokeMethod<Map>('getDeviceInfo');
      if (raw == null) return false;
      final info = Map<String, dynamic>.from(raw);
      return info['idiom'] == 'phone' &&
          (info['systemMajor'] as num).toInt() >= _firstVersion;
    } catch (_) {
      return false;
    }
  }
}
