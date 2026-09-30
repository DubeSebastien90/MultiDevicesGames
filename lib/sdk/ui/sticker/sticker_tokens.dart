import 'package:flutter/material.dart';

export 'package:material_symbols_icons/symbols.dart';

/// Visual tokens for the "sticker" screens: yellow paper, ink outlines, hard
/// shadows with no blur.
///
/// Player colours are not here. They already live on [PlayerColor] — the same
/// eight swatches the design was drawn with — and a second copy is how the
/// character picker and the character on the board end up two shades apart.
class St {
  const St._();

  static const ink = Color(0xFF111111);
  static const bg = Color(0xFFFFD23F);
  static const white = Color(0xFFFFFFFF);

  /// Secondary text on yellow.
  static const muted = Color(0xFF5A4A10);

  static const back = Color(0xFFD23131);
  static const go = Color(0xFF31B83C);
  static const premium = Color(0xFF8D13FF);
  static const premiumTint = Color(0xFFE6E0F0);
  static const lockedText = Color(0xFF7A6A94);
  static const gold = Color(0xFFFFDA4C);
  static const silver = Color(0xFFDCDCDC);
  static const bronze = Color(0xFFD2843C);
  static const pink = Color(0xFFFB48C4);
  static const blue = Color(0xFF14AEEF);
  static const scrim = Color(0x99111111);

  /// Home's two big actions and its dice — brighter than the palette entries
  /// they sit next to, as drawn.
  static const create = Color(0xFF2FD152);
  static const join = Color(0xFFFF4F9E);
  static const dice = Color(0xFF3AA8FF);

  /// A game tile's ribbon when it is in the run, cycling by position.
  static const tileBands = [
    Color(0xFFFB48C4),
    Color(0xFF14AEEF),
    Color(0xFF31B83C),
    Color(0xFFFE7013),
    Color(0xFFF3C61A),
    Color(0xFF8D13FF),
    Color(0xFFD23131),
    Color(0xFFBA6C24),
  ];

  /// The floating shapes behind every screen, in the characters' own colours.
  static const shapeColors = [
    Color(0xFF14AEEF),
    Color(0xFFBA6C24),
    Color(0xFFF3C61A),
    Color(0xFF8D13FF),
    Color(0xFFFE7013),
    Color(0xFFFB48C4),
    Color(0xFFD23131),
    Color(0xFF31B83C),
  ];

  static const press = Duration(milliseconds: 80);

  /// A tap shorter than this still shows the whole sink. Without it a quick
  /// tap lifts before [press] has drawn anything.
  static const minPress = Duration(milliseconds: 140);

  static const quick = Duration(milliseconds: 150);
  static const sheet = Duration(milliseconds: 280);

  /// Hard offset shadow, no blur. [o] is the offset: 3 small, 5 medium,
  /// 7 large.
  static List<BoxShadow> hard(double o) => o <= 0
      ? const []
      : [BoxShadow(color: ink, offset: Offset(o, o), blurRadius: 0)];

  /// Fill, 3px ink border, hard shadow — every card and button.
  static BoxDecoration sticker({
    Color color = white,
    double radius = 22,
    double shadow = 5,
    double border = 3,
  }) => BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: ink, width: border),
    boxShadow: hard(shadow),
  );

  /// Lilita One: titles, buttons, badges. One weight.
  static TextStyle display(
    double size, {
    Color color = ink,
    double height = 1.05,
  }) => TextStyle(
    fontFamily: 'LilitaOne',
    fontSize: size,
    color: color,
    height: height,
  );

  /// Fredoka: body and labels, at 500, 600 or 700 — the three weights bundled.
  static TextStyle body(
    double size, {
    FontWeight weight = FontWeight.w600,
    Color color = ink,
    double height = 1.3,
  }) => TextStyle(
    fontFamily: 'Fredoka',
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
  );
}

/// The app-wide [ThemeData]: the sticker palette, so anything Material draws
/// on its own — a text-selection handle, a dropdown's menu, a tooltip — looks
/// like it belongs.
///
/// Every screen draws its own stickers and does not lean on this; it is the
/// floor under them, not the design. The games are drawn under their own dark
/// theme — see `SessionScreen`.
ThemeData stickerTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: St.bg,
        brightness: Brightness.light,
      ).copyWith(
        primary: St.ink,
        onPrimary: St.white,
        secondary: St.blue,
        surface: St.white,
        onSurface: St.ink,
        error: St.back,
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: St.bg,
    fontFamily: 'Fredoka',
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: St.ink,
      selectionColor: St.blue.withValues(alpha: .35),
      selectionHandleColor: St.ink,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: St.ink,
        borderRadius: BorderRadius.circular(10),
      ),
      textStyle: St.body(13, color: St.bg),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: St.ink,
      contentTextStyle: St.body(15, color: St.bg),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

/// The colour matrix for CSS's `grayscale(amount)`: 0 leaves the picture
/// alone, 1 takes all its colour out.
List<double> greyscaleMatrix(double amount) {
  final s = 1 - amount;
  return [
    0.2126 + 0.7874 * s, 0.7152 - 0.7152 * s, 0.0722 - 0.0722 * s, 0, 0, //
    0.2126 - 0.2126 * s, 0.7152 + 0.2848 * s, 0.0722 - 0.0722 * s, 0, 0, //
    0.2126 - 0.2126 * s, 0.7152 - 0.7152 * s, 0.0722 + 0.9278 * s, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}

/// A Material Symbol, rounded, filled, at weight 600 — how the designs draw
/// every icon.
class StIcon extends StatelessWidget {
  const StIcon(this.icon, {super.key, this.size = 24, this.color = St.ink});

  final IconData icon;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Icon(icon, size: size, color: color, fill: 1, weight: 600);
}
