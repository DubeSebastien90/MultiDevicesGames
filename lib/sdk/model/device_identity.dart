import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// A name this device answers to, kept between runs.
///
/// The point is to be recognised. A player whose phone drops out — battery,
/// a tunnel, a fat thumb on the home button — should come back to the seat they
/// left, with their score in it, rather than as a stranger who happens to have
/// the same name. The host cannot work that out on its own: a socket carries no
/// identity, and an address changes with the network.
///
/// **Not the phone number the host hands out.** That is `p2`, and it means
/// something only inside one session — guessable, reused by the next player to
/// join, and meaningless once the host restarts. This is the device's own name:
/// long, random, and picked once, so claiming somebody else's seat would take
/// guessing a number nobody publishes.
///
/// Kept deliberately dull — a string in the same preferences the host name
/// already lives in. It identifies a phone to a game of hot potato, which is
/// not a thing worth protecting with anything cleverer.
class DeviceIdentity {
  const DeviceIdentity._();

  static const _key = 'deviceId';

  /// The id this device already had, or a new one saved for next time.
  static Future<String> load() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_key);
    if (existing != null && existing.isNotEmpty) return existing;

    final fresh = generate();
    await prefs.setString(_key, fresh);
    return fresh;
  }

  /// 128 random bits as hex.
  ///
  /// [Random.secure] rather than the ordinary one: two phones opening the app
  /// at the same moment must not think of the same name, and a seeded generator
  /// started from the clock is exactly how that happens.
  static String generate() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
