library;

import '../model/player_character.dart';
import '../model/player_color.dart';
import 'sound_cue.dart';

class Sounds {
  const Sounds._();

  static const countdown = SoundCue('countdown');

  static const tick = SoundCue('tick');

  static const win = SoundCue('win');
  static const lose = SoundCue('lose');

  static const draw = SoundCue('draw');

  static const score = SoundCue('score');

  static const tap = SoundCue('tap');
  static const denied = SoundCue('denied');

  static const pop = SoundCue('pop', 'assets/sdk/sfx/pop.wav');

  static const introChime = SoundCue(
    'introChime',
    'assets/sdk/sfx/dingdingding.wav',
  );

  static const joined = SoundCue('joined');
  static const left = SoundCue('left');

  static const lobbyTheme = SoundCue('lobbyTheme');

  static final holdSteps = List<SoundCue>.unmodifiable([
    for (var i = 0; i < 12; i++)
      SoundCue(
        'hold.$i',
        'assets/sdk/sfx/hold_${i.toString().padLeft(2, '0')}.wav',
      ),
  ]);

  static final buttonPress = List<SoundCue>.unmodifiable([
    for (var i = 0; i < 5; i++)
      SoundCue('button.$i', 'assets/sdk/sfx/boup_$i.wav'),
  ]);

  static const all = <SoundCue>[
    countdown,
    tick,
    win,
    lose,
    draw,
    score,
    tap,
    denied,
    pop,
    introChime,
    joined,
    left,
    lobbyTheme,
  ];
}

class PlayerSounds {
  const PlayerSounds._();

  static final _happy = <String, SoundCue>{
    for (final c in Cast.all)
      c.colorId: SoundCue('${c.colorId}.happy', c.happyAsset),
  };

  static final _sad = <String, SoundCue>{
    for (final c in Cast.all)
      c.colorId: SoundCue('${c.colorId}.sad', c.sadAsset),
  };

  static SoundCue happy(PlayerColor color) =>
      _happy[color.id] ?? SoundCue('${color.id}.happy');

  static SoundCue sad(PlayerColor color) =>
      _sad[color.id] ?? SoundCue('${color.id}.sad');
}
