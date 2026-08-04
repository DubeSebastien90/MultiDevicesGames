/// Tunables shared by both Flood variants, and the ones each owns alone.
///
/// Split three ways on purpose: the numbers that define the board and the feel
/// of a tap are common, and each variant then adds exactly one knob for the
/// mechanic that distinguishes it. Playtesting one variant should not silently
/// retune the other.
class FloodConfig {
  const FloodConfig._();

  // ------------------------------------------------------------- the board

  /// Teams. Blue owns the top row, red the bottom, and the boundary starts on
  /// the seam between them.
  static const String blue = 'blue';
  static const String red = 'red';

  /// Smallest and largest table. Always two equal rows, so always even.
  static const int minPhones = 2;
  static const int maxPhones = 6;

  // ------------------------------------------------------------- the round

  /// Nobody's taps count until this has passed. Long enough that everyone
  /// looks up from placing their phone, short enough not to be a wait.
  static const double countdownSeconds = 3.0;

  /// Hard backstop. A perfectly even 1v1 could otherwise run past the point
  /// where anyone is enjoying it, so at this mark whoever is even marginally
  /// ahead takes it. Both READMEs specify the same 45s.
  static const double maxRoundLength = 45.0;

  /// The win line, in either direction. The world axis is [-1, +1].
  static const double winAt = 1.0;

  // --------------------------------------------------------------- the tap

  /// How far one tap moves the boundary.
  ///
  /// The READMEs ask for "~20 solo taps = full swing", i.e. one tap crosses a
  /// twentieth of the half-axis it has to cover. Unopposed at t=0 that is 20
  /// taps to win, and both variants then bend that number their own way.
  static const double basePush = 1.0 / 20;

  /// A phone cannot register taps faster than this. Guards against a held
  /// finger reporting as a stream of downs, and against an autoclicker; a
  /// human mashing tops out around 10/s, so this is generous.
  static const double minTapIntervalSeconds = 0.04;

  // ---------------------------------------------------------------- colour

  static const int colorBlue = 0xFF2F6FED;
  static const int colorRed = 0xFFED4B2F;
  static const int colorNeutral = 0xFF0B1020;
}

/// Option A's one knob.
class FloodGrowingConfig {
  const FloodGrowingConfig._();

  /// Seconds until a tap hits twice as hard as it did at the start.
  ///
  /// The snowball knob. Lower makes rounds end abruptly; higher lets a
  /// stalemate run longer before the ramp breaks it open.
  static const double rampWindow = 15.0;
}

/// Option B's two knobs.
class FloodShrinkingConfig {
  const FloodShrinkingConfig._();

  /// Seconds until the contested field is as narrow as it will get.
  static const double shrinkWindow = 25.0;

  /// The floor the field shrinks to. Never zero: a sliver of contested ground
  /// always remains, or the last moment of the round becomes a coin toss.
  static const double minScale = 0.15;
}
