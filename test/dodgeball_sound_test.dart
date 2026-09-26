import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/dodgeball/dodgeball_config.dart';
import 'package:multiscreen_slingshot/games/dodgeball/dodgeball_game.dart';
import 'package:multiscreen_slingshot/games/dodgeball/dodgeball_sim.dart';
import 'package:multiscreen_slingshot/sdk/audio/game_audio.dart';
import 'package:multiscreen_slingshot/sdk/audio/sound_cue.dart';
import 'package:multiscreen_slingshot/sdk/audio/tone.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/model/player.dart';
import 'package:multiscreen_slingshot/sdk/model/player_color.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

import 'dodgeball_movement_test.dart' as move;

/// The woosh on the dasher's phone, the boing on the screen the ball bounced on.
({DodgeballSim sim, BoardLayout board, _HeardAudio audio}) heard(
  int count, {
  bool skipIntro = true,
}) {
  final lobby = LobbyInfo([
    for (var i = 0; i < count; i++)
      move.phone('p${i + 1}', PlayerPalette.all[i]),
  ]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }
  final board = const BoardCompiler().compile(
    const DodgeballGame().planBoard(lobby),
    lobby,
  );
  final audio = _HeardAudio();
  final sim = DodgeballSim(
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
    move.run(
      sim,
      DodgeballConfig.briefingSeconds + DodgeballConfig.countdownSeconds + 0.1,
    );
    audio.plays.clear();
  }
  return (sim: sim, board: board, audio: audio);
}

void main() {
  test('a dash wooshes on the dasher\'s phone and nowhere else', () {
    final h = heard(2);
    move.tap(h.sim, 'p1');

    expect(h.audio.plays, hasLength(1));
    expect(h.audio.plays.single.phoneId, 'p1');
    expect(h.audio.plays.single.cue, DodgeballConfig.woosh);
  });

  test('a dash still cooling down makes no sound', () {
    final h = heard(2);
    move.tap(h.sim, 'p1');
    move.run(h.sim, DodgeballConfig.dashDuration + 0.05);
    move.tap(h.sim, 'p1');

    expect(
      h.audio.plays.where((p) => p.cue == DodgeballConfig.woosh),
      hasLength(1),
    );
  });

  test('the briefing\'s dash wooshes on every phone', () {
    final h = heard(3, skipIntro: false);
    move.run(h.sim, DodgeballConfig.briefingSeconds);

    final wooshes = h.audio.plays.where((p) => p.cue == DodgeballConfig.woosh);
    expect([
      for (final p in wooshes) p.phoneId,
    ], unorderedEquals(['p1', 'p2', 'p3']));
  });

  test('a bounce boings on the phone whose screen it bounced on', () {
    final h = heard(3);
    var checked = 0;

    for (var t = 0.0; t < 20 && checked < 5; t += 1 / 60) {
      final before = h.audio.plays.length;
      h.sim.step(1 / 60);
      final boings = h.audio.plays
          .skip(before)
          .where((p) => p.cue == DodgeballConfig.boing);

      for (final boing in boings) {
        // Some ball is on (or right against) that phone's screen.
        final screen = h.board.slices
            .firstWhere((s) => s.phoneId == boing.phoneId)
            .screen
            .bounds
            .inflate(DodgeballConfig.ballRadius * 2);
        final balls = h.sim.entities.where((e) => e.descriptor.kind == 'ball');
        expect(
          balls.any((b) => screen.contains(b.x, b.y)),
          isTrue,
          reason: 'boing on ${boing.phoneId} with no ball there',
        );
        checked++;
      }
    }
    expect(checked, greaterThan(0), reason: 'no ball bounced');
  });

  test('a player knocked out hears their own sad voice', () {
    final h = heard(2);
    String? out;
    for (var t = 0.0; t < 300 && out == null; t += 1 / 60) {
      h.sim.step(1 / 60);
      if (h.sim.sharedState['alive_p0'] == false) out = 'p1';
      if (h.sim.sharedState['alive_p1'] == false) out = 'p2';
    }
    expect(out, isNotNull, reason: 'nobody was hit');

    final seat = out == 'p1' ? 0 : 1;
    final sad = Player(phoneId: out!, color: PlayerPalette.all[seat]).soundSad;
    final sads = h.audio.plays.where((p) => p.cue == sad).toList();
    expect(sads, hasLength(1));
    expect(sads.single.phoneId, out);
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
  }) => throw StateError('Dodgeball only ever plays on a phone');

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
