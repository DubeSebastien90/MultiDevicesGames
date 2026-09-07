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
  // Out of the countdown, where touches are ignored.
  for (var t = 0.0; t < ArenaConfig.countdownSeconds + _dt; t += _dt) {
    sim.step(_dt);
  }
  return sim;
}

void touch(ArenaSim sim, String phoneId, String phase, double x, double y) {
  sim.onTouch(TouchEvent(
    phoneId: phoneId,
    worldX: x,
    worldY: y,
    phase: phase,
  ));
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
void attack(ArenaSim sim, String phoneId) {
  final at = positionOf(sim, phoneId == 'p1' ? 0 : 1);
  touch(sim, phoneId, TouchPhase.down, at.x, at.y);
  touch(sim, phoneId, TouchPhase.up, at.x, at.y);
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

    test('the anchor is where the finger landed, and stays put as it drags',
        () {
      final sim = start(2);
      touch(sim, 'p1', TouchPhase.down, 4.0, 5.0);
      expect(anchorOf(sim, 'p0'), (x: 4.0, y: 5.0));
      expect(knobOf(sim, 'p0'), (x: 4.0, y: 5.0));

      touch(sim, 'p1', TouchPhase.move, 6.5, 5.0);
      // The anchor does not chase the finger — that is the whole point of it.
      expect(anchorOf(sim, 'p0'), (x: 4.0, y: 5.0));
      expect(knobOf(sim, 'p0'), (x: 6.5, y: 5.0));
    });

    test('a drag shorter than the dead zone still shows a tilt', () {
      final sim = start(2);
      touch(sim, 'p1', TouchPhase.down, 4.0, 5.0);
      final creep = ArenaConfig.minMoveDistance / 2;
      touch(sim, 'p1', TouchPhase.move, 4.0 + creep, 5.0);

      // No movement yet, by design — but the player can see how far they are
      // from getting some, which is the reason the ring is drawn at all.
      expect(knobOf(sim, 'p0')!.x, closeTo(4.0 + creep, 0.05));
    });

    test('it goes when the finger comes off', () {
      final sim = start(2);
      touch(sim, 'p1', TouchPhase.down, 4.0, 5.0);
      touch(sim, 'p1', TouchPhase.move, 8.0, 5.0);
      touch(sim, 'p1', TouchPhase.up, 8.0, 5.0);
      expect(anchorOf(sim, 'p0'), isNull);
      expect(knobOf(sim, 'p0'), isNull);
    });

    test('a fighter cut down with their finger down leaves no stick behind',
        () {
      final sim = start(2);
      run(sim, ArenaConfig.spawnInvincibility + 0.1);
      walkTogether(sim);

      // Three blows land on a fighter who is not touching anything.
      for (var i = 0; i < 3; i++) {
        attack(sim, 'p1');
        run(sim, ArenaConfig.attackCooldown + 0.1);
      }
      expect(sim.sharedState['hp_p1'], ArenaConfig.attackDamage);

      // The fourth lands while their finger is on the glass. Their own
      // touch-up never reaches the sim — [onTouch] turns a dead fighter away —
      // so if the fall does not clear the stick, it is painted on the floor
      // for the rest of the round. Not stepped between the two, or the held
      // touch would turn into a block and reflect the attack.
      final at = positionOf(sim, 1);
      touch(sim, 'p2', TouchPhase.down, at.x, at.y);
      expect(anchorOf(sim, 'p1'), isNotNull);

      attack(sim, 'p1');
      expect(sim.sharedState['alive_p1'], isFalse);
      expect(anchorOf(sim, 'p1'), isNull);
    });

    test('a replay starts with no stick showing', () {
      final sim = start(2);
      touch(sim, 'p1', TouchPhase.down, 4.0, 5.0);
      sim.reset();
      run(sim, ArenaConfig.countdownSeconds + _dt);
      expect(anchorOf(sim, 'p0'), isNull);
    });
  });
}
