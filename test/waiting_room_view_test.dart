import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';
import 'package:multiscreen_slingshot/sdk/ui/waiting_room_view.dart';

/// A phone that comes back mid-round sees this instead of a lobby that looks
/// like nothing is happening. What it has to get across is that the wait is
/// deliberate and the seat was kept.
void main() {
  const scores = ScoreView([
    ScoreEntry(phoneId: 'p1', label: 'Ada', total: 7, roundDelta: 0),
    ScoreEntry(phoneId: 'p2', label: 'Bob', total: 3, roundDelta: 0),
  ]);

  Future<void> show(WidgetTester tester, {String? playing}) =>
      tester.pumpWidget(
        MaterialApp(
          home: WaitingRoomView(
            scores: scores,
            meId: 'p2',
            playing: playing,
            offline: const {},
          ),
        ),
      );

  testWidgets('it says what is happening and what happens next', (
    tester,
  ) async {
    await show(tester, playing: 'Guacamole');

    expect(find.text('Waiting for the minigame to start'), findsOneWidget);
    expect(find.text('You will join in the next one.'), findsOneWidget);
    expect(find.text('Now playing: Guacamole'), findsOneWidget);
  });

  testWidgets('the seat is visibly still theirs', (tester) async {
    // The reason to show standings here at all: a returning player's worry is
    // that their score is gone, and the answer is their own row with their own
    // number in it.
    await show(tester, playing: 'Guacamole');

    expect(find.text('Bob (you)'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('it holds together with no game named', (tester) async {
    // Reachable: the sit-out message can land before the lobby broadcast that
    // says what is being played.
    await show(tester);

    expect(find.text('Waiting for the minigame to start'), findsOneWidget);
    expect(find.textContaining('Now playing'), findsNothing);
  });

  testWidgets('it fits a short phone without overflowing', (tester) async {
    // Standings plus copy plus a spinner is a tall column, and this screen is
    // the one a player stares at for a whole round.
    tester.view.physicalSize = const Size(360, 560);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await show(tester, playing: 'Guacamole');

    expect(tester.takeException(), isNull);
  });
}
