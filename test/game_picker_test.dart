import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
        body: GamePicker(
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
  );

  /// A game on the list. Its icon stands where its title was, and carries the
  /// title as its label — which is what a screen reader says, and what these
  /// tests look it up by.
  Finder game(String title) => find.byWidgetPredicate(
    (widget) => widget is SvgPicture && widget.semanticsLabel == title,
  );

  /// The cell a game sits in: its icon and the marks on it, as one widget.
  Finder rowOf(String title) => find
      .ancestor(of: game(title), matching: find.byType(GestureDetector))
      .first;

  /// Whether that row is ticked. Asked of the row rather than of the screen,
  /// because the list is lazy — off-screen rows are not built, which is the
  /// point of it — so counting ticks across the whole list counts the ones
  /// that happen to be on screen.
  bool ticked(String title) => find
      .descendant(of: rowOf(title), matching: find.byIcon(Icons.check))
      .evaluate()
      .isNotEmpty;

  /// How brightly a game's icon is drawn. Full colour is in the run, faded is
  /// not, and that pair replaced the tally the sheet used to print under the
  /// rows — and then the green plates that replaced the tally.
  double fadeOf(WidgetTester tester, String title) => tester
      .widget<AnimatedOpacity>(
        find.ancestor(of: game(title), matching: find.byType(AnimatedOpacity)),
      )
      .opacity;

  bool lit(WidgetTester tester, String title) => fadeOf(tester, title) == 1;

  testWidgets('every game is listed with its tick', (tester) async {
    await show(tester, [
      offer(const ArenaGame()),
      offer(const DodgeballGame(), chosen: false),
    ]);

    expect(game('Arena'), findsOneWidget);
    expect(game('Dodgeball'), findsOneWidget);

    // One tick, for the one game that is in the run.
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(lit(tester, 'Arena'), isTrue);
    expect(lit(tester, 'Dodgeball'), isFalse);
  });

  testWidgets('a ticked game the table cannot play does not look like one it '
      'can', (tester) async {
    // Ticked is not the same as in the run. Flood is ticked and will not be
    // played tonight, and an icon as bright as Arena's would be telling the
    // host they are about to play a game they are not. The sheet used to
    // correct that in a footer; now the icon simply does not make the claim.
    await show(tester, [
      offer(const ArenaGame()),
      offer(const FloodGame(), fits: false),
    ]);

    expect(lit(tester, 'Arena'), isTrue);
    expect(lit(tester, 'Flood'), isFalse);
    expect(ticked('Flood'), isTrue);
  });

  testWidgets('tapping a row takes it out of the run', (tester) async {
    await show(tester, [offer(const ArenaGame())]);

    await tester.tap(game('Arena'));
    expect(toggles, [('arena', false)]);
  });

  testWidgets('tapping an unticked row puts it back', (tester) async {
    await show(tester, [offer(const ArenaGame(), chosen: false)]);

    await tester.tap(game('Arena'));
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

    expect(
      fadeOf(tester, 'Flood'),
      lessThan(fadeOf(tester, 'Arena')),
      reason: 'a game this table cannot play looked like one it can',
    );

    await tester.tap(game('Flood'));
    expect(toggles, [
      ('flood', false),
    ], reason: 'a run could not be shaped before the table filled up');
  });

  testWidgets('a game that does not fit says how many phones it needs', (
    tester,
  ) async {
    await show(tester, [offer(const FloodGame(), fits: false)]);

    // The smallest table it would take, under the icon — and nothing else:
    // the grid is pictures, not a page of taglines.
    expect(
      find.textContaining(const FloodGame().manifest.smallestTable.toString()),
      findsWidgets,
    );
    expect(find.text(const FloodGame().manifest.tagline), findsNothing);
  });

  testWidgets("a game played in pairs shows two people next to its phone count, until it fits", (
    tester,
  ) async {
    bool team(String title) => find
        .descendant(of: rowOf(title), matching: find.byIcon(Icons.people))
        .evaluate()
        .isNotEmpty;

    await show(tester, [
      offer(const FloodGame(), fits: false),
      offer(const ArenaGame(), fits: false),
    ]);
    expect(team(const FloodGame().manifest.title), isTrue);
    expect(team(const ArenaGame().manifest.title), isFalse);

    // Gone with the phone count once the table can play it.
    await show(tester, [offer(const FloodGame())]);
    expect(team(const FloodGame().manifest.title), isFalse);
  });

  test("only the even-table games are marked as played in pairs", () {
    final pairs = [
      for (final game in GameCatalog.playlist)
        if (game.manifest.players.pairsOnly) game.manifest.id,
    ];
    expect(pairs, unorderedEquals(['flood', 'hungryhippos', 'copsrobbers']));
  });

  testWidgets('a locked Premium game has no checkbox and opens the paywall '
      'on tap', (tester) async {
    var lockedTaps = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GamePicker(
            offers: [
              offer(const ArenaGame()),
              offer(const HotPotatoGame(), locked: true),
            ],
            onChoose: (game, chosen) => toggles.add((game.manifest.id, chosen)),
            onLockedTap: (offer) => lockedTaps.add(offer.manifest.id),
          ),
        ),
      ),
    );

    expect(game('Hot Potato'), findsOneWidget);
    expect(find.text('PREMIUM'), findsOneWidget);
    // One tick only — Arena's. A locked row has nothing to tick, and shows a
    // padlock where the ring would be.
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);

    await tester.tap(game('Hot Potato'));
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

    // The padlock means Premium: a free game keeps its tick even when the
    // host cannot change the selection.
    expect(find.byIcon(Icons.lock_outline), findsNothing);
    expect(find.text('Tap a game to add it'), findsNothing);

    await tester.tap(game('Arena'));
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

      // Nor is it offered as tickable, which would be the opposite lie: the
      // one tick on screen is Flood's.
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.text('Checking your purchase…'), findsOneWidget);

      // The rest of the list still works while one game waits: Flood keeps its
      // colour, its tick and its tap.
      expect(lit(tester, 'Flood'), isTrue);
      await tester.tap(game('Flood'));
      expect(toggles, [('flood', false)]);
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
    testWidgets('it says so, instead of letting padlocks speak', (
      tester,
    ) async {
      await show(tester, [
        offer(const HotPotatoGame(), locked: true),
      ], premiumError: 'PlatformException(23, no connection, null, null)');

      expect(
        find.textContaining('Could not check your purchase'),
        findsOneWidget,
      );
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

  testWidgets('the gear opens the screen, and a tick reaches the session', (
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
              onPressed: () => showGamesScreen(context, host, premium),
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
    expect(game('Arena'), findsOneWidget);
    // Nobody has connected, so nothing fits: every game is ticked and none of
    // them is in the run, which is a screen of faded icons rather than bright
    // ones.
    expect(ticked('Arena'), isTrue);
    expect(lit(tester, 'Arena'), isFalse);
    expect(host.chosenGames.length, total);

    await tester.tap(game('Arena'));
    await tester.pumpAndSettle();
    expect(host.chosenGames.length, total - 1);
    expect(
      ticked('Arena'),
      isFalse,
      reason: 'the screen did not redraw from the session it wrote to',
    );

    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();
    expect(ticked('Arena'), isFalse);
    expect(host.chosenGames, isEmpty);
  });
}
