import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/game/game_config.dart';
import 'package:multiscreen_slingshot/host/ball_bin_sim.dart';
import 'package:multiscreen_slingshot/host/game_catalog.dart';
import 'package:multiscreen_slingshot/host/layout_solver.dart';
import 'package:multiscreen_slingshot/host/slingshot_sim.dart';
import 'package:multiscreen_slingshot/model/arrangement.dart';
import 'package:multiscreen_slingshot/model/device_metrics.dart';
import 'package:multiscreen_slingshot/net/protocol.dart';

/// Two minigames, two board shapes, one playlist.
DeviceMetrics landscapePhone(String label) => DeviceMetrics(
  activePxWidth: 2400,
  activePxHeight: 1080,
  widthMm: 152.4, // 400 dpi
  heightMm: 68.58,
  bezelMm: 3,
  devicePixelRatio: 3,
  label: label,
);

BoardLayout solve(int count, Arrangement arrangement) =>
    const LayoutSolver().solve(
      [
        for (var i = 0; i < count; i++)
          CalibratedPhone('p${i + 1}', landscapePhone('phone ${i + 1}')),
      ],
      arrangement: arrangement,
    );

void main() {
  group('the stack arrangement', () {
    test('phones accumulate downward, flush on the left', () {
      final board = solve(3, Arrangement.stack);

      expect(board.arrangement, Arrangement.stack);
      // One phone wide: the board hugs the narrowest screen.
      expect(board.board.width, closeTo(15.24, 1e-9));
      // Three screens plus two bezel gaps of 3+3mm.
      expect(board.board.height, closeTo(6.858 * 3 + 0.6 * 2, 1e-9));

      final ys = board.phones.map((p) => p.worldOffsetY).toList();
      expect(ys[0], closeTo(0, 1e-9));
      expect(ys[1], closeTo(6.858 + 0.6, 1e-9));
      expect(ys[2], closeTo((6.858 + 0.6) * 2, 1e-9));

      // Every phone starts at x = 0; that is what "left edges flush" means.
      expect(board.phones.every((p) => p.worldOffsetX == 0), isTrue);
      expect(board.phones[1].placement, contains('below phone 1'));
    });

    test('the strip still works exactly as before', () {
      final board = solve(2, Arrangement.strip);
      expect(board.board.width, closeTo(15.24 * 2 + 0.6, 1e-9));
      expect(board.board.height, closeTo(6.858, 1e-9));
      expect(board.phones[1].worldOffsetX, closeTo(15.24 + 0.6, 1e-9));
      expect(board.phones.every((p) => p.worldOffsetY == 0), isTrue);
    });

    test('seams run across the board, perpendicular to the packing axis', () {
      final stacked = solve(3, Arrangement.stack).coverage.seamRects();
      expect(stacked, hasLength(2));
      for (final seam in stacked) {
        // A horizontal band: full board width, one bezel-gap tall.
        expect(seam.width, closeTo(15.24, 1e-9));
        expect(seam.height, closeTo(0.6, 1e-6));
      }

      final strip = solve(3, Arrangement.strip).coverage.seamRects();
      expect(strip, hasLength(2));
      for (final seam in strip) {
        expect(seam.width, closeTo(0.6, 1e-6));
        expect(seam.height, closeTo(6.858, 1e-9));
      }
    });

    test('a point in the gap is inside the board but on no screen', () {
      final board = solve(2, Arrangement.stack);
      final seam = board.coverage.seamRects().single;
      final x = board.board.centerX;

      expect(board.coverage.isCovered(x, seam.centerY), isFalse);
      expect(board.board.contains(x, seam.centerY), isTrue);
    });
  });

  group('the slingshot is won by hitting the tower', () {
    late SlingshotSim sim;

    setUp(() => sim = SlingshotSim(coverage: solve(2, Arrangement.strip).coverage));

    test('a fresh board is not already won', () {
      // The tower settles under gravity in the first frames; box-on-box
      // contact must never be mistaken for a hit.
      for (var i = 0; i < 180; i++) {
        sim.step(1 / GameConfig.simHz);
      }
      expect(sim.won, isFalse);
    });

    test('a shot that reaches the tower ends the round', () {
      final anchor = sim.anchor;
      const pullBack = 2.8;
      const angle = 20 * math.pi / 180;

      sim.onTouch(
        phoneId: 'p1',
        worldX: anchor.x,
        worldY: anchor.y,
        phase: TouchPhase.down,
      );
      sim.onTouch(
        phoneId: 'p1',
        worldX: anchor.x - pullBack * math.cos(angle),
        worldY: anchor.y + pullBack * math.sin(angle),
        phase: TouchPhase.move,
      );
      sim.onTouch(
        phoneId: 'p1',
        worldX: anchor.x - pullBack * math.cos(angle),
        worldY: anchor.y + pullBack * math.sin(angle),
        phase: TouchPhase.up,
      );

      var steps = 0;
      while (!sim.won && steps < GameConfig.simHz * 10) {
        sim.step(1 / GameConfig.simHz);
        steps++;
      }

      expect(sim.won, isTrue, reason: 'the bird never reached the tower');
    });

    test('winning stops the bird being yanked back for another go', () {
      final anchor = sim.anchor;
      sim.onTouch(
        phoneId: 'p1',
        worldX: anchor.x,
        worldY: anchor.y,
        phase: TouchPhase.down,
      );
      // The pull has to be dragged, not just released somewhere else: a tap
      // with no travel is deliberately not a shot.
      sim.onTouch(
        phoneId: 'p1',
        worldX: anchor.x - 2.8,
        worldY: anchor.y + 1.0,
        phase: TouchPhase.move,
      );
      sim.onTouch(
        phoneId: 'p1',
        worldX: anchor.x - 2.8,
        worldY: anchor.y + 1.0,
        phase: TouchPhase.up,
      );

      var steps = 0;
      while (!sim.won && steps < GameConfig.simHz * 10) {
        sim.step(1 / GameConfig.simHz);
        steps++;
      }
      expect(sim.won, isTrue);

      // Long past the auto-reset delay, the bird must not be back in the pouch.
      final birdAfterWin = _entity(sim.entityStates(), 'bird');
      for (var i = 0; i < GameConfig.simHz * 4; i++) {
        sim.step(1 / GameConfig.simHz);
      }
      final birdNow = _entity(sim.entityStates(), 'bird');
      expect(
        (birdNow.x - sim.anchor.x).abs() + (birdNow.y - sim.anchor.y).abs(),
        greaterThan(0.5),
        reason: 'the bird was reset after the win (was at '
            '${birdAfterWin.x}, now ${birdNow.x})',
      );
    });
  });

  group('the ball bin', () {
    late BallBinSim sim;

    setUp(() {
      sim = BallBinSim(
        coverage: solve(3, Arrangement.stack).coverage,
        random: math.Random(7),
      );
    });

    test('starts empty, unwon, with a bin and no balls in play', () {
      expect(sim.won, isFalse);
      expect(sim.progress!.value, 0);
      expect(sim.progress!.goal, BinConfig.goal);

      final ids = sim.entityStates().map((e) => e.id).toSet();
      expect(ids, contains('bin'));
      expect(ids.where((id) => id.startsWith('ball')), isEmpty);
    });

    test('balls appear on their own and fall', () {
      final first = _runUntil(sim, () => _balls(sim).isNotEmpty);
      expect(first, isTrue, reason: 'no ball ever spawned');

      final ball = _balls(sim).first;
      final startY = ball.y;
      for (var i = 0; i < 30; i++) {
        sim.step(1 / GameConfig.simHz);
      }
      final moved = _entity(sim.entityStates(), ball.id);
      expect(moved.y, greaterThan(startY), reason: 'the ball did not fall');
    });

    test('every ball declared up front, so none needs a spawn message', () {
      // The pool is fixed and every member is in `specs` from the start; a ball
      // that is not in play is simply absent from the snapshot.
      final declared =
          sim.specs.where((s) => s.role == 'ball').map((s) => s.id).toSet();
      expect(declared, hasLength(BinConfig.maxLiveBalls));

      _runUntil(sim, () => _balls(sim).length >= 2);
      final live = _balls(sim).map((e) => e.id).toSet();
      expect(live.length, lessThan(declared.length));
      expect(declared.containsAll(live), isTrue);
    });

    test('a player who tracks the balls wins', () {
      final won = _runUntil(
        sim,
        () => sim.won,
        maxSeconds: 120,
        onStep: () => _chaseLowestBall(sim),
      );

      expect(won, isTrue, reason: 'never reached ${BinConfig.goal} catches');
      expect(sim.progress!.value, greaterThanOrEqualTo(BinConfig.goal));
    });

    test('a player who never moves the bin does not win', () {
      // Long past the point where ten balls have come and gone.
      final won = _runUntil(sim, () => sim.won, maxSeconds: 25);
      expect(won, isFalse);
      // Balls that miss are retired rather than piling up on the floor.
      expect(_balls(sim).length, lessThanOrEqualTo(BinConfig.maxLiveBalls));
    });

    test('the bin cannot be dragged off the board', () {
      final board = sim.board;
      _grabBin(sim);
      for (var i = 0; i < 200; i++) {
        sim.onTouch(
          phoneId: 'p1',
          worldX: board.right + 50,
          worldY: _binY(sim),
          phase: TouchPhase.move,
        );
        sim.step(1 / GameConfig.simHz);
      }
      final bin = _entity(sim.entityStates(), 'bin');
      expect(bin.x, lessThanOrEqualTo(board.right - BinConfig.binWidth / 2 + 1e-6));
      expect(bin.x, greaterThan(board.centerX));
    });

    test('it has no slingshot, and says so rather than faking one', () {
      expect(sim.slingState(), isNull);
    });
  });

  group('the playlist', () {
    test('alternates between the two board shapes and wraps', () {
      expect(GameCatalog.at(0).id, 'slingshot');
      expect(GameCatalog.at(0).arrangement, Arrangement.strip);
      expect(GameCatalog.at(1).id, 'ballbin');
      expect(GameCatalog.at(1).arrangement, Arrangement.stack);

      // Wrapping means a session never runs out of games.
      expect(GameCatalog.at(2).id, 'slingshot');
      expect(GameCatalog.at(7).id, 'ballbin');
    });

    test('every game says what it is and how it ends', () {
      for (final game in GameCatalog.playlist) {
        expect(game.title, isNotEmpty);
        expect(game.tagline, isNotEmpty);
        expect(game.goal, isNotEmpty);
      }
    });
  });
}

// ---------------------------------------------------------------- helpers

EntityState _entity(List<EntityState> states, String id) =>
    states.firstWhere((e) => e.id == id);

List<EntityState> _balls(BallBinSim sim) =>
    sim.entityStates().where((e) => e.id.startsWith('ball')).toList();

double _binY(BallBinSim sim) => _entity(sim.entityStates(), 'bin').y;

void _grabBin(BallBinSim sim) {
  final bin = _entity(sim.entityStates(), 'bin');
  sim.onTouch(
    phoneId: 'p1',
    worldX: bin.x,
    worldY: bin.y,
    phase: TouchPhase.down,
  );
}

/// A perfect player: keep the bin under whichever ball is closest to landing.
void _chaseLowestBall(BallBinSim sim) {
  final balls = _balls(sim);
  if (balls.isEmpty) return;
  final target = balls.reduce((a, b) => a.y > b.y ? a : b);
  _grabBin(sim);
  sim.onTouch(
    phoneId: 'p1',
    worldX: target.x,
    worldY: _binY(sim),
    phase: TouchPhase.move,
  );
}

/// Steps the sim until [done], up to [maxSeconds] of simulated time.
bool _runUntil(
  BallBinSim sim,
  bool Function() done, {
  int maxSeconds = 20,
  void Function()? onStep,
}) {
  final limit = GameConfig.simHz * maxSeconds;
  for (var i = 0; i < limit; i++) {
    if (done()) return true;
    onStep?.call();
    sim.step(1 / GameConfig.simHz);
  }
  return done();
}
