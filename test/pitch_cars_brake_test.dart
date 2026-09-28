import 'package:flutter_test/flutter_test.dart';
import 'package:forge2d/forge2d.dart' show Vector2;
import 'package:multiscreen_slingshot/games/pitch_cars/pitch_cars_config.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/platform_config.dart';

import 'pitch_cars_test.dart' as cars;

const _dt = 1 / PlatformConfig.simHz;

/// The end of a flick: a car nearly stopped brakes to a dead stop rather than
/// creeping on, and the turn waits for exactly that.
void main() {
  test('under the brake speed, a car stops dead within the brake time', () {
    final sim = cars.start(2).sim;
    final car = sim.carOf(sim.currentTurn);
    final along = sim.track.tangentAt(0);
    car.linearVelocity =
        Vector2(along.x, along.y) * (sim.scale.brakeSpeed * 0.95);

    var t = 0.0;
    while (car.linearVelocity.length > 0 && t < 2) {
      sim.step(_dt);
      t += _dt;
    }
    expect(car.linearVelocity.length, 0, reason: 'exactly nothing');
    expect(t, lessThanOrEqualTo(PitchCarsConfig.brakeSeconds + 2 * _dt));

    // And it stays there.
    for (var i = 0; i < 30; i++) {
      sim.step(_dt);
    }
    expect(car.linearVelocity.length, 0);
    expect(car.angularVelocity, 0);
  });

  test('above the brake speed, it still coasts on friction', () {
    final sim = cars.start(2).sim;
    final car = sim.carOf(sim.currentTurn);
    final along = sim.track.tangentAt(0);
    car.linearVelocity = Vector2(along.x, along.y) * (sim.scale.brakeSpeed * 4);
    sim.step(_dt);
    expect(car.linearVelocity.length, greaterThan(sim.scale.brakeSpeed * 3));
  });

  test('a flick ends its turn only once every car is at exactly nothing', () {
    final sim = cars.start(2).sim;
    final me = sim.currentTurn;
    final car = sim.carOf(me);
    final at = car.position.clone();
    final along = sim.track.tangentAt(0);
    // A gentle flick, straight down the road: this is about how a car comes
    // to rest, and a car that leaves the track lands already stopped — which
    // is a different story, and ends its turn on landing.
    final back =
        at -
        Vector2(along.x, along.y) *
            (sim.scale.maxPull * (PitchCarsConfig.cancelPullFraction + 0.08));
    for (final (phase, p) in [
      (TouchPhase.down, at),
      (TouchPhase.move, back),
      (TouchPhase.up, back),
    ]) {
      sim.onTouch(
        TouchEvent(phoneId: me, worldX: p.x, worldY: p.y, phase: phase),
      );
    }
    expect(sim.sharedState['moving'], isTrue);

    double? stoppedAt;
    var t = 0.0;
    while (sim.sharedState['moving'] == true && t < 10) {
      sim.step(_dt);
      t += _dt;
      expect(
        sim.sharedState.keys.where((k) => k.startsWith('fall_')),
        isEmpty,
        reason: 'the flick sent the car off the road',
      );
      if (stoppedAt == null && car.linearVelocity.length == 0) stoppedAt = t;
      if (sim.sharedState['moving'] == true && stoppedAt == null) {
        // Still rolling means still this turn.
        expect(sim.currentTurn, me);
      }
    }
    expect(stoppedAt, isNotNull);
    // The turn ends the rest delay after the dead stop — not before it.
    final restDelay = PitchCarsConfig.restDelay.inMicroseconds / 1e6;
    expect(t - stoppedAt!, closeTo(restDelay, 3 * _dt));
    expect(sim.currentTurn, isNot(me));
  });
}
