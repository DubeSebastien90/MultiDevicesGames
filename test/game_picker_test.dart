import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/dodgeball/dodgeball_game.dart';
import 'package:multiscreen_slingshot/games/hot_potato/hot_potato_game.dart';
import 'package:multiscreen_slingshot/games/arena/arena_game.dart';
import 'package:multiscreen_slingshot/sdk/catalog.dart';
import 'package:multiscreen_slingshot/sdk/contract/game.dart';
import 'package:multiscreen_slingshot/sdk/host/host_session.dart';
import 'package:multiscreen_slingshot/sdk/ui/game_picker.dart';

/// The list decides what the evening consists of, so the two facts it carries
/// have to stay apart: whether a game is *ticked* is the host's choice, and
/// whether it *fits* is the table's shape. A row can be either without being
/// the other.
void main() {
  GameOffer offer(
    MultiscreenGame game, {
    bool fits = true,
    bool chosen = true,
  }) => GameOffer(
    game: game,
    fitsTable: fits,
    reason: fits ? null : game.manifest.requirement(),
    chosen: chosen,
  );

  var toggles = <(String, bool)>[];
  var alls = 0;
  var nones = 0;

  setUp(() {
    toggles = [];
    alls = 0;
    nones = 0;
  });

  Future<void> show(WidgetTester tester, List<GameOffer> offers) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GamePicker(
                offers: offers,
                onChoose: (game, chosen) =>
                    toggles.add((game.manifest.id, chosen)),
                onAll: () => alls++,
                onNone: () => nones++,
              ),
            ),
          ),
        ),
      );

  testWidgets('every game is listed with its tick', (tester) async {
    await show(tester, [
      offer(const ArenaGame()),
      offer(const DodgeballGame(), chosen: false),
    ]);

    expect(find.text('Arena'), findsOneWidget);
    expect(find.text('Dodgeball'), findsOneWidget);

    final boxes = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .toList();
    expect(boxes.map((b) => b.value), [true, false]);
    expect(find.text('1 of 2 in the run'), findsOneWidget);
  });

  testWidgets('a ticked game the table cannot play is not counted as in the '
      'run', (tester) async {
    // The count is the run, not the ticks. Hot Potato is ticked and will not be
    // played, and a footer that counts it is telling the host they are about to
    // play a game they are not.
    await show(tester, [
      offer(const ArenaGame()),
      offer(const HotPotatoGame(), fits: false),
    ]);

    expect(find.text('1 of 2 in the run'), findsNothing);
    expect(
      find.text(
        '1 of 2 in the run · 1 ticked but the wrong size for this table',
      ),
      findsOneWidget,
    );
  });

  testWidgets('tapping a row takes it out of the run', (tester) async {
    await show(tester, [offer(const ArenaGame())]);

    await tester.tap(find.text('Arena'));
    expect(toggles, [('arena', false)]);
  });

  testWidgets('tapping an unticked row puts it back', (tester) async {
    await show(tester, [offer(const ArenaGame(), chosen: false)]);

    await tester.tap(find.text('Arena'));
    expect(toggles, [('arena', true)]);
  });

  testWidgets('a game the table cannot play is greyed but still tickable', (
    tester,
  ) async {
    // Greyed, because the table cannot play it right now. Still tickable,
    // because the list is usually opened while people are still arriving —
    // before anyone has calibrated, *every* row is the wrong size, and a
    // settings screen where nothing can be set is not a settings screen.
    await show(tester, [
      offer(const ArenaGame()),
      offer(const HotPotatoGame(), fits: false),
    ]);

    final playable = tester.widget<Text>(find.text('Arena'));
    final greyed = tester.widget<Text>(find.text('Hot Potato'));
    expect(greyed.style!.color, isNot(playable.style?.color),
        reason: 'a game this table cannot play looked like one it can');

    await tester.tap(find.text('Hot Potato'));
    expect(toggles, [('hotpotato', false)],
        reason: 'a run could not be shaped before the table filled up');
  });

  testWidgets('a game that does not fit says what it needs instead of its '
      'tagline', (tester) async {
    await show(tester, [offer(const HotPotatoGame(), fits: false)]);

    // The requirement is the more useful sentence at that moment, and the
    // smallest table it would take is on the row as well.
    expect(find.textContaining('3'), findsWidgets);
    expect(find.text(const HotPotatoGame().manifest.tagline), findsNothing);
  });

  testWidgets('both ends of the list are one tap each', (tester) async {
    // Twelve taps to play one game is not a choice anybody makes twice.
    await show(tester, [offer(const ArenaGame())]);

    await tester.tap(find.text('None'));
    await tester.tap(find.text('All'));
    expect((alls, nones), (1, 1));
  });

  testWidgets('the gear opens it, and a tick reaches the session', (
    tester,
  ) async {
    // The whole path, because the two halves were built apart: the sheet has to
    // write through to the host, and the host has to redraw the sheet. A copy
    // of the offers taken once when the sheet opened would tick nothing.
    final host = HostSession(name: 'kitchen table', advertise: false);
    addTearDown(host.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () => showGamesSheet(context, host),
            ),
          ),
        ),
      ),
    );

    // Counted from the playlist rather than written out: registering a game is
    // meant to be one import and one list entry, not one import, one list entry
    // and a test to go and fix.
    final total = GameCatalog.playlist.length;

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    expect(find.text('Games in the run'), findsOneWidget);
    expect(find.text('Arena'), findsOneWidget);
    // Nobody has connected, so nothing fits and nothing is in the run — and it
    // says so rather than counting every tick as a game.
    expect(
      find.text(
        '0 of $total in the run · $total ticked but the wrong size for this '
        'table',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Arena'));
    await tester.pumpAndSettle();
    expect(host.chosenGames.map((g) => g.manifest.id),
        isNot(contains('arena')));
    expect(
      find.text(
        '0 of $total in the run · ${total - 1} ticked but the wrong size for '
        'this table',
      ),
      findsOneWidget,
      reason: 'the sheet did not redraw from the session it wrote to',
    );

    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();
    expect(find.text('0 of $total in the run'), findsOneWidget);
    expect(host.chosenGames, isEmpty);
  });
}
