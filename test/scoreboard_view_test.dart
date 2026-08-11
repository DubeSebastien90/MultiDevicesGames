import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';
import 'package:multiscreen_slingshot/sdk/ui/scoreboard_view.dart';

/// The last screen of the evening. It exists because the per-round results
/// screen answers a different question — what just happened — and the table
/// stayed for the other one: who won the whole thing.
void main() {
  const scores = ScoreView([
    ScoreEntry(phoneId: 'p1', label: 'Ada', total: 12, roundDelta: 3),
    ScoreEntry(phoneId: 'p2', label: 'Bob', total: 40, roundDelta: 10),
    ScoreEntry(phoneId: 'p3', label: 'Cy', total: 7, roundDelta: 0),
  ]);

  var backs = 0;
  setUp(() => backs = 0);

  Future<void> show(
    WidgetTester tester, {
    ScoreView board = scores,
    String? meId = 'p1',
    bool host = true,
    Set<String> offline = const {},
  }) => tester.pumpWidget(
    MaterialApp(
      home: ScoreboardView(
        scores: board,
        meId: meId,
        offline: offline,
        onBackToLobby: host ? () => backs++ : null,
      ),
    ),
  );

  testWidgets('it names the winner and ranks everybody', (tester) async {
    await show(tester);

    expect(find.text('Bob wins!'), findsOneWidget);
    expect(find.text('Final standings'), findsOneWidget);
    // Every player, in order, with their totals — this is the whole point of
    // the screen, so nobody is left off it.
    expect(find.text('Ada (you)'), findsOneWidget);
    expect(find.text('Cy'), findsOneWidget);
    expect(find.text('40'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('the winner is told so in the second person', (tester) async {
    await show(tester, meId: 'p2');

    expect(find.text('You win!'), findsOneWidget);
    expect(find.text('Bob wins!'), findsNothing);
  });

  testWidgets('a level top says so instead of picking one', (tester) async {
    // Naming either of them would be inventing a result. The leader is
    // deliberately null when the top two are level, and this is what that has
    // to look like.
    await show(
      tester,
      board: const ScoreView([
        ScoreEntry(phoneId: 'p1', label: 'Ada', total: 9, roundDelta: 0),
        ScoreEntry(phoneId: 'p2', label: 'Bob', total: 9, roundDelta: 0),
      ]),
    );

    expect(find.text('It is a tie!'), findsOneWidget);
    // Both are second-equal by count, so neither is shown a place above the
    // other: two firsts, no second.
    expect(find.text('1'), findsNWidgets(2));
    expect(find.text('2'), findsNothing);
  });

  testWidgets('a run where nobody scored still lists the table', (
    tester,
  ) async {
    // The standings card renders nothing at all on an all-zero board, which is
    // right beside other content and catastrophic here: the final screen of the
    // evening would be an empty card.
    await show(
      tester,
      board: const ScoreView([
        ScoreEntry(phoneId: 'p1', label: 'Ada', total: 0, roundDelta: 0),
        ScoreEntry(phoneId: 'p2', label: 'Bob', total: 0, roundDelta: 0),
      ]),
    );

    expect(find.text('Ada (you)'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('That is the lot'), findsOneWidget);
  });

  testWidgets('a player who left keeps the place they played for', (
    tester,
  ) async {
    await show(tester, offline: const {'p2'});

    expect(find.text('Bob wins!'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
  });

  testWidgets('only the host is given the way out', (tester) async {
    await show(tester, host: false);

    expect(find.text('Back to lobby'), findsNothing);
    expect(find.text('Waiting for the host…'), findsOneWidget);
  });

  testWidgets('the host button is the way back to the lobby', (tester) async {
    await show(tester);

    await tester.tap(find.text('Back to lobby'));
    expect(backs, 1);
  });

  testWidgets('a full table fits a short phone without overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 560);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await show(
      tester,
      board: ScoreView([
        for (var i = 0; i < 8; i++)
          ScoreEntry(
            phoneId: 'p$i',
            label: 'Player $i',
            total: i * 5,
            roundDelta: 0,
          ),
      ]),
    );

    expect(tester.takeException(), isNull);
  });
}
