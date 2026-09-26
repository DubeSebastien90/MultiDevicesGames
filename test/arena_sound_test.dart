import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/arena/arena_config.dart';
import 'package:multiscreen_slingshot/games/arena/arena_game.dart';
import 'package:multiscreen_slingshot/games/arena/arena_sim.dart';
import 'package:multiscreen_slingshot/sdk/audio/game_audio.dart';
import 'package:multiscreen_slingshot/sdk/audio/sound_cue.dart';
import 'package:multiscreen_slingshot/sdk/audio/tone.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/model/player.dart';
import 'package:multiscreen_slingshot/sdk/model/player_color.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

import 'arena_sword_test.dart' as sword;

/// The lightsaber sounds: each one on the phone of the fighter it is about.
({ArenaSim sim, _HeardAudio audio}) heard(int count, {bool skipIntro = true}) {
  final lobby = LobbyInfo([
    for (var i = 0; i < count; i++)
      sword.phone('p${i + 1}', PlayerPalette.all[i]),
  ]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }
  final board = const BoardCompiler().compile(
    const ArenaGame().planBoard(lobby),
    lobby,
  );
  final audio = _HeardAudio();
  final sim = ArenaSim(
    BoardContext(
      board: board.board,
      coverage: board.coverage,
      scores: scores,
      slices: board.slices,
      roster: Roster([
        for (var i = 0; i < count; i++)
          Player(phoneId: 'p${i + 1}', color: PlayerPalette.all[i]),
      ]),
      audio: audio,
    ),
  );
  scores.beginRound();
  if (skipIntro) {
    sword.run(
      sim,
      ArenaConfig.briefingSeconds +
          ArenaConfig.countdownSeconds +
          ArenaConfig.spawnInvincibility +
          0.1,
    );
  }
  return (sim: sim, audio: audio);
}

void main() {
  test('the briefing and the count are silent', () {
    final h = heard(2, skipIntro: false);
    sword.run(
      h.sim,
      ArenaConfig.briefingSeconds + ArenaConfig.countdownSeconds + 0.1,
    );
    expect(
      h.audio.plays,
      isEmpty,
      reason: 'the demonstration swings on every phone at once',
    );
  });

  test('a swing whooshes on the swinger\'s phone, once, on the cut', () {
    final h = heard(2);
    sword.attack(h.sim, 'p1', 0);
    expect(h.audio.plays, isEmpty, reason: 'the raise is not the cut');

    sword.run(h.sim, sword.swingWindow);
    expect(h.audio.plays, hasLength(1));
    expect(h.audio.plays.single.phoneId, 'p1');
    expect(ArenaConfig.saberVoid, contains(h.audio.plays.single.cue));
  });

  test('the same whoosh never plays twice in a row', () {
    final h = heard(2);
    for (var i = 0; i < 12; i++) {
      sword.slash(h.sim, 'p1', 0);
      sword.run(h.sim, ArenaConfig.attackCooldown);
    }
    final cues = [for (final p in h.audio.plays) p.cue];
    expect(cues, hasLength(12));
    for (var i = 1; i < cues.length; i++) {
      expect(cues[i], isNot(cues[i - 1]), reason: 'swing $i');
    }
    expect(cues.toSet().length, greaterThan(1));
  });

  test('a blow that lands plays a hit on the attacker\'s phone', () {
    final h = heard(2);
    sword.placeSecond(h.sim, 0, ArenaConfig.attackRange * 0.6);
    final them = sword.positionOf(h.sim, 1);
    sword.faceTowards(h.sim, 'p1', 0, them.x, them.y);
    h.audio.plays.clear();

    sword.slash(h.sim, 'p1', 0);
    expect(sword.livesOf(h.sim, 1), ArenaConfig.maxLives - 1);

    final hits = h.audio.plays
        .where((p) => ArenaConfig.saberHit.contains(p.cue))
        .toList();
    expect(hits, hasLength(1));
    expect(hits.single.phoneId, 'p1');
  });

  test('raising a guard whooshes, and the blade relighting hums', () {
    final h = heard(2);
    final me = sword.positionOf(h.sim, 0);
    sword.touch(h.sim, 'p1', TouchPhase.down, me.x, me.y);
    sword.run(h.sim, ArenaConfig.blockHoldMs / 1000 + 0.1);

    expect(h.sim.sharedState['blocking_p0'], isTrue);
    expect(h.audio.plays, hasLength(1));
    expect(h.audio.plays.single.phoneId, 'p1');
    expect(ArenaConfig.saberVoid, contains(h.audio.plays.single.cue));

    sword.touch(h.sim, 'p1', TouchPhase.up, me.x, me.y);
    sword.run(h.sim, ArenaConfig.blockCooldown * 0.9);
    expect(h.audio.plays, hasLength(1), reason: 'still recharging');

    sword.run(h.sim, ArenaConfig.blockCooldown * 0.2);
    expect(h.audio.plays, hasLength(2));
    expect(h.audio.plays.last.cue, ArenaConfig.saberOn);
    expect(h.audio.plays.last.phoneId, 'p1');
  });

  test(
    'a swing turned back by a guard dazes the swinger, faded in and out',
    () {
      final h = heard(2);
      sword.placeSecond(h.sim, 0, ArenaConfig.attackRange * 0.6);
      final me = sword.positionOf(h.sim, 0);
      final them = sword.positionOf(h.sim, 1);
      sword.faceTowards(h.sim, 'p2', 1, me.x, me.y);
      sword.faceTowards(h.sim, 'p1', 0, them.x, them.y);
      // Long enough that the second drag's up is not taken for a tap.
      sword.run(h.sim, ArenaConfig.attackCooldown);

      // p2 raises the guard and holds it.
      sword.touch(h.sim, 'p2', TouchPhase.down, them.x, them.y);
      sword.run(h.sim, ArenaConfig.blockHoldMs / 1000 + 0.1);
      expect(h.sim.sharedState['blocking_p1'], isTrue);
      h.audio.plays.clear();

      sword.slash(h.sim, 'p1', 0);
      expect(sword.livesOf(h.sim, 1), ArenaConfig.maxLives, reason: 'parried');

      final dazes = h.audio.plays
          .where((p) => p.cue == ArenaConfig.knockedOut)
          .toList();
      expect(dazes, hasLength(1));
      expect(dazes.single.phoneId, 'p1', reason: 'the one who is stunned');
      expect(dazes.single.fadeIn, ArenaConfig.knockedOutFadeIn);
      expect(h.audio.stopped, isEmpty, reason: 'still stunned');

      sword.run(h.sim, ArenaConfig.stunDuration);
      expect(h.audio.stopped, [
        (dazes.single.handle, ArenaConfig.knockedOutFadeOut),
      ]);
    },
  );
}

class _Play {
  _Play(this.handle, this.phoneId, this.cue, this.fadeIn);
  final SoundHandle handle;
  final String phoneId;
  final SoundCue cue;
  final Duration fadeIn;
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
  }) => throw StateError('Arena only ever plays on a phone');

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
    plays.add(_Play(handle, player.phoneId, cue, fadeIn));
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
