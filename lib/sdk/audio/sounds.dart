/// The house sound library: what every game gets for free.
///
/// The argument for the SDK owning these is the one that put [PlayerPalette] in
/// the SDK. A countdown is not a property of a round — it is the platform's
/// voice, and thirteen games each recording their own is thirteen slightly
/// different countdowns at one table, which reads as thirteen products.
///
/// **Most of these files do not exist yet, and that is fine.** A cue with no
/// asset is a silence, so the table is named in full and filled in as the
/// recordings arrive. Games written against `Sounds.win` today start making a
/// noise the day `win.wav` is committed, and none of them is edited.
///
/// Adding a sound is one line here. There is no registry, no `register()` call
/// and no initialisation order to get wrong — the same static-table shape as
/// [PlayerPalette] and [Cast], for the same reason: two devices must
/// never disagree about what a cue id means, and a table compiled into both
/// builds cannot.
library;

import '../model/player_character.dart';
import '../model/player_color.dart';
import 'sound_cue.dart';

/// Sounds the platform speaks in.
///
/// Assets, when they arrive, live under `assets/sdk/sfx/`, beside the player
/// art in `assets/sdk/players/` — everything the SDK owns under one root, so
/// extracting `lib/sdk/` into a real package one day is a `git mv` and not an
/// audit.
class Sounds {
  const Sounds._();

  /// Three-two-one. The platform's own voice before a round.
  static const countdown = SoundCue('countdown');

  /// The last second of a timer running out.
  static const tick = SoundCue('tick');

  /// A round ended well, and a round ended badly. The headline, not the detail:
  /// a game with something more specific to say plays its own on top.
  static const win = SoundCue('win');
  static const lose = SoundCue('lose');

  /// Nobody won, and that is a result rather than a missing one — the same
  /// distinction `OutcomeKind.draw` makes.
  static const draw = SoundCue('draw');

  /// A point landed. Short enough to fire several times a second, because in
  /// Guac-a-Mole it will.
  static const score = SoundCue('score');

  /// A tap that did something, and one that did not.
  static const tap = SoundCue('tap');
  static const denied = SoundCue('denied');

  /// A short, bright impact — 71ms of it. The first sound in the library with
  /// a file behind it, and the one a mole being squished wants.
  static const pop = SoundCue('pop', 'assets/sdk/sfx/pop.wav');

  /// A phone joined the table, and a phone left it. Platform events, played by
  /// the lobby rather than by any game.
  static const joined = SoundCue('joined');
  static const left = SoundCue('left');

  /// The bed under the lobby. Loops, and the one cue expected to outlive a
  /// round — see `persist` on the audio API.
  static const lobbyTheme = SoundCue('lobbyTheme');

  /// The hold-to-confirm gauge, lowest first: one tick per step of the ring,
  /// each higher than the last. Separate files rather than one rising sweep,
  /// because the low-latency path cannot start a clip halfway — and a hold
  /// resumed from half full has to sound half full.
  ///
  /// Synthesised by `audio-src/gen_hold_steps.py`; change the count there and
  /// here together.
  static final holdSteps = List<SoundCue>.unmodifiable([
    for (var i = 0; i < 12; i++)
      SoundCue(
        'hold.$i',
        'assets/sdk/sfx/hold_${i.toString().padLeft(2, '0')}.wav',
      ),
  ]);

  /// A menu button pressed: one recording at five pitches, -0.9% to +1.1%,
  /// picked at random per press by [UiAudio.buttonPress]. Built by
  /// `audio-src/gen_boup_variants.py`.
  static final buttonPress = List<SoundCue>.unmodifiable([
    for (var i = 0; i < 5; i++)
      SoundCue('button.$i', 'assets/sdk/sfx/boup_$i.wav'),
  ]);

  /// Everything above, for a test that wants to walk the table and for the
  /// asset audit that will eventually check each one is really there.
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
    joined,
    left,
    lobbyTheme,
  ];
}

/// The two sounds every character has.
///
/// Kept here rather than on [PlayerCharacter] so that adding a third — a hurt,
/// a taunt — is an entry in one table instead of a field on eight characters,
/// and so the naming convention that ties a cue id to a colour lives in one
/// place.
///
/// Ids are `'<colour>.happy'`, which is what crosses the wire. Deriving them
/// rather than writing sixteen constants means a ninth colour cannot arrive
/// with its sounds silently missing.
///
/// The paths come from [PlayerCharacter], which is the one place any asset path
/// is written down. Built once per colour rather than per call: a sim reaching
/// for `player.soundSad` inside a step must not allocate.
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
