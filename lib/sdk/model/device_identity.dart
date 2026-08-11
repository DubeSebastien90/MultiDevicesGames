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

  /// A short, one-way stand-in for a device id, for saying *which* seats are
  /// free to reclaim without saying who they belong to.
  ///
  /// The join list has to know whether this phone has a seat waiting in a game
  /// that has already started, and only the host knows. Broadcasting the ids
  /// themselves would undo the reason they are random in the first place:
  /// anyone listening on the network could read one off the air and walk into
  /// somebody's seat. A fingerprint answers "is one of these mine?" and nothing
  /// else.
  ///
  /// FNV-1a, not a cryptographic hash — this is not protecting a secret, only
  /// avoiding publishing one. Two ids landing on the same fingerprint would
  /// mean a phone is offered a seat the host then declines to give it, which is
  /// where it started.
  ///
  /// Kept to 32 bits deliberately. Dart's ints are 64-bit and **signed**, and a
  /// mask of `0xFFFFFFFFFFFFFFFF` is not the no-op it looks like — it is -1, so
  /// it changes nothing and the hash runs off into negative numbers that print
  /// with a minus sign. Half a word stays comfortably positive, and eight hex
  /// characters is more than enough to tell a handful of seats apart.
  static String fingerprint(String deviceId) {
    var hash = 0x811c9dc5;
    for (final unit in deviceId.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
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
