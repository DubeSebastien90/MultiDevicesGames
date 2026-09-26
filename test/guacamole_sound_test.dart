import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/guacamole/guacamole_config.dart';
import 'package:multiscreen_slingshot/games/guacamole/guacamole_game.dart';
import 'package:multiscreen_slingshot/games/guacamole/guacamole_sim.dart';
import 'package:multiscreen_slingshot/sdk/audio/game_audio.dart';
import 'package:multiscreen_slingshot/sdk/audio/sound_cue.dart';
import 'package:multiscreen_slingshot/sdk/audio/sounds.dart';
import 'package:multiscreen_slingshot/sdk/audio/tone.dart';
import 'package:multiscreen_slingshot/sdk/contract/entity.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/model/player.dart';
import 'package:multiscreen_slingshot/sdk/model/player_color.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

import 'guacamole_test.dart' as guac;

const _dt = 1 / 60;

({GuacamoleSim sim, _HeardAudio audio}) heard(int count) {
  final lobby = LobbyInfo([
    for (var i = 0; i < count; i++)
      guac.phone('p${i + 1}', PlayerPalette.all[i]),
  ]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }
  final board = const BoardCompiler().compile(
    const GuacamoleGame().planBoard(lobby),
    lobby,
  );
  final audio = _HeardAudio();
  final sim = GuacamoleSim(
    board.contextFor(scores, audio: audio),
    random: math.Random(7),
  );
  scores.beginRound();
  return (sim: sim, audio: audio);
}

String? phaseOf(GuacamoleSim sim, String moleId) =>
    ((sim.sharedState['moles']! as Map)[moleId] as Map?)?['p'] as String?;

/// The hole [mole] is sitting in.
Hole holeUnder(GuacamoleSim sim, Entity mole) =>
    sim.holes.firstWhere((h) => h.centerX == mole.x && h.centerY == mole.y);

/// Step until a mole is up and in [phase], and return it.
Entity waitForMole(GuacamoleSim sim, String phase) {
  for (var i = 0; i < 60 * 20; i++) {
    sim.step(_dt);
    for (final e in sim.entities.where((e) => e.kind == 'mole')) {
      if (phaseOf(sim, e.id) == phase) return e;
    }
  }
  fail('no mole got to $phase');
}

void tap(GuacamoleSim sim, String phoneId, double x, double y) => sim.onTouch(
  TouchEvent(phoneId: phoneId, worldX: x, worldY: y, phase: TouchPhase.down),
);

void main() {
  test('every avocado pops up with a voice, on the phone it is on', () {
    final h = heard(4);
    for (var i = 0; i < 60 * 10; i++) {
      final before = h.sim.entities.where((e) => e.kind == 'mole').toSet();
      final heardBefore = h.audio.plays.length;
      h.sim.step(_dt);
      final born = h.sim.entities
          .where((e) => e.kind == 'mole')
          .where((e) => !before.any((b) => b.id == e.id))
          .toList();
      final voices = h.audio.plays
          .skip(heardBefore)
          .where((p) => GuacamoleConfig.voices.contains(p.cue))
          .toList();
      expect(voices, hasLength(born.length));
      for (var k = 0; k < born.length; k++) {
        expect(voices[k].phoneId, holeUnder(h.sim, born[k]).phoneId);
      }
    }

    final all = [
      for (final p in h.audio.plays)
        if (GuacamoleConfig.voices.contains(p.cue)) p.cue,
    ];
    expect(all.length, greaterThan(5));
    for (var i = 1; i < all.length; i++) {
      expect(all[i], isNot(all[i - 1]), reason: 'the same voice twice');
    }
    expect(all.toSet().length, greaterThan(3), reason: 'always the same few');
  });

  test('a squish boups on the phone it was squished on', () {
    final h = heard(4);
    final mole = waitForMole(h.sim, 'up');
    final hole = holeUnder(h.sim, mole);
    h.audio.plays.clear();

    tap(h.sim, hole.phoneId, hole.centerX, hole.centerY);

    expect(phaseOf(h.sim, mole.id), 'squished');
    final boups = [
      for (final p in h.audio.plays)
        if (Sounds.buttonPress.contains(p.cue)) p.phoneId,
    ];
    expect(boups, [hole.phoneId]);
  });

  test('an avocado on its way down cannot be squished', () {
    final h = heard(4);
    final mole = waitForMole(h.sim, 'sinking');
    final hole = holeUnder(h.sim, mole);
    h.audio.plays.clear();
    final before = h.sim.squishedBy(hole.phoneId);

    for (final p in h.sim.context.phoneIds) {
      tap(h.sim, p, hole.centerX, hole.centerY);
    }

    expect(phaseOf(h.sim, mole.id), 'sinking');
    expect(
      h.audio.plays.where((p) => Sounds.buttonPress.contains(p.cue)),
      isEmpty,
    );
    expect(h.sim.squishedBy(hole.phoneId), before);
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
  }) => throw StateError('Guac-a-Mole only ever plays on a phone');

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
