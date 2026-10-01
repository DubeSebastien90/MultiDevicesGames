library;

import 'dart:ui' show Color;

class PlayerColor {
  const PlayerColor({
    required this.id,
    required this.name,
    required this.value,
    required this.onColor,
    required this.skinLight,
    required this.skinDark,
  });

  final String id;

  final String name;

  final Color value;

  final Color onColor;

  final Color skinLight;
  final Color skinDark;

  @override
  String toString() => 'PlayerColor($id)';
}

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

  static const away = PlayerColor(
    id: 'away',
    name: 'Away',
    value: Color(0xFF9E9E9E),
    onColor: Color(0xFF2B2B2B),
    skinLight: Color(0xFFC6C6C6),
    skinDark: Color(0xFF6F6F6F),
  );

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

  static int get size => all.length;

  static PlayerColor? byId(String? id) {
    if (id == null) return null;
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }

  static PlayerColor? firstFree(Iterable<String> taken) {
    final used = taken.toSet();
    for (final c in all) {
      if (!used.contains(c.id)) return c;
    }
    return null;
  }
}
