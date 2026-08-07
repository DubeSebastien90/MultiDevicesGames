/// The palette the lobby chrome is built from.
///
/// Deliberately small and flat: six values, no gradients, no elevation tints.
/// A colour here is either the page, a surface on the page, ink on a surface,
/// or the one accent that means "this is the thing to press". Anything that
/// needs to be *vivid* — a player, a seam, a game entity — comes from
/// [PlayerPalette] instead, so there is exactly one family of bright colour in
/// the app and it always means "somebody".
///
/// These are the menu-and-lobby colours. The playfield keeps its own dark
/// surface ([AppColors.canvas]) because a board seen across a table is read by
/// contrast against the room, not against the app.
library;

import 'dart:ui' show Color;

class AppColors {
  const AppColors._();

  /// The page. Pure white, not off-white: every card on it is a light grey, and
  /// two near-whites a few percent apart read as a printing error rather than a
  /// hierarchy.
  static const bg = Color(0xFFFFFFFF);

  /// Cards and inputs sitting on [bg]. Carries the whole separation on its own
  /// since nothing here casts a shadow.
  static const surface = Color(0xFFF6F7F9);

  /// Text, icons, and the cards that need to shout. Not pure black — #14161B
  /// keeps a trace of blue, which stops large ink areas from looking like a
  /// hole punched in the page.
  static const ink = Color(0xFF14161B);

  /// Secondary text. The one grey, used everywhere the old code reached for
  /// `colorScheme.onSurfaceVariant`.
  static const inkSoft = Color(0xFF6B7280);

  /// Hairlines. Only ever 1px, only ever between two light surfaces.
  static const outline = Color(0xFFE5E7EB);

  /// The primary. Golden rather than lemon so it can carry ink text as a large
  /// filled button — a saturated yellow at this size vibrates against black.
  static const yellow = Color(0xFFFFC83D);

  /// Text and icons drawn on [yellow]. ~11:1 against it.
  static const onYellow = ink;

  /// White drawn on [ink] cards.
  static const onInk = Color(0xFFFFFFFF);

  /// Secondary text on [ink] cards. Warmer and lighter than [inkSoft], which
  /// would disappear against it.
  static const onInkSoft = Color(0xFF9AA1AE);

  /// Trouble. Kept red rather than tinted toward the brand: an error that
  /// looks like the rest of the app is an error nobody reads.
  static const danger = Color(0xFFE5484D);
  static const dangerSurface = Color(0xFFFFF0F0);

  /// The playfield background, and the surface the placement screen paints.
  ///
  /// Shared by the dark theme, [ViewportGame.backgroundColor] and
  /// `ShapeView`'s default — it used to be the literal `0xFF0B1020` written out
  /// in four separate files.
  static const canvas = Color(0xFF0B1020);
}
