import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/arena/arena_game.dart';
import 'package:multiscreen_slingshot/games/ball_bin/ball_bin_game.dart';
import 'package:multiscreen_slingshot/games/hot_potato/hot_potato_game.dart';
import 'package:multiscreen_slingshot/games/slingshot/slingshot_game.dart';
import 'package:multiscreen_slingshot/sdk/catalog.dart';
import 'package:multiscreen_slingshot/sdk/contract/game.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/client/client_session.dart';
import 'package:multiscreen_slingshot/sdk/host/host_session.dart';
import 'package:multiscreen_slingshot/sdk/model/device_identity.dart';
import 'package:multiscreen_slingshot/sdk/model/device_metrics.dart';
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

void main() {
  late HostSession host;
  late Uri local;

  setUp(() async {
    host = HostSession(name: 'kitchen table', advertise: false);
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
      expect(host.offers.every((o) => !o.playable), isTrue);
      expect(host.blockedReason, isNotNull);
      expect(host.canStart, isFalse);
    });

    test('one phone unlocks the one-phone game and no other', () async {
      final client = joiner(code: host.joinCode);
      await client.connect();
      await waitFor('calibrated',
          () => host.phones.length == 1 && host.phones.single.calibrated);

      final byId = {for (final o in host.offers) o.manifest.id: o};
      expect(byId['slingshot']!.playable, isTrue);
      expect(byId['slingshot']!.reason, isNull);

      // The others stay in the list, greyed, saying what they need — a game
      // silently missing tells you nothing.
      expect(byId['ballbin']!.playable, isFalse);
      expect(byId['ballbin']!.reason, contains('2'));
      expect(byId['hotpotato']!.playable, isFalse);
      expect(byId['hotpotato']!.reason, contains('3'));

      client.dispose();
    });

    test('picking an ineligible game does nothing', () async {
      final client = joiner(code: host.joinCode);
      await client.connect();
      await waitFor('calibrated',
          () => host.phones.length == 1 && host.phones.single.calibrated);

      // Hot Potato needs three. The tap is refused rather than starting a
      // round the board could not be laid out for.
      host.startGame(const HotPotatoGame());
      expect(host.phase, HostPhase.lobby);

      host.startGame(const SlingshotGame());
      expect(host.phase, HostPhase.placing);
      expect(host.game!.manifest.id, 'slingshot');

      client.dispose();
    });

    test('the two ways to play end in different places', () async {
      final client = joiner(code: host.joinCode);
      await client.connect();
      await waitFor('calibrated',
          () => host.phones.length == 1 && host.phones.single.calibrated);

      // Play: the never-ending playlist, so a round knows what follows it.
      host.startRound();
      expect(host.mode, RoundMode.playlist);
      expect(host.game!.manifest.id, 'slingshot');

      host.returnToLobby();
      await waitFor('back', () => client.phase == ClientPhase.lobby);

      // The games list: one round, and nothing queued behind it.
      host.startGame(const SlingshotGame());
      expect(host.mode, RoundMode.oneOff);
      expect(host.nextGame, isNull,
          reason: 'a one-off has nothing after it, by construction');

      client.dispose();
    });

    test('the playlist ends at the lobby instead of starting over', () async {
      final client = joiner(code: host.joinCode);
      await client.connect();
      await waitFor('calibrated',
          () => host.phones.length == 1 && host.phones.single.calibrated);

      // One phone plays exactly one game: Slingshot, first in the list.
      host.startRound();
      expect(host.game!.manifest.id, 'slingshot');

      // And nothing follows it. This used to wrap round to Slingshot again and
      // keep going for as long as anyone kept winning.
      expect(host.nextGame, isNull);

      host.returnToLobby();

      // A second Play starts the run from the top rather than from where the
      // last one stopped — which, after a full run, would be past the end.
      expect(host.canStart, isTrue);
      expect(host.upcoming!.manifest.id, 'slingshot');
      host.startRound();
      expect(host.game!.manifest.id, 'slingshot');

      client.dispose();
    });

    test('returning to the lobby forgets the one-off mode', () async {
      final client = joiner(code: host.joinCode);
      await client.connect();
      await waitFor('calibrated',
          () => host.phones.length == 1 && host.phones.single.calibrated);

      host.startGame(const SlingshotGame());
      expect(host.mode, RoundMode.oneOff);

      // Otherwise a later Play would inherit the one-off ending and stop after
      // a single game.
      host.returnToLobby();
      expect(host.mode, RoundMode.playlist);

      client.dispose();
    });

    test('a reason is only given when the game itself does not fit', () async {
      final client = joiner(code: host.joinCode);
      await client.connect();
      await waitFor('calibrated',
          () => host.phones.length == 1 && host.phones.single.calibrated);

      for (final offer in host.offers) {
        // Either it fits and has no complaint, or it does not and says so.
        expect(offer.reason == null, offer.manifest.fits(1));
      }
      client.dispose();
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
      await waitFor('both calibrated',
          () => host.phones.length == 2 && host.phones.every((p) => p.calibrated));

      bob.dispose();
      await waitFor('bob gone',
          () => host.phones.where((p) => p.connected).length == 1);

      // One phone left, so the one-phone game is what fits — and the host is
      // not blocked by a seat nobody is sitting in.
      expect(host.canStart, isTrue,
          reason: 'an empty seat should not stop the table playing');
      host.startRound();
      expect(host.phase, HostPhase.placing);
      expect(host.layout!.phones, hasLength(1));

      ada.dispose();
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

      host.startGame(const BallBinGame());
      await waitFor('placing', () => host.phase == HostPhase.placing);
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
      await waitFor('back in', () => again.phase == ClientPhase.placing);

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

    test('somebody who left before the round started waits for the next one',
        () async {
      // There is no slice for them: the board was laid out for the phones that
      // were there. Better to wait in the lobby than to be handed a screen with
      // nothing on it.
      final bobsPhone = DeviceIdentity.generate();
      final ada = joiner(label: 'Ada');
      await ada.connect();
      final bob = joiner(deviceId: bobsPhone, label: 'Bob');
      await bob.connect();
      await waitFor('calibrated',
          () => host.phones.length == 2 && host.phones.every((p) => p.calibrated));
      final bobsSeat = host.phones[1].phoneId;

      bob.dispose();
      await waitFor('bob gone', () => !host.phones[1].connected);

      host.startRound();
      await waitFor('placing', () => host.phase == HostPhase.placing);
      expect(host.layout!.phones, hasLength(1),
          reason: 'the board was built for a phone that is not here');

      final again = joiner(deviceId: bobsPhone, label: 'Bob');
      await again.connect();
      await waitFor('welcomed', () => again.phoneId != null);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(again.phoneId, bobsSeat, reason: 'he lost his seat');
      expect(again.layout, isNull,
          reason: 'he was handed a slice of a board he is not on');

      ada.dispose();
      again.dispose();
    });
  });

  group('a device knows its own name', () {
    test('two phones never think of the same one', () {
      final ids = {for (var i = 0; i < 500; i++) DeviceIdentity.generate()};
      expect(ids, hasLength(500));
    });

    test('it is long enough that nobody guesses it', () {
      // The whole reason a seat is matched on this rather than on the phone
      // number the host hands out: `p2` can be typed by anyone.
      final id = DeviceIdentity.generate();
      expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('a seat cannot be taken by guessing the phone number', () async {
      // The hole the device id closes. `p1` is short, published in every lobby
      // broadcast, and reused by the next player to join.
      final ada = joiner(label: 'Ada');
      await ada.connect();
      await waitFor('welcomed', () => host.phones.length == 1);
      final seat = host.phones.single.phoneId;
      host.scores.award(seat, 9);

      ada.dispose();
      await waitFor('ada gone', () => !host.phones.single.connected);

      // Somebody who knows the seat number but is not that phone.
      final guesser = joiner(deviceId: seat, label: 'Cat');
      await guesser.connect();
      await waitFor('seated', () => guesser.phoneId != null);

      expect(guesser.phoneId, isNot(seat), reason: 'the seat was guessed into');
      expect(host.scores[seat], 9, reason: 'somebody took over their score');

      guesser.dispose();
    });

    test('a phone with no name at all is simply a newcomer', () async {
      // An older build, or the very first run before storage answers.
      final anonymous = ClientSession(
        transport: WebSocketTransport(local),
        metrics: phone('Ada'),
      );
      await anonymous.connect();
      await waitFor('welcomed', () => anonymous.phase == ClientPhase.lobby);
      expect(host.phones, hasLength(1));

      anonymous.dispose();
      await waitFor('gone', () => !host.phones.single.connected);

      final second = ClientSession(
        transport: WebSocketTransport(local),
        metrics: phone('Ada'),
      );
      await second.connect();
      await waitFor('welcomed again', () => second.phase == ClientPhase.lobby);

      // Nameless phones cannot be told apart, so they get a seat each rather
      // than the first empty one they find.
      expect(host.phones, hasLength(2));
      second.dispose();
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
      final table = await aRoundOf(const BallBinGame());
      table.bob.dispose();
      await waitFor('round called', () => host.phase == HostPhase.finished);

      expect(host.outcome!.kind, OutcomeKind.draw);
      expect(host.outcome!.summary, contains('Bob'));

      table.ada.dispose();
    });

    test('a game that has asked is told, and keeps playing', () async {
      // Arena implements PlayerPresence, so it decides what a missing player
      // means — the round carries on with their fighter left standing.
      final table = await aRoundOf(const ArenaGame());
      final bobsSeat = host.phones[1].phoneId;

      table.bob.dispose();
      await waitFor('bob gone', () => !host.phones[1].connected);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(host.phase, HostPhase.playing,
          reason: 'the round was ended for a game that can handle this');

      // Read off Ada's phone rather than the host: what matters is that the
      // other screens are told, since that is what greys the fighter out.
      await waitFor('Ada sees him greyed',
          () => table.ada.sharedState['away_p1'] == true);

      // And back again, mid-round.
      final again = joiner(deviceId: table.bobsPhone, label: 'Bob');
      await again.connect();
      await waitFor('back in', () => host.phones[1].connected);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await waitFor('Ada sees him back',
          () => table.ada.sharedState['away_p1'] == false);
      expect(again.phoneId, bobsSeat);

      table.ada.dispose();
      again.dispose();
    });
  });

  group('nobody is waited on for a screen they do not have', () {
    test('a phone that rejoins mid-placement does not stall the round',
        () async {
      // The freeze. Bob drops out before the round is laid out, so the board is
      // built for Ada alone. He comes back while she is on the placement
      // screen — connected again, but with no slice and so no button to press.
      // Counting him left the table waiting for a confirmation that could
      // never arrive.
      final bobsPhone = DeviceIdentity.generate();
      final ada = joiner(label: 'Ada');
      await ada.connect();
      final bob = joiner(deviceId: bobsPhone, label: 'Bob');
      await bob.connect();
      await waitFor('calibrated',
          () => host.phones.length == 2 && host.phones.every((p) => p.calibrated));

      bob.dispose();
      await waitFor('bob gone', () => !host.phones[1].connected);

      // A game one phone can play, since Bob is not here to make up a pair.
      host.startGame(const SlingshotGame());
      await waitFor('placing', () => host.phase == HostPhase.placing);
      expect(host.layout!.phones, hasLength(1),
          reason: 'the board should have been built for Ada alone');

      final again = joiner(deviceId: bobsPhone, label: 'Bob');
      await again.connect();
      await waitFor('bob back', () => host.phones[1].connected);

      ada.confirmPlacement();
      await waitFor('the round started', () => host.phase == HostPhase.playing);

      ada.dispose();
      again.dispose();
    });

    test('the last phone leaving instead of confirming starts the round',
        () async {
      // The mirror of it. Nothing else was going to ask the question: a
      // confirmation is what triggers the check, and that phone left rather
      // than pressing.
      final ada = joiner(label: 'Ada');
      await ada.connect();
      final bob = joiner(label: 'Bob');
      await bob.connect();
      await waitFor('calibrated',
          () => host.phones.length == 2 && host.phones.every((p) => p.calibrated));

      host.startGame(const BallBinGame());
      await waitFor('placing', () => host.phase == HostPhase.placing);

      ada.confirmPlacement();
      await waitFor('ada is in place',
          () => host.phones.first.confirmed);

      bob.dispose();
      await waitFor('the round started', () => host.phase == HostPhase.playing);

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
