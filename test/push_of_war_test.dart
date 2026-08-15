import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/push_of_war/push_of_war_config.dart';
import 'package:multiscreen_slingshot/games/push_of_war/push_of_war_game.dart';
import 'package:multiscreen_slingshot/games/push_of_war/push_of_war_sim.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/platform_config.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

/// A physics ball, tapped by two teams on a row of phones — no ring, no
/// grid, and (unlike Ball Bin, the only other physics game on a packing
/// axis) two competing sides rather than one shared goal.
PhoneSpec phone(String id) => PhoneSpec(
  phoneId: id,
  label: 'phone $id',
  widthMm: 68.58,
  heightMm: 152.4,
  bezelMm: 3,
  dpi: 400,
  devicePixelRatio: 3,
  activePxWidth: 1080,
  activePxHeight: 2400,
);

({
  PushOfWarSim sim,
  BoardLayout board,
  Scoreboard scores,
  Set<String> teamA,
  Set<String> teamB,
}) start(int count) {
  final lobby = LobbyInfo([for (var i = 0; i < count; i++) phone('p${i + 1}')]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }
  const game = PushOfWarGame();
  final board = const BoardCompiler().compile(game.planBoard(lobby), lobby);
  final sim = PushOfWarSim(board.contextFor(scores));
  scores.beginRound();

  // The same split the sim derives internally, from where the phones ended
  // up rather than from the sort planBoard happened to use.
  final sorted = List.of(board.slices)
    ..sort((a, b) => a.viewport.centerX.compareTo(b.viewport.centerX));
  final half = sorted.length ~/ 2;
  final teamA = {for (final s in sorted.take(half)) s.phoneId};
  final teamB = {for (final s in sorted.skip(half)) s.phoneId};

  return (sim: sim, board: board, scores: scores, teamA: teamA, teamB: teamB);
}

void tap(PushOfWarSim sim, String phoneId) {
  sim.onTouch(
    TouchEvent(phoneId: phoneId, worldX: 0, worldY: 0, phase: TouchPhase.down),
  );
}

const dt = 1 / PlatformConfig.simHz;

void main() {
  test('two equal teams for every even table the manifest allows', () {
    const manifest = PushOfWarGame();
    for (final count in [2, 4, 6, 8]) {
      expect(manifest.manifest.fits(count), isTrue);
      final started = start(count);
      expect(started.teamA, hasLength(count ~/ 2));
      expect(started.teamB, hasLength(count ~/ 2));
      expect(started.teamA.intersection(started.teamB), isEmpty);
    }
    expect(manifest.manifest.fits(3), isFalse, reason: 'teams must be even');
  });

  test('the ball starts at rest in the middle of the lane', () {
    final started = start(4);
    final ball = started.sim.entities.single;
    expect(ball.kind, 'ball');
    expect(ball.x, closeTo(started.board.board.centerX, 1e-6));
    expect(ball.y, closeTo(started.board.board.centerY, 1e-6));
  });

  test('a touch from nobody seated does not move the ball', () {
    final started = start(4);
    tap(started.sim, 'ghost');
    started.sim.step(dt);
    final ball = started.sim.entities.single;
    expect(ball.vx, 0);
    expect(started.sim.outcome, isNull);
  });

  test('mashing faster than the rate limit counts as one tap', () {
    final once = start(4);
    tap(once.sim, once.teamA.first);
    once.sim.step(dt);
    final vxOnce = once.sim.entities.single.vx;

    final twice = start(4);
    tap(twice.sim, twice.teamA.first);
    tap(twice.sim, twice.teamA.first); // same instant — rate-limited away
    twice.sim.step(dt);
    final vxTwice = twice.sim.entities.single.vx;

    expect(vxTwice, closeTo(vxOnce, 1e-9));
  });

  test('team A tapping alone pushes the ball toward team B and wins', () {
    final started = start(4);
    final tapper = started.teamA.first;

    var ticks = 0;
    const maxTicks = PlatformConfig.simHz * 20;
    while (started.sim.outcome == null && ticks < maxTicks) {
      tap(started.sim, tapper);
      started.sim.step(dt);
      ticks++;
    }

    final outcome = started.sim.outcome;
    expect(outcome, isNotNull, reason: 'never crossed the line');
    expect(outcome!.kind, OutcomeKind.contest);
    expect(outcome.winners, started.teamA);

    for (final id in started.teamA) {
      expect(started.scores[id], PushOfWarConfig.winPoints);
    }
    for (final id in started.teamB) {
      expect(started.scores[id], 0);
    }

    // Latched: polled repeatedly, always the same verdict.
    expect(identical(started.sim.outcome, outcome), isTrue);
  });

  test('team B tapping alone sends it the other way and wins instead', () {
    final started = start(4);
    final tapper = started.teamB.first;

    var ticks = 0;
    const maxTicks = PlatformConfig.simHz * 20;
    while (started.sim.outcome == null && ticks < maxTicks) {
      tap(started.sim, tapper);
      started.sim.step(dt);
      ticks++;
    }

    final outcome = started.sim.outcome;
    expect(outcome, isNotNull, reason: 'never crossed the line');
    expect(outcome!.winners, started.teamB);
  });

  test('nobody tapping for the whole round is a draw', () {
    final started = start(4);
    const maxTicks = PlatformConfig.simHz * PushOfWarConfig.maxRoundSeconds;
    for (var i = 0; i < maxTicks + 1; i++) {
      started.sim.step(dt);
    }
    final outcome = started.sim.outcome;
    expect(outcome, isNotNull);
    expect(outcome!.kind, OutcomeKind.draw);
    expect(started.scores.isUsed, isFalse);
  });

  test('reset puts the ball back and clears the verdict', () {
    final started = start(4);
    final tapper = started.teamA.first;
    var ticks = 0;
    const maxTicks = PlatformConfig.simHz * 20;
    while (started.sim.outcome == null && ticks < maxTicks) {
      tap(started.sim, tapper);
      started.sim.step(dt);
      ticks++;
    }
    expect(started.sim.outcome, isNotNull);

    started.sim.reset();

    expect(started.sim.outcome, isNull);
    final ball = started.sim.entities.single;
    expect(ball.x, closeTo(started.board.board.centerX, 1e-6));
    expect(ball.y, closeTo(started.board.board.centerY, 1e-6));
    expect(ball.vx, 0);
    expect(ball.vy, 0);
  });
}
