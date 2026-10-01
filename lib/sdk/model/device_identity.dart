import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdentity {
  const DeviceIdentity._();

  static const _key = 'deviceId';

  static Future<String> load() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_key);
    if (existing != null && existing.isNotEmpty) return existing;

    final fresh = generate();
    await prefs.setString(_key, fresh);
    return fresh;
  }

  static String fingerprint(String deviceId) {
    var hash = 0x811c9dc5;
    for (final unit in deviceId.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static String generate() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
