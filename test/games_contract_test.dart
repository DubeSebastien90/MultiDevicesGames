
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/model/phone_layout.dart';
import 'package:multiscreen_slingshot/sdk/catalog.dart';
import 'package:multiscreen_slingshot/sdk/contract/entity.dart';
import 'package:multiscreen_slingshot/sdk/contract/game.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

/// The two shipped games, driven entirely through the SDK contract — no host,
/// no sockets, no rendering. If a game can be played this way it can be played
/// at all, because the platform only ever calls these methods.
PhoneSpec phone(String id) => PhoneSpec(
  phoneId: id,
  label: 'phone $id',
  // Portrait: the panel as the device is held. Both games turn it sideways.
  widthMm: 68.58,
  heightMm: 152.4,
  bezelMm: 3,
  dpi: 400,
  devicePixelRatio: 3,
  activePxWidth: 1080,
  activePxHeight: 2400,
);

/// Everything the platform does between "game chosen" and "sim running".
({GameSim sim, BoardLayout board, Scoreboard scores}) start(
  MultiscreenGame game,
  int phoneCount, {
  GameSim Function(BoardContext)? overrideSim,
}) {
  final lobby = LobbyInfo([
    for (var i = 0; i < phoneCount; i++) phone('p${i + 1}'),
  ]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }

  final board = const BoardCompiler().compile(game.planBoard(lobby), lobby);
  final context = board.contextFor(scores);
  final sim = (overrideSim ?? game.createSim)(context);
  scores.beginRound();
  return (sim: sim, board: board, scores: scores);
}

Entity entityOf(GameSim sim, String id) =>
    sim.entities.firstWhere((e) => e.id == id);

void main() {
  group('the catalog', () {
    test('offers every registered game and wraps', () {
      // Counted from the playlist rather than written down: registering a game
      // is meant to be one import and one list entry, and a hardcoded length
      // here made it one import, one list entry and a test to go and fix.
      expect(GameCatalog.playlist, isNotEmpty);
      for (final game in GameCatalog.playlist) {
        expect(GameCatalog.byId(game.manifest.id), same(game),
            reason: 'every registered game must be reachable by its own id');
      }

      expect(GameCatalog.byId('hotpotato'), isNotNull);
      expect(GameCatalog.byId('flood'), isNotNull);
      expect(GameCatalog.byId('arena'), isNotNull);
      // NO-IAP: Guacamole is Premium and out of the build for now.
      // expect(GameCatalog.byId('guacamole'), isNotNull);
      expect(GameCatalog.byId('pitch_cars'), isNotNull);
      expect(GameCatalog.byId('nope'), isNull);
    });

    test('skips a game that does not fit the table', () {
      // Every game needs two phones or more, so a lone phone is offered
      // nothing at all. That is a fact about the catalogue rather than about
      // the walk — the walk's job is to return null rather than something
      // unplayable.
      expect(GameCatalog.anyPlayable(1), isFalse);
      expect(GameCatalog.playableFrom(0, 1), isNull);

      // Two is the smallest real table, and the walk starts at the first
      // entry that fits it.
      expect(GameCatalog.anyPlayable(2), isTrue);
      expect(GameCatalog.playableFrom(0, 2), isNotNull);
      expect(GameCatalog.playableFrom(0, 2)!.manifest.fits(2), isTrue);

      // Hot Potato needs three, so a two-phone table walks past it.
      expect(GameCatalog.playableFrom(0, 2)!.manifest.id, isNot('hotpotato'));
    });

    test('the list runs out rather than looping', () {
      // Played through once and then everyone is back in the lobby. Asking
      // past the end is how the host knows the run is over, so it must answer
      // "nothing left" rather than starting again at the top.
      expect(GameCatalog.playableFrom(GameCatalog.playlist.length, 8), isNull);
      expect(
        GameCatalog.playableIndexFrom(GameCatalog.playlist.length, 8),
        isNull,
      );

      // One phone can only play Slingshot, and it is first. Asking for what
      // follows it used to wrap straight back to it.
      expect(GameCatalog.playableFrom(1, 1), isNull);
    });

    test('the fingerprint changes with the game list, not with a rebuild', () {
      expect(GameCatalog.fingerprint, GameCatalog.fingerprint);
      expect(GameCatalog.fingerprint, contains('flood'));
      expect(GameCatalog.fingerprint, contains('pitch_cars'));
    });
  });


  group('the scoreboard', () {
    test('survives rounds and reports the delta for each', () {
      final scores = Scoreboard()
        ..register('p1', 'one')
        ..register('p2', 'two');

      scores.beginRound();
      scores.award('p1', 3);
      expect(scores['p1'], 3);
      expect(scores.roundDelta('p1'), 3);

      // Next round: the total carries, the delta resets.
      scores.beginRound();
      expect(scores['p1'], 3);
      expect(scores.roundDelta('p1'), 0);
      scores.award('p1', 2);
      expect(scores['p1'], 5);
      expect(scores.roundDelta('p1'), 2);
    });

    test('hides itself until somebody scores', () {
      final scores = Scoreboard()..register('p1', 'one');
      expect(scores.isUsed, isFalse);
      scores.award('p1', 1);
      expect(scores.isUsed, isTrue);
    });

    test('awardAll is how a co-op game puts points on the board', () {
      final scores = Scoreboard()
        ..register('p1', 'one')
        ..register('p2', 'two')
        ..awardAll(5);
      expect(scores['p1'], 5);
      expect(scores['p2'], 5);
      expect(scores.view.leader, isNull, reason: 'a tie has no leader');
    });

    test('ranks highest first', () {
      final scores = Scoreboard()
        ..register('p1', 'one')
        ..register('p2', 'two')
        ..award('p1', 2)
        ..award('p2', 9);
      expect(scores.view.ranked.first.phoneId, 'p2');
      expect(scores.view.leader!.phoneId, 'p2');
    });
  });
}


/// Left/top edge of a compiled screen, which is what these expectations were
/// originally written against. The layout itself is centre-based now, because a
/// screen that can be turned has no meaningful axis-aligned corner.
extension EdgeReadout on PhoneLayout {
  double get leftEdge => viewport.left;
  double get topEdge => viewport.top;
}
