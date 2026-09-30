/// What a colour *is*, beyond a swatch.
///
/// [PlayerColor] answered "which one of you is that" from across a table. This
/// answers the next question, which people ask immediately and out loud: not
/// "the green one" but "the frog". A colour is unambiguous and forgettable; a
/// frog is neither.
///
/// **The colour is the character.** Not a second thing to pick — one table of
/// eight, indexed by colour id, so the host's existing promise that no two
/// phones share a colour is already the promise that no two share a character.
/// Nothing new to allocate, nothing new for the lobby to ask, and no way for
/// the two identities to disagree.
library;

import 'player_color.dart';

/// One character: a name, two pictures and two sounds.
///
/// Asset paths live here and **nowhere else in the codebase**. A game reaches
/// its art through [Player], never through a string, which is what keeps the
/// door open on `lib/sdk/` becoming a real package later — a package's assets
/// are addressed as `packages/<name>/…`, so every path a game had hardcoded
/// would break on the day of the split. Games cannot hardcode one because they
/// are never shown one.
///
/// Every asset field is nullable and every one of them is null today. That is
/// the point: the art does not exist yet, the interface does, and a null asset
/// draws the placeholder rather than failing. Filling these in is a one-line
/// change per character that no game is recompiled for.
class PlayerCharacter {
  const PlayerCharacter({
    required this.colorId,
    required this.name,
    this.topdownAsset,
    this.faceAsset,
    this.happyAsset,
    this.sadAsset,
  });

  /// Which [PlayerColor] this belongs to. The join between the two tables.
  final String colorId;

  /// What it is called out loud: 'Frog'. Read with the colour — 'Green Frog' —
  /// so it has to be one short word that survives being shouted across a table.
  final String name;

  /// Seen from above: the piece on the board, drawn small and at any angle.
  final String? topdownAsset;

  /// Seen from the front: a portrait, drawn upright and large enough to have a
  /// face. The lobby's character picker. Painted from one tinted `.riv` for
  /// the whole cast where Rive runs; this image is what stands in where it
  /// does not.
  final String? faceAsset;

  final String? happyAsset;
  final String? sadAsset;

  @override
  String toString() => 'PlayerCharacter($colorId/$name)';
}

/// The eight characters, and the way back from a colour to one.
///
/// Named `Cast` and not `Characters`, which is the obvious name and an
/// unusable one: `package:characters` exports a `Characters` class, Flutter
/// re-exports it from `widgets.dart`, and any file drawing a character would
/// have imported both and refused to compile.
///
/// Deliberately a static table rather than a registry with a `register()` call:
/// [PlayerPalette] is one, so is `PlayerNames`, and none of them can be
/// half-initialised, called in the wrong order, or populated differently on two
/// devices that must agree. Adding a character is an entry here.
///
/// The animals are chosen for their **silhouettes**. The topdown picture will
/// be drawn a few world units across and read from two metres, so the shape has
/// to carry at a glance — which rules out anything whose outline is a blob, and
/// is the same constraint that shaped the palette itself.
class Cast {
  const Cast._();

  /// Everything a character is, on disk: two pictures and two voices.
  ///
  /// The pictures are placeholders with a real file behind them — the loading
  /// path an illustration will use. The voices are not placeholders. They were
  /// recorded as `player1`..`player8` and renamed to the colour they belong to,
  /// following the palette's hand-out order, so that the Frog keeps its voice
  /// if the palette is ever reordered. A sound belongs to a character, not to
  /// a seat number.
  ///
  /// Written out rather than derived from the colour id, because `const` is
  /// worth more here than brevity: eight entries checked at compile time beat
  /// eight built at startup, and a test walks the table to prove every path
  /// resolves.
  static const green = PlayerCharacter(
    colorId: 'green',
    name: 'Frog',
    topdownAsset: 'assets/sdk/players/green-topdown.png',
    faceAsset: 'assets/sdk/players/green-face.png',
    happyAsset: 'assets/sdk/players/green-happy.wav',
    sadAsset: 'assets/sdk/players/green-sad.wav',
  );

  static const orange = PlayerCharacter(
    colorId: 'orange',
    name: 'Fox',
    topdownAsset: 'assets/sdk/players/orange-topdown.png',
    faceAsset: 'assets/sdk/players/orange-face.png',
    happyAsset: 'assets/sdk/players/orange-happy.wav',
    sadAsset: 'assets/sdk/players/orange-sad.wav',
  );

  static const blue = PlayerCharacter(
    colorId: 'blue',
    name: 'Whale',
    topdownAsset: 'assets/sdk/players/blue-topdown.png',
    faceAsset: 'assets/sdk/players/blue-face.png',
    happyAsset: 'assets/sdk/players/blue-happy.wav',
    sadAsset: 'assets/sdk/players/blue-sad.wav',
  );

  static const pink = PlayerCharacter(
    colorId: 'pink',
    name: 'Flamingo',
    topdownAsset: 'assets/sdk/players/pink-topdown.png',
    faceAsset: 'assets/sdk/players/pink-face.png',
    happyAsset: 'assets/sdk/players/pink-happy.wav',
    sadAsset: 'assets/sdk/players/pink-sad.wav',
  );

  static const yellow = PlayerCharacter(
    colorId: 'yellow',
    name: 'Bee',
    topdownAsset: 'assets/sdk/players/yellow-topdown.png',
    faceAsset: 'assets/sdk/players/yellow-face.png',
    happyAsset: 'assets/sdk/players/yellow-happy.wav',
    sadAsset: 'assets/sdk/players/yellow-sad.wav',
  );

  static const purple = PlayerCharacter(
    colorId: 'purple',
    name: 'Octopus',
    topdownAsset: 'assets/sdk/players/purple-topdown.png',
    faceAsset: 'assets/sdk/players/purple-face.png',
    happyAsset: 'assets/sdk/players/purple-happy.wav',
    sadAsset: 'assets/sdk/players/purple-sad.wav',
  );

  static const brown = PlayerCharacter(
    colorId: 'brown',
    name: 'Bear',
    topdownAsset: 'assets/sdk/players/brown-topdown.png',
    faceAsset: 'assets/sdk/players/brown-face.png',
    happyAsset: 'assets/sdk/players/brown-happy.wav',
    sadAsset: 'assets/sdk/players/brown-sad.wav',
  );

  static const red = PlayerCharacter(
    colorId: 'red',
    name: 'Crab',
    topdownAsset: 'assets/sdk/players/red-topdown.png',
    faceAsset: 'assets/sdk/players/red-face.png',
    happyAsset: 'assets/sdk/players/red-happy.wav',
    sadAsset: 'assets/sdk/players/red-sad.wav',
  );

  /// In palette order, so the two tables can be read side by side.
  static const all = <PlayerCharacter>[
    green,
    orange,
    blue,
    pink,
    yellow,
    purple,
    brown,
    red,
  ];

  /// The character wearing this colour.
  ///
  /// Total: every palette entry has one, and the test that proves it is the
  /// thing that stops the two tables drifting apart when a ninth colour is
  /// added. The fallback exists only so a colour id read off the wire from a
  /// newer build cannot crash an older one.
  static PlayerCharacter of(PlayerColor color) => byColorId(color.id) ?? green;

  static PlayerCharacter? byColorId(String colorId) {
    for (final c in all) {
      if (c.colorId == colorId) return c;
    }
    return null;
  }
}
