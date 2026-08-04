import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/slingshot/slingshot_view.dart';
import 'package:multiscreen_slingshot/sdk/render/lottie_sprite.dart';

/// Artwork must never decide whether a game starts.
///
/// Slingshot used to rasterise thirty Lottie frames inside `GameView.load()`,
/// which the client awaits before it has anything to draw. That took real time,
/// and on some machines intermittently never finished — leaving that phone on a
/// screen that never appeared while everyone else played. These tests pin the
/// contract that prevents it, and deliberately do *not* assert that any
/// rasterisation completes: the whole point is that nothing depends on it.
void main() {
  testWidgets('a view is ready before its artwork is', (tester) async {
    final view = SlingshotView();
    await view.load();

    // The sharp end of the fix. `load()` is what the client awaits before it
    // has anything to draw, so it must come back *while the artwork is still
    // rasterising* — not after. Timing bounds were no use here: the load
    // usually finishes quickly, and the failure was intermittent. This is
    // structural, and fails outright if load() ever waits again.
    expect(view.artworkReady, isFalse,
        reason: 'load() must start the artwork, not wait for it');

    view.dispose();
  });

  test('an unloaded sprite draws nothing, and says so', () {
    final sprite = LottieSprite();
    final canvas = Canvas(PictureRecorder());

    // False is the signal a caller needs to draw its fallback. Silently
    // painting nothing would leave a bird-shaped hole on the table.
    expect(sprite.draw(canvas, Offset.zero, 0, worldSize: 1), isFalse);
    expect(sprite.drawFrame(canvas, Offset.zero, 0, worldSize: 1), isFalse);
    expect(sprite.isLoaded, isFalse);
    expect(sprite.frameCount, 0);
  });

  testWidgets('disposing while frames are still rasterising is safe',
      (tester) async {
    final sprite = LottieSprite()
      ..beginLoading('assets/animations/character_test.json',
          width: 64, height: 64);

    // The round moved on. Whatever the loader produces after this must be
    // thrown away rather than adopted — thirty images that nothing will ever
    // dispose is a leak on every round change.
    sprite.dispose();

    expect(sprite.isLoaded, isFalse);
    expect(sprite.draw(Canvas(PictureRecorder()), Offset.zero, 0, worldSize: 1),
        isFalse);

    // And a disposed sprite refuses to start again.
    sprite.beginLoading('assets/animations/character_test.json',
        width: 64, height: 64);
    expect(sprite.isLoaded, isFalse);
  });

  testWidgets('asking twice does not start two rasterisations', (tester) async {
    final sprite = LottieSprite();
    sprite.beginLoading('assets/animations/character_test.json',
        width: 64, height: 64);
    final first = sprite.loading;

    sprite.beginLoading('assets/animations/character_test.json',
        width: 64, height: 64);
    expect(identical(sprite.loading, first), isTrue);

    sprite.dispose();
  });

  testWidgets('a missing asset is recorded, not thrown at the game',
      (tester) async {
    final sprite = LottieSprite()
      ..beginLoading('assets/animations/not_here.json', width: 8, height: 8);

    // The failure belongs to the sprite. A game that asked for artwork it does
    // not have still runs, without it.
    await sprite.loading;
    expect(sprite.loadError, isNotNull);
    expect(sprite.isLoaded, isFalse);
    expect(sprite.draw(Canvas(PictureRecorder()), Offset.zero, 0, worldSize: 1),
        isFalse);
  });
}
