import 'dart:ui';

/// Colours for the edge stripes that mark which screen meets which.
///
/// One list, used by both the full-screen edges and the schema, so a red line
/// on the glass and a red line in the picture are the same red. Chosen to stay
/// distinct from each other and from the board's own blues.
class LinkPalette {
  const LinkPalette._();

  static const _colors = <Color>[
    Color(0xFFFF4D4D), // red
    Color(0xFFFFD166), // yellow
    Color(0xFF7FD1C4), // teal
    Color(0xFFB980F0), // violet
    Color(0xFF6BCB77), // green
    Color(0xFFFF9F45), // orange
    Color(0xFF4D9DE0), // blue
  ];

  static Color of(int index) => _colors[index % _colors.length];

  /// For a stripe with no partner — the one that only says "the middle of the
  /// table is this way".
  ///
  /// Deliberately outside the list above. It is not half of anything, and
  /// painting it in a pairing colour is how a ring once looked like a row of
  /// joins that had all come out the same.
  ///
  /// Muted stone rather than the near-white it used to be: these screens are
  /// drawn on the flow's paper now, and a white line on white paper is no line
  /// at all.
  static const Color inward = Color(0xFF8C8370);
}
