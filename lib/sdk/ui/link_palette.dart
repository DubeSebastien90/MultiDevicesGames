import 'dart:ui';

class LinkPalette {
  const LinkPalette._();

  static const _colors = <Color>[
    Color(0xFFFF4D4D),
    Color(0xFFFFD166),
    Color(0xFF7FD1C4),
    Color(0xFFB980F0),
    Color(0xFF6BCB77),
    Color(0xFFFF9F45),
    Color(0xFF4D9DE0),
  ];

  static Color of(int index) => _colors[index % _colors.length];

  static const Color inward = Color(0xFF8C8370);
}
