import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/subway_skater/subway_skater_config.dart';
import 'package:multiscreen_slingshot/games/subway_skater/subway_skater_game.dart';
import 'package:multiscreen_slingshot/games/subway_skater/subway_skater_sim.dart';
import 'package:multiscreen_slingshot/sdk/audio/game_audio.dart';
import 'package:multiscreen_slingshot/sdk/audio/sound_cue.dart';
import 'package:multiscreen_slingshot/sdk/audio/tone.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/model/player.dart';
import 'package:multiscreen_slingshot/sdk/model/player_color.dart';
import 'package:multiscreen_slingshot/sdk/platform_config.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

import 'subway_skater_test.dart' as road;

const _tick = 1 / PlatformConfig.simHz;

/// Road Runner's sounds, each on the phone where it happened.
({SubwaySkaterSim sim, BoardLayout board, _HeardAudio audio}) heard(
  int count, {
  int seed = 5,
}) {
  final lobby = LobbyInfo([
    for (var i = 0; i < count; i++)
      PhoneSpec(
        phoneId: 'p${i + 1}',
        label: 'phone p${i + 1}',
        widthMm: 68.58,
        heightMm: 152.4,
        bezelMm: 3,
        dpi: 400,
        devicePixelRatio: 3,
        activePxWidth: 1080,
        activePxHeight: 2400,
        color: PlayerPalette.all[i],
      ),
  ]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }
  final board = const BoardCompiler().compile(
    const SubwaySkaterGame().planBoard(lobby),
    lobby,
  );
  final audio = _HeardAudio();
  final sim = SubwaySkaterSim(
    board.contextFor(scores, audio: audio),
    random: math.Random(seed),
  );
  scores.beginRound();
  return (sim: sim, board: board, audio: audio);
}

void main() {
  test('it is called Road Runner', () {
    expect(const SubwaySkaterGame().manifest.title, 'Road Runner');
  });

  test('a lane change wooshes on the phone that was swiped', () {
    final h = heard(3);
    road.swipe(h.sim, 'p2', 1);

    expect(
      [for (final p in h.audio.plays) (p.phoneId, p.cue)],
      [('p2', SubwaySkaterConfig.woosh)],
    );
  });

  test('a swipe into the wall of the corridor makes no sound', () {
    final h = heard(2);
    road.swipe(h.sim, 'p1', 1); // middle to the edge
    road.swipe(h.sim, 'p1', 1); // and no further
    expect(
      h.audio.plays.where((p) => p.cue == SubwaySkaterConfig.woosh),
      hasLength(1),
    );
  });

  test('cars sometimes honk, on the phone they have just driven onto', () {
    final h = heard(4);
    final sim = h.sim;
    var honks = 0;
    var arrivals = 0;
    final onPhone = <String, String?>{};

    for (var t = 0.0; t < 30; t += _tick) {
      final before = h.audio.plays.length;
      sim.step(_tick);

      // Every car's bonnet, and the phone under it.
      final arrivedOn = <String>{};
      for (final e in sim.entities.where((e) => e.kind == 'obstacle')) {
        final front = e.x + SubwaySkaterConfig.obstacleLength / 2;
        final phone = sim.context.phoneAt(front, e.y);
        if (phone != null && phone != onPhone[e.id]) {
          if (onPhone.containsKey(e.id) ||
              phone == sim.context.phoneIds.first) {
            arrivals++;
            arrivedOn.add(phone);
          }
          onPhone[e.id] = phone;
        }
      }

      for (final p in h.audio.plays.skip(before)) {
        if (p.cue != SubwaySkaterConfig.honk) continue;
        honks++;
        expect(
          arrivedOn,
          contains(p.phoneId),
          reason: 'a honk on ${p.phoneId} with no car arriving there',
        );
      }
    }

    expect(honks, greaterThan(0), reason: 'not one car honked');
    expect(arrivals, greaterThan(20));
    // One in four, loosely: well above none and well below every time.
    expect(honks / arrivals, inInclusiveRange(0.1, 0.45));
  });

  test('a runner clipped by a car: crash and explosion, where it happened', () {
    final h = heard(3);
    road.aimFirstWaveAtTheFront(h.sim, h.board);
    h.audio.plays.clear();

    final front = road.skaterOf(h.sim, 'p1');
    final where = h.sim.context.nearestPhone(front.x, front.y);

    var steps = 0;
    while (h.sim.hitsOf('p1') == 0 && steps < PlatformConfig.simHz * 5) {
      h.sim.step(_tick);
      steps++;
    }
    expect(h.sim.hitsOf('p1'), 1);

    final bangs = [
      for (final p in h.audio.plays)
        if (p.cue != SubwaySkaterConfig.honk) (p.phoneId, p.cue),
    ];
    expect(
      bangs,
      unorderedEquals([
        (where, SubwaySkaterConfig.crash),
        (where, SubwaySkaterConfig.knockedDown),
      ]),
    );
  });

  test('a charged runner flattening a car: a crash, and no explosion', () {
    final h = heard(3);
    final sim = h.sim;
    final board = h.board;

    road.run(sim, SubwaySkaterConfig.leadInSeconds + 0.05);
    final blocked = road.wavesOf(sim, board.board).values.single;
    final lane = blocked.first;
    final safe = [
      for (var l = 0; l < SubwaySkaterConfig.lanes; l++)
        if (!blocked.contains(l)) l,
    ].first;
    road.steerSlotTo(sim, board, 2, safe);
    road.steerSlotTo(sim, board, 1, lane);
    road.steerSlotTo(sim, board, 0, lane);
    road.run(sim, 0.2);

    // p1 is clipped first, which charges p2 — who then runs through it.
    var steps = 0;
    while (sim.smashesOf('p2') == 0 && steps < PlatformConfig.simHz * 6) {
      sim.step(_tick);
      steps++;
    }
    expect(sim.smashesOf('p2'), 1);

    final crashes = h.audio.plays
        .where((p) => p.cue == SubwaySkaterConfig.crash)
        .length;
    final explosions = h.audio.plays
        .where((p) => p.cue == SubwaySkaterConfig.knockedDown)
        .length;
    expect(explosions, sim.hitsOf('p1') + sim.hitsOf('p2') + sim.hitsOf('p3'));
    expect(crashes, explosions + 1, reason: 'one crash for the smash');
  });
}

class _Play {
  _Play(this.phoneId, this.cue);
  final String phoneId;
  final SoundCue cue;
}

class _HeardAudio implements GameAudio {
  final plays = <_Play>[];
  var _next = 1;

  @override
  SoundHandle playGeneral(
    SoundCue cue, {
    bool loop = false,
    double volume = 1.0,
    bool persist = false,
    Duration fadeIn = Duration.zero,
  }) => throw StateError('Road Runner only ever plays on a phone');

  @override
  SoundHandle playOnPhone(
    Player player,
    SoundCue cue, {
    bool loop = false,
    double volume = 1.0,
    bool persist = false,
    Duration fadeIn = Duration.zero,
  }) {
    plays.add(_Play(player.phoneId, cue));
    return SoundHandle(_next++);
  }

  @override
  SoundHandle playToneOnPhone(
    Player player,
    Tone tone, {
    bool persist = false,
  }) => SoundHandle(_next++);

  @override
  void stopSound(SoundHandle handle, {Duration fade = Duration.zero}) {}

  @override
  void stopRoundSounds() {}
}
