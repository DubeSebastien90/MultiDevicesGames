import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/arena/arena_config.dart';
import 'package:multiscreen_slingshot/games/arena/arena_game.dart';
import 'package:multiscreen_slingshot/games/arena/arena_sim.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/model/player_color.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

/// The joystick is drawn from shared state alone, so what the sim publishes
/// *is* the feature: an anchor where the finger landed, a point where it is
/// now, and — the part that goes wrong quietly — nothing at all once the hand
/// is off the glass.
PhoneSpec phone(String id, PlayerColor? color) => PhoneSpec(
  phoneId: id,
  label: 'phone $id',
  widthMm: 68.58,
  heightMm: 152.4,
  bezelMm: 3,
  dpi: 400,
  devicePixelRatio: 3,
  activePxWidth: 1080,
  activePxHeight: 2400,
  color: color,
);

const _dt = 1 / 60;

ArenaSim start(int phoneCount) {
  final lobby = LobbyInfo([
    for (var i = 0; i < phoneCount; i++)
      phone('p${i + 1}', PlayerPalette.all[i]),
  ]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }
  const game = ArenaGame();
  final board = const BoardCompiler().compile(game.planBoard(lobby), lobby);
  final sim = ArenaSim(board.contextFor(scores));
  scores.beginRound();
  // Out of the briefing and the countdown, both of which ignore touches.
  for (
    var t = 0.0;
    t < ArenaConfig.briefingSeconds + ArenaConfig.countdownSeconds + _dt;
    t += _dt
  ) {
    sim.step(_dt);
  }
  return sim;
}

void touch(ArenaSim sim, String phoneId, String phase, double x, double y) {
  sim.onTouch(TouchEvent(phoneId: phoneId, worldX: x, worldY: y, phase: phase));
}

void run(ArenaSim sim, double seconds) {
  for (var t = 0.0; t < seconds; t += _dt) {
    sim.step(_dt);
  }
}

/// Where fighter [index] is standing, straight off the entity it publishes.
({double x, double y}) positionOf(ArenaSim sim, int index) {
  final e = sim.entities.firstWhere((e) => e.descriptor.id == 'fighter_$index');
  return (x: e.x, y: e.y);
}

/// A tap: down and up with nothing stepped between, which is what separates it
/// from a hold.
///
/// It no longer hits anybody by itself — it starts a swing, and the blade cuts
/// what it reaches on the frames that follow. [swing] is the whole gesture.
void attack(ArenaSim sim, String phoneId) {
  final at = positionOf(sim, phoneId == 'p1' ? 0 : 1);
  touch(sim, phoneId, TouchPhase.down, at.x, at.y);
  touch(sim, phoneId, TouchPhase.up, at.x, at.y);
}

/// A tap, and the blade's whole trip round: up to the shoulder, then the cut.
///
/// Longer than [ArenaConfig.attackSwing], which times the cut alone — how long
/// the blade takes to *reach* the shoulder depends on where it started, and
/// half a turn is the worst it can be.
void swing(ArenaSim sim, String phoneId) {
  attack(sim, phoneId);
  run(sim, math.pi / ArenaConfig.swordSlew + ArenaConfig.attackSwing + 4 / 60);
}

/// Walks the first fighter onto the second until they are inside its reach and
/// facing it, so an attack can actually land.
void walkTogether(ArenaSim sim) {
  for (var i = 0; i < 600; i++) {
    final me = positionOf(sim, 0);
    final them = positionOf(sim, 1);
    final dx = them.x - me.x;
    final dy = them.y - me.y;
    if (dx * dx + dy * dy <= math.pow(ArenaConfig.attackRange * 0.6, 2)) {
      touch(sim, 'p1', TouchPhase.up, me.x + dx, me.y + dy);
      return;
    }
    touch(sim, 'p1', TouchPhase.down, me.x, me.y);
    touch(sim, 'p1', TouchPhase.move, them.x, them.y);
    sim.step(_dt);
  }
  fail('the fighter never closed the distance');
}

({double x, double y})? anchorOf(ArenaSim sim, String key) {
  final x = sim.sharedState['stickX_$key'] as num?;
  final y = sim.sharedState['stickY_$key'] as num?;
  if (x == null || y == null) return null;
  return (x: x.toDouble(), y: y.toDouble());
}

({double x, double y})? knobOf(ArenaSim sim, String key) {
  final x = sim.sharedState['stickToX_$key'] as num?;
  final y = sim.sharedState['stickToY_$key'] as num?;
  if (x == null || y == null) return null;
  return (x: x.toDouble(), y: y.toDouble());
}

void main() {
  group('the joystick shows where the drag is measured from', () {
    test('nothing is published before a finger touches down', () {
      final sim = start(2);
      expect(anchorOf(sim, 'p0'), isNull);
    });

    test('a finger resting on the glass draws nothing', () {
      final sim = start(2);
      touch(sim, 'p1', TouchPhase.down, 4.0, 5.0);
      // A tap and a held block both start exactly like this, and neither is
      // movement.
      expect(anchorOf(sim, 'p0'), isNull);
    });

    test('a drag shorter than the dead zone draws nothing either', () {
      final sim = start(2);
      touch(sim, 'p1', TouchPhase.down, 4.0, 5.0);
      touch(
        sim,
        'p1',
        TouchPhase.move,
        4.0 + ArenaConfig.minMoveDistance / 2,
        5.0,
      );
      expect(anchorOf(sim, 'p0'), isNull);
    });

    test(
      'the anchor is where the finger landed, and stays put as it drags',
      () {
        final sim = start(2);
        touch(sim, 'p1', TouchPhase.down, 4.0, 5.0);
        touch(sim, 'p1', TouchPhase.move, 6.5, 5.0);
        // The anchor does not chase the finger — that is the whole point of it.
        expect(anchorOf(sim, 'p0'), (x: 4.0, y: 5.0));
        expect(knobOf(sim, 'p0'), (x: 6.5, y: 5.0));
      },
    );

    test(
      'coming back to the middle puts the stick away and stops the fighter',
      () {
        final sim = start(2);
        run(sim, ArenaConfig.spawnInvincibility + 0.1);
        touch(sim, 'p1', TouchPhase.down, 4.0, 5.0);
        touch(sim, 'p1', TouchPhase.move, 6.5, 5.0);
        run(sim, 0.2);

        touch(sim, 'p1', TouchPhase.move, 4.1, 5.0);
        expect(anchorOf(sim, 'p0'), isNull);

        final at = positionOf(sim, 0);
        run(sim, 0.5);
        expect(positionOf(sim, 0).x, closeTo(at.x, 0.001));
      },
    );
  });

  group('how far the stick is pushed is how fast the fighter goes', () {
    test('the ramp starts at nothing and tops out at the walking speed', () {
      expect(ArenaConfig.moveScaleFor(0), 0);
      expect(ArenaConfig.moveScaleFor(ArenaConfig.minMoveDistance), 0);
      expect(ArenaConfig.moveScaleFor(ArenaConfig.joystickRadius), 1);
      // Past full tilt is still full tilt, never faster.
      expect(ArenaConfig.moveScaleFor(ArenaConfig.joystickRadius * 10), 1);
      expect(
        ArenaConfig.moveScaleFor(
          (ArenaConfig.minMoveDistance + ArenaConfig.joystickRadius) / 2,
        ),
        closeTo(0.5, 1e-9),
      );
    });

    test('a gentle push crawls where a full one runs', () {
      const seconds = 0.5;

      double coveredPushing(double distance) {
        final sim = start(2);
        run(sim, ArenaConfig.spawnInvincibility + 0.1);
        final from = positionOf(sim, 0);
        touch(sim, 'p1', TouchPhase.down, from.x, from.y);
        touch(sim, 'p1', TouchPhase.move, from.x + distance, from.y);
        run(sim, seconds);
        return positionOf(sim, 0).x - from.x;
      }

      final full = coveredPushing(ArenaConfig.joystickRadius);
      final half = coveredPushing(
        (ArenaConfig.minMoveDistance + ArenaConfig.joystickRadius) / 2,
      );

      // Full tilt is the old speed, unchanged: this made the stick finer, not
      // the game slower.
      expect(full, closeTo(ArenaConfig.moveSpeed * seconds, 0.2));
      expect(half, closeTo(full / 2, 0.2));
    });
  });

  group('the stick is put away when it stops meaning anything', () {
    test('it goes when the finger comes off', () {
      final sim = start(2);
      touch(sim, 'p1', TouchPhase.down, 4.0, 5.0);
      touch(sim, 'p1', TouchPhase.move, 8.0, 5.0);
      touch(sim, 'p1', TouchPhase.up, 8.0, 5.0);
      expect(anchorOf(sim, 'p0'), isNull);
      expect(knobOf(sim, 'p0'), isNull);
    });

    test(
      'a fighter cut down with their finger down leaves no stick behind',
      () {
        final sim = start(2);
        run(sim, ArenaConfig.spawnInvincibility + 0.1);
        walkTogether(sim);

        // Two of the three lives, taken off a fighter who is not touching
        // anything. The grace after a hit has to run out between them, or the
        // second blade passes through somebody still flashing.
        for (var i = 0; i < ArenaConfig.maxLives - 1; i++) {
          swing(sim, 'p1');
          run(sim, ArenaConfig.attackCooldown + ArenaConfig.hitInvincibility);
        }
        expect(sim.sharedState['lives_p1'], 1);
        expect(sim.sharedState['alive_p1'], isTrue);

        // The last one lands while their finger is on the glass, and dragging —
        // *towards* the blade, so the swing does not simply miss a fighter who
        // ran away from it, and far enough out of the dead zone that they are
        // steering rather than raising a guard.
        final me = positionOf(sim, 0);
        final them = positionOf(sim, 1);
        touch(sim, 'p2', TouchPhase.down, them.x, them.y);
        touch(sim, 'p2', TouchPhase.move, me.x, me.y);
        expect(anchorOf(sim, 'p1'), isNotNull);

        // Their own touch-up never reaches the sim — [onTouch] turns a dead
        // fighter away — so if the fall does not clear the stick, it is painted
        // on the floor for the rest of the round.
        swing(sim, 'p1');
        expect(sim.sharedState['alive_p1'], isFalse);
        expect(anchorOf(sim, 'p1'), isNull);
      },
    );

    test('a replay starts with no stick showing', () {
      final sim = start(2);
      touch(sim, 'p1', TouchPhase.down, 4.0, 5.0);
      sim.reset();
      run(
        sim,
        ArenaConfig.briefingSeconds + ArenaConfig.countdownSeconds + _dt,
      );
      expect(anchorOf(sim, 'p0'), isNull);
    });
  });
}
