/// Radii and spacing, so the chrome agrees with itself.
///
/// Every one of these was previously written inline at each call site — eight
/// hand-typed `BorderRadius.circular(10)`s, a `SizedBox(height: 14)` between
/// every pair of lobby cards. Naming them is what makes "big and rounded" a
/// property of the app rather than of whoever last edited a file.
library;

class AppRadius {
  const AppRadius._();

  /// Cards and panels. Large on purpose: it is the single strongest signal of
  /// the flat/friendly language, and it has to survive being read at arm's
  /// length across a table.
  static const card = 24.0;

  /// Buttons. Softer than the card so a button inside a card does not fight
  /// the corner it sits next to.
  static const button = 18.0;

  /// Text fields and the QR block.
  static const field = 16.0;

  /// Chips, badges, and the primary call to action. Any number past half the
  /// height gives a stadium.
  static const pill = 999.0;
}

class AppSpacing {
  const AppSpacing._();

  static const xs = 6.0;
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 18.0;
  static const xl = 24.0;
}
