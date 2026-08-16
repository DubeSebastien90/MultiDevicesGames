import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/model/player_color.dart';
import 'package:multiscreen_slingshot/sdk/render/player_art.dart';

/// Artwork must never decide whether a game starts.
///
/// A game here once rasterised thirty animation frames inside `GameView.load()`
/// — which the client awaits before it has anything to draw. That took real
/// time, and on some machines intermittently never finished, leaving that phone
/// on a screen that never appeared while everyone else played.
///
/// The game and the sprite loader are both gone. The rule they cost is not, and
/// it is now enforced one level down, where every game inherits it: preloading
/// hands control straight back, and anything asked to draw before its file has
/// arrived draws something anyway.
void main() {
  test('preloading hands control back rather than waiting', () {
    // Deliberately not awaited and deliberately not awaitable. The signature is
    // the guarantee: there is nothing here for a caller to block on, so no
    // future round can be held up by a decode the way that one was.
    PlayerArt.preload(PlayerPalette.all);

    expect(
      PlayerArt.of(PlayerPalette.green, PlayerArtSlot.face).isLoaded,
      isFalse,
      reason: 'preload waited for the file instead of starting it',
    );
  });

  test('a picture that has not arrived still paints', () {
    // The other half of the same rule. A caller that had to check would
    // eventually forget to, so there is no answer to check: draw always draws.
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    for (final slot in PlayerArtSlot.values) {
      PlayerArt.of(PlayerPalette.red, slot).draw(
        canvas,
        const Offset(4, 4),
        worldSize: 2,
      );
    }

    expect(recorder.endRecording().approximateBytesUsed, greaterThan(0));
  });
}
