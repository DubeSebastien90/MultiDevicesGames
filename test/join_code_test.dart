import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/arena/arena_game.dart';
import 'package:multiscreen_slingshot/games/subway_skater/subway_skater_game.dart';
import 'package:multiscreen_slingshot/games/dodgeball/dodgeball_game.dart';
import 'package:multiscreen_slingshot/games/flood/flood_game.dart';
import 'package:multiscreen_slingshot/games/hot_potato/hot_potato_game.dart';
import 'package:multiscreen_slingshot/sdk/catalog.dart';
import 'package:multiscreen_slingshot/sdk/contract/game.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/client/client_session.dart';
import 'package:multiscreen_slingshot/sdk/host/host_session.dart';
import 'package:multiscreen_slingshot/sdk/model/device_identity.dart';
import 'package:multiscreen_slingshot/sdk/model/device_metrics.dart';
import 'package:multiscreen_slingshot/sdk/monetization/premium_status.dart';
import 'package:multiscreen_slingshot/sdk/net/discovery.dart';
import 'package:multiscreen_slingshot/sdk/net/host_address.dart';
import 'package:multiscreen_slingshot/sdk/net/loopback_transport.dart';
import 'package:multiscreen_slingshot/sdk/net/websocket_transport.dart';

/// The door policy — currently: there isn't one. The code is still generated
/// and still travels, but the host does not check it, so anyone who can reach
/// the socket becomes a phone. See `JOIN CODE DISABLED` in `host_session.dart`.
DeviceMetrics phone(String label) => DeviceMetrics(
  activePxWidth: 2400,
  activePxHeight: 1080,
  widthMm: 152.4,
  heightMm: 68.58,
  bezelMm: 3,
  devicePixelRatio: 3,
  label: label,
);

Future<void> waitFor(
  String what,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for: $what');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// The empty seats a host is advertising, as a browsing phone would read them.
List<String> beaconSeats(HostSession host) => [
      for (final p in host.phones)
        if (!p.connected && p.deviceId != null)
          DeviceIdentity.fingerprint(p.deviceId!),
    ];

/// A host that has paid, without going near a store.
///
/// Most of this file is about session mechanics — handshakes, playlists,
/// rejoining — and wants the whole catalogue available so it can pick whichever
/// game suits the assertion. A host left at the default is a *free* host, which
/// silently drops every Premium game out of the run and makes `chooseGame` a
/// no-op, so tests written before the paywall existed started failing on
/// arithmetic that had nothing to do with what they were testing.
///
/// The tests that are genuinely about the paywall build their own free host —
/// see 'every game starts ticked'.
class _UnlockedPremiumStatus extends PremiumStatus {
  @override
  bool get isPremium => true;
}

void main() {
  late HostSession host;
  late Uri local;

  setUp(() async {
    host = HostSession(
      name: 'kitchen table',
      advertise: false,
      premium: _UnlockedPremiumStatus(),
    );
    final address = await host.start();
    local = address.replace(host: '127.0.0.1');
  });

  tearDown(() async {
    host.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  ClientSession joiner({String? code, String? deviceId, String? label}) =>
      ClientSession(
        transport: WebSocketTransport(local),
        metrics: phone(label ?? 'joiner'),
        joinCode: code,
        // A real phone always has one, and it is the same every run.
        deviceId: deviceId ?? DeviceIdentity.generate(),
      );

  group('the lobby offers games the table can actually play', () {
    test('nothing is offered before a phone has reported its size', () async {
      // Fresh host, nobody in: every entry is unplayable and the lobby says
      // why once rather than on each row.
      //
      // Counted from the playlist, not written out, so registering a game is
      // still one import and one list entry.
      expect(host.offers, hasLength(GameCatalog.playlist.length));
      expect(host.offers.every((o) => !o.fitsTable), isTrue);
      expect(host.blockedReason, isNotNull);
      expect(host.canStart, isFalse);
    });

    test('one phone unlocks nothing at all', () async {
      final client = joiner(code: host.joinCode);
      await client.connect();
      await waitFor('calibrated',
          () => host.phones.length == 1 && host.phones.single.calibrated);

      // Every game needs two phones or more, so a lone phone can play none of
      // them. The list still shows all of them, greyed, each saying what it
      // needs — a game silently missing tells you nothing.
      final byId = {for (final o in host.offers) o.manifest.id: o};
      expect(host.offers.every((o) => !o.fitsTable), isTrue);
      expect(byId['arena']!.reason, contains('2'));
      expect(byId['hotpotato']!.reason, contains('3'));
      expect(host.canStart, isFalse);

      client.dispose();
    });

    test('picking an ineligible game does nothing', () async {
      final client = joiner(code: host.joinCode);
      final second = joiner(code: host.joinCode);
      await client.connect();
      await second.connect();
      await waitFor('calibrated',
          () => host.phones.length == 2 &&
              host.phones.every((p) => p.calibrated));

      // Hot Potato needs three. The tap is refused rather than starting a
      // round the board could not be laid out for.
      host.startGame(const HotPotatoGame());
      expect(host.phase, HostPhase.lobby);

      host.startGame(const ArenaGame());
      expect(host.phase, HostPhase.placing);
      expect(host.game!.manifest.id, 'arena');

      client.dispose();
      second.dispose();
    });

    test('the two ways to play end in different places', () async {
      final client = joiner(code: host.joinCode);
      final second = joiner(code: host.joinCode);
      await client.connect();
      await second.connect();
      await waitFor('calibrated',
          () => host.phones.length == 2 &&
              host.phones.every((p) => p.calibrated));

      // Play: the never-ending playlist, so a round knows what follows it.
      host.startRound();
      expect(host.mode, RoundMode.playlist);
      expect(host.game!.manifest.id, 'flood');

      host.returnToLobby();
      await waitFor('back', () => client.phase == ClientPhase.lobby);

      // The games list: one round, and nothing queued behind it.
      host.startGame(const ArenaGame());
      expect(host.mode, RoundMode.oneOff);
      expect(host.nextGame, isNull,
          reason: 'a one-off has nothing after it, by construction');

      client.dispose();
      second.dispose();
    });

    test('the playlist ends at the lobby instead of starting over', () async {
      final client = joiner(code: host.joinCode);
      final second = joiner(code: host.joinCode);
      await client.connect();
      await second.connect();
      await waitFor('calibrated',
          () => host.phones.length == 2 &&
              host.phones.every((p) => p.calibrated));

      // Cut the list to one game, so the end of the run arrives immediately
      // and there is something to test about what follows it.
      for (final game in GameCatalog.playlist) {
        host.chooseGame(game, chosen: game.manifest.id == 'flood');
      }

      host.startRound();
      expect(host.game!.manifest.id, 'flood');

      // And nothing follows it. This used to wrap round to the top again and
      // keep going for as long as anyone kept winning.
      expect(host.nextGame, isNull);

      host.returnToLobby();

      // A second Play starts the run from the top rather than from where the
      // last one stopped — which, after a full run, would be past the end.
      expect(host.canStart, isTrue);
      expect(host.upcoming!.manifest.id, 'flood');
      host.startRound();
      expect(host.game!.manifest.id, 'flood');

      client.dispose();
      second.dispose();
    });

    test('returning to the lobby forgets the one-off mode', () async {
      final client = joiner(code: host.joinCode);
      final second = joiner(code: host.joinCode);
      await client.connect();
      await second.connect();
      await waitFor('calibrated',
          () => host.phones.length == 2 &&
              host.phones.every((p) => p.calibrated));

      host.startGame(const ArenaGame());
      expect(host.mode, RoundMode.oneOff);

      // Otherwise a later Play would inherit the one-off ending and stop after
      // a single game.
      host.returnToLobby();
      expect(host.mode, RoundMode.playlist);

      client.dispose();
      second.dispose();
    });

    test('every game starts ticked', () async {
      // The one test in this group that wants a host who has *not* paid: the
      // whole point below is the gap between what is ticked and what a free
      // host would actually play.
      final host = HostSession(name: 'free table', advertise: false);
      addTearDown(host.dispose);

      // The default has to be everything, or a host who never opens the list
      // gets a shorter evening than the one before this existed.
      expect(host.chosenGames, hasLength(GameCatalog.playlist.length));

      // "Chosen" in the offers list means "Play would actually run this",
      // which a locked Premium game never is — this host has not unlocked
      // Premium, so only the free games read as chosen even though every
      // game is ticked underneath.
      final free = GameCatalog.playlist
          .where((g) => g.manifest.tier == GameTier.free)
          .map((g) => g.manifest.id)
          .toSet();
      expect(
        host.offers.where((o) => o.chosen).map((o) => o.manifest.id).toSet(),
        free,
      );
      expect(host.offers.where((o) => o.isLocked), isNotEmpty);

      // Ticked is not the same as in the run, and with nobody connected the
      // difference is the whole list: twelve ticks, no games.
      expect(host.runningOrder, isEmpty);
    });

    test('a ticked game the table cannot play is not in the run', () async {
      final ada = joiner(label: 'Ada');
      final bob = joiner(label: 'Bob');
      await ada.connect();
      await bob.connect();
      await waitFor('calibrated',
          () => host.phones.length == 2 &&
              host.phones.every((p) => p.calibrated));

      // Everything ticked, at a table of two. Ticked is not the same as in the
      // run: Hot Potato needs three, so it stays ticked *and* greyed *and* out
      // of the walk — which is two facts, not one.
      expect(host.chosenGames, hasLength(GameCatalog.playlist.length));
      expect(host.runningOrder.map((g) => g.manifest.id),
          isNot(contains('hotpotato')));
      expect(host.runningOrder, isNotEmpty);

      // And it is the run that Play walks, in the run's own order.
      for (final game in GameCatalog.playlist) {
        host.chooseGame(game, chosen: game.manifest.id == 'flood');
      }
      host.startRound();
      expect(host.game!.manifest.id, 'flood');
      expect(host.nextGame, isNull);

      ada.dispose();
      bob.dispose();
    });

    test('unticking a game takes it out of the run', () async {
      final ada = joiner(label: 'Ada');
      await ada.connect();
      final bob = joiner(label: 'Bob');
      await bob.connect();
      await waitFor('calibrated',
          () => host.phones.length == 2 && host.phones.every((p) => p.calibrated));

      expect(host.upcoming!.manifest.id, 'flood');

      host.chooseGame(const FloodGame(), chosen: false);
      expect(host.upcoming!.manifest.id, 'arena',
          reason: 'Play started the game the host had just removed');
      expect(host.chosenGames.map((g) => g.manifest.id), isNot(contains(
          'flood')));

      // And the row is still in the list, unticked rather than gone: a game you
      // cannot see is a game you cannot put back.
      final byId = {for (final o in host.offers) o.manifest.id: o};
      expect(byId['flood']!.chosen, isFalse);
      expect(byId['flood']!.fitsTable, isTrue,
          reason: 'unticking is not the same fact as not fitting');

      host.chooseGame(const FloodGame(), chosen: true);
      expect(host.upcoming!.manifest.id, 'flood');

      ada.dispose();
      bob.dispose();
    });

    test('the run walks only the ticked games', () async {
      final ada = joiner(label: 'Ada');
      await ada.connect();
      final bob = joiner(label: 'Bob');
      await bob.connect();
      await waitFor('calibrated',
          () => host.phones.length == 2 && host.phones.every((p) => p.calibrated));

      // Leave one game ticked and the run is one game long — which is also
      // what makes it end.
      for (final game in GameCatalog.playlist) {
        host.chooseGame(game, chosen: game.manifest.id == 'arena');
      }

      host.startRound();
      expect(host.game!.manifest.id, 'arena');
      expect(host.nextGame, isNull, reason: 'nothing else was ticked');
      expect(host.runIsOver, isTrue);

      ada.dispose();
      bob.dispose();
    });

    test('a game greyed out at Play stays out when the table shrinks to fit it',
        () async {
      // The bug, exactly as it was hit: tick Arena and Flood at a table of
      // three. Flood wants exactly two, so it is greyed and the lobby says it
      // is not in the run. Then a phone dies mid-Arena — and Flood, which had
      // just been promised as not-happening, played itself.
      //
      // A run is settled when Play is pressed. It may shrink after that; it may
      // not grow.
      final phones = [for (var i = 0; i < 3; i++) joiner(label: 'p$i')];
      for (final c in phones) {
        await c.connect();
      }
      await waitFor('calibrated',
          () => host.phones.length == 3 && host.phones.every((p) => p.calibrated));

      for (final game in GameCatalog.playlist) {
        final id = game.manifest.id;
        host.chooseGame(game, chosen: id == 'arena' || id == 'flood');
      }

      // The premise: Flood cannot be played by three, so it is not in the run,
      // and the lobby is already saying as much.
      expect(const FloodGame().manifest.fits(3), isFalse);
      expect(const FloodGame().manifest.fits(2), isTrue);
      expect(host.runningOrder.map((g) => g.manifest.id), ['arena']);

      host.startRound();
      expect(host.game!.manifest.id, 'arena');

      // A phone dies. Flood now fits the table — and must still not be played.
      phones[2].dispose();
      await waitFor('the host noticed', () => host.phones
          .where((p) => p.connected)
          .length == 2);

      expect(host.nextGame, isNull,
          reason: 'a game the lobby had greyed out queued itself up');
      expect(host.runIsOver, isTrue);
      expect(host.runningOrder.map((g) => g.manifest.id),
          isNot(contains('flood')),
          reason: 'the run grew a game it never had');

      // And the ticks are untouched, so the next run started from this lobby
      // gets Flood back — the table really is the right size for it now.
      host.returnToLobby();
      expect(host.chosenGames.map((g) => g.manifest.id),
          containsAll(<String>['arena', 'flood']));
      expect(host.runningOrder.map((g) => g.manifest.id),
          ['flood', 'arena'],
          reason: 'a fresh run is worked out from the table it starts with');

      phones[0].dispose();
      phones[1].dispose();
    });

    test('an empty list blocks Play and says which problem it is', () async {
      final ada = joiner(label: 'Ada');
      final bert = joiner(label: 'Bert');
      await ada.connect();
      await bert.connect();
      await waitFor('calibrated',
          () => host.phones.length == 2 &&
              host.phones.every((p) => p.calibrated));
      expect(host.canStart, isTrue);

      host.chooseNoGames();
      expect(host.canStart, isFalse);
      expect(host.chosenGames, isEmpty);
      // Not "no game fits one phone" — the table is fine, the list is empty,
      // and the two have different fixes.
      expect(host.blockedReason, contains('ticked'));
      expect(host.blockedReason, isNot(contains('fits')));

      host.chooseAllGames();
      expect(host.canStart, isTrue);
      expect(host.upcoming!.manifest.id, 'flood');

      ada.dispose();
      bert.dispose();
    });

    test('advice never sends you after a game that was unticked', () async {
      final ada = joiner(label: 'Ada');
      final bea = joiner(label: 'Bea');
      await ada.connect();
      await bea.connect();
      await waitFor('calibrated',
          () => host.phones.length == 2 &&
              host.phones.every((p) => p.calibrated));

      // Leave only games that need more phones than are here, so nothing is
      // playable. What the lobby then says has to be about the games still in
      // the run: telling this table to fetch a friend for a game they have
      // just unticked would be sending them after the one thing they removed.
      for (final game in GameCatalog.playlist) {
        host.chooseGame(game, chosen: !game.manifest.fits(2));
      }
      expect(host.canStart, isFalse);
      expect(host.blockedReason, contains('2 phone(s)'));
      expect(host.blockedReason, isNot(contains('Flood')));

      ada.dispose();
      bea.dispose();
    });

    test('a reason is only given when the game itself does not fit', () async {
      final client = joiner(code: host.joinCode);
      final second = joiner(code: host.joinCode);
      await client.connect();
      await second.connect();
      await waitFor('calibrated',
          () => host.phones.length == 2 &&
              host.phones.every((p) => p.calibrated));

      for (final offer in host.offers) {
        // Either it fits and has no complaint, or it does not and says so.
        expect(offer.reason == null, offer.manifest.fits(2));
      }
      client.dispose();
      second.dispose();
    });
  });

  group('a player who drops out keeps their seat', () {
    test('their row stays, marked disconnected', () async {
      final client = joiner(label: 'Ada');
      await client.connect();
      await waitFor('welcomed', () => host.phones.length == 1);
      final seat = host.phones.single.phoneId;

      host.scores.award(seat, 7);
      client.dispose();
      await waitFor('noticed', () => !host.phones.single.connected);

      // Still on the roster, still holding their points — the lobby used to
      // erase them, which is what made a returning player a stranger.
      expect(host.phones, hasLength(1));
      expect(host.phones.single.phoneId, seat);
      expect(host.scores[seat], 7);
    });

    test('coming back takes the same seat, not a second one', () async {
      final adasPhone = DeviceIdentity.generate();
      final first = joiner(deviceId: adasPhone, label: 'Ada');
      await first.connect();
      await waitFor('welcomed', () => host.phones.length == 1);
      final seat = host.phones.single.phoneId;
      host.scores.award(seat, 12);

      first.dispose();
      await waitFor('noticed', () => !host.phones.single.connected);

      final again = joiner(deviceId: adasPhone, label: 'Ada');
      await again.connect();
      await waitFor('back', () => again.phase == ClientPhase.lobby);

      expect(host.phones, hasLength(1), reason: 'they were seated twice');
      expect(again.phoneId, seat, reason: 'they were given a new number');
      expect(host.phones.single.connected, isTrue);
      expect(host.scores[seat], 12, reason: 'their score did not follow them');

      again.dispose();
    });

    test('a phone that has never been here gets a seat of its own', () async {
      final ada = joiner(label: 'Ada');
      await ada.connect();
      await waitFor('welcomed', () => host.phones.length == 1);

      final bob = joiner(label: 'Bob');
      await bob.connect();
      await waitFor('two in', () => host.phones.length == 2);

      expect(host.phones.map((p) => p.phoneId).toSet(), hasLength(2));

      ada.dispose();
      bob.dispose();
    });

    test('a seat still being sat in cannot be claimed', () async {
      // Either a mistake or somebody helping themselves to a stranger's score.
      // Whoever is holding the seat keeps it; the newcomer is just a newcomer.
      final adasPhone = DeviceIdentity.generate();
      final ada = joiner(deviceId: adasPhone, label: 'Ada');
      await ada.connect();
      await waitFor('welcomed', () => host.phones.length == 1);
      final seat = host.phones.single.phoneId;
      host.scores.award(seat, 5);

      final impostor = joiner(deviceId: adasPhone, label: 'Bob');
      await impostor.connect();
      await waitFor('two in', () => host.phones.length == 2);

      expect(impostor.phoneId, isNot(seat));
      expect(host.scores[seat], 5);
      expect(host.phones.where((p) => p.connected), hasLength(2));

      ada.dispose();
      impostor.dispose();
    });

    test('their name and score reach every other phone, not just the host',
        () async {
      // What the table sees is the point. The standings are keyed by phone but
      // read by name, and the label only arrives with a phone's measurements —
      // so without a broadcast at that moment every other screen showed a
      // nameless row for somebody it had already met, and kept showing it after
      // they dropped out. On a joiner that reads as the player having vanished.
      final ada = joiner(label: 'Ada');
      await ada.connect();
      final bob = joiner(label: 'Bob');
      await bob.connect();
      await waitFor('both calibrated',
          () => host.phones.length == 2 && host.phones.every((p) => p.calibrated));
      await waitFor('names reached Ada',
          () => ada.scores.ranked.every((e) => e.label != e.phoneId));

      final bobsSeat = host.phones[1].phoneId;
      host.scores.award(bobsSeat, 6);
      bob.dispose();
      await waitFor('bob gone', () => !host.phones[1].connected);
      await waitFor('Ada was told',
          () => ada.scores.entryFor(bobsSeat)?.total == 6);

      final onAda = ada.scores.entryFor(bobsSeat)!;
      expect(onAda.label, 'Bob', reason: 'still a bare phone number');
      expect(onAda.total, 6, reason: 'their score did not survive the drop');

      ada.dispose();
    });

    test('a round is built from who is here, not who is remembered', () async {
      // The seat that stays behind must not ask for a slice of the board.
      final ada = joiner(label: 'Ada');
      await ada.connect();
      await waitFor('calibrated',
          () => host.phones.length == 1 && host.phones.single.calibrated);

      final bob = joiner(label: 'Bob');
      await bob.connect();
      final cara = joiner(label: 'Cara');
      await cara.connect();
      await waitFor('all calibrated',
          () => host.phones.length == 3 && host.phones.every((p) => p.calibrated));

      bob.dispose();
      await waitFor('bob gone',
          () => host.phones.where((p) => p.connected).length == 2);

      // Two phones left, which is a table — and the host is not blocked by a
      // seat nobody is sitting in.
      expect(host.canStart, isTrue,
          reason: 'an empty seat should not stop the table playing');
      host.startRound();
      expect(host.phase, HostPhase.placing);
      expect(host.layout!.phones, hasLength(2),
          reason: 'the empty seat asked for a slice of the board');

      ada.dispose();
      cara.dispose();
    });
  });

  group('coming back to a round already under way', () {
    /// Two phones in, calibrated, and a round started.
    Future<
        ({
          ClientSession ada,
          ClientSession bob,
          String bobsSeat,
          String bobsPhone,
        })> aRoundInProgress() async {
      final bobsPhone = DeviceIdentity.generate();
      final ada = joiner(label: 'Ada');
      await ada.connect();
      final bob = joiner(deviceId: bobsPhone, label: 'Bob');
      await bob.connect();
      await waitFor('calibrated',
          () => host.phones.length == 2 && host.phones.every((p) => p.calibrated));

      // Subway Skater, and played rather than left on the placement screen: a
      // phone leaving *during* placement re-lays the board, and a game that has
      // not asked to hear about it ends the round. Neither leaves a round to
      // walk back into.
      host.startGame(const SubwaySkaterGame());
      await waitFor('placing', () => host.phase == HostPhase.placing);
      ada.confirmPlacement();
      bob.confirmPlacement();
      await waitFor('playing', () => host.phase == HostPhase.playing);
      return (
        ada: ada,
        bob: bob,
        bobsSeat: host.phones[1].phoneId,
        bobsPhone: bobsPhone,
      );
    }

    test('a phone that was in the game gets its seat and the board back',
        () async {
      final table = await aRoundInProgress();
      table.bob.dispose();
      await waitFor('bob gone', () => !host.phones[1].connected);

      // The door used to be shut the moment a socket opened, before the host
      // knew who was knocking. Somebody whose phone died is not a stranger.
      final again = joiner(deviceId: table.bobsPhone, label: 'Bob');
      await again.connect();
      await waitFor('back in', () => again.phase == ClientPhase.playing);

      expect(again.phoneId, table.bobsSeat, reason: 'a new seat, not his own');
      expect(host.phones, hasLength(2), reason: 'seated twice');
      expect(again.layout, isNotNull,
          reason: 'he came back to a round with no slice of the board');
      expect(again.slices, isNotEmpty,
          reason: 'he cannot see where anybody is');

      table.ada.dispose();
      again.dispose();
    });

    test('a phone nobody has met is still turned away, and told why', () async {
      final table = await aRoundInProgress();

      final stranger = joiner(label: 'Cat');
      await stranger.connect();
      await waitFor('turned away',
          () => stranger.phase == ClientPhase.rejected);

      expect(stranger.message, contains('already started'));
      expect(host.phones, hasLength(2), reason: 'a stranger got a seat');

      table.ada.dispose();
      table.bob.dispose();
      stranger.dispose();
    });

    test('a phone claiming a seat somebody is sitting in is turned away',
        () async {
      final table = await aRoundInProgress();

      // Bob has not gone anywhere, so his seat is not free to claim.
      final impostor = joiner(deviceId: table.bobsPhone, label: 'Cat');
      await impostor.connect();
      await waitFor('turned away',
          () => impostor.phase == ClientPhase.rejected);

      expect(host.phones, hasLength(2));
      expect(host.phones[1].connected, isTrue, reason: 'Bob was evicted');

      table.ada.dispose();
      table.bob.dispose();
      impostor.dispose();
    });

    test('somebody who left before the round is dealt in when they return',
        () async {
      // The board was compiled for the phones that were here, so there was no
      // slice for them. Rather than leave them watching, the table is laid out
      // again with them on it — and everybody confirms afresh, because one more
      // phone moves all the others.
      //
      // Three phones, so that one saying Ready does not start the round on its
      // own and the reset is there to see.
      final bobsPhone = DeviceIdentity.generate();
      final ada = joiner(label: 'Ada');
      await ada.connect();
      final cat = joiner(label: 'Cat');
      await cat.connect();
      final bob = joiner(deviceId: bobsPhone, label: 'Bob');
      await bob.connect();
      await waitFor('calibrated',
          () => host.phones.length == 3 && host.phones.every((p) => p.calibrated));

      bob.dispose();
      await waitFor('bob gone', () => !host.phones[2].connected);

      host.startGame(const ArenaGame());
      await waitFor('placing', () => host.phase == HostPhase.placing);
      expect(host.layout!.phones, hasLength(2));

      ada.confirmPlacement();
      await waitFor('ada ready', () => host.phones.first.confirmed);

      final again = joiner(deviceId: bobsPhone, label: 'Bob');
      await again.connect();
      await waitFor('the board grew', () => host.layout?.phones.length == 3);

      expect(host.phase, HostPhase.placing);
      expect(host.phones.first.confirmed, isFalse,
          reason: 'Ada is still ready for a table that has changed');

      ada.confirmPlacement();
      cat.confirmPlacement();
      again.confirmPlacement();
      await waitFor('playing', () => host.phase == HostPhase.playing);

      ada.dispose();
      cat.dispose();
      again.dispose();
    });

    test('rejoining a round already being played means waiting for the next',
        () async {
      // Mid-play is different: the world is running and the arrangement is on
      // the table in front of people. Nobody is asked to pick their phones up
      // in the middle of it, so a phone with no slice waits.
      final bobsPhone = DeviceIdentity.generate();
      final ada = joiner(label: 'Ada');
      await ada.connect();
      final cara = joiner(label: 'Cara');
      await cara.connect();
      final bob = joiner(deviceId: bobsPhone, label: 'Bob');
      await bob.connect();
      await waitFor('calibrated',
          () => host.phones.length == 3 && host.phones.every((p) => p.calibrated));

      bob.dispose();
      await waitFor('bob gone', () => !host.phones[2].connected);

      host.startGame(const ArenaGame());
      await waitFor('placing', () => host.phase == HostPhase.placing);
      ada.confirmPlacement();
      cara.confirmPlacement();
      await waitFor('playing', () => host.phase == HostPhase.playing);

      final again = joiner(deviceId: bobsPhone, label: 'Bob');
      await again.connect();
      await waitFor('welcomed', () => again.phoneId != null);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(again.layout, isNull,
          reason: 'he was handed a slice of a board he is not on');
      expect(host.phase, HostPhase.playing,
          reason: 'the round was interrupted for him');

      // And told so, on a screen of its own. Waiting is not the lobby: the
      // lobby looks like a table where nothing is happening, and something is
      // happening — everybody else is playing.
      expect(again.phase, ClientPhase.waiting);

      ada.dispose();
      cara.dispose();
      again.dispose();
    });

    test('rejoining at the results screen also waits for the next round',
        () async {
      // The round is over, so there is nothing to be caught up to even though a
      // slice still has this phone's name on it. Handing it the world would put
      // it in a frozen game with no verdict to show.
      final bobsPhone = DeviceIdentity.generate();
      final ada = joiner(label: 'Ada');
      await ada.connect();
      final bob = joiner(deviceId: bobsPhone, label: 'Bob');
      await bob.connect();
      await waitFor('calibrated',
          () => host.phones.length == 2 && host.phones.every((p) => p.calibrated));

      // Ball Bin rather than Arena: Arena asks to hear about players leaving and
      // carries on without them, and this test needs the round to actually end.
      host.startGame(const DodgeballGame());
      await waitFor('placing', () => host.phase == HostPhase.placing);
      ada.confirmPlacement();
      bob.confirmPlacement();
      await waitFor('playing', () => host.phase == HostPhase.playing);

      bob.dispose();
      await waitFor('the round ended', () => host.phase == HostPhase.finished);

      final again = joiner(deviceId: bobsPhone, label: 'Bob');
      await again.connect();
      await waitFor('welcomed', () => again.phoneId != null);
      await waitFor('told to wait', () => again.phase == ClientPhase.waiting);

      expect(again.result, isNull,
          reason: 'a round he was not there for has no verdict for him');

      ada.dispose();
      again.dispose();
    });

    test('the next round deals a waiting phone back in', () async {
      // The whole promise of the screen. Its seat was kept, so the next board is
      // laid out including it and it goes straight to placement.
      final bobsPhone = DeviceIdentity.generate();
      final ada = joiner(label: 'Ada');
      await ada.connect();
      final cara = joiner(label: 'Cara');
      await cara.connect();
      final bob = joiner(deviceId: bobsPhone, label: 'Bob');
      await bob.connect();
      await waitFor('calibrated',
          () => host.phones.length == 3 && host.phones.every((p) => p.calibrated));

      bob.dispose();
      await waitFor('bob gone', () => !host.phones[2].connected);

      host.startGame(const ArenaGame());
      await waitFor('placing', () => host.phase == HostPhase.placing);
      ada.confirmPlacement();
      cara.confirmPlacement();
      await waitFor('playing', () => host.phase == HostPhase.playing);

      final again = joiner(deviceId: bobsPhone, label: 'Bob');
      await again.connect();
      await waitFor('waiting', () => again.phase == ClientPhase.waiting);

      host.returnToLobby();
      await waitFor('back with everyone else',
          () => again.phase == ClientPhase.lobby);

      host.startGame(const DodgeballGame());
      await waitFor('dealt in', () => again.phase == ClientPhase.placing);
      expect(again.layout, isNotNull);

      ada.dispose();
      again.dispose();
    });
  });

  group('a game hears about the table emptying', () {
    /// Two phones, calibrated, and [game] running.
    Future<({ClientSession ada, ClientSession bob, String bobsPhone})>
        aRoundOf(MultiscreenGame game) async {
      final bobsPhone = DeviceIdentity.generate();
      final ada = joiner(label: 'Ada');
      await ada.connect();
      final bob = joiner(deviceId: bobsPhone, label: 'Bob');
      await bob.connect();
      await waitFor('calibrated',
          () => host.phones.length == 2 && host.phones.every((p) => p.calibrated));

      host.startGame(game);
      await waitFor('placing', () => host.phase == HostPhase.placing);
      for (final c in [ada, bob]) {
        c.confirmPlacement();
      }
      await waitFor('playing', () => host.phase == HostPhase.playing);
      return (ada: ada, bob: bob, bobsPhone: bobsPhone);
    }

    test('a game that has not asked ends the round level', () async {
      // Carrying on is a claim only the game can make. Ball Bin has not made
      // it, so rather than let one player finish a round the other was dropped
      // out of, the platform calls it even.
      final table = await aRoundOf(const DodgeballGame());
      table.bob.dispose();
      await waitFor('round called', () => host.phase == HostPhase.finished);

      expect(host.outcome!.kind, OutcomeKind.draw);
      expect(host.outcome!.summary, contains('Bob'));

      table.ada.dispose();
    });

    test('a game that has asked is told, and keeps playing', () async {
      // Subway Skater implements PlayerPresence, so it decides what a missing
      // player means — the line closes up around them and the round carries on.
      final table = await aRoundOf(const SubwaySkaterGame());
      final bobsSeat = host.phones[1].phoneId;

      table.bob.dispose();
      await waitFor('bob gone', () => !host.phones[1].connected);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(host.phase, HostPhase.playing,
          reason: 'the round was ended for a game that can handle this');

      // Read off Ada's phone rather than the host: what matters is that the
      // other screens are told, since that is what takes him out of the line.
      await waitFor('Ada sees the line close up',
          () => !'${table.ada.sharedState['order']}'.contains(bobsSeat));

      // And back again, mid-round.
      final again = joiner(deviceId: table.bobsPhone, label: 'Bob');
      await again.connect();
      await waitFor('back in', () => host.phones[1].connected);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await waitFor('Ada sees him back in the line',
          () => '${table.ada.sharedState['order']}'.contains(bobsSeat));
      expect(again.phoneId, bobsSeat);

      table.ada.dispose();
      again.dispose();
    });
  });

  group('nobody is waited on for a screen they do not have', () {
    test('a phone that rejoins mid-placement is dealt in, not waited on',
        () async {
      // The freeze this replaced: a phone that came back with no slice was
      // counted among those who must confirm, while having no button to press.
      // It is now given a place on the board instead, which answers the same
      // problem the right way round.
      final bobsPhone = DeviceIdentity.generate();
      final ada = joiner(label: 'Ada');
      await ada.connect();
      final cara = joiner(label: 'Cara');
      await cara.connect();
      final bob = joiner(deviceId: bobsPhone, label: 'Bob');
      await bob.connect();
      await waitFor('calibrated',
          () => host.phones.length == 3 && host.phones.every((p) => p.calibrated));

      bob.dispose();
      await waitFor('bob gone', () => !host.phones[2].connected);

      host.startGame(const ArenaGame());
      await waitFor('placing', () => host.phase == HostPhase.placing);

      final again = joiner(deviceId: bobsPhone, label: 'Bob');
      await again.connect();
      await waitFor('bob is on the board',
          () => host.layout?.forPhone(host.phones[1].phoneId) != null);

      ada.confirmPlacement();
      cara.confirmPlacement();
      again.confirmPlacement();
      await waitFor('the round started', () => host.phase == HostPhase.playing);

      ada.dispose();
      cara.dispose();
      again.dispose();
    });

    test('a phone leaving during placement re-lays the table and asks again',
        () async {
      // Their slice becomes a hole: a piece of the world belonging to a screen
      // nobody is holding. So the arrangement is worked out again for whoever
      // is left, and the Ready everybody already gave is thrown away — it was
      // about a table that no longer exists, and their phone has to move.
      final ada = joiner(label: 'Ada');
      await ada.connect();
      final bob = joiner(label: 'Bob');
      await bob.connect();
      final cara = joiner(label: 'Cara');
      await cara.connect();
      await waitFor('calibrated',
          () => host.phones.length == 3 && host.phones.every((p) => p.calibrated));

      host.startGame(const ArenaGame());
      await waitFor('placing', () => host.phase == HostPhase.placing);
      expect(host.layout!.phones, hasLength(3));

      ada.confirmPlacement();
      await waitFor('ada is in place', () => host.phones.first.confirmed);

      bob.dispose();
      await waitFor('the board was re-laid',
          () => host.layout?.phones.length == 2);

      expect(host.phase, HostPhase.placing,
          reason: 'the round started on a board with a hole in it');
      expect(host.phones.first.confirmed, isFalse,
          reason: 'Ada was still counted as ready for the old arrangement');

      // And it starts once everyone left says they are in place on the new one.
      ada.confirmPlacement();
      cara.confirmPlacement();
      await waitFor('playing', () => host.phase == HostPhase.playing);

      ada.dispose();
    });

    test('a table too small for the game carries on down the playlist',
        () async {
      // Hot Potato wants three. With two left the playlist moves along to
      // something two can play, rather than dropping everybody to the lobby:
      // losing a player is a reason to change game, not to stop.
      final phones = [for (var i = 0; i < 3; i++) joiner(label: 'p$i')];
      for (final c in phones) {
        await c.connect();
      }
      await waitFor('calibrated',
          () => host.phones.length == 3 && host.phones.every((p) => p.calibrated));

      host.startGame(const HotPotatoGame());
      await waitFor('placing', () => host.phase == HostPhase.placing);

      phones[2].dispose();
      await waitFor('a different game',
          () => host.game?.manifest.id != 'hotpotato');

      expect(host.phase, HostPhase.placing,
          reason: 'the table was sent back to the lobby');
      expect(host.game!.manifest.fits(2), isTrue);
      expect(host.layout!.phones, hasLength(2));
      expect(host.tableChange?.nextGame, host.game!.manifest.title,
          reason: 'nobody was told what they are about to play');

      phones[0].dispose();
      phones[1].dispose();
    });

    test('and goes back to the menu when nothing further fits', () async {
      // One phone fits nothing at all, so when the table drops to one there is
      // no game left to carry on with. The playlist runs once, so rather than
      // double back the table returns to the lobby — and is told what it would
      // need.
      final ada = joiner(label: 'Ada');
      await ada.connect();
      final bob = joiner(label: 'Bob');
      await bob.connect();
      await waitFor('calibrated',
          () => host.phones.length == 2 && host.phones.every((p) => p.calibrated));

      host.startGame(const DodgeballGame());
      await waitFor('placing', () => host.phase == HostPhase.placing);

      bob.dispose();
      await waitFor('back to the lobby', () => host.phase == HostPhase.lobby);

      expect(host.planError, contains('phone'),
          reason: 'nobody was told what the table would need');
      expect(host.layout, isNull);

      // And said to the table's face, not only in the lobby's small print. A
      // dead end is the one case where nothing carries on, so the screen has to
      // be able to tell the two apart.
      expect(host.tableChange, isNotNull,
          reason: 'the round vanished without a word');
      expect(host.tableChange!.who, contains('left'));
      expect(host.tableChange!.nextGame, isNull);
      expect(host.tableChange!.carriesOn, isFalse);
      await waitFor('ada was told too', () => ada.tableChange != null);
      expect(ada.tableChange!.carriesOn, isFalse);

      // And the way out of it actually leads somewhere. Three separate things
      // were wrong with tapping the button, and all three read as "it does
      // nothing": the message survived, the joiner kept its placement screen,
      // and the lobby it landed on could not start a thing.
      //
      // The button is the score board now, not the lobby: a dead end is the end
      // of the run, and a run that ends owes the table its final standings
      // before dropping everybody back at the games list. Everybody goes there,
      // not only the host — the standings are the table's.
      host.showScoreboard();
      expect(host.phase, HostPhase.scoreboard);
      expect(host.tableChange, isNull, reason: 'the screen would not close');
      await waitFor('ada is looking at the standings too',
          () => ada.phase == ClientPhase.scoreboard && ada.tableChange == null);

      host.returnToLobby();

      // One phone fits nothing, so the lobby is honest about it rather than
      // offering a Play that could not work.
      expect(host.canStart, isFalse);
      expect(host.blockedReason, isNotNull);

      await waitFor('ada came along too',
          () => ada.phase == ClientPhase.lobby && ada.tableChange == null);

      // And the way out really does lead somewhere: the playlist was left past
      // its end, so the moment the table is a table again Play works — from the
      // top, rather than from where the last run stopped.
      final dave = joiner(label: 'Dave');
      await dave.connect();
      await waitFor('a table again',
          () => host.phones.where((p) => p.connected).length == 2 &&
              host.phones.every((p) => p.calibrated));
      expect(host.canStart, isTrue);
      expect(host.upcoming, isNotNull);

      ada.dispose();
      dave.dispose();
    });

    test('every phone is told, not only the host', () async {
      // It was being written down on the host and read by nobody: no screen
      // looked at it, and it never crossed the wire at all. The message that
      // matters most lands while people are staring at the placement screen.
      final phones = [for (var i = 0; i < 3; i++) joiner(label: 'p$i')];
      for (final c in phones) {
        await c.connect();
      }
      await waitFor('calibrated',
          () => host.phones.length == 3 && host.phones.every((p) => p.calibrated));

      host.startGame(const ArenaGame());
      await waitFor('placing', () => host.phase == HostPhase.placing);

      phones[2].dispose();
      // Both, not just the first. Two phones on two sockets are not told in the
      // same instant, and waiting on one then reading the other is a race the
      // test loses whenever the machine is busy.
      await waitFor(
        'the others were told',
        () => phones[0].tableChange != null && phones[1].tableChange != null,
      );

      expect(phones[0].tableChange!.nextGame, isNotNull);
      expect(phones[1].tableChange!.who, phones[0].tableChange!.who,
          reason: 'the table is not reading the same thing');

      // And the host clears it for the room. Six phones each needing their own
      // tap is six chances for one of them to be face-down on the table while
      // the other five wait, so there is one button and it is the host's.
      host.dismissTableChange();
      expect(host.tableChange, isNull);
      await waitFor('the screen left every phone',
          () => phones[0].tableChange == null && phones[1].tableChange == null);

      phones[0].dispose();
      phones[1].dispose();
    });

    test('the notice does not follow the table into the round', () async {
      // Left set, it comes back the next time the board is laid out: whoever
      // dismissed it sees last round's news again, and whoever did not never
      // sees it change.
      final phones = [for (var i = 0; i < 3; i++) joiner(label: 'p$i')];
      for (final c in phones) {
        await c.connect();
      }
      await waitFor('calibrated',
          () => host.phones.length == 3 && host.phones.every((p) => p.calibrated));

      host.startGame(const ArenaGame());
      await waitFor('placing', () => host.phase == HostPhase.placing);

      phones[2].dispose();
      await waitFor('told', () => phones[0].tableChange != null);

      // Everybody left says they are in place, so the round starts.
      for (final c in phones.take(2)) {
        c.confirmPlacement();
      }
      await waitFor('playing', () => host.phase == HostPhase.playing);

      expect(host.tableChange, isNull);
      await waitFor('the phones forgot it too',
          () => phones[0].tableChange == null && phones[1].tableChange == null);

      phones[0].dispose();
      phones[1].dispose();
    });

    test('the table is told even when the game stays the same', () async {
      // The warning is about the *table* changing shape, not the game. Everyone
      // is about to be asked to put their phone somewhere new and the Ready
      // they already gave has been thrown away; saying nothing unless the game
      // changed would leave that looking like the app forgetting itself.
      final phones = [for (var i = 0; i < 3; i++) joiner(label: 'p$i')];
      for (final c in phones) {
        await c.connect();
      }
      await waitFor('calibrated',
          () => host.phones.length == 3 && host.phones.every((p) => p.calibrated));

      host.startGame(const ArenaGame());
      await waitFor('placing', () => host.phase == HostPhase.placing);
      host.dismissTableChange();

      phones[2].dispose();
      await waitFor('re-laid', () => host.layout?.phones.length == 2);

      expect(host.game!.manifest.id, 'arena', reason: 'the game changed');
      expect(host.tableChange, isNotNull,
          reason: 'the table was re-laid without a word');
      expect(host.tableChange!.nextGame, 'Arena');
      expect(host.tableChange!.who, contains('left'));

      phones[0].dispose();
      phones[1].dispose();
    });

    test('a phone leaving during placement re-lays the table and asks again',
        () async {
      // Their slice becomes a hole: a piece of the world belonging to a screen
      // nobody is holding. So the arrangement is worked out again for whoever
      // is left, and the Ready everybody already gave is thrown away — it was
      // about a table that no longer exists, and their phone has to move.
      final ada = joiner(label: 'Ada');
      await ada.connect();
      final bob = joiner(label: 'Bob');
      await bob.connect();
      final cara = joiner(label: 'Cara');
      await cara.connect();
      await waitFor('calibrated',
          () => host.phones.length == 3 && host.phones.every((p) => p.calibrated));

      host.startGame(const ArenaGame());
      await waitFor('placing', () => host.phase == HostPhase.placing);
      expect(host.layout!.phones, hasLength(3));

      ada.confirmPlacement();
      await waitFor('ada is in place', () => host.phones.first.confirmed);

      bob.dispose();
      await waitFor('the board was re-laid',
          () => host.layout?.phones.length == 2);

      expect(host.phase, HostPhase.placing,
          reason: 'the round started on a board with a hole in it');
      expect(host.phones.first.confirmed, isFalse,
          reason: 'Ada was still counted as ready for the old arrangement');

      // And it starts once everyone left says they are in place on the new one.
      ada.confirmPlacement();
      cara.confirmPlacement();
      await waitFor('playing', () => host.phase == HostPhase.playing);

      ada.dispose();
    });

  });

  test('a host has a 5-digit code and a name', () {
    expect(host.joinCode, matches(RegExp(r'^\d{5}$')));
    expect(host.name, 'kitchen table');
    expect(isValidJoinCode(host.joinCode), isTrue);
  });

  test('the right code gets you in', () async {
    final client = joiner(code: host.joinCode);
    await client.connect();

    await waitFor('welcomed', () => client.phase == ClientPhase.lobby);
    expect(client.phoneId, isNotNull);
    expect(client.sessionName, 'kitchen table');
    expect(host.phones.length, 1);

    client.dispose();
  });

  // JOIN CODE DISABLED — the door is open, so what used to be turned away is
  // now let in. These three assert the *current* behaviour; the originals are
  // kept below them, ready to come back with the gate.
  test('with the gate open, the wrong code still gets you in', () async {
    final wrong = host.joinCode == '00000' ? '11111' : '00000';
    final client = joiner(code: wrong);
    await client.connect();

    await waitFor('welcomed', () => client.phase == ClientPhase.lobby);
    expect(client.phoneId, 'p1');
    expect(host.phones.length, 1);

    client.dispose();
  });

  test('with the gate open, no code at all gets you in', () async {
    final client = joiner();
    await client.connect();

    await waitFor('welcomed', () => client.phase == ClientPhase.lobby);
    expect(host.phones.length, 1);

    client.dispose();
  });

  /* JOIN CODE DISABLED — restore these when the gate closes again.
  test('a wrong code is turned away and never becomes a phone', () async {
    final wrong = host.joinCode == '00000' ? '11111' : '00000';
    final client = joiner(code: wrong);
    await client.connect();

    await waitFor('rejected', () => client.phase == ClientPhase.rejected);
    expect(client.message, contains('Wrong code'));
    expect(client.phoneId, isNull);
    expect(host.phones, isEmpty, reason: 'a rejected peer must not hold a slot');

    client.dispose();
  });

  test('no code at all is turned away', () async {
    final client = joiner();
    await client.connect();

    await waitFor('rejected', () => client.phase == ClientPhase.rejected);
    expect(host.phones, isEmpty);

    client.dispose();
  });

  test('a failed attempt does not burn a phone number', () async {
    final wrong = host.joinCode == '00000' ? '11111' : '00000';
    final rejected = joiner(code: wrong);
    await rejected.connect();
    await waitFor('rejected', () => rejected.phase == ClientPhase.rejected);
    rejected.dispose();

    final accepted = joiner(code: host.joinCode);
    await accepted.connect();
    await waitFor('welcomed', () => accepted.phase == ClientPhase.lobby);

    // p1, not p2: the stranger never got a number.
    expect(accepted.phoneId, 'p1');
    accepted.dispose();
  });
  */

  test('the host own screen skips the gate', () async {
    final loopback = LoopbackPair();
    final me = ClientSession(
      transport: loopback.transport,
      metrics: phone('host screen'),
    );
    await me.connect();
    host.addLocalPeer(loopback.peer);

    await waitFor('host is in its own lobby',
        () => me.phase == ClientPhase.lobby);
    expect(host.phones.length, 1);

    me.dispose();
    await loopback.dispose();
  });

  group('the QR carries the code so a scan needs no keypad', () {
    test('address plus code', () {
      final target = parseHostTarget('ws://192.168.1.42:8080#48213');
      expect(target, isNotNull);
      expect(target!.uri.toString(), 'ws://192.168.1.42:8080');
      expect(target.code, '48213');
    });

    test('a bare typed address carries no code', () {
      final target = parseHostTarget('192.168.1.42');
      expect(target!.uri.port, kDefaultPort);
      expect(target.code, isNull);
    });

    test('a junk fragment is not mistaken for a code', () {
      expect(parseHostTarget('ws://192.168.1.42:8080#nope')!.code, isNull);
      expect(parseHostTarget('ws://192.168.1.42:8080#123')!.code, isNull);
    });

    test('nonsense is rejected outright', () {
      expect(parseHostTarget(''), isNull);
      expect(parseHostTarget('http://example.com'), isNull);
    });
  });

  group('the join list knows whose game it is', () {
    test('a fingerprint stands in for a device id without giving it away', () {
      // Broadcast on the network, so it must not be the id itself: reading one
      // off the air would be enough to walk into somebody's seat.
      final id = DeviceIdentity.generate();
      final print = DeviceIdentity.fingerprint(id);

      expect(print, isNot(contains(id)));
      expect(id, isNot(contains(print)));
      // Plain hex, no minus sign: Dart's ints are signed, and a 64-bit mask
      // is -1 rather than the no-op it resembles.
      expect(print, matches(RegExp(r'^[0-9a-f]{8}$')));
      expect(DeviceIdentity.fingerprint(id), print, reason: 'not stable');

      final others = {
        for (var i = 0; i < 400; i++)
          DeviceIdentity.fingerprint(DeviceIdentity.generate()),
      };
      expect(others, hasLength(400), reason: 'two devices looked alike');
    });

    test('a started game advertises the seats sitting empty', () async {
      final bobsPhone = DeviceIdentity.generate();
      final ada = joiner(label: 'Ada');
      await ada.connect();
      final bob = joiner(deviceId: bobsPhone, label: 'Bob');
      await bob.connect();
      await waitFor('calibrated',
          () => host.phones.length == 2 && host.phones.every((p) => p.calibrated));

      host.startGame(const DodgeballGame());
      await waitFor('placing', () => host.phase == HostPhase.placing);
      bob.dispose();
      await waitFor('bob gone', () => !host.phones[1].connected);

      // What a phone browsing the list would receive.
      final seats = beaconSeats(host);
      expect(seats, contains(DeviceIdentity.fingerprint(bobsPhone)),
          reason: 'Bob cannot see that the game is still his');
      expect(seats,
          isNot(contains(DeviceIdentity.fingerprint(DeviceIdentity.generate()))),
          reason: 'a stranger is being offered a seat');

      ada.dispose();
    });

    test('a beacon carrying junk seats is not trusted', () {
      // It arrives from an unauthenticated stranger and goes straight into a
      // comparison, so anything that is not plain hex is dropped.
      final parsed = GameBeacon.tryParse(
        '{"app":"mss1","id":"x","name":"g","ws":"ws://10.0.0.1:8080",'
                '"players":1,"open":false,'
                '"rejoin":["abc123",42,"NOT HEX","../../etc",null]}'
            .codeUnits,
      );
      expect(parsed!.rejoinable, ['abc123']);
    });
  });

  group('beacons', () {
    test('round-trip through the wire format', () {
      final beacon = GameBeacon(
        id: 'abc',
        name: 'kitchen table',
        uri: Uri.parse('ws://192.168.1.42:8080'),
        players: 2,
        open: true,
        seenAt: DateTime.now(),
      );

      final parsed =
          GameBeacon.tryParse(utf8.encode(jsonEncode(beacon.toJson())));

      expect(parsed, isNotNull);
      expect(parsed!.id, 'abc');
      expect(parsed.name, 'kitchen table');
      expect(parsed.uri, Uri.parse('ws://192.168.1.42:8080'));
      expect(parsed.players, 2);
      expect(parsed.open, isTrue);
    });

    test('a beacon never carries the join code', () {
      final host2 = HostSession(name: 'x', advertise: false);
      final json = jsonEncode(GameBeacon(
        id: 'abc',
        name: host2.name,
        uri: Uri.parse('ws://192.168.1.42:8080'),
        players: 1,
        open: true,
        seenAt: DateTime.now(),
      ).toJson());
      expect(json, isNot(contains(host2.joinCode)));
      host2.dispose();
    });

    test('a hostile name cannot draw newlines into the list', () {
      final parsed = GameBeacon.tryParse(
        '{"app":"mss1","id":"x","name":"evil\\nlist\\ninjection",'
                '"ws":"ws://10.0.0.1:8080","players":1,"open":true}'
            .codeUnits,
      );
      expect(parsed!.name, 'evil list injection');
    });

    test('junk on the port is ignored', () {
      expect(GameBeacon.tryParse('hello'.codeUnits), isNull);
      expect(GameBeacon.tryParse('{"app":"other"}'.codeUnits), isNull);
      expect(
        GameBeacon.tryParse('{"app":"mss1","id":"x","ws":"nope"}'.codeUnits),
        isNull,
      );
    });
  });
}
