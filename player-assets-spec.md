# Player assets: the SDK owns what a player looks and sounds like

A colour already tells a table who you are. This extends that: the same choice
also decides a **character** — two pictures and a set of sounds — and the SDK
hands them out. A game asks `player.topdown` and draws it; it never knows where
the file lives, never ships art of its own for players, and every game on the
platform ends up with the same eight faces.

The bet is the same one `PlayerColor` already made. Identity is a property of the
*person*, not of the round, so it outlives every minigame — and if it outlives
them, exactly one thing should own it.

---

## Where this lands in what already exists

The good news first, because it decides how much of this is real work:

**Identity already crosses the wire.** `PhoneSlice` carries a `PlayerColor` and
serialises its `id` (`sdk/contract/sim.dart`), and `client_session.dart:558`
already parses the full slice list on every phone. Every device therefore
*already knows* every player's colour. Nothing about the art needs a new
message, a new field, or a protocol version. Art is a pure function of a colour
id, and the colour id is already there.

**The host is already the only writer of colour.** `HostSession` seats a phone
on join and settles conflicts (`host_session.dart:580`). Characters inherit that
uniqueness for free — one character per palette entry means "unique colour"
already means "unique character", with no second allocator to keep honest.

**There is a precedent for how art is allowed to behave.** `LottieSprite` was
made non-blocking after a stalled rasterise left a phone on a screen that never
appeared, and `beginLoading` + a `draw` that returns `false` is the shape that
came out of it. Player art must obey the same rule, and can go one better —
see *Never returns false* below.

Two things are genuinely missing:

**A view has no roster.** `ViewContext` is `{phoneId, board}`. There is no way
for a `GameView` to ask who is playing, which is why Guac-a-Mole ships a
`colors` map through `sharedState` and reassembles it in
`guacamole_view.dart:406` — with a comment apologising for it. Any art API is
unusable without fixing this, and fixing it deletes that hack.

**There is no audio at all.** No package in `pubspec.yaml`, no player, no mute.
Sound is not an extension of an existing system here; it is a new one, and it
is the only part of this proposal with a real design question in it (below).

---

## The API

### Naming

`getPlayerTopdownSVG()` in Dart wants to be `player.topdown`. The rest of the
SDK reads that way already — `frame.visible`, `context.players`,
`slice.viewport` — and a getter that says `SVG` in its name promises a file
format the caller then has to care about. What a game actually wants is
"something I can draw"; the format is the SDK's business and will change the
first time an SVG turns out to be too slow to rasterise per frame.

```dart
player.topdown.draw(canvas, Offset(e.x, e.y), worldSize: 3.0, angle: e.angle);
player.face.widget(size: 48)                       // in a HUD
context.audio.playOnPhone(player, player.soundHappy);
```

### `Player` — the thing a game is handed

```dart
// sdk/model/player.dart
class Player {
  final String phoneId;        // for the scoreboard and for touch events
  final PlayerColor color;     // unchanged, still the identity
  final String label;          // the device's own name: 'Pixel 7'

  PlayerCharacter get character;  // the Frog, the Crab
  String get title;               // 'Green Frog', for saying out loud

  PlayerArt get topdown;       // seen from above: the board pieces
  PlayerArt get face;          // a portrait: HUDs, results, the lobby
  SoundCue get soundHappy;
  SoundCue get soundSad;
}
```

`Roster` comes with it — the list plus `byPhone`, `byColor` and `others`, which
is what every game writes for itself otherwise.

`Player` composes `PlayerColor`; it does not replace it. `PlayerColor` stays
exactly what it is — the wire value, the palette, the swatch — and everything
that reads `.value` today keeps working untouched.

### `PlayerArt` — a handle, not a file

```dart
abstract class PlayerArt {
  /// Paints centred at [center], scaled to fill [worldSize] world units.
  void draw(Canvas canvas, Offset center,
            {required double worldSize, double angle = 0, double opacity = 1});

  /// The same art as a widget, for HUDs and platform screens.
  Widget widget({double size});
}
```

**Never returns false.** `LottieSprite.draw` hands the fallback problem back to
the caller, and every caller solves it the same way — Slingshot draws a circle.
Player art solves it once, inside: if the real asset has not rasterised, `draw`
paints the coloured circle and returns. A game writes one line and is never
wrong-looking, only plain. This is also what makes phase 1 shippable with **zero
asset files** — the circle *is* the v1 implementation, and dropping real art in
later touches no game code.

### Slots

```dart
enum PlayerArtSlot { topdown, face }
```

**`topdown`** is the character seen from above — the piece on the board, drawn
small, at any angle, and the one that has to survive being read from two metres.
**`face`** is the character from the side: a portrait for HUDs, the lobby, the
results screen, drawn upright and large enough to have a personality.

No moods. `happy` and `sad` exist as sounds, and one portrait per character
keeps the art budget at sixteen images for the whole platform. If a game wants
a reaction it plays the sound and animates the sprite it already has.

Closed and small on purpose. Two views of a character is a promise eight
characters can actually keep; "whatever the game needs" is a promise that gets
broken by the fourth game. A game that needs a third angle draws its own, as it
does today.

**There are two layers of stand-in, and the difference matters.** The *files*
are real: sixteen PNGs under `assets/sdk/players/`, a square in the colour for
`face` and a round piece with a black centre for `topdown`. Behind them, and
used until a decode lands or when a character has no file at all, is the same
shape drawn as *geometry*. Both paint to the same box, so the swap changes
detail and never silhouette — nothing on the board moves when an image
arrives.

Having real files this early is the point. The interesting part of art is never
the drawing, it is the loading: the asset declaration, the async decode, the
cache, the fallback, the moment a round starts before the picture is ready.
That path is exercised now, by pictures that are trivial to replace.

### Sounds

Flat getters — `player.soundSad` — rather than a `sounds` sub-object, because
the call site is usually one cue in the middle of a rule and a second hop earns
nothing there.

A `SoundCue` is a name, not a file — `player.soundSad` resolves through `Cast`
the same way the art does. Games can make their own with
`SoundCue.asset('assets/games/flood/splash.mp3')`, because music and
game-specific effects are the game's own and the audio system must not care
which kind it is holding.

### The character table

```dart
// sdk/model/player_character.dart
class PlayerCharacter {
  final String colorId;      // binds to PlayerPalette, one each
  final String name;         // 'Fox' — for prompts: 'Green Fox scored'
  final String? topdownAsset;  // a real PNG today
  final String? faceAsset;     // a real PNG today
  final String? happyAsset;    // null — a null asset is a silence
  final String? sadAsset;
}

class Cast {
  static PlayerCharacter of(PlayerColor color);
}
```

The table is `Cast`, not the obvious `Characters`: `package:characters` exports
a class by that name, Flutter re-exports it from `widgets.dart`, and any file
drawing a character would have imported both and refused to compile.

Asset paths live here and **nowhere else**. That is the one rule that keeps the
door open on extracting `lib/sdk/` into a real Dart package later: a package's
assets are addressed as `packages/<name>/...`, so every hardcoded path in a
game would break on the day of the split. Games can never hardcode one, because
they are never shown one.

Files go under `assets/sdk/players/`, declared once in `pubspec.yaml`, kept
separate from `assets/animations/` so the split is a `git mv` and not an audit.

---

## Getting the roster to a game

### View side — the change that unblocks everything

```dart
class ViewContext {
  const ViewContext({
    required this.phoneId,
    required this.board,
    required this.players,   // new
  });

  final List<Player> players;
  Player get me;             // the one whose phoneId == phoneId
  Player? byPhone(String phoneId);
}
```

Built at `client_session.dart:690` — the single construction site — from
`_slices`, which is already populated and already carries colour. This is
plumbing, not protocol.

**`ViewContext`, not `Frame`.** The roster is fixed for the round; `Frame` is
rebuilt every tick and is for things that move. Putting a stable list there
would be sixty allocations a second of a list that never changes.

### Sim side

`BoardContext` already has `slices`, `players` (as colours) and
`phoneOfColor`. Add `List<Player> roster` alongside, leaving the existing
members in place so no game has to change. A sim rarely needs art — it needs to
deal a mole to Green — but it does need `Player` to *name* somebody in an
outcome line, and having two different "player" types on the two sides of the
contract would be the kind of thing that reads fine and confuses everyone.

---

## Audio: two speakers, one clock

Art is a pure function of identity, evaluated locally at draw time. Sound is an
*event* — it happens at a moment, and the moment is decided by the rules, which
run on the host and nowhere else. Nothing in the contract carries events today:
`sharedState` is state, coalesced on purpose, and a client that misses an
intermediate value is *supposed* to. So this is the one part of the feature that
adds something to the wire.

A table of phones is not one speaker, and pretending otherwise is what makes
multi-device audio sound wrong. There are two distinct things:

```dart
context.audio.playGeneral(cue);              // the table's speaker: the host
context.audio.playOnPhone(deadPlayer, deadPlayer.soundSad);   // one phone
```

**`playGeneral`** is the room: music, the countdown, the goal horn. One device
carries it — the host — because eight phones playing the same clip at eight
distances with eight different codec latencies is a flam, not a chord. Even
perfectly synchronised it would be worse, not better.

**`playOnPhone`** is the person. Green dies, Green's phone in Green's hand says
so. It is directional information — you know it is *you* before you have found
your character on the board — which is the one thing a phone-per-player table
can do that a television cannot.

### How it gets there

Both verbs are host-side, because both are raised by rules.

**The emitter arrives in `BoardContext`, not on `GameSim`.** This is not
tidiness. Thirteen games say `implements MultiscreenGame` / `implements
GameSim`, and Dart makes an `implements` clause carry every member of the
interface — including ones with a body. Adding `void onSound(...)` to `GameSim`
breaks all thirteen at once and makes each write an empty method. `BoardContext`
is already "everything a sim is handed" and already gained fields without
incident; `context.audio` costs no game anything. The same reasoning is already
written down for `PlayerPresence` in `sdk/contract/sim.dart`.

**One new message, `HostMsg.sound`, and no new transport primitive.** The host
already sends to one phone (`_phoneById(phoneId)?.link.send(...)`,
`host_session.dart:993`) and to all (`_broadcast`). `playOnPhone` is the first;
`playGeneral` is the second.

**Including to itself.** The host's own screen is a viewport receiving snapshots
like any other — that is stated in `host_session.dart` and it is what makes the
seam work. Audio should keep that true: the sim does not reach for an audio
player directly, it emits a cue that the host's *own client side* receives and
plays. One code path, and the host stops being a special case that has to be
remembered.

### Timing: on the shared timeline, not on arrival

A cue carries `atMs` — the timeline instant it was raised — and each phone fires
it when its delayed clock passes that instant, using the buffer that already
exists in `snapshot_buffer.dart`.

The tempting shortcut is to play on arrival, since a targeted sound is local
feedback and immediacy sounds like a virtue. It is not. A player dying at time
T appears on every screen at T + delay, host included. Playing the sound on
arrival puts it ~80ms *before* the picture on the phone that owns it — and
sound-before-picture is the far more noticeable direction of error. Scheduling
on the timeline also makes `playGeneral` and `playOnPhone` land together for
free, which matters the moment a game does both for one event.

Two rules fall out of it: a cue that arrives already stale — a phone
reconnecting, a long stall — is **dropped, not played late**; and a cue for a
phone that has left is a no-op, not an error.

Exactly-once is free. Because a cue is a discrete reliable message rather than a
field re-sent with every snapshot, the transport's ordering gives each cue once
and there is no fired-once guard to write.

### Handles, and who is allowed to still be playing

Anything that loops needs a way to be stopped, so both verbs return a handle:

```dart
final music = context.audio.playGeneral(Sounds.lobbyTheme, loop: true);
...
context.audio.stopSound(music, fade: const Duration(milliseconds: 400));
```

Three things this has to get right.

**A handle is a token, not an object.** The thing actually playing lives on
another device — even for `playGeneral`, since the host plays through its own
client side. So a `SoundHandle` is an id the host mints and puts in the message,
and `stopSound` is a second message carrying the same id. There is no audio
player on the sim side to hold a reference to.

**The id comes from a counter, never a clock.** `step` is required to be pure
with respect to wall-clock time — no `DateTime.now()`, no timers — and that is
what keeps the timeline reproducible. An id minted from the clock would quietly
break the one rule the whole engine rests on. A monotonic counter on the emitter
is deterministic and replayable.

**Emitting is queueing, not I/O.** Cues raised during `step` go into a buffer
that the host drains after the step, the same way entity changes already are.
A step that reached a speaker directly would be a step that cannot be replayed.

Stop has to cancel a cue that has not started yet, not only one that is
playing: with cues scheduled on the delayed timeline, a play at T and a stop at
T + 200ms can both be in a phone's queue before its clock has reached T at all.
Stopping something already finished is a no-op, not an error.

### Lifetime: round-scoped by default, persistent on purpose

Music surviving a round boundary is a feature, and it is also exactly how a
platform ends up with a loop playing forever that nobody holds the handle to —
the sim that started it was disposed two rounds ago.

So: **everything a round starts is stopped when the round ends**, automatically,
by the platform. A game that crashes, a round that is abandoned, an outcome
fired early — all of them go quiet without anyone remembering to. Surviving the
boundary is then a deliberate flag on the call:

```dart
context.audio.playGeneral(Sounds.tableTheme, loop: true, persist: true);
```

which hands ownership to the *session* rather than the round. The platform keeps
it through results and the lobby, and it is stoppable by the same handle, which
stays valid across the boundary because the id is minted by the host and the
host is the thing that persists.

`sim.reset()` counts as a round boundary for this: it puts the round back to its
opening position, and a mole-squish loop still running from the previous attempt
is not that position.

### The sound library, and adding to it

The SDK owns a house set — countdown, win, lose, tick, the UI click, a theme —
alongside the sixteen player clips. None of them exist yet, and the architecture
is built so that this does not matter:

```dart
// sdk/audio/sounds.dart
class Sounds {
  static const countdown = SoundCue('countdown', 'assets/sdk/sfx/countdown.mp3');
  static const win       = SoundCue('win',       'assets/sdk/sfx/win.mp3');
  // adding one is one line here and nothing anywhere else
}
```

A static table, like `PlayerPalette` and `Characters` — not a runtime registry
with registration calls and an initialisation order to get wrong. Adding a
sound is one line in one SDK file; every game can use it the next time it is
compiled, and no game is edited.

**A missing file is a silence, not a crash.** A cue whose asset is not there
logs once and plays nothing, the same way art falls back to a circle. That is
what makes it safe to name the whole library today and fill it in over the next
six months: games can be written against `Sounds.win` before `win.mp3` exists,
and they start working the day it lands.

Game-owned sounds need no registry at all — `SoundCue.asset('assets/games/flood/splash.mp3')`
makes one on the spot. The library is for what is shared.

### The rest of it

A package (`audioplayers` is the least fuss for short one-shots), an SDK-level
mute honoured centrally rather than per game — settings already live in
`shared_preferences` — and a cap on concurrent voices, because eight players and
one scoring event is eight simultaneous clips.

A `GameView` may also want a purely local sound with no round trip: a tap tick
on its own glass. `ViewContext.audio` exposes the same interface restricted to
this device, so a game never has to reach past the SDK to a raw audio player.

---

## Phases

All four phases are **built**; what they landed as is at the bottom.

**Phase 0 — the roster.** `Player`, `ViewContext.players` / `.me`,
`BoardContext.roster`. No art, no sound. Delete Guac-a-Mole's `colors`
round-trip through `sharedState` and read `context.byPhone(...)` instead —
that is the proof the plumbing is right. *Small: one new model file, one
construction site, one game simplified.*

**Phase 1 — art, drawn procedurally.** `PlayerArt`, `PlayerArtSlot`,
`Cast`, and one implementation painting the circle and the rounded square.
Ships with **no asset files**. Migrate one game — Subway Skater already tints a
player shape from `props['color']` and is the smallest honest test. *Small.*

**Phase 2 — audio plumbing.** The mute, `HostMsg.sound`,
`BoardContext.audio` and `ViewContext.audio`, timeline scheduling and the stale
drop. Prove it with two cues and no art: a general countdown beep and a targeted
one. This is the only phase that touches the protocol, and it is worth doing
before the sounds exist for the same reason phase 1 is worth doing before the
art does. *Medium.*

**Phase 3 — real assets.** Sixteen PNGs at 512², decoded once per (colour,
slot) and scaled at draw time. Preloaded during
placement — dead time, while people are pushing phones together — and only for
the colours at this table, because a four-player round has no reason to hold
eight pictures nobody is looking at. Never awaited: the first frame draws
geometry if the decode has not landed.

PNG rather than SVG, despite the feature starting life as `getPlayerSVG()`.
`flutter_svg` is a real dependency to add across four platform builds, and the
format was never the promise — the interface hands out something drawable, and
what is behind it can become a vector or a sprite sheet without a game
noticing. That was the reason for dropping `SVG` from the name.

**No game was edited in this phase**, which is the whole point of the three
before it. The sixteen player clips will land the same way. *Entirely inside the
SDK.*

The order matters: every phase is useful on its own, and phases 0 and 1 are
worth doing even if no art is ever drawn — they delete an existing hack and give
every future game a first-class roster.

---

## What was built

All four phases, against a clean analyzer and 527 passing tests (31 new).

| | |
| --- | --- |
| `sdk/model/player.dart` | `Player`, `Roster` |
| `sdk/model/player_character.dart` | `PlayerCharacter`, `Cast` — eight animals, no assets |
| `sdk/render/player_art.dart` | `PlayerArt`, `PlayerArtSlot`, image loading, the geometry fallback |
| `assets/sdk/players/*.png` | sixteen images: a square per colour, a round piece with a black centre |
| `assets/sdk/players/*.wav` | sixteen voices: a happy and a sad per colour |
| `assets/sdk/sfx/pop.wav` | the first cue of the house library with a recording behind it |
| `sdk/audio/sound_cue.dart` | `SoundCue`, `SoundHandle` |
| `sdk/audio/sounds.dart` | `Sounds` — the house library, named and silent — and `PlayerSounds` |
| `sdk/audio/game_audio.dart` | `GameAudio`, `LocalAudio`, `RoundAudio`, `AudioCommand` |
| `sdk/audio/audio_engine.dart` | scheduling, staleness, the voice cap, mute, lifetime |
| `sdk/audio/audio_output.dart` | the seam a real audio package plugs into |

Wired through `ViewContext` (`roster`, `me`, `audio`), `BoardContext` (`roster`,
`audio`), `BoardLayout.contextFor`, `HostMsg.sound`, `HostSession._flushAudio` /
`_silenceRound`, and `ClientSession.audio` pumped from `frameAt`.

Guac-a-Mole's `colors` round-trip through `sharedState` is gone — it reads
`context.me.color`, known at build time instead of after the first HUD frame.
Subway Skater draws its skaters with `player.topdown.draw(...)`, which is the
same circle it drew by hand and will be a fox without being edited. Slingshot
fires the **host's face** at the tower, which took `Roster.hostPhoneId` — who is
running the session is platform knowledge no game can derive, since board order
is not join order and a host that reconnects reclaims neither.

**Lottie is gone.** It was in the project for one thing — Slingshot's bird — and
that is now a player portrait from the SDK. The package, `LottieSprite`, and
`assets/animations/character_test.json` are all deleted. The contract that class
existed to defend is not: `test/sprite_loading_test.dart` still proves `load()`
returns while the artwork is still decoding, retargeted at the new path. Worth
knowing for later — Lottie was also the road to *animated* characters, so
animating one means bringing it back.

The art and the player voices are real files now. **The one piece deliberately
left out is the audio backend.** `AudioOutput` has
exactly one implementation, `SilentAudioOutput`, which is correct in every
respect except making noise. There is not a sound file in the project, so
shipping a native audio plugin across four platform builds today would add a
dependency in order to play nothing. When the first clip is recorded, one class
lands behind that interface and nothing else changes — the routing, the
scheduling, the lifetime rules and their tests are all already exercised through
it.

---

## Constraints this inherits

The palette exists because a player has to be identifiable *at arm's length,
upside down, against a moving background, by someone who has had a drink*. Art
does not get to weaken that. A character must read as its colour first and its
species second — colour filling the silhouette, not an accent on it — or the
eight characters become eight small grey shapes and the whole reason `PlayerColor`
is in the SDK goes away. The topdown slot especially: it will be drawn at maybe
three world units across, seen from two metres, in a room with the lights on.

And artwork never decides whether a round starts. That lesson is already written
into `LottieSprite`; here it is enforced by making the fallback unavoidable.

---

## Settled

- **The colour *is* the character.** One per palette entry, so the host's
  existing uniqueness promise covers both and there is no second allocator, no
  extra lobby step, and no two-Foxes-at-one-table case to arbitrate.
- **Two slots, no moods**: `topdown` from above, `face` from the side.
- **No `SVG` in the names.** The format is the SDK's business.
- **Two audio verbs**, `playGeneral` on the host and `playOnPhone` on one
  device.

- **The SDK owns a general sound library**, extensible one line at a time, and
  usable by name before the file exists.
- **`playGeneral` returns a handle**; `stopSound(handle)` stops it mid-round.
  Round-scoped by default, `persist: true` to cross a round boundary.

- **Several loops may play at once.** The audio system does not enforce a single
  music slot; tracks are held by hand, by handle, because a game that wants two
  beds layered has a better view of its own edge cases than a rule would.
- **A muted or departed phone is silence.** `playOnPhone` never falls back to
  the host: a sound from the wrong device is worse than no sound.

## The player voices, and where they came from

Recorded as `player1`..`player8`, each with `-1` for happy and `-2` for sad, and
renamed on the way in to the colour they belong to — `player1` is `green`,
following the palette's own hand-out order, through to `player8` as `red`.

Renamed rather than mapped in a table, because **a voice belongs to a character,
not to a seat number**. Had the files kept their recording names, reordering the
palette would silently hand the Frog somebody else's voice; named by colour, the
Frog keeps its own. It also puts them beside `green-face.png` in one folder,
where the whole of a character is visible at a glance.

They live in `assets/`, not `lib/`. Assets under a source directory are not
bundled unless something declares them, and nothing did — they would have
resolved to silence at runtime with no error to explain it.

## What the platform says out loud

Two moments belong to the SDK rather than to any game, and both play in the
player's own voice on the phone in their hand:

**'I am ready.'** Confirming placement plays that player's happy sound, locally
and immediately — local feedback for a local tap, with no shared instant to
agree with. It is also the first time most people hear which character they
are.

**The verdict.** When a round ends, each phone plays happy or sad according to
the headline it is already showing. Decided locally rather than sent, because
every phone has the outcome and works out its own verdict from it — routing it
through the host would be a second implementation of a question that must have
exactly one answer.

| ending | what plays |
| --- | --- |
| `contest` | happy on the winners' phones, sad on everyone else's |
| `shared`, won | happy on every phone |
| `shared`, lost | sad on every phone |
| `personal` — a score attack nobody wins | happy on every phone |
| `draw` | **nothing** |

The draw is a judgement, not a spec: nobody won and nobody lost, and a sad
voice on every phone would be telling eight people they lost a round that
nothing lost. It is the same reason `OutcomeKind.draw` exists rather than being
inferred from a missing winner.

## Open questions

1. **Is extracting `lib/sdk/` into a real package on the roadmap?** It does not
   change the design — asset paths stay hidden either way — but it decides how
   hard to insist on the path discipline in `Characters` and `Sounds`.
