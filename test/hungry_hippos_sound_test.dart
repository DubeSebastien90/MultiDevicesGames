import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:forge2d/forge2d.dart' show Vector2;
import 'package:multiscreen_slingshot/games/hungry_hippos/hungry_hippos_config.dart';
import 'package:multiscreen_slingshot/games/hungry_hippos/hungry_hippos_game.dart';
import 'package:multiscreen_slingshot/games/hungry_hippos/hungry_hippos_sim.dart';
import 'package:multiscreen_slingshot/sdk/audio/game_audio.dart';
import 'package:multiscreen_slingshot/sdk/audio/sound_cue.dart';
import 'package:multiscreen_slingshot/sdk/audio/sounds.dart';
import 'package:multiscreen_slingshot/sdk/audio/tone.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/model/player.dart';
import 'package:multiscreen_slingshot/sdk/model/player_color.dart';
import 'package:multiscreen_slingshot/sdk/platform_config.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

const _tick = 1 / PlatformConfig.simHz;

({HungryHipposSim sim, _HeardAudio audio}) heard(int count) {
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
    const HungryHipposGame().planBoard(lobby),
    lobby,
  );
  final audio = _HeardAudio();
  final sim = HungryHipposSim(
    board.contextFor(scores, audio: audio),
    random: math.Random(2),
  );
  scores.beginRound();
  return (sim: sim, audio: audio);
}

void press(HungryHipposSim sim, String phoneId) => sim.onTouch(
  TouchEvent(phoneId: phoneId, worldX: 0, worldY: 0, phase: TouchPhase.down),
);

void lift(HungryHipposSim sim, String phoneId) => sim.onTouch(
  TouchEvent(phoneId: phoneId, worldX: 0, worldY: 0, phase: TouchPhase.up),
);

void run(HungryHipposSim sim, double seconds) {
  for (var t = 0.0; t < seconds; t += _tick) {
    sim.step(_tick);
  }
}

void main() {
  test('a press starts the hold on the presser\'s phone', () {
    final h = heard(4);
    press(h.sim, 'p2');

    expect(
      [for (final p in h.audio.plays) (p.phoneId, p.cue)],
      [('p2', HungryHipposConfig.hold)],
    );
  });

  test('letting go fades the hold and fires the shot', () {
    final h = heard(4);
    press(h.sim, 'p1');
    run(h.sim, 0.3);
    lift(h.sim, 'p1');

    expect(
      [for (final p in h.audio.plays) (p.phoneId, p.cue)],
      [('p1', HungryHipposConfig.hold), ('p1', HungryHipposConfig.shot)],
    );
    expect(h.audio.stopped, [
      (h.audio.plays.first.handle, HungryHipposConfig.holdFadeOut),
    ]);
  });

  test('a charge held too long goes by itself, with its shot', () {
    final h = heard(4);
    press(h.sim, 'p1');
    run(h.sim, HungryHipposConfig.chargeMaxHoldSeconds + 0.1);

    // Only the hold and the shot: the lunge may well have eaten something on
    // the way, and that is a different sound.
    List<SoundCue> charges() => [
      for (final p in h.audio.plays)
        if (!Sounds.buttonPress.contains(p.cue)) p.cue,
    ];
    expect(charges(), [HungryHipposConfig.hold, HungryHipposConfig.shot]);
    expect(h.audio.stopped.single.$1, h.audio.plays.first.handle);

    // The finger still on the glass starts nothing more.
    run(h.sim, 3);
    expect(charges(), hasLength(2));
  });

  test('every marble swallowed boups on the eater\'s phone', () {
    final h = heard(4);
    final sim = h.sim;

    press(sim, 'p3');
    lift(sim, 'p3');

    // Hold two marbles in the hippo's mouth all the way out.
    final ids = ['marble0', 'marble1'];
    for (var i = 0; i < 120 && sim.eatenBy('p3') < 2; i++) {
      final hippo = sim.entities.firstWhere((e) => e.id == 'hippo_p3');
      for (final id in ids) {
        sim.bodyOf(id)
          ?..setTransform(Vector2(hippo.x, hippo.y), 0)
          ..linearVelocity = Vector2.zero();
      }
      sim.step(_tick);
    }
    expect(sim.eatenBy('p3'), 2);

    final boups = [
      for (final p in h.audio.plays)
        if (Sounds.buttonPress.contains(p.cue)) p.phoneId,
    ];
    expect(boups, ['p3', 'p3']);
  });

  group('the penalty', () {
    /// One tap lunge by p1 with a single marble held [offset] to the side of
    /// the hippo all the way out, and every other marble parked across the
    /// dish where nothing can reach it. Returns p1's status after the lunge.
    String lungeWithMarbleAt(double offset) {
      final h = heard(4);
      final sim = h.sim;
      final board = sim.context.board;
      final rest = sim.entities.firstWhere((e) => e.id == 'hippo_p1');
      var dx = rest.x - board.centerX;
      var dy = rest.y - board.centerY;
      final d = math.sqrt(dx * dx + dy * dy);
      dx /= d;
      dy /= d;
      final parked = Vector2(
        board.centerX - dx * sim.dishRadius * 0.8,
        board.centerY - dy * sim.dishRadius * 0.8,
      );

      press(sim, 'p1');
      lift(sim, 'p1');
      String? status;
      for (var i = 0; i < 90; i++) {
        final hippo = sim.entities.firstWhere((e) => e.id == 'hippo_p1');
        for (var m = 0; m < 200; m++) {
          final body = sim.bodyOf('marble$m');
          if (body == null) break;
          final at = m == 0
              ? Vector2(hippo.x - dy * offset, hippo.y + dx * offset)
              : parked;
          body
            ..setTransform(at, 0)
            ..linearVelocity = Vector2.zero();
        }
        sim.step(_tick);
        final now = (sim.sharedState['hippos']! as Map)['p1'] as String? ?? '';
        if (now == 's') status = now;
      }
      return status ?? '';
    }

    test('a lunge that only shoves a marble aside is still a miss', () {
      const between =
          (HungryHipposConfig.mouthRadius + HungryHipposConfig.pushRadius) / 2;
      expect(lungeWithMarbleAt(between), 's');
    });

    test('a lunge that eats is not', () {
      expect(lungeWithMarbleAt(0), '');
    });
  });
}

class _Play {
  _Play(this.handle, this.phoneId, this.cue);
  final SoundHandle handle;
  final String phoneId;
  final SoundCue cue;
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
  }) => throw StateError('Hungry Hippos only ever plays on a phone');

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
    plays.add(_Play(handle, player.phoneId, cue));
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
