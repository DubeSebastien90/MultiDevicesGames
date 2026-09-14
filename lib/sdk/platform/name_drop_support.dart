import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'native_dpi_channel.dart';

/// Whether this device is one that can interrupt a game with NameDrop.
///
/// NameDrop is the iOS 17 feature that puts a Share Contact card over whatever
/// is on screen when the tops of two iPhones are brought together — which is
/// precisely the arrangement half this catalogue asks for. It is the reason
/// [NameDropOptimizer] exists, and the reason the lobby offers to talk people
/// through turning it off.
///
/// Three conditions, and all of them have to hold:
///
/// - **iOS.** Nothing else has this feature.
/// - **An iPhone.** iPads report `TargetPlatform.iOS` too, and do not do
///   NameDrop. Without this every iPad at the table gets a full-screen notice
///   about a setting it does not have.
/// - **iOS 17 or later**, which is when the feature shipped.
///
/// There is deliberately no way to ask whether the *setting* is on. Apple
/// exposes no API for it — reading it, or turning it off for the duration of a
/// game, is simply not something an app may do. So this answers the much weaker
/// question it can answer, and everything downstream is built to be wrong
/// occasionally.
class NameDropSupport {
  const NameDropSupport._();

  static const _channel = MethodChannel(NativeDpiChannel.channelName);

  /// iOS 17 is where NameDrop shipped.
  static const _firstVersion = 17;

  /// Settled once per launch. The answer cannot change while the app is
  /// running, and this is read on the way into every lobby.
  static bool? _cached;

  /// Forget the cached answer. Tests only.
  @visibleForTesting
  static void reset() => _cached = null;

  /// Pretend every device can NameDrop while running a debug build.
  ///
  /// The notice is otherwise unreachable off an iPhone, which makes its
  /// wording, its layout and the walkthrough behind it impossible to look at
  /// on the emulator or the desktop build most of the work happens on. In a
  /// release build this is const `false` and the branch below compiles out.
  ///
  /// Set to false from a test that needs the real answer in debug.
  @visibleForTesting
  static bool debugAlwaysSupported = kDebugMode;

  static Future<bool> onThisDevice() async {
    final cached = _cached;
    if (cached != null) return cached;
    return _cached = await _ask();
  }

  static Future<bool> _ask() async {
    if (kDebugMode && debugAlwaysSupported) return true;

    // Skips the channel round trip on the platforms that are most of the
    // table, and keeps the web build — where the channel does not exist at
    // all — from relying on the catch below.
    if (defaultTargetPlatform != TargetPlatform.iOS || kIsWeb) return false;

    try {
      final raw = await _channel.invokeMethod<Map>('getDeviceInfo');
      if (raw == null) return false;
      final info = Map<String, dynamic>.from(raw);
      return info['idiom'] == 'phone' &&
          (info['systemMajor'] as num).toInt() >= _firstVersion;
    } catch (_) {
      // MissingPluginException on a build whose native side predates this,
      // PlatformException, a cast that fails on an unexpected shape. None of
      // them are worth a crash: not knowing means not nagging.
      return false;
    }
  }
}
