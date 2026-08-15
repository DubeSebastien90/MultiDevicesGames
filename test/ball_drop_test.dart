import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/model/player_color.dart';
import 'package:multiscreen_slingshot/sdk/ui/ball_drop.dart';

/// The shower over the results screen.
///
/// The one thing that must hold: the result is visible whatever the animation
/// does. Balls are painted *over* it, so a rasterise that fails, a file that
/// was renamed, or a phone too slow to run the clock all end in the same
/// place — somebody reading their result a moment early.
void main() {
  testWidgets('the result is underneath from the first frame', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: BallDrop(child: Text('You win!'))),
    );

    // Before any ball has rasterised.
    expect(find.text('You win!'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('You win!'), findsOneWidget);
  });

  testWidgets('a table with no colours still shows its result', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BallDrop(colors: [], child: Text('Round over')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Round over'), findsOneWidget);
  });

  test('the shower is the whole palette, not this table', () {
    // Deliberately not the roster: a two-player round and an eight-player one
    // get the same downpour, so the moment belongs to the game rather than to
    // whoever happened to be holding a phone.
    const drop = BallDrop(child: SizedBox());
    expect(drop.colors, PlayerPalette.all);
    expect(BallDrop.perColor * PlayerPalette.size, greaterThanOrEqualTo(200));
  });

  test('every palette colour has a ball, and every ball a file', () {
    // A colour with no ball is a player who silently never appears in the
    // shower. Pinned because nothing about that failure is visible.
    for (final color in PlayerPalette.all) {
      expect(
        BallDrop.assetFor(color),
        isNotNull,
        reason: '${color.id} has no ball',
      );
    }
    expect(BallDrop.assets, hasLength(PlayerPalette.size));
  });

  testWidgets('every ball file is really in the bundle', (tester) async {
    // A path typo or a missing pubspec entry is a shower with a colour
    // missing from it — invisible until somebody notices their own ball never
    // falls.
    for (final asset in BallDrop.assets) {
      await tester.runAsync(() async {
        final data = await rootBundle.loadString(asset);
        expect(data, contains('<svg'), reason: '$asset is not an SVG');
      });
    }
  });
}
