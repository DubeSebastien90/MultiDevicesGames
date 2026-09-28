# Audio source

Where the sounds come from, as opposed to what the app ships.

**Nothing in here is bundled.** Only paths listed under `flutter: assets:` in
`pubspec.yaml` end up in a build, and this folder is not one of them — so the
39 MB project below costs the app nothing.

| | |
| --- | --- |
| `projetAudio.aup3` | the Audacity project the voices were recorded and cut in |
| `originals/` | the raw exports, before processing |

## What was done to the originals

The clips in `originals/` are the untouched exports. What sits in
`assets/sdk/players/` and `assets/sdk/sfx/` has been through one pass:

- **Downmixed to mono.** A phone speaker is mono, and the same clip plays on
  eight devices around a table. Stereo was bytes nobody could hear.
- **Loudness matched** to −18 dBFS RMS with a −1 dBFS ceiling. The originals
  ranged from −0.1 to −16.4 dBFS peak, which at a table means one character
  shouting and another inaudible. RMS rather than peak: peak-matching leaves a
  clip with a single sharp transient quiet for its whole length.
- **Leading silence trimmed to zero.** Anything before the sound starts is
  latency, and these carried 4–36 ms of it. That is felt on a cue that answers
  a finger.
- **Tails trimmed** at a gentler threshold, with an 8 ms fade, so a natural
  decay is not chopped and the cut does not click.

`pop.wav` was handled separately: at 53 ms it is a click, not a voice, and RMS
over something that short reads quiet however loud it sounds. It is peak
normalised to −3 dBFS and kept out of the voices' loudness pool.

## Levels

Whole-file RMS is the wrong ruler for a 60 ms click next to a one-second
voice: the click is mostly its own attack, the voice mostly pauses. So levels
are compared on the **loudest 50 ms** of each sound (RMS over that window):

| Sound | Loudest 50 ms | Why |
| --- | --- | --- |
| Character voices | about −11 dBFS (−9 to −14) | the reference; from the −18 RMS pass above |
| Hold gauge (`hold_*.wav`) | −12 dBFS | feedback the player is waiting on — same family as the voices |
| Menu button (`boup_*.wav`) | −18 dBFS | answers every tap in every menu; heard that often, it sits 6 dB under |
| Intro chime (`dingdingding.wav`) | −14 dBFS | over the curtain at the start of a run; a notch under the voices so it greets rather than blares — leveled with the game script's pass at `TARGET_DB = -14` |

New sounds should land in the voices' band unless, like the button, they are
heard constantly. `gen_hold_steps.py` and `gen_boup_variants.py` normalise to
their target themselves (`TARGET_DB` at the top of each), peak-limited at
−1 dBFS.

## Game sounds

A game's own sounds go through the same pass, by script:

1. Put the untouched export in `originals/games/<game id>/` (wav, mp3, flac
   or ogg). The id is the one in the game's `*_game.dart` manifest.
2. From the repo root: `python audio-src/normalise_game_sounds.py <game id>`
   (needs `pip install miniaudio`; no argument does every game).
3. The leveled mono wav lands in `assets/games/<game id>/`, at −11 dBFS on the
   loudest 50 ms — the voices' band. Change `TARGET_DB` in the script for a
   sound that should sit elsewhere.

Never drop a file straight into `assets/games/`: it would skip the pass, and
the next run of the script would not know it exists.

## Re-exporting

Export from Audacity into `originals/`, then re-run the processing pass — the
`assets/` copies are derived, and editing them by hand loses that.

Filenames follow the colour, not the recording order: `player1`..`player8`
became `green`..`red` in `PlayerPalette` hand-out order. A voice belongs to a
character, so the Frog keeps its own if the palette is ever reordered. The
mapping is written down in `player-assets-spec.md`.
