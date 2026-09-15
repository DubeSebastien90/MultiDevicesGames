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

  /// The lobby's arrangement: a slot of a known height, and a card told to fit
  /// inside it and work the rest out for itself.
  Future<void> showInSlot(
    WidgetTester tester, {
    required int players,
    required double slot,
    bool host = true,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            SizedBox(
              height: slot,
              child: Align(
                alignment: Alignment.topCenter,
                child: StandingsCard(
                  scores: table(players),
                  meId: 'p1',
                  // The host's card carries a Reset button in its heading, and
                  // nobody else's does. That is the whole reason the card has
                  // to measure its own heading rather than be told about it.
                  onReset: host ? () {} : null,
                  maxListHeight: double.infinity,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  testWidgets('a full table fits the height it was given', (tester) async {
    await show(tester, players: 8, maxListHeight: 80);

    // An overflow is reported as an exception rather than a failed
    // expectation, so it has to be asked for by name.
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(StandingsCard.plateKey)).height, lessThan(160));
  });

  testWidgets('everybody is reachable by scrolling the names', (tester) async {
    await show(tester, players: 8, maxListHeight: 80);

    // The bottom of the table starts below the fold, and is one drag away.
    expect(find.text('Player 8'), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Player 8'), findsOneWidget);
  });

  testWidgets('a short table draws short', (tester) async {
    await show(tester, players: 2, maxListHeight: 200);

    // The point of a ceiling rather than a height: two players do not leave a
    // card with six rows of white under them.
    // Two rows of character art and the card's own furniture.
    expect(
      tester.getSize(find.byKey(StandingsCard.plateKey)).height,
      lessThan(160),
    );
  });

  testWidgets('it stays away until somebody scores', (tester) async {
    await show(tester, players: 0, maxListHeight: 200);

    expect(find.byKey(StandingsCard.plateKey), findsNothing);
  });

  testWidgets('it fits the slot it is given, Reset button and all', (
    tester,
  ) async {
    // Five players on an iPhone: the list is long enough to want more than the
    // slot has, which is when a card that guesses at its own heading overflows.
    await showInSlot(tester, players: 5, slot: 150);

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(StandingsCard.plateKey)).height, lessThanOrEqualTo(150));
  });

  testWidgets('a slot it cannot fill is not padded out', (tester) async {
    await showInSlot(tester, players: 2, slot: 400);

    expect(tester.getSize(find.byKey(StandingsCard.plateKey)).height, lessThan(180));
  });

  testWidgets('every table size fits every slot', (tester) async {
    for (final players in [2, 5, 8]) {
      for (final slot in [130.0, 150.0, 220.0, 400.0]) {
        await showInSlot(tester, players: players, slot: slot);

        expect(
          tester.takeException(),
          isNull,
          reason: '$players players in a ${slot.toInt()}px slot',
        );
        expect(
          tester.getSize(find.byKey(StandingsCard.plateKey)).height,
          lessThanOrEqualTo(slot),
          reason: '$players players in a ${slot.toInt()}px slot',
        );
      }
    }
  });

  testWidgets('the scores step aside for the scrollbar', (tester) async {
    EdgeInsets listPadding() =>
        tester.widget<ListView>(find.byType(ListView)).padding as EdgeInsets;

    await showInSlot(tester, players: 2, slot: 400);
    // Nothing to scroll, so nothing to make room for.
    expect(listPadding().right, 0);

    await showInSlot(tester, players: 8, slot: 150);
    // One frame lays the list out and reports the overflow; the next rebuilds
    // with the lane in place.
    await tester.pump();
    await tester.pump();

    expect(listPadding().right, greaterThan(0));
  });
}
