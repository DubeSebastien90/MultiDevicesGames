import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/dodgeball/dodgeball_config.dart';
import 'package:multiscreen_slingshot/games/dodgeball/dodgeball_game.dart';
import 'package:multiscreen_slingshot/games/dodgeball/dodgeball_sim.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/model/player_color.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

/// Steering and dashing, which in this game are the same finger doing two
/// different things — so most of what can go wrong is one of them being left
/// holding the other's state.
///
/// Every run here is kept under the first ball spawn: a ball arriving mid-test
/// could eliminate the player being measured, and a movement test has no
/// business depending on where the balls went.
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

DodgeballSim start(int phoneCount) {
  final lobby = LobbyInfo([
    for (var i = 0; i < phoneCount; i++)
      phone('p${i + 1}', PlayerPalette.all[i]),
  ]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }
  const game = DodgeballGame();
  final board = const BoardCompiler().compile(game.planBoard(lobby), lobby);
  final sim = DodgeballSim(board.contextFor(scores));
  scores.beginRound();
  // Out of the briefing and the countdown, both of which ignore touches.
  //
  // With slack rather than a single frame: each phase hands over on the step
  // *after* its clock runs out, so an exact sum lands a frame or two short and
  // every test in the file starts failing for a reason none of them are about.
  run(
    sim,
    DodgeballConfig.briefingSeconds + DodgeballConfig.countdownSeconds + 0.1,
  );
  return sim;
}

void run(DodgeballSim sim, double seconds) {
  for (var t = 0.0; t < seconds; t += _dt) {
    sim.step(_dt);
  }
}

void touch(DodgeballSim sim, String phoneId, String phase, double x, double y) {
  sim.onTouch(TouchEvent(phoneId: phoneId, worldX: x, worldY: y, phase: phase));
}

/// Where player [index] is standing, straight off the entity it publishes.
({double x, double y}) positionOf(DodgeballSim sim, int index) {
  final e = sim.entities.firstWhere((e) => e.descriptor.id == 'player_$index');
  return (x: e.x, y: e.y);
}

/// A tap: down and up with nothing stepped between, which is what separates it
/// from a drag.
void tap(DodgeballSim sim, String phoneId) {
  final at = positionOf(sim, 0);
  touch(sim, phoneId, TouchPhase.down, at.x, at.y);
  touch(sim, phoneId, TouchPhase.up, at.x, at.y);
}

({double x, double y})? anchorOf(DodgeballSim sim, String key) {
  final x = sim.sharedState['stickX_$key'] as num?;
  final y = sim.sharedState['stickY_$key'] as num?;
  if (x == null || y == null) return null;
  return (x: x.toDouble(), y: y.toDouble());
}

({double x, double y})? knobOf(DodgeballSim sim, String key) {
  final x = sim.sharedState['stickToX_$key'] as num?;
  final y = sim.sharedState['stickToY_$key'] as num?;
  if (x == null || y == null) return null;
  return (x: x.toDouble(), y: y.toDouble());
}

/// A sim at the very start, before anything has been stepped.
DodgeballSim fresh(int phoneCount) {
  final lobby = LobbyInfo([
    for (var i = 0; i < phoneCount; i++)
      phone('p${i + 1}', PlayerPalette.all[i]),
  ]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }
  final board = const BoardCompiler().compile(
    const DodgeballGame().planBoard(lobby),
    lobby,
  );
  final sim = DodgeballSim(board.contextFor(scores));
  scores.beginRound();
  return sim;
}

int ballsOn(DodgeballSim sim) =>
    sim.entities.where((e) => e.descriptor.kind == 'ball').length;

void main() {
  // The two lines that open a round, and the player doing what the second one
  // says. A caption beside a still figure is a caption; the demonstration is
  // what makes it an instruction — and it shows the one thing the words
  // cannot, which is *when* to dash.
  group('the briefing shows what the controls do', () {
    test('it opens on the briefing and walks its three lines', () {
      final sim = fresh(2);
      sim.step(_dt);
      expect(sim.sharedState['phase'], 'briefing');
      expect(sim.sharedState['step'], 0);

      run(sim, DodgeballConfig.briefingStepSeconds);
      expect(sim.sharedState['step'], 1);

      run(sim, DodgeballConfig.briefingStepSeconds);
      expect(sim.sharedState['step'], 2);
    });

    test('a ball is thrown at each player, and dodged', () {
      final sim = fresh(2);
      run(
        sim,
        DodgeballConfig.briefingStepSeconds + DodgeballConfig.briefingDemoAt,
      );
      run(sim, 2 * _dt);

      // One each: every phone has to see the demonstration on its own glass,
      // and a single ball crossing the board would be a lesson for whoever it
      // happened to pass.
      expect(ballsOn(sim), 2);

      final before = positionOf(sim, 0);
      run(sim, DodgeballConfig.demoDashAt + DodgeballConfig.dashDuration);
      final after = positionOf(sim, 0);
      final moved = math.sqrt(
        math.pow(after.x - before.x, 2) + math.pow(after.y - before.y, 2),
      );
      expect(
        moved,
        greaterThan(
          DodgeballConfig.moveSpeed * DodgeballConfig.dashDuration * 1.5,
        ),
        reason: 'nobody dodged anything',
      );
    });

    test('a demonstration cannot eliminate anybody', () {
      // The ball is aimed straight at them and only misses because they move.
      // If the collision check ran here, a player whose dash was a frame late
      // would be out before the round started.
      final sim = fresh(2);
      run(sim, DodgeballConfig.briefingSeconds);
      expect(sim.sharedState['alive_p0'], isTrue);
      expect(sim.sharedState['alive_p1'], isTrue);
    });

    test('the demonstration ball goes with the line that threw it', () {
      // Left lying about, it would still be crossing the board under the last
      // line — which says "here comes another one" to somebody who has just
      // been told not to get hit.
      final sim = fresh(2);
      run(sim, DodgeballConfig.briefingStepSeconds * 2 + _dt);
      expect(sim.sharedState['step'], 2);
      expect(ballsOn(sim), 0);
    });

    test(
      'the walk home starts under the last line and finishes in the count',
      () {
        // The demonstration leaves them a dash off their mark and facing
        // sideways. Snapping them back when the round begins would be a
        // teleport on every screen at once — so they walk, starting under the
        // line that has nothing of its own to show.
        final sim = fresh(2);
        // Where the round will start them: their own screen's middle.
        final mark = positionOf(sim, 0);

        run(sim, DodgeballConfig.briefingStepSeconds * 2 + _dt);
        expect(sim.sharedState['step'], 2);
        expect(
          positionOf(sim, 0).x,
          isNot(closeTo(mark.x, 0.01)),
          reason: 'the dash never moved them off their mark',
        );

        final atLastLine = positionOf(sim, 0);
        run(sim, 0.3);
        expect(
          positionOf(sim, 0).x,
          isNot(closeTo(atLastLine.x, 0.01)),
          reason: 'nobody set off while the last line was up',
        );

        // Through the rest of the briefing and the whole count.
        run(
          sim,
          DodgeballConfig.briefingStepSeconds +
              DodgeballConfig.countdownSeconds +
              0.1,
        );
        expect(sim.sharedState['phase'], 'playing');

        // Back on the mark, facing the way they started.
        final home = sim.entities.firstWhere(
          (e) => e.descriptor.id == 'player_0',
        );
        expect(home.x, closeTo(mark.x, 0.05));
        expect(home.y, closeTo(mark.y, 0.05));
        expect(home.angle, closeTo(0, 0.01), reason: 'they never turned back');
      },
    );
  });

  group('a dash is a burst, not a direction the player is left in', () {
    test('the player stops when the dash runs out', () {
      final sim = start(2);
      final from = positionOf(sim, 0);

      // The bug this guards: the touch-up that fires a dash used to skip
      // clearing the heading, so that it would not cancel the burst it had
      // just started. The finger was already off the glass, so nothing ever
      // cleared it again — the dash ended and the player kept walking that way
      // for the rest of the round.
      tap(sim, 'p1');
      run(sim, DodgeballConfig.dashDuration + _dt);
      final afterDash = positionOf(sim, 0);
      expect(
        afterDash.x,
        isNot(closeTo(from.x, 0.01)),
        reason: 'the dash should have moved them',
      );

      run(sim, 1.5);
      expect(positionOf(sim, 0).x, closeTo(afterDash.x, 0.001));
      expect(positionOf(sim, 0).y, closeTo(afterDash.y, 0.001));
    });

    test('the touch-up that starts the dash does not cancel it', () {
      final sim = start(2);
      final from = positionOf(sim, 0);
      tap(sim, 'p1');
      run(sim, DodgeballConfig.dashDuration);

      // Dash speed, not walking speed — the burst really ran.
      final covered = (positionOf(sim, 0).x - from.x).abs();
      expect(
        covered,
        greaterThan(
          DodgeballConfig.moveSpeed * DodgeballConfig.dashDuration * 1.5,
        ),
      );
    });

    test('a dash keeps its heading when the stick is released mid-burst', () {
      final sim = start(2);
      final from = positionOf(sim, 0);

      // Walk left, stop, then dash: the dash goes the way they were facing.
      touch(sim, 'p1', TouchPhase.down, from.x, from.y);
      touch(sim, 'p1', TouchPhase.move, from.x - 4, from.y);
      run(sim, 0.2);
      touch(sim, 'p1', TouchPhase.up, from.x - 4, from.y);

      final beforeDash = positionOf(sim, 0);
      tap(sim, 'p1');
      run(sim, DodgeballConfig.dashDuration + _dt);
      // Still leftward, and further than a walk would have taken them.
      expect(positionOf(sim, 0).x, lessThan(beforeDash.x));

      final landed = positionOf(sim, 0);
      run(sim, 1.0);
      expect(positionOf(sim, 0).x, closeTo(landed.x, 0.001));
    });
  });

  group('the joystick shows where the drag is measured from', () {
    test('nothing is published before a finger touches down', () {
      final sim = start(2);
      expect(anchorOf(sim, 'p0'), isNull);
    });

    test('a finger resting on the glass draws nothing', () {
      final sim = start(2);
      touch(sim, 'p1', TouchPhase.down, 4.0, 5.0);
      // This is a dash being aimed, not movement.
      expect(anchorOf(sim, 'p0'), isNull);
    });

    test('a drag shorter than the dead zone draws nothing either', () {
      final sim = start(2);
      touch(sim, 'p1', TouchPhase.down, 4.0, 5.0);
      touch(
        sim,
        'p1',
        TouchPhase.move,
        4.0 + DodgeballConfig.minMoveDistance / 2,
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
      'coming back to the middle puts the stick away and stops the player',
      () {
        final sim = start(2);
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

    test('it goes when the finger comes off', () {
      final sim = start(2);
      touch(sim, 'p1', TouchPhase.down, 4.0, 5.0);
      touch(sim, 'p1', TouchPhase.move, 8.0, 5.0);
      touch(sim, 'p1', TouchPhase.up, 8.0, 5.0);
      expect(anchorOf(sim, 'p0'), isNull);
      expect(knobOf(sim, 'p0'), isNull);
    });

    test('a replay starts with no stick showing', () {
      final sim = start(2);
      touch(sim, 'p1', TouchPhase.down, 4.0, 5.0);
      touch(sim, 'p1', TouchPhase.move, 8.0, 5.0);
      sim.reset();
      run(
        sim,
        DodgeballConfig.briefingSeconds +
            DodgeballConfig.countdownSeconds +
            0.1,
      );
      expect(anchorOf(sim, 'p0'), isNull);
    });
  });

  group('how far the stick is pushed is how fast the player goes', () {
    test('the ramp starts at nothing and tops out at the walking speed', () {
      expect(DodgeballConfig.moveScaleFor(0), 0);
      expect(DodgeballConfig.moveScaleFor(DodgeballConfig.minMoveDistance), 0);
      expect(DodgeballConfig.moveScaleFor(DodgeballConfig.joystickRadius), 1);
      // Past full tilt is still full tilt, never faster.
      expect(
        DodgeballConfig.moveScaleFor(DodgeballConfig.joystickRadius * 10),
        1,
      );
      expect(
        DodgeballConfig.moveScaleFor(
          (DodgeballConfig.minMoveDistance + DodgeballConfig.joystickRadius) /
              2,
        ),
        closeTo(0.5, 1e-9),
      );
    });

    test('a gentle push crawls where a full one runs', () {
      const seconds = 0.5;

      double coveredPushing(double distance) {
        final sim = start(2);
        final from = positionOf(sim, 0);
        touch(sim, 'p1', TouchPhase.down, from.x, from.y);
        touch(sim, 'p1', TouchPhase.move, from.x + distance, from.y);
        run(sim, seconds);
        return positionOf(sim, 0).x - from.x;
      }

      final full = coveredPushing(DodgeballConfig.joystickRadius);
      final half = coveredPushing(
        (DodgeballConfig.minMoveDistance + DodgeballConfig.joystickRadius) / 2,
      );

      // Full tilt is the old speed, unchanged: this made the stick finer, not
      // the game slower.
      expect(full, closeTo(DodgeballConfig.moveSpeed * seconds, 0.2));
      expect(half, closeTo(full / 2, 0.2));
    });
  });
}
