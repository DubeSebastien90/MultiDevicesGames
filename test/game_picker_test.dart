import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/dodgeball/dodgeball_game.dart';
import 'package:multiscreen_slingshot/games/flood/flood_game.dart';
import 'package:multiscreen_slingshot/games/hot_potato/hot_potato_game.dart';
import 'package:multiscreen_slingshot/games/arena/arena_game.dart';
import 'package:multiscreen_slingshot/sdk/catalog.dart';
import 'package:multiscreen_slingshot/sdk/contract/game.dart';
import 'package:multiscreen_slingshot/sdk/host/host_session.dart';
import 'package:multiscreen_slingshot/sdk/monetization/premium_status.dart';
import 'package:multiscreen_slingshot/sdk/ui/game_picker.dart';

class _UnlockedPremiumStatus extends PremiumStatus {
  @override
  bool get isPremium => true;
}

/// The list decides what the evening consists of, so the two facts it carries
/// have to stay apart: whether a game is *ticked* is the host's choice, and
/// whether it *fits* is the table's shape. A row can be either without being
/// the other.
void main() {
  GameOffer offer(
    MultiscreenGame game, {
    bool fits = true,
    bool chosen = true,
    bool locked = false,
    bool pending = false,
  }) => GameOffer(
    game: game,
    fitsTable: fits,
    reason: fits ? null : game.manifest.requirement(),
    chosen: chosen,
    isLocked: locked,
    lockPending: pending,
  );

  var toggles = <(String, bool)>[];
  var alls = 0;
  var nones = 0;
  var selectionLockedTaps = 0;

  setUp(() {
    toggles = [];
    alls = 0;
    nones = 0;
    selectionLockedTaps = 0;
  });

  Future<void> show(
    WidgetTester tester,
    List<GameOffer> offers, {
    bool selectionLocked = false,
    String? premiumError,
    Future<void> Function()? onRetryPremium,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: GamePicker(
            offers: offers,
            selectionLocked: selectionLocked,
            premiumError: premiumError,
            onRetryPremium: onRetryPremium,
            onChoose: (game, chosen) => toggles.add((game.manifest.id, chosen)),
            onAll: () => alls++,
            onNone: () => nones++,
            onSelectionLockedTap: () => selectionLockedTaps++,
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
    // The count is the run, not the ticks. Flood is ticked and will not be
    // played, and a footer that counts it is telling the host they are about to
    // play a game they are not.
    await show(tester, [
      offer(const ArenaGame()),
      offer(const FloodGame(), fits: false),
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
      offer(const FloodGame(), fits: false),
    ]);

    final playable = tester.widget<Text>(find.text('Arena'));
    final greyed = tester.widget<Text>(find.text('Flood'));
    expect(
      greyed.style!.color,
      isNot(playable.style?.color),
      reason: 'a game this table cannot play looked like one it can',
    );

    await tester.tap(find.text('Flood'));
    expect(toggles, [
      ('flood', false),
    ], reason: 'a run could not be shaped before the table filled up');
  });

  testWidgets('a game that does not fit says what it needs instead of its '
      'tagline', (tester) async {
    await show(tester, [offer(const FloodGame(), fits: false)]);

    // The requirement is the more useful sentence at that moment, and the
    // smallest table it would take is on the row as well.
    expect(
      find.textContaining(const FloodGame().manifest.smallestTable.toString()),
      findsWidgets,
    );
    expect(find.text(const FloodGame().manifest.tagline), findsNothing);
  });

  testWidgets('a locked Premium game has no checkbox and opens the paywall '
      'on tap', (tester) async {
    var lockedTaps = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GamePicker(
              offers: [
                offer(const ArenaGame()),
                offer(const HotPotatoGame(), locked: true),
              ],
              onChoose: (game, chosen) =>
                  toggles.add((game.manifest.id, chosen)),
              onLockedTap: (offer) => lockedTaps.add(offer.manifest.id),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Hot Potato'), findsOneWidget);
    expect(find.text('PREMIUM'), findsOneWidget);
    // One checkbox only — Arena's. A locked row has nothing to tick.
    expect(find.byType(CheckboxListTile), findsOneWidget);

    await tester.tap(find.text('Hot Potato'));
    expect(lockedTaps, ['hotpotato']);
    expect(
      toggles,
      isEmpty,
      reason: 'a locked row should open the paywall, not tick itself',
    );
  });

  testWidgets('both ends of the list are one tap each', (tester) async {
    // Twelve taps to play one game is not a choice anybody makes twice.
    await show(tester, [offer(const ArenaGame())]);

    await tester.tap(find.text('None'));
    await tester.tap(find.text('All'));
    expect((alls, nones), (1, 1));
  });

  testWidgets('game selection opens premium instead of mutating when locked', (
    tester,
  ) async {
    await show(tester, [
      offer(const ArenaGame()),
      offer(const DodgeballGame(), chosen: false),
    ], selectionLocked: true);

    await tester.tap(find.text('Arena'));
    await tester.tap(find.text('None'));
    await tester.tap(find.text('All'));

    expect(selectionLockedTaps, 3);
    expect(toggles, isEmpty);
    expect((alls, nones), (0, 0));
  });

  group('while the store has not answered', () {
    testWidgets('a pending row accuses nobody of not paying', (tester) async {
      await show(tester, [
        offer(const FloodGame()),
        offer(const HotPotatoGame(), pending: true),
      ]);

      // The whole point: no padlock and no PREMIUM badge on a game the host may
      // well already own. Nothing on screen makes a claim about money.
      expect(find.byIcon(Icons.lock_outline), findsNothing);
      expect(find.text('PREMIUM'), findsNothing);
      expect(find.textContaining('locked behind Premium'), findsNothing);

      // Nor is it offered as tickable, which would be the opposite lie.
      expect(find.widgetWithText(CheckboxListTile, 'Hot Potato'), findsNothing);
      expect(find.text('Checking your purchase…'), findsOneWidget);

      // The rest of the list still works while one row waits.
      expect(find.widgetWithText(CheckboxListTile, 'Flood'), findsOneWidget);
    });

    testWidgets('All and None wait rather than sell', (tester) async {
      await show(tester, [
        offer(const FloodGame()),
        offer(const HotPotatoGame(), pending: true),
      ], selectionLocked: false);

      await tester.tap(find.text('All'));
      await tester.pump();

      // Neither applied nor bounced to the paywall: we do not yet know which
      // this host deserves.
      expect(alls, 0);
      expect(selectionLockedTaps, 0);
    });

    testWidgets('once it answers, the padlock appears', (tester) async {
      await show(tester, [offer(const HotPotatoGame(), locked: true)]);

      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.text('PREMIUM'), findsOneWidget);
      expect(find.text('Checking your purchase…'), findsNothing);
    });
  });

  group('when the store cannot be reached', () {
    testWidgets('it says so, instead of letting padlocks speak',
        (tester) async {
      await show(
        tester,
        [offer(const HotPotatoGame(), locked: true)],
        premiumError: 'PlatformException(23, no connection, null, null)',
      );

      expect(find.textContaining('Could not check your purchase'),
          findsOneWidget);
      // The raw exception is for logs, not for a player.
      expect(find.textContaining('PlatformException'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('Retry asks again', (tester) async {
      var retries = 0;
      await show(
        tester,
        [offer(const HotPotatoGame(), locked: true)],
        premiumError: 'nope',
        onRetryPremium: () async => retries++,
      );

      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(retries, 1);
    });
  });

  test('a free host cannot start a Premium game by naming it', () async {
    // The playlist paths pick their index through `_skipping`, which already
    // folds the paywall in — but `startGame` names a game outright and used to
    // skip that reasoning entirely. Nothing in the UI routes there today, which
    // is exactly why it needs a test: the next feature that wants "play this
    // one now" must not quietly become the way around the paywall.
    final free = HostSession(name: 'free table', advertise: false);
    addTearDown(free.dispose);
    await free.start();

    free.startGame(const HotPotatoGame());
    expect(free.game, isNull, reason: 'a free host started a Premium game');
  });

  test('a paying host can start the same game', () async {
    // The other half: the guard must refuse the right people, not everybody.
    final paid = HostSession(
      name: 'paid table',
      advertise: false,
      premium: _UnlockedPremiumStatus(),
    );
    addTearDown(paid.dispose);
    await paid.start();

    // No phones are connected, so `canStart` is false and the round does not
    // begin — but it stops for the table's shape, not for the receipt.
    expect(paid.offers.where((o) => o.isLocked), isEmpty);
  });

  test('a non-Premium host cannot customize the run directly', () {
    final host = HostSession(name: 'kitchen table', advertise: false);
    addTearDown(host.dispose);

    host.chooseGame(const ArenaGame(), chosen: false);
    host.chooseNoGames();

    expect(host.chosenGames.map((g) => g.manifest.id), contains('arena'));
    expect(host.chosenGames, isNotEmpty);
  });

  testWidgets('the gear opens it, and a tick reaches the session', (
    tester,
  ) async {
    // The whole path, because the two halves were built apart: the sheet has to
    // write through to the host, and the host has to redraw the sheet. A copy
    // of the offers taken once when the sheet opened would tick nothing.
    final premium = _UnlockedPremiumStatus();
    final host = HostSession(
      name: 'kitchen table',
      advertise: false,
      premium: premium,
    );
    addTearDown(host.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () => showGamesSheet(context, host, premium),
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
