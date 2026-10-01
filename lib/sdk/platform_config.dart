import 'package:flutter/foundation.dart';

class PlatformConfig {
  const PlatformConfig._();

  static const bool showDevChrome = !kReleaseMode && !screenshotMode;

  static const bool screenshotMode = bool.fromEnvironment('SCREENSHOT_MODE');

  static const bool showDebugUi = kDebugMode && !screenshotMode;

  static const double mmToWorld = 0.1;

  static const int simHz = 60;

  static const int broadcastHz = 60;

  static const Duration roundEndFade = Duration(milliseconds: 250);
}
