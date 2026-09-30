import 'dart:async';

import 'package:multiscreen_slingshot/sdk/ui/sticker/sticker_motion.dart';

/// Runs before every test file in this directory.
///
/// The sticker screens idle forever — a bobbing title, a drifting background —
/// and `pumpAndSettle` waits for the screen to stop moving. Stilled here, once,
/// so no test has to know which screens loop.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  StickerMotion.loops = false;
  await testMain();
}
