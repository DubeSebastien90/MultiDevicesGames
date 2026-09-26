import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:forge2d/forge2d.dart' show Vector2;
import 'package:multiscreen_slingshot/games/pitch_cars/pitch_cars_config.dart';
import 'package:multiscreen_slingshot/games/pitch_cars/pitch_cars_game.dart';
import 'package:multiscreen_slingshot/games/pitch_cars/pitch_cars_sim.dart';
import 'package:multiscreen_slingshot/sdk/audio/game_audio.dart';
import 'package:multiscreen_slingshot/sdk/audio/sound_cue.dart';
import 'package:multiscreen_slingshot/sdk/audio/tone.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/model/player.dart';
import 'package:multiscreen_slingshot/sdk/model/player_color.dart';
import 'package:multiscreen_slingshot/sdk/platform_config.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

import 'pitch_cars_test.dart' as cars;

const _dt = 1 / PlatformConfig.simHz;

({PitchCarsSim sim, BoardLayout board, _HeardAudio audio}) heard(
  int count, {
  int seed = 1,
}) {
  final lobby = LobbyInfo([
    for (var i = 0; i < count; i++)
      cars.phone('p${i + 1}', color: PlayerPalette.all[i]),
  ]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }
  final board = const BoardCompiler().compile(
    const PitchCarsGame().planBoard(lobby),
    lobby,
  );
  final audio = _HeardAudio();
  final sim = PitchCarsSim(
    board.contextFor(scores, audio: audio),
    random: math.Random(seed),
  );
  scores.beginRound();
  return (sim: sim, board: board, audio: audio);
}

void touch(PitchCarsSim sim, String phoneId, String phase, Vector2 at) =>
    sim.onTouch(
      TouchEvent(phoneId: phoneId, worldX: at.x, worldY: at.y, phase: phase),
    );

void main() {
  test('an aim hums on the phone the finger came down on', () {
    final h = heard(2);
    final car = h.sim.carOf(h.sim.currentTurn).position.clone();
    // Aimed from the other phone: input is never gated by whose it is.
    touch(h.sim, 'p2', TouchPhase.down, car);

    expect(h.audio.plays, hasLength(1));
    expect(h.audio.plays.single.phoneId, 'p2');
    expect(h.audio.plays.single.cue, PitchCarsConfig.hold);
  });

  test('a release in the cancel zone fires nothing and hushes the hold', () {
    final h = heard(2);
    final car = h.sim.carOf(h.sim.currentTurn).position.clone();
    touch(h.sim, 'p1', TouchPhase.down, car);
    touch(h.sim, 'p1', TouchPhase.up, car);

    expect([for (final p in h.audio.plays) p.cue], [PitchCarsConfig.hold]);
    expect(h.audio.stopped, [
      (h.audio.plays.single.handle, PitchCarsConfig.holdFadeOut),
    ]);
  });

  test('a shot fires on the phone it was aimed from', () {
    final h = heard(2);
    final car = h.sim.carOf(h.sim.currentTurn).position.clone();
    final back = car - Vector2(h.sim.scale.maxPull * 0.8, 0);
    touch(h.sim, 'p2', TouchPhase.down, car);
    touch(h.sim, 'p2', TouchPhase.move, back);
    touch(h.sim, 'p2', TouchPhase.up, back);

    expect(
      [for (final p in h.audio.plays) (p.phoneId, p.cue)],
      [('p2', PitchCarsConfig.hold), ('p2', PitchCarsConfig.shot)],
    );
    expect(h.audio.stopped.single.$1, h.audio.plays.first.handle);
  });

  test('two cars meeting hard crash once, on the phone under them', () {
    final h = heard(2);
    final me = h.sim.currentTurn;
    final them = me == 'p1' ? 'p2' : 'p1';
    final a = h.sim.carOf(me);
    final b = h.sim.carOf(them);

    final towards = (b.position - a.position)..normalize();
    a.linearVelocity = towards * 20;
    for (var i = 0; i < 30; i++) {
      h.sim.step(_dt);
    }

    final crashes = h.audio.plays
        .where((p) => p.cue == PitchCarsConfig.crash)
        .toList();
    expect(crashes, hasLength(1));
    expect(crashes.single.volume, PitchCarsConfig.crashVolume);
    final mid = (a.position + b.position) / 2;
    expect(crashes.single.phoneId, h.sim.context.nearestPhone(mid.x, mid.y));
  });

  test('a second impact inside the cooldown is not heard', () {
    final h = heard(2);
    final me = h.sim.currentTurn;
    final them = me == 'p1' ? 'p2' : 'p1';
    final a = h.sim.carOf(me);
    final b = h.sim.carOf(them);
    int crashes() =>
        h.audio.plays.where((p) => p.cue == PitchCarsConfig.crash).length;

    // Back to the grid before every impact, and not so fast that either
    // car leaves the road: a car falling off the edge is touching nothing.
    final homeA = a.position.clone();
    final homeB = b.position.clone();
    final away = (homeA - homeB)..normalize();
    final speed = h.sim.scale.restSpeed * PitchCarsConfig.crashSpeedFactor * 3;

    /// Put the cars a hair apart and closing fast, then step until they meet.
    void slam({int maxTicks = 20}) {
      b
        ..setTransform(homeB, 0)
        ..linearVelocity = Vector2.zero()
        ..angularVelocity = 0;
      a
        ..setTransform(homeB + away * (h.sim.scale.carRadius * 2.3), 0)
        ..linearVelocity = away * -speed
        ..angularVelocity = 0;
      final before = crashes();
      for (var i = 0; i < maxTicks && crashes() == before; i++) {
        h.sim.step(_dt);
      }
    }

    slam();
    expect(crashes(), 1);

    // At once, and stopped short of the cooldown running out.
    slam(maxTicks: (PitchCarsConfig.crashCooldownSeconds / _dt).floor() - 1);
    expect(crashes(), 1);

    for (
      var t = 0.0;
      t < PitchCarsConfig.crashCooldownSeconds + 0.05;
      t += _dt
    ) {
      h.sim.step(_dt);
    }
    slam();
    expect(crashes(), 2);
  });

  test('two cars barely touching make no crash', () {
    final h = heard(2);
    final me = h.sim.currentTurn;
    final them = me == 'p1' ? 'p2' : 'p1';
    final a = h.sim.carOf(me);
    final b = h.sim.carOf(them);

    final towards = (b.position - a.position)..normalize();
    a.linearVelocity = towards * (h.sim.scale.restSpeed * 2);
    for (var i = 0; i < 240; i++) {
      h.sim.step(_dt);
    }
    expect(h.audio.plays.where((p) => p.cue == PitchCarsConfig.crash), isEmpty);
  });

  test('a car over the edge falls out loud, on the phone it fell from', () {
    final h = heard(3);
    final sim = h.sim;
    final car = sim.carOf(sim.currentTurn);

    // Beside the road halfway round, well clear of its edge.
    final arc = sim.track.length / 2;
    final on = sim.track.pointAtArclength(arc);
    final t = sim.track.tangentAt(arc);
    final off = Vector2(
      on.x - t.y * sim.track.widthWorld * 1.2,
      on.y + t.x * sim.track.widthWorld * 1.2,
    );
    expect(sim.track.isOnTrack(off.x, off.y), isFalse);

    car
      ..setTransform(off, 0)
      ..linearVelocity = Vector2.zero();
    sim.step(_dt);

    final falls = h.audio.plays
        .where((p) => p.cue == PitchCarsConfig.falling)
        .toList();
    expect(falls, hasLength(1));
    final at = car.position;
    expect(falls.single.phoneId, sim.context.nearestPhone(at.x, at.y));

    // Once, not every tick of the fall.
    for (var i = 0; i < 60; i++) {
      sim.step(_dt);
    }
    expect(
      h.audio.plays.where((p) => p.cue == PitchCarsConfig.falling),
      hasLength(1),
    );
  });

  test('a fall lasts as long as its sound, tumbling, and lands facing the '
      'way it went over', () {
    final h = heard(3);
    final sim = h.sim;
    final id = sim.currentTurn;
    final car = sim.carOf(id);

    final arc = sim.track.length / 2;
    final on = sim.track.pointAtArclength(arc);
    final t = sim.track.tangentAt(arc);
    final off = Vector2(
      on.x - t.y * sim.track.widthWorld * 1.2,
      on.y + t.x * sim.track.widthWorld * 1.2,
    );
    const heading = 0.7;
    car
      ..setTransform(off, heading)
      ..linearVelocity = Vector2.zero()
      ..angularVelocity = 0;
    sim.step(_dt);
    expect(sim.sharedState.containsKey('fall_$id'), isTrue);

    // Halfway down: still in the air, and turning.
    for (var i = 0; i < PitchCarsConfig.fallSeconds / 2 / _dt; i++) {
      sim.step(_dt);
    }
    expect(sim.track.isOnTrack(car.position.x, car.position.y), isFalse);
    expect(car.angularVelocity, greaterThan(0));
    expect((car.angle - heading).abs(), greaterThan(1));

    // And back once the sound has run out.
    for (var i = 0; i < PitchCarsConfig.fallSeconds / 2 / _dt + 2; i++) {
      sim.step(_dt);
    }
    expect(sim.track.isOnTrack(car.position.x, car.position.y), isTrue);
    expect(car.angle, closeTo(heading, 1e-6));
    expect(car.angularVelocity, 0);
  });

  test('crossing the line cheers on the winner\'s phone', () {
    final h = heard(3);
    final sim = h.sim;
    final me = sim.currentTurn;
    final car = sim.carOf(me);

    final at = car.position.clone();
    touch(sim, me, TouchPhase.down, at);
    touch(sim, me, TouchPhase.move, at - Vector2(0.5, 0));
    touch(sim, me, TouchPhase.up, at - Vector2(0.5, 0));

    final track = sim.track;
    final end = track.pointAtArclength(track.length);
    final tangent = track.tangentAt(track.length);
    final inCap = Vector2(
      end.x + tangent.x * track.widthWorld * 0.3,
      end.y + tangent.y * track.widthWorld * 0.3,
    );
    final ticks =
        (PitchCarsConfig.restDelay.inMicroseconds / 1e6 / _dt).ceil() + 10;
    for (var i = 0; i < ticks && sim.sharedState['winner'] == null; i++) {
      car
        ..setTransform(inCap, 0)
        ..linearVelocity = Vector2.zero()
        ..angularVelocity = 0;
      sim.step(_dt);
    }
    expect(sim.sharedState['winner'], me);

    final seat = int.parse(me.substring(1)) - 1;
    final happy = Player(
      phoneId: me,
      color: PlayerPalette.all[seat],
    ).soundHappy;
    final cheers = h.audio.plays.where((p) => p.cue == happy).toList();
    expect(cheers, hasLength(1));
    expect(cheers.single.phoneId, me);
  });
}

class _Play {
  _Play(this.handle, this.phoneId, this.cue, this.volume);
  final SoundHandle handle;
  final String phoneId;
  final SoundCue cue;
  final double volume;
}

class _HeardAudio implements GameAudio {
  final plays = <_Play>[];
  final stopped = <(SoundHandle, Duration)>[];
  var _next = 1;

  @override
  SoundHandle playGeneral(
    SoundCue cue, {
    bool loop = false,
    double volume = 1.0,
    bool persist = false,
    Duration fadeIn = Duration.zero,
  }) => throw StateError('Pitch Cars only ever plays on a phone');

  @override
  SoundHandle playOnPhone(
    Player player,
    SoundCue cue, {
    bool loop = false,
    double volume = 1.0,
    bool persist = false,
    Duration fadeIn = Duration.zero,
  }) {
    final handle = SoundHandle(_next++);
    plays.add(_Play(handle, player.phoneId, cue, volume));
    return handle;
  }

  @override
  SoundHandle playToneOnPhone(
    Player player,
    Tone tone, {
    bool persist = false,
  }) => SoundHandle(_next++);

  @override
  void stopSound(SoundHandle handle, {Duration fade = Duration.zero}) =>
      stopped.add((handle, fade));

  @override
  void stopRoundSounds() {}
}
