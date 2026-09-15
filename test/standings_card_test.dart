import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';
import 'package:multiscreen_slingshot/sdk/ui/standings_card.dart';

/// The card is shown on screens that have no room to spare — the lobby squeezes
/// it between the table and the Play button — so what it does when the table is
/// bigger than the hole is the whole of its behaviour.
void main() {
  ScoreView table(int players) => ScoreView([
    for (var i = 1; i <= players; i++)
      ScoreEntry(
        phoneId: 'p$i',
        label: 'Player $i',
        total: players - i,
        roundDelta: 0,
      ),
  ]);

  Future<void> show(
    WidgetTester tester, {
    required int players,
    required double maxListHeight,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: StandingsCard(
            scores: table(players),
            meId: 'p1',
            maxListHeight: maxListHeight,
          ),
        ),
      ),
    ),
  );

  testWidgets('a full table fits the height it was given', (tester) async {
    await show(tester, players: 8, maxListHeight: 80);

    // An overflow is reported as an exception rather than a failed
    // expectation, so it has to be asked for by name.
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(Card)).height, lessThan(160));
  });

  testWidgets('everybody is reachable by scrolling the names', (tester) async {
    await show(tester, players: 8, maxListHeight: 80);

    // The bottom of the table starts below the fold, and is one drag away.
    expect(find.text('Player 8'), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Player 8'), findsOneWidget);
  });

  testWidgets('a short table draws short', (tester) async {
    await show(tester, players: 2, maxListHeight: 200);

    // The point of a ceiling rather than a height: two players do not leave a
    // card with six rows of white under them.
    // Two rows and the card's own furniture: a shade over 120.
    expect(tester.getSize(find.byType(Card)).height, lessThan(130));
  });

  testWidgets('it stays away until somebody scores', (tester) async {
    await show(tester, players: 0, maxListHeight: 200);

    expect(find.byType(Card), findsNothing);
  });
}
