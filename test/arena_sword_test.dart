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

/// The sword is the fight: it is what the player sees in front of them, and it
/// is the hitbox. Which makes two things worth pinning down that a cone never
/// needed — that a blow lands only where the blade actually is, and that the
/// blade is never anywhere it was not a moment ago.
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
  final board = const BoardCompiler().compile(
    const ArenaGame().planBoard(lobby),
    lobby,
  );
  final sim = ArenaSim(board.contextFor(scores));
  scores.beginRound();

  // Past the briefing, the countdown and the spawn grace, which is where a
  // fight starts.
  run(
    sim,
    ArenaConfig.briefingSeconds +
        ArenaConfig.countdownSeconds +
        ArenaConfig.spawnInvincibility +
        0.1,
  );
  return sim;
}

void run(ArenaSim sim, double seconds) {
  for (var t = 0.0; t < seconds; t += _dt) {
    sim.step(_dt);
  }
}

void touch(ArenaSim sim, String phoneId, String phase, double x, double y) =>
    sim.onTouch(
      TouchEvent(phoneId: phoneId, worldX: x, worldY: y, phase: phase),
    );

({double x, double y}) positionOf(ArenaSim sim, int index) {
  final e = sim.entities.firstWhere((e) => e.descriptor.id == 'fighter_$index');
  return (x: e.x, y: e.y);
}

/// The blade's angle this instant, straight off the entity every phone draws.
double swordAngle(ArenaSim sim, int index) =>
    sim.entities.firstWhere((e) => e.descriptor.id == 'sword_$index').angle;

/// Where the hilt is — which is where the sword entity sits.
({double x, double y}) hiltOf(ArenaSim sim, int index) {
  final e = sim.entities.firstWhere((e) => e.descriptor.id == 'sword_$index');
  return (x: e.x, y: e.y);
}

/// The blade's far end.
({double x, double y}) tipOf(ArenaSim sim, int index) {
  final hilt = hiltOf(sim, index);
  final a = swordAngle(sim, index);
  return (
    x: hilt.x + math.cos(a) * ArenaConfig.swordLength,
    y: hilt.y + math.sin(a) * ArenaConfig.swordLength,
  );
}

/// How far the blade lies off the way its owner is pointing. The pose, as
/// against the world angle — this is the part that animates.
double tiltOf(ArenaSim sim, int index) =>
    shortestTurn(facingOf(sim, index), swordAngle(sim, index));

/// Which way fighter [index] is facing.
double facingOf(ArenaSim sim, int index) =>
    sim.entities.firstWhere((e) => e.descriptor.id == 'fighter_$index').angle;

double shortestTurn(double from, double to) {
  var d = (to - from) % (2 * math.pi);
  if (d > math.pi) d -= 2 * math.pi;
  if (d < -math.pi) d += 2 * math.pi;
  return d;
}

/// Point fighter [index] at ([x], [y]) and leave them standing there.
///
/// A drag sets the facing, and the up that ends it is far enough from where it
/// started not to be read as a tap.
void faceTowards(ArenaSim sim, String phoneId, int index, double x, double y) {
  final me = positionOf(sim, index);
  touch(sim, phoneId, TouchPhase.down, me.x, me.y);
  touch(sim, phoneId, TouchPhase.move, x, y);
  sim.step(_dt);
  touch(sim, phoneId, TouchPhase.up, x, y);
}

void attack(ArenaSim sim, String phoneId, int index) {
  final me = positionOf(sim, index);
  touch(sim, phoneId, TouchPhase.down, me.x, me.y);
  touch(sim, phoneId, TouchPhase.up, me.x, me.y);
}

/// Long enough for the blade to reach the shoulder *and* cut.
///
/// More than [ArenaConfig.attackSwing], which is the slash alone: a tap first
/// carries the blade up to the shoulder at the pose speed, and how long that
/// takes depends on where it was. Half a turn is the worst case.
final double swingWindow =
    math.pi / ArenaConfig.swordSlew + ArenaConfig.attackSwing + 4 / 60;

void slash(ArenaSim sim, String phoneId, int index) {
  attack(sim, phoneId, index);
  run(sim, swingWindow);
}

int livesOf(ArenaSim sim, int index) =>
    (sim.sharedState['lives_p$index'] as num).toInt();

/// Stand fighter 1 at [angle] from fighter 0, [distance] away, without either
/// of them walking — the sim only moves fighters, so this is done by putting
/// them there through their own joystick and stopping.
void placeSecond(ArenaSim sim, double angle, double distance) {
  final me = positionOf(sim, 0);
  final target = (
    x: me.x + math.cos(angle) * distance,
    y: me.y + math.sin(angle) * distance,
  );
  for (var i = 0; i < 400; i++) {
    final them = positionOf(sim, 1);
    final dx = target.x - them.x;
    final dy = target.y - them.y;
    if (dx * dx + dy * dy < 0.01) break;
    touch(sim, 'p2', TouchPhase.down, them.x, them.y);
    touch(sim, 'p2', TouchPhase.move, target.x, target.y);
    sim.step(_dt);
  }
  final them = positionOf(sim, 1);
  touch(sim, 'p2', TouchPhase.up, them.x, them.y);
  // Long enough for the grace after any shove to lapse, and for both blades to
  // settle.
  run(sim, ArenaConfig.hitInvincibility + 0.2);
}

void main() {
  group('the blade is always there', () {
    test('every living fighter publishes one', () {
      final sim = start(3);
      final swords = sim.entities
          .where((e) => e.descriptor.kind == 'sword')
          .toList();
      expect(swords, hasLength(3));
    });

    test('it rests in front of its fighter', () {
      final sim = start(2);
      // Turned to face along the board, and given long enough for the blade to
      // follow the turn.
      final me = positionOf(sim, 0);
      faceTowards(sim, 'p1', 0, me.x + 5, me.y);
      run(sim, 0.6);

      expect(
        shortestTurn(facingOf(sim, 0), swordAngle(sim, 0)).abs(),
        lessThan(0.05),
        reason: 'the blade is meant to rest straight ahead',
      );
    });

    test('the hand is held away from the body', () {
      final sim = start(2);
      run(sim, 0.4);

      final me = positionOf(sim, 0);
      final hilt = hiltOf(sim, 0);
      final facing = facingOf(sim, 0);
      final dx = hilt.x - me.x;
      final dy = hilt.y - me.y;
      final ahead = dx * math.cos(facing) + dy * math.sin(facing);
      final aside = -dx * math.sin(facing) + dy * math.cos(facing);

      expect(
        ahead,
        closeTo(ArenaConfig.swordGrip, 0.01),
        reason: 'the hilt is meant to be held out, not stuck to the chest',
      );
      expect(
        aside,
        closeTo(ArenaConfig.swordHandSide, 0.01),
        reason: 'the sword is meant to be in the right hand',
      );
      expect(
        math.sqrt(dx * dx + dy * dy),
        greaterThan(ArenaConfig.characterRadius),
        reason: 'the hilt is inside the body',
      );
    });

    test('a shorter blade reaches exactly as far as the old one', () {
      final sim = start(2);
      run(sim, 0.4);

      // Measured along the facing: the hand is off to one side, and the reach
      // is how far ahead the blade gets.
      final me = positionOf(sim, 0);
      final tip = tipOf(sim, 0);
      final facing = facingOf(sim, 0);
      expect(
        (tip.x - me.x) * math.cos(facing) + (tip.y - me.y) * math.sin(facing),
        closeTo(ArenaConfig.attackRange, 0.01),
      );
    });

    test('a guard holds the blade across the front', () {
      final sim = start(2);
      final me = positionOf(sim, 0);
      // Held still: that is what a block is, and the hold has to outlast
      // blockHoldMs.
      touch(sim, 'p1', TouchPhase.down, me.x, me.y);
      run(sim, ArenaConfig.blockHoldMs / 1000 + 0.6);

      expect(sim.sharedState['blocking_p0'], isTrue);
      expect(
        shortestTurn(
          facingOf(sim, 0) + ArenaConfig.swordBlockTilt,
          swordAngle(sim, 0),
        ).abs(),
        lessThan(0.05),
        reason: 'a raised guard turns the blade across the line of the body',
      );

      // And the bar is *in front of* the fighter rather than off to one side:
      // its middle sits along the facing, square in the way of what is coming.
      final facing = facingOf(sim, 0);
      final at = positionOf(sim, 0);
      final hilt = hiltOf(sim, 0);
      final tip = tipOf(sim, 0);
      final midX = (hilt.x + tip.x) / 2 - at.x;
      final midY = (hilt.y + tip.y) / 2 - at.y;

      final ahead = midX * math.cos(facing) + midY * math.sin(facing);
      final aside = -midX * math.sin(facing) + midY * math.cos(facing);

      expect(ahead, closeTo(ArenaConfig.swordBlockReach, 0.02));
      expect(aside.abs(), lessThan(0.02), reason: 'the guard drifted sideways');
    });
  });

  // Two different promises, and they pull in opposite directions.
  //
  // The sword is rigidly attached to its owner: turn the fighter and the blade
  // is already round with them, no lag, no catching up. So the world angle
  // *must* be allowed to jump — a thumb can flick a fighter through half a
  // turn between one tick and the next.
  //
  // What may never jump is the pose: how far off the facing the blade lies.
  // That is the part with states in it — resting, guarding, swinging — and it
  // is the part that is watched here, every tick, because a teleport is
  // exactly the thing a before-and-after comparison cannot see.
  group('the pose never teleports', () {
    /// The largest single-tick change of pose over [seconds], in radians.
    double biggestJump(ArenaSim sim, int index, double seconds) {
      var worst = 0.0;
      var before = tiltOf(sim, index);
      for (var t = 0.0; t < seconds; t += _dt) {
        sim.step(_dt);
        final now = tiltOf(sim, index);
        final step = shortestTurn(before, now).abs();
        if (step > worst) worst = step;
        before = now;
      }
      return worst;
    }

    /// What one tick of the fastest thing the blade does is allowed to cover.
    ///
    /// The slash runs at a flat [ArenaConfig.swingSpeed] from end to end —
    /// there is no easing inside it any more — so this is that speed and
    /// nothing else. Anything past it is the blade being put somewhere rather
    /// than taken there.
    final swingCeiling = ArenaConfig.swingSpeed * _dt * 1.05;

    test('carrying it about', () {
      final sim = start(2);
      final me = positionOf(sim, 0);
      touch(sim, 'p1', TouchPhase.down, me.x, me.y);
      touch(sim, 'p1', TouchPhase.move, me.x, me.y + 6);

      expect(
        biggestJump(sim, 0, 1.5),
        lessThan(ArenaConfig.swordSlew * _dt * 1.01),
        reason: 'the blade outran its own slew while the fighter turned',
      );
    });

    test('but the fighter takes it round with them the instant they turn', () {
      final sim = start(2);
      final me = positionOf(sim, 0);
      faceTowards(sim, 'p1', 0, me.x + 5, me.y);
      run(sim, 0.5);
      expect(tiltOf(sim, 0).abs(), lessThan(0.01));

      // Hard about, in a single tick. The old sword swept round to catch up
      // over a tenth of a second, which looked like it had been left behind.
      touch(sim, 'p1', TouchPhase.down, me.x, me.y);
      touch(sim, 'p1', TouchPhase.move, me.x - 5, me.y);
      sim.step(_dt);

      expect(
        shortestTurn(facingOf(sim, 0), swordAngle(sim, 0)).abs(),
        lessThan(0.01),
        reason: 'the blade lagged behind the fighter holding it',
      );
    });

    test('raising and dropping a guard', () {
      final sim = start(2);
      final me = positionOf(sim, 0);
      touch(sim, 'p1', TouchPhase.down, me.x, me.y);
      final raising = biggestJump(sim, 0, 1.0);
      touch(sim, 'p1', TouchPhase.up, me.x, me.y);
      final lowering = biggestJump(sim, 0, 1.0);

      expect(raising, lessThan(ArenaConfig.swordSlew * _dt * 1.01));
      expect(lowering, lessThan(ArenaConfig.swordSlew * _dt * 1.01));
    });

    test('a swing, from wherever the blade happened to be', () {
      final sim = start(2);
      attack(sim, 'p1', 0);

      // Up to the shoulder, through the cut, and out the other side where the
      // blade finds its way back to resting. Both joins are places a snap
      // would hide.
      expect(biggestJump(sim, 0, swingWindow + 1.0), lessThan(swingCeiling));
    });

    test('a swing thrown straight out of a guard', () {
      // The nastiest join: the blade is out at the side, the block ends and a
      // swing starts in the same breath. It has to travel from where it is.
      final sim = start(2);
      final me = positionOf(sim, 0);
      touch(sim, 'p1', TouchPhase.down, me.x, me.y);
      run(sim, ArenaConfig.blockHoldMs / 1000 + 0.4);
      touch(sim, 'p1', TouchPhase.up, me.x, me.y);
      attack(sim, 'p1', 0);

      // Longer than a swing from rest, on purpose: the blade has further to
      // come, and it comes at the same speed.
      expect(biggestJump(sim, 0, swingWindow + 1.0), lessThan(swingCeiling));
    });
  });

  // What the slash is *supposed* to look like, as against merely not jumping:
  // it starts on seventy degrees, ends on minus seventy, and covers the ground
  // between them at one rate. Getting the blade up to the shoulder is a move
  // between poses and happens before any of that.
  group('the cut runs end to end', () {
    /// Every tilt the blade takes while it is actually cutting.
    List<double> slashSamples(ArenaSim sim) {
      final seen = <double>[];
      for (var t = 0.0; t < swingWindow; t += _dt) {
        sim.step(_dt);
        if (sim.sharedState['slashing_p0'] == true) seen.add(tiltOf(sim, 0));
      }
      return seen;
    }

    test('it begins exactly at the wind-up and ends exactly at the follow', () {
      final sim = start(2);
      attack(sim, 'p1', 0);
      final seen = slashSamples(sim);

      expect(seen, isNotEmpty);
      expect(
        seen.first,
        closeTo(ArenaConfig.attackWindup, 0.001),
        reason: 'the cut did not start on the shoulder',
      );
      expect(
        seen.last,
        closeTo(ArenaConfig.attackFollow, 0.001),
        reason: 'the cut did not finish on the follow-through',
      );
    });

    test('and covers the ground between them at one flat rate', () {
      final sim = start(2);
      attack(sim, 'p1', 0);
      final seen = slashSamples(sim);

      final steps = [
        for (var i = 1; i < seen.length; i++) (seen[i] - seen[i - 1]).abs(),
      ];
      // The last tick is a part-tick — it lands on the follow-through exactly
      // rather than overshooting it — so it is allowed to be short.
      final full = steps.sublist(0, steps.length - 1);
      final flat = ArenaConfig.swingSpeed * _dt;

      expect(full, everyElement(closeTo(flat, 0.0005)));
      expect(
        steps.last,
        lessThanOrEqualTo(flat + 0.0005),
        reason: 'the blade overshot the end of the cut',
      );
    });

    test('nobody is cut before the cut starts', () {
      // The blade travels to the shoulder first, and that trip is a fighter
      // getting ready rather than a fighter attacking. A tap that took a life
      // before the slash had begun would be a hit nobody could see coming.
      final sim = start(2);
      placeSecond(sim, ArenaConfig.attackWindup, ArenaConfig.attackRange * 0.6);

      final me = positionOf(sim, 0);
      faceTowards(sim, 'p1', 0, me.x + 5, me.y);
      run(sim, 0.4);

      attack(sim, 'p1', 0);
      // Stopped short of the shoulder: the blade is on its way and the cut has
      // not begun.
      run(sim, ArenaConfig.attackWindup / ArenaConfig.swordSlew * 0.8);

      expect(sim.sharedState['slashing_p0'], isFalse);
      expect(livesOf(sim, 1), ArenaConfig.maxLives);

      // And then it does begin, and it does bite.
      run(sim, swingWindow);
      expect(livesOf(sim, 1), ArenaConfig.maxLives - 1);
    });
  });

  // The three lines that open a round, and the fighters doing what they say.
  // A caption next to a still figure is a caption; the demonstration is what
  // makes it an instruction.
  group('the briefing shows what the controls do', () {
    /// A sim at the very start, before anything has been stepped.
    ArenaSim fresh() {
      final lobby = LobbyInfo([
        for (var i = 0; i < 2; i++) phone('p${i + 1}', PlayerPalette.all[i]),
      ]);
      final scores = Scoreboard();
      for (final p in lobby.phones) {
        scores.register(p.phoneId, p.label);
      }
      final board = const BoardCompiler().compile(
        const ArenaGame().planBoard(lobby),
        lobby,
      );
      final sim = ArenaSim(board.contextFor(scores));
      scores.beginRound();
      return sim;
    }

    test('it opens on the briefing and walks its three lines', () {
      final sim = fresh();
      sim.step(_dt);
      expect(sim.sharedState['phase'], 'briefing');
      expect(sim.sharedState['step'], 0);

      run(sim, ArenaConfig.briefingStepSeconds);
      expect(sim.sharedState['step'], 1);

      run(sim, ArenaConfig.briefingStepSeconds);
      expect(sim.sharedState['step'], 2);
    });

    test('the fighters swing on the attack line', () {
      final sim = fresh();
      run(sim, ArenaConfig.briefingStepSeconds);

      // Watched across the whole step rather than sampled at the moment the
      // demo is asked for: a tap only starts the blade towards the shoulder,
      // and the cut itself is a tenth of a second further on.
      var slashed = false;
      for (var t = 0.0; t < ArenaConfig.briefingStepSeconds; t += _dt) {
        sim.step(_dt);
        if (sim.sharedState['slashing_p0'] == true) slashed = true;
      }

      expect(slashed, isTrue, reason: 'nobody demonstrated the attack');
    });

    test('and raise a guard on the block line', () {
      final sim = fresh();
      run(
        sim,
        ArenaConfig.briefingStepSeconds * 2 + ArenaConfig.briefingDemoAt + _dt,
      );
      expect(sim.sharedState['blocking_p0'], isTrue);
    });

    test('a demonstration cannot cost anybody a life', () {
      // Two fighters spawned within reach of each other is a board the
      // compiler can hand out, and a swing thrown to explain a swing must not
      // take a life off a neighbour who has not been told the game started.
      final sim = fresh();
      run(sim, ArenaConfig.briefingSeconds);
      expect(sim.sharedState['lives_p0'], ArenaConfig.maxLives);
      expect(sim.sharedState['lives_p1'], ArenaConfig.maxLives);
    });

    test(
      'the guard comes down during the count, not when the round starts',
      () {
        // The briefing ends with everybody's blade across their chest. Nothing
        // moves during '3, 2, 1' — nobody can act and nobody can be touched —
        // but the swords still have to travel back, or the count is three
        // seconds of a table that looks frozen mid-pose.
        final sim = fresh();
        run(sim, ArenaConfig.briefingSeconds + _dt);
        final posed = shortestTurn(facingOf(sim, 0), swordAngle(sim, 0)).abs();
        expect(posed, greaterThan(0.5), reason: 'the guard was never raised');

        run(sim, ArenaConfig.countdownSeconds);
        expect(sim.sharedState['phase'], 'playing');
        expect(
          shortestTurn(facingOf(sim, 0), swordAngle(sim, 0)).abs(),
          lessThan(0.05),
          reason: 'the blade was still stuck in the block pose',
        );
      },
    );

    test('the demo block is spent, and recharges during the count', () {
      // The recharge is half of what there is to learn: a guard costs
      // something and the blade fills back up before it can be raised again.
      // The count is the window it is shown in.
      final sim = fresh();
      run(sim, ArenaConfig.briefingSeconds + _dt);

      expect(sim.sharedState['phase'], 'countdown');
      expect(sim.sharedState['blocking_p0'], isFalse);
      expect(
        (sim.sharedState['blkCd_p0'] as num).toDouble(),
        greaterThan(0),
        reason: 'the demonstration cost nothing, so nothing was demonstrated',
      );

      // Halfway through the count it is partway back.
      run(sim, ArenaConfig.countdownSeconds / 2);
      final midway = (sim.sharedState['blkCd_p0'] as num).toDouble();
      expect(midway, greaterThan(0));
      expect(midway, lessThan(ArenaConfig.blockCooldown));
    });

    test('and the guard is ready by the time the round starts', () {
      // Which is only true while the count outlasts the cooldown. It does, and
      // this is what says so — change either number and somebody finds out
      // here rather than in a round that opens with everybody defenceless.
      expect(
        ArenaConfig.countdownSeconds,
        greaterThan(ArenaConfig.blockCooldown),
      );

      final sim = fresh();
      // With slack rather than a single frame: each phase hands over on the
      // step *after* its clock runs out.
      run(
        sim,
        ArenaConfig.briefingSeconds + ArenaConfig.countdownSeconds + 0.1,
      );

      expect(sim.sharedState['phase'], 'playing');
      expect(sim.sharedState['blkCd_p0'], 0);
    });
  });

  group('the blade is the hitbox', () {
    test('a swing at somebody in reach takes a life', () {
      final sim = start(2);
      placeSecond(sim, 0, ArenaConfig.attackRange * 0.6);

      final them = positionOf(sim, 1);
      faceTowards(sim, 'p1', 0, them.x, them.y);
      expect(livesOf(sim, 1), ArenaConfig.maxLives);

      slash(sim, 'p1', 0);
      expect(livesOf(sim, 1), ArenaConfig.maxLives - 1);
    });

    test('a swing takes one life however long the blade lies across them', () {
      // The blade sweeps through a body over several frames. A life a frame is
      // not a fight, and the per-swing ledger is what stops it.
      final sim = start(2);
      placeSecond(sim, 0, ArenaConfig.attackRange * 0.5);

      final them = positionOf(sim, 1);
      faceTowards(sim, 'p1', 0, them.x, them.y);
      slash(sim, 'p1', 0);

      expect(livesOf(sim, 1), ArenaConfig.maxLives - 1);
    });

    test('a swing at nothing costs nobody anything', () {
      final sim = start(2);
      // Well outside the blade's reach, and in front of nobody.
      placeSecond(sim, 0, ArenaConfig.attackRange * 2.5);

      final them = positionOf(sim, 1);
      faceTowards(sim, 'p1', 0, them.x, them.y);
      slash(sim, 'p1', 0);

      expect(livesOf(sim, 1), ArenaConfig.maxLives);
    });

    test('three of them and a fighter is out', () {
      final sim = start(2);
      placeSecond(sim, 0, ArenaConfig.attackRange * 0.6);
      final them = positionOf(sim, 1);
      faceTowards(sim, 'p1', 0, them.x, them.y);

      for (var i = 0; i < ArenaConfig.maxLives; i++) {
        expect(sim.sharedState['alive_p1'], isTrue);
        slash(sim, 'p1', 0);
        expect(livesOf(sim, 1), ArenaConfig.maxLives - 1 - i);
        run(sim, ArenaConfig.attackCooldown + ArenaConfig.hitInvincibility);
      }

      expect(sim.sharedState['alive_p1'], isFalse);
      expect(livesOf(sim, 1), 0);
    });
  });

  // What the phones are told when a blade reaches somebody. Both bursts are
  // drawn from this and nothing else, so what matters is that each blow is
  // counted once, says which kind it was, and says where.
  group('a blow that reaches somebody is announced', () {
    test('a hit is counted, placed, and named', () {
      final sim = start(2);
      placeSecond(sim, 0, ArenaConfig.attackRange * 0.6);
      final them = positionOf(sim, 1);
      faceTowards(sim, 'p1', 0, them.x, them.y);

      expect(sim.sharedState['impacts_p1'], isNull);
      slash(sim, 'p1', 0);

      expect(sim.sharedState['impacts_p1'], 1);
      expect(sim.sharedState['impactKind_p1'], 'hit');

      // On the fighter it happened to, not on the blade that reached them: a
      // burst thrown from the point of contact is a few dots off to one side
      // of somebody, which is what nobody noticed.
      final at = positionOf(sim, 1);
      final x = (sim.sharedState['impactX_p1'] as num).toDouble();
      final y = (sim.sharedState['impactY_p1'] as num).toDouble();
      expect(x, closeTo(at.x, 0.1));
      expect(y, closeTo(at.y, 0.1));
    });

    test('every blow counts, so two in a row are two bursts', () {
      // The reason this is a counter and not a flag: shared state is diffed,
      // and a flag raised twice running never changes.
      final sim = start(2);
      placeSecond(sim, 0, ArenaConfig.attackRange * 0.6);
      final them = positionOf(sim, 1);
      faceTowards(sim, 'p1', 0, them.x, them.y);

      slash(sim, 'p1', 0);
      expect(sim.sharedState['impacts_p1'], 1);

      run(sim, ArenaConfig.attackCooldown + ArenaConfig.hitInvincibility);
      slash(sim, 'p1', 0);
      expect(sim.sharedState['impacts_p1'], 2);
    });

    test('a guard that holds is announced as a parry, and costs no life', () {
      final sim = start(2);
      placeSecond(sim, 0, ArenaConfig.attackRange * 0.5);

      // The defender turns to face the attacker and holds still, which is what
      // raising a guard is.
      final me = positionOf(sim, 0);
      final them = positionOf(sim, 1);
      faceTowards(sim, 'p2', 1, me.x, me.y);
      touch(sim, 'p2', TouchPhase.down, them.x, them.y);
      run(sim, ArenaConfig.blockHoldMs / 1000 + 0.2);
      expect(sim.sharedState['blocking_p1'], isTrue);

      faceTowards(sim, 'p1', 0, them.x, them.y);
      slash(sim, 'p1', 0);

      expect(sim.sharedState['impactKind_p1'], 'parry');
      expect(sim.sharedState['impacts_p1'], 1);
      expect(livesOf(sim, 1), ArenaConfig.maxLives, reason: 'the guard held');
      expect(
        sim.sharedState['stunned_p0'],
        isTrue,
        reason: 'the blow should come back on whoever threw it',
      );
    });

    test('a fatal blow says nothing extra — the fall is the announcement', () {
      final sim = start(2);
      placeSecond(sim, 0, ArenaConfig.attackRange * 0.6);
      final them = positionOf(sim, 1);
      faceTowards(sim, 'p1', 0, them.x, them.y);

      for (var i = 0; i < ArenaConfig.maxLives; i++) {
        slash(sim, 'p1', 0);
        run(sim, ArenaConfig.attackCooldown + ArenaConfig.hitInvincibility);
      }

      expect(sim.sharedState['alive_p1'], isFalse);
      expect(
        sim.sharedState['impacts_p1'],
        ArenaConfig.maxLives - 1,
        reason: 'the killing blow would have thrown two bursts at once',
      );
    });
  });

  group('the round waits for the last fall to be seen', () {
    /// Fight until one of the two is out, and answer with the sim the instant
    /// it happens.
    ArenaSim untilTheLastFall() {
      final sim = start(2);
      placeSecond(sim, 0, ArenaConfig.attackRange * 0.6);
      final them = positionOf(sim, 1);
      faceTowards(sim, 'p1', 0, them.x, them.y);

      for (var i = 0; i < ArenaConfig.maxLives; i++) {
        slash(sim, 'p1', 0);
        if (sim.sharedState['alive_p1'] == false) return sim;
        run(sim, ArenaConfig.attackCooldown + ArenaConfig.hitInvincibility);
      }
      fail('nobody fell');
    }

    test('the round is decided at once but does not end at once', () {
      final sim = untilTheLastFall();

      // Settled: the winner has their points, and the fight is over in every
      // way that matters to the scoreboard.
      expect(sim.sharedState['alive_p1'], isFalse);
      expect(sim.outcome, isNull, reason: 'the round ended on the same frame');
      expect(sim.sharedState['phase'], 'playing');

      // Still running, so the burst has a round to play in.
      run(sim, ArenaConfig.deathShowSeconds * 0.5);
      expect(sim.sharedState['phase'], 'playing');

      run(sim, ArenaConfig.deathShowSeconds * 0.6);
      expect(sim.sharedState['phase'], 'finished');
      expect(sim.outcome, isNotNull);
    });

    test('and says where the fallen fell, for the burst to play on', () {
      final sim = untilTheLastFall();

      // The entity is gone the moment they are out, so the last thing anybody
      // knew about them has to be in shared state or the burst has nowhere to
      // happen.
      expect(
        sim.entities.where((e) => e.descriptor.id == 'fighter_1'),
        isEmpty,
      );
      expect(sim.sharedState['deadX_p1'], isNotNull);
      expect(sim.sharedState['deadY_p1'], isNotNull);
      expect(sim.sharedState['color_p1'], isNotNull);
    });
  });
}
