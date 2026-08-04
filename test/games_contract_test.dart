import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/model/phone_layout.dart';
import 'package:multiscreen_slingshot/sdk/platform_config.dart';
import 'package:multiscreen_slingshot/games/ball_bin/ball_bin_game.dart';
import 'package:multiscreen_slingshot/games/ball_bin/ball_bin_sim.dart';
import 'package:multiscreen_slingshot/games/slingshot/slingshot_game.dart';
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

      expect(GameCatalog.byId('slingshot'), isNotNull);
      expect(GameCatalog.byId('ballbin'), isNotNull);
      expect(GameCatalog.byId('hotpotato'), isNotNull);
      expect(GameCatalog.byId('flood'), isNotNull);
      expect(GameCatalog.byId('floodclosing'), isNotNull);
      expect(GameCatalog.byId('nope'), isNull);
    });

    test('skips a game that does not fit the table', () {
      // Ball Bin needs 2+. On one phone the playlist must not offer it.
      expect(GameCatalog.playableFrom(0, 1)!.manifest.id, 'slingshot');
      expect(GameCatalog.playableFrom(1, 2)!.manifest.id, 'ballbin');
      expect(GameCatalog.anyPlayable(1), isTrue);
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
      expect(GameCatalog.fingerprint, contains('slingshot'));
      expect(GameCatalog.fingerprint, contains('ballbin'));
    });
  });

  group('Slingshot through the contract', () {
    test('plans a row and builds a wide board', () {
      final started = start(const SlingshotGame(), 2);
      expect(started.board.board.width,
          greaterThan(started.board.board.height * 3));
      expect(started.board.instruction, contains('side by side'));
    });

    test('a shot that hits the tower wins', () {
      final started = start(const SlingshotGame(), 2);
      final sim = started.sim;

      final anchorX = sim.sharedState['anchorX']! as double;
      final anchorY = sim.sharedState['anchorY']! as double;
      const pullBack = 2.8;
      const angle = 20 * math.pi / 180;
      final pullX = anchorX - pullBack * math.cos(angle);
      final pullY = anchorY + pullBack * math.sin(angle);

      void touch(double x, double y, String phase) => sim.onTouch(
        TouchEvent(phoneId: 'p1', worldX: x, worldY: y, phase: phase),
      );

      touch(anchorX, anchorY, TouchPhase.down);
      touch(pullX, pullY, TouchPhase.move);

      // While pulled, the pouch is an ordinary entity — that is what puts the
      // band on the same interpolated clock as the bird.
      final pouch = entityOf(sim, 'pouch');
      expect(pouch.x, closeTo(pullX, 1e-6));
      expect(sim.sharedState['dragging'], 'p1');

      touch(pullX, pullY, TouchPhase.up);

      var steps = 0;
      while (sim.outcome == null && steps < PlatformConfig.simHz * 10) {
        sim.step(1 / PlatformConfig.simHz);
        steps++;
      }

      expect(sim.outcome, isNotNull);
      expect(sim.outcome!.won, isTrue);
      expect(sim.outcome!.summary, 'the tower fell');
    });

    test('a fresh board is not already won when the tower settles', () {
      final started = start(const SlingshotGame(), 2);
      for (var i = 0; i < 180; i++) {
        started.sim.step(1 / PlatformConfig.simHz);
      }
      expect(started.sim.outcome, isNull);
    });

    test('it is co-operative — nobody scores', () {
      final started = start(const SlingshotGame(), 2);
      for (var i = 0; i < 120; i++) {
        started.sim.step(1 / PlatformConfig.simHz);
      }
      expect(started.scores.isUsed, isFalse,
          reason: 'the slingshot never awards points; standings stay hidden');
    });
  });

  group('Ball Bin through the contract', () {
    test('plans a column and builds a tall board', () {
      final started = start(const BallBinGame(), 3);
      expect(started.board.board.height,
          greaterThan(started.board.board.width));
      expect(started.board.instruction, contains('one above the other'));
    });

    test('the biggest phone goes at the bottom, where the bin lives', () {
      final lobby = LobbyInfo([
        PhoneSpec(
          phoneId: 'small',
          label: 'small',
          widthMm: 55,
          heightMm: 120,
          bezelMm: 3,
          dpi: 400,
          devicePixelRatio: 3,
          activePxWidth: 866,
          activePxHeight: 1890,
        ),
        phone('big'),
      ]);
      final board = const BoardCompiler()
          .compile(const BallBinGame().planBoard(lobby), lobby);

      expect(board.phones.last.phoneId, 'big');
      expect(board.phones.last.topEdge,
          greaterThan(board.phones.first.topEdge));
    });

    test('a player who tracks the balls wins, and gets the points', () {
      final started = start(
        const BallBinGame(),
        3,
        overrideSim: (c) => BallBinSim(c, random: math.Random(7)),
      );
      final sim = started.sim;

      var steps = 0;
      while (sim.outcome == null && steps < PlatformConfig.simHz * 120) {
        _chaseLowestBall(sim);
        sim.step(1 / PlatformConfig.simHz);
        steps++;
      }

      expect(sim.outcome, isNotNull, reason: 'never reached 10 catches');
      expect(sim.sharedState['caught'], greaterThanOrEqualTo(10));

      // Every catch was credited to a real phone, and they add up.
      final ranked = started.scores.view.ranked;
      expect(started.scores.isUsed, isTrue);
      expect(
        ranked.fold<int>(0, (sum, e) => sum + e.total),
        sim.sharedState['caught'],
        reason: 'a catch must be credited to exactly one phone',
      );

      // The bin lives on the bottom phone, so that is who scores.
      expect(ranked.first.phoneId, 'p3');
    });

    test('balls spawn and retire without any protocol help', () {
      final started = start(
        const BallBinGame(),
        3,
        overrideSim: (c) => BallBinSim(c, random: math.Random(3)),
      );
      final sim = started.sim;

      List<Entity> balls() =>
          sim.entities.where((e) => e.kind == 'ball').toList();

      expect(balls(), isEmpty, reason: 'the pool starts parked');

      var steps = 0;
      while (balls().isEmpty && steps < PlatformConfig.simHz * 10) {
        sim.step(1 / PlatformConfig.simHz);
        steps++;
      }
      expect(balls(), isNotEmpty, reason: 'no ball ever spawned');

      // A parked ball is simply absent from `entities`; the platform diffs the
      // set and nobody had to send a spawn message by hand.
      final ids = balls().map((e) => e.id).toSet();
      expect(ids.length, lessThanOrEqualTo(6));
    });

    test('a player who never moves does not win', () {
      final started = start(
        const BallBinGame(),
        3,
        overrideSim: (c) => BallBinSim(c, random: math.Random(11)),
      );
      for (var i = 0; i < PlatformConfig.simHz * 25; i++) {
        started.sim.step(1 / PlatformConfig.simHz);
      }

      expect(started.sim.outcome, isNull);
      // A stationary bin still catches the occasional ball that happens to
      // spawn above it — luck is not a strategy, but it is not nothing.
      expect(started.sim.sharedState['caught'], lessThan(10));
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

/// A perfect player: keep the bin under whichever ball is closest to landing.
void _chaseLowestBall(GameSim sim) {
  final balls = sim.entities.where((e) => e.kind == 'ball').toList();
  if (balls.isEmpty) return;
  final target = balls.reduce((a, b) => a.y > b.y ? a : b);
  final bin = sim.entities.firstWhere((e) => e.kind == 'bin');

  sim.onTouch(TouchEvent(
    phoneId: 'p1',
    worldX: bin.x,
    worldY: bin.y,
    phase: TouchPhase.down,
  ));
  sim.onTouch(TouchEvent(
    phoneId: 'p1',
    worldX: target.x,
    worldY: bin.y,
    phase: TouchPhase.move,
  ));
}

/// Left/top edge of a compiled screen, which is what these expectations were
/// originally written against. The layout itself is centre-based now, because a
/// screen that can be turned has no meaningful axis-aligned corner.
extension EdgeReadout on PhoneLayout {
  double get leftEdge => viewport.left;
  double get topEdge => viewport.top;
}
