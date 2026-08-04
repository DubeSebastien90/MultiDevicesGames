/// Who a player *is*, at a glance, across a table of phones.
///
/// The platform already identifies a phone two ways — `phoneId` ('p1') for the
/// wire and `label` ('Pixel 7') for a diagram — and neither survives being
/// looked at from two metres away. A colour does. That is the whole reason this
/// belongs to the SDK rather than to any one game: it is a property of the
/// person, not of the round, and it outlives every minigame the way the
/// [Scoreboard] does.
///
/// The palette is fixed and small. Colours are picked from it, never mixed:
/// a player's colour has to be identifiable at arm's length, upside down,
/// against a moving background, by someone who has had a drink. That rules out
/// a colour wheel, and it rules out more than a handful of options.
library;

import 'dart:ui' show Color;

/// One entry in the palette.
///
/// [id] is what crosses the wire and what a game stores; [value] is only ever
/// used for drawing. Keeping them apart means the palette can be re-tuned —
/// and it will be, on real screens in real light — without invalidating a
/// saved choice or breaking two builds that disagree about a shade.
class PlayerColor {
  const PlayerColor({
    required this.id,
    required this.name,
    required this.value,
    required this.onColor,
  });

  /// Stable and wire-visible: 'green'. Never derived from the swatch.
  final String id;

  /// What a person calls it out loud: 'Green'. Used in prompts — 'that one is
  /// Green's' — so it has to be a word, not a hex code.
  final String name;

  /// The swatch itself.
  final Color value;

  /// Text or line work drawn *on* [value]. Precomputed per entry rather than
  /// derived from luminance, because the two light swatches here sit close
  /// enough to the threshold that an automatic answer flips between them.
  final Color onColor;

  @override
  String toString() => 'PlayerColor($id)';
}

/// The palette, and the rules for handing it out.
///
/// Eight entries, ordered so that the first four — the ones a four-player game
/// actually uses — are maximally far apart in hue. Growing the table adds
/// colours that are still distinct but sit closer to their neighbours, which is
/// the honest trade: eight-way distinguishable is about the limit of a phone
/// screen seen across a table.
///
/// Chosen to stay separable for the common colour-vision deficiencies: the
/// red/green pair that deuteranopia collapses is split by a large lightness
/// gap, and no two adjacent entries rely on hue alone.
class PlayerPalette {
  const PlayerPalette._();

  static const green = PlayerColor(
    id: 'green',
    name: 'Green',
    value: Color(0xFF4CAF50),
    onColor: Color(0xFF0B2D0D),
  );

  static const orange = PlayerColor(
    id: 'orange',
    name: 'Orange',
    value: Color(0xFFFF9800),
    onColor: Color(0xFF3A2000),
  );

  static const blue = PlayerColor(
    id: 'blue',
    name: 'Blue',
    value: Color(0xFF2196F3),
    onColor: Color(0xFF04243D),
  );

  static const pink = PlayerColor(
    id: 'pink',
    name: 'Pink',
    value: Color(0xFFEC407A),
    onColor: Color(0xFF3D0A1C),
  );

  static const yellow = PlayerColor(
    id: 'yellow',
    name: 'Yellow',
    value: Color(0xFFFFEB3B),
    onColor: Color(0xFF3B3600),
  );

  static const purple = PlayerColor(
    id: 'purple',
    name: 'Purple',
    value: Color(0xFF9C27B0),
    onColor: Color(0xFF2B0A32),
  );

  static const cyan = PlayerColor(
    id: 'cyan',
    name: 'Cyan',
    value: Color(0xFF26C6DA),
    onColor: Color(0xFF04302F),
  );

  static const red = PlayerColor(
    id: 'red',
    name: 'Red',
    value: Color(0xFFE53935),
    onColor: Color(0xFF3D0A09),
  );

  /// Every colour, in hand-out order.
  static const all = <PlayerColor>[
    green,
    orange,
    blue,
    pink,
    yellow,
    purple,
    cyan,
    red,
  ];

  /// The ceiling on players in one session, and therefore on phones.
  static int get size => all.length;

  static PlayerColor? byId(String? id) {
    if (id == null) return null;
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// The first colour nobody has taken, or null when the palette is exhausted.
  ///
  /// Used to seat a phone the moment it joins, so a player who never opens the
  /// picker still has an identity. Picking is a *change*, not a gate — a lobby
  /// that demands eight people each make a choice before anyone can play is a
  /// lobby nobody gets out of.
  static PlayerColor? firstFree(Iterable<String> taken) {
    final used = taken.toSet();
    for (final c in all) {
      if (!used.contains(c.id)) return c;
    }
    return null;
  }
}
