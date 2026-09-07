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
    required this.skinLight,
    required this.skinDark,
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

  /// The highlight and the shadow of [value] — 'reflet lumineux' and 'ombre'
  /// on the palette sheet, and `SkinLight` / `SkinDark` on the character's
  /// view model.
  ///
  /// Given per entry rather than computed from [value] by lightening and
  /// darkening it. A uniform shift in HSL reads wrong across a palette this
  /// wide: the same step that flatters the blue turns the yellow to mustard
  /// and the brown to mud, because how far a hue can travel before it stops
  /// being that colour is a property of the hue. These are the swatches that
  /// were drawn, so they are the swatches that ship.
  final Color skinLight;
  final Color skinDark;

  @override
  String toString() => 'PlayerColor($id)';
}

/// The palette, and the rules for handing it out.
///
/// Eight entries. The first four — what a four-player game actually uses — are
/// the four that stay furthest apart, including in a photograph with the colour
/// taken out. Growing the table adds colours that are still distinct but sit
/// closer to their neighbours, which is the honest trade: eight-way
/// distinguishable is about the limit of a phone screen seen across a table.
///
/// The swatches are fixed. The **order** is the part that is chosen: seats are
/// filled from the top, so the earlier entries are the ones a small table
/// actually uses, and they are sorted so that the fewer people are playing, the
/// further apart their colours are.
class PlayerPalette {
  const PlayerPalette._();

  static const green = PlayerColor(
    id: 'green',
    name: 'Green',
    value: Color(0xFF31B83C),
    onColor: Color(0xFF0B280D),
    skinLight: Color(0xFF4EE45A),
    skinDark: Color(0xFF258C2E),
  );

  static const orange = PlayerColor(
    id: 'orange',
    name: 'Orange',
    value: Color(0xFFFE7013),
    onColor: Color(0xFF381904),
    skinLight: Color(0xFFFF944E),
    skinDark: Color(0xFFCC5E17),
  );

  static const blue = PlayerColor(
    id: 'blue',
    name: 'Blue',
    value: Color(0xFF14AEEF),
    onColor: Color(0xFF042635),
    skinLight: Color(0xFF4EC4F6),
    skinDark: Color(0xFF1B87B5),
  );

  static const pink = PlayerColor(
    id: 'pink',
    name: 'Pink',
    value: Color(0xFFFB48C4),
    onColor: Color(0xFF37102B),
    skinLight: Color(0xFFFF6CD2),
    skinDark: Color(0xFFD23DA5),
  );

  static const yellow = PlayerColor(
    id: 'yellow',
    name: 'Yellow',
    value: Color(0xFFF3C61A),
    onColor: Color(0xFF352C06),
    skinLight: Color(0xFFFFDA4C),
    skinDark: Color(0xFFD5AF1B),
  );

  static const purple = PlayerColor(
    id: 'purple',
    name: 'Purple',
    value: Color(0xFF8D13FF),
    onColor: Color(0xFF1F0438),
    skinLight: Color(0xFFAE58FF),
    skinDark: Color(0xFF6D19BB),
  );

  static const brown = PlayerColor(
    id: 'brown',
    name: 'Brown',
    value: Color(0xFFBA6C24),
    onColor: Color(0xFF291808),
    skinLight: Color(0xFFD2843C),
    skinDark: Color(0xFFA15D1E),
  );

  static const red = PlayerColor(
    id: 'red',
    name: 'Red',
    value: Color(0xFFD23131),
    onColor: Color(0xFF2E0B0B),
    skinLight: Color(0xFFE05D5D),
    skinDark: Color(0xFF932323),
  );

  /// Every colour, in hand-out order.
  static const all = <PlayerColor>[
    green,
    yellow,
    purple,
    brown,
    pink,
    red,
    orange,
    blue,
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
