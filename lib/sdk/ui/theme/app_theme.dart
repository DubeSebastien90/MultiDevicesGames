/// The app's two themes, and the component styling that makes the restyle
/// mostly free.
///
/// The screens themselves ask for very little: a `Card`, a `FilledButton`, a
/// `TextField`. Before this file every one of those rendered as stock Material
/// because [ThemeData] carried nothing but a seed colour — so the way to change
/// how the app looks was to edit every widget. Putting the answers in
/// `cardTheme`, `filledButtonTheme`, `inputDecorationTheme` and friends means
/// the widgets keep asking for the same thing and get the new look anyway.
///
/// Two themes, not one, because the app has two jobs. [light] is the lobby: a
/// page you read up close, in a lit room, deciding things. [dark] is the
/// playfield: a surface you look *at*, laid flat on a table, where a white
/// background would be a lamp pointed at everyone. [SessionScreen] hands the
/// dark one to the placement and play phases; everything else is light.
library;

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_dimens.dart';

class AppTheme {
  const AppTheme._();

  /// Poppins, embedded rather than fetched. The whole app runs on a local
  /// hotspot with no route to the internet, and `google_fonts` would silently
  /// fall back to Roboto in exactly the situation the app is designed for.
  static const _font = 'Poppins';

  static const _lightScheme = ColorScheme.light(
    primary: AppColors.yellow,
    onPrimary: AppColors.onYellow,
    primaryContainer: Color(0xFFFFF1D0),
    onPrimaryContainer: AppColors.ink,
    // Ink is the *other* primary: the second button on the menu, the host
    // panel, every strong border. Material has no name for "the dark one", so
    // it lives in the secondary slot.
    secondary: AppColors.ink,
    onSecondary: AppColors.onInk,
    surface: AppColors.bg,
    onSurface: AppColors.ink,
    surfaceContainerHighest: AppColors.surface,
    surfaceContainerHigh: AppColors.surface,
    onSurfaceVariant: AppColors.inkSoft,
    outline: AppColors.outline,
    outlineVariant: AppColors.outline,
    error: AppColors.danger,
    onError: Color(0xFFFFFFFF),
    errorContainer: AppColors.dangerSurface,
    onErrorContainer: Color(0xFF7F1D1D),
  );

  /// The menu and the lobby.
  static final ThemeData light = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: _lightScheme,
    scaffoldBackgroundColor: AppColors.bg,
    fontFamily: _font,
    textTheme: _textTheme(AppColors.ink, AppColors.inkSoft),

    // Flat means flat: no tint that shifts with elevation, no shadow under a
    // card. Separation is carried by the fill alone.
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      // Every call site used to pass this by hand.
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
    ),

    // The 56pt floor is what retires the `label: Padding(vertical: 12)` trick
    // the four call sites each reinvented to get a button worth tapping.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.yellow,
        foregroundColor: AppColors.onYellow,
        disabledBackgroundColor: AppColors.surface,
        disabledForegroundColor: AppColors.inkSoft,
        minimumSize: const Size(0, 56),
        elevation: 0,
        textStyle: const TextStyle(
          fontFamily: _font,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size(0, 56),
        side: const BorderSide(color: AppColors.ink, width: 2),
        textStyle: const TextStyle(
          fontFamily: _font,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.ink,
        textStyle: const TextStyle(
          fontFamily: _font,
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
    ),

    // Filled, borderless at rest, ink at focus. An outlined field on a white
    // page reads as a box to be inspected; a filled one reads as a slot to be
    // typed in, which is what these are.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: const TextStyle(color: AppColors.inkSoft),
      floatingLabelStyle: const TextStyle(
        color: AppColors.ink,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: const TextStyle(color: AppColors.inkSoft),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.ink, width: 2),
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      side: BorderSide.none,
      showCheckmark: false,
      labelStyle: const TextStyle(
        fontFamily: _font,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      shape: const StadiumBorder(),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      titleTextStyle: const TextStyle(
        fontFamily: _font,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: _font,
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
        color: AppColors.ink,
      ),
    ),

    listTileTheme: ListTileThemeData(
      iconColor: AppColors.ink,
      textColor: AppColors.ink,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
    ),

    dividerTheme: const DividerThemeData(
      color: AppColors.outline,
      thickness: 1,
      space: 1,
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: const TextStyle(
        fontFamily: _font,
        color: AppColors.onInk,
        fontWeight: FontWeight.w500,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.ink,
    ),
  );

  /// The placement and play phases, unchanged from what shipped before the
  /// restyle apart from the accent.
  ///
  /// Kept as a real theme rather than deleted because those screens paint their
  /// own dark canvas and then draw text with `colorScheme.onSurfaceVariant` on
  /// top of it. Under the light scheme that is dark grey on dark navy — the
  /// legend on the placement screen would simply vanish.
  static final ThemeData dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.yellow,
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: AppColors.canvas,
    fontFamily: _font,
  );

  /// One scale, both themes. Sizes are fixed; only the two ink colours change.
  ///
  /// Weights run heavier than Material's defaults across the board — w500 for
  /// body, w700 for every title. That, plus negative tracking on the large
  /// sizes, is most of what makes the type look drawn rather than typed.
  static TextTheme _textTheme(Color ink, Color soft) => TextTheme(
    displaySmall: TextStyle(
      fontSize: 34,
      height: 1.08,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.6,
      color: ink,
    ),
    headlineMedium: TextStyle(
      fontSize: 28,
      height: 1.12,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
      color: ink,
    ),
    headlineSmall: TextStyle(
      fontSize: 24,
      height: 1.15,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.4,
      color: ink,
    ),
    titleLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
      color: ink,
    ),
    titleMedium: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.1,
      color: ink,
    ),
    titleSmall: TextStyle(
      fontSize: 14.5,
      fontWeight: FontWeight.w700,
      color: ink,
    ),
    bodyLarge: TextStyle(fontSize: 16, height: 1.45, color: ink),
    bodyMedium: TextStyle(
      fontSize: 15,
      height: 1.45,
      fontWeight: FontWeight.w500,
      color: ink,
    ),
    bodySmall: TextStyle(
      fontSize: 13,
      height: 1.4,
      fontWeight: FontWeight.w500,
      color: soft,
    ),
    labelLarge: TextStyle(
      fontSize: 14.5,
      fontWeight: FontWeight.w700,
      color: ink,
    ),
    labelMedium: TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: soft,
    ),
    labelSmall: TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: soft,
    ),
  );
}
