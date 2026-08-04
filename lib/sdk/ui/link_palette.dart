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
}
