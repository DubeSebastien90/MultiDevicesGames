import 'dart:math' as math;

/// Where one phone goes, in board millimetres.
///
/// The position is the **middle of the lit area**, and [turnDeg] is how far the
/// phone is turned clockwise from upright. Centre-plus-angle rather than a
/// corner, because once a phone can lie at 37° there is no meaningful
/// axis-aligned corner to measure from.
class PhonePlacement {
  const PhonePlacement(
    this.phoneId, {
    required this.xMm,
    required this.yMm,
    this.turnDeg = 0,
    this.hint,
  });

  final String phoneId;

  /// Middle of the lit area, in board millimetres. The compiler normalises the
  /// whole plan so the board's top-left corner is the world origin.
  final double xMm;
  final double yMm;

  /// Clockwise, degrees, from the phone held upright.
  ///
  /// The app is locked portrait and never rotates. This is the game saying how
  /// the device lies on the table; the phone then turns its camera and its UI
  /// to match, so the board reads the right way up to its player.
  final double turnDeg;

  double get turnRadians => turnDeg * math.pi / 180;

  /// Optional line shown on that phone's placement screen: 'below the big one'.
  final String? hint;

  PhonePlacement copyWith({double? xMm, double? yMm, double? turnDeg}) =>
      PhonePlacement(
        phoneId,
        xMm: xMm ?? this.xMm,
        yMm: yMm ?? this.yMm,
        turnDeg: turnDeg ?? this.turnDeg,
        hint: hint,
      );
}

/// The playfield rectangle, in the same millimetre space as the placements.
///
/// Worth stating separately from "the box around all the screens", because with
/// mismatched phones those differ. A row of a tall phone and a short one is only
/// *fully covered* as deep as the short one; treating the taller phone's extra
/// centimetre as playfield would invent a dead zone that is not a real gap
/// between screens. Games that want that extra space can ask for it.
class BoardBoundsMm {
  const BoardBoundsMm({
    required this.leftMm,
    required this.topMm,
    required this.widthMm,
    required this.heightMm,
  });

  final double leftMm;
  final double topMm;
  final double widthMm;
  final double heightMm;
}

/// A game's answer to "where does everyone go?".
class BoardPlan {
  const BoardPlan(
    this.placements, {
    this.instruction,
    this.bounds,
    this.allowGaps = false,
  });

  final List<PhonePlacement> placements;

  /// The one line everyone reads before moving their phone.
  final String? instruction;

  /// The playfield. Null means "the box around every screen", which is the
  /// right answer whenever the phones are butted together.
  final BoardBoundsMm? bounds;

  /// The board is meant to have space between screens.
  ///
  /// Normally a phone sitting far from its neighbours is a bug in the plan's
  /// arithmetic, and the compiler refuses it. A ring of phones around a table
  /// is the legitimate exception: nothing touches, and the potato crossing the
  /// void between two screens is the game working, not failing.
  final bool allowGaps;

  PhonePlacement? forPhone(String phoneId) {
    for (final p in placements) {
      if (p.phoneId == phoneId) return p;
    }
    return null;
  }

  /// Returns a copy with [placement] replacing whatever was there for that
  /// phone — for a game that calls a helper and then adjusts one screen.
  BoardPlan withPlacement(PhonePlacement placement) => BoardPlan(
    [
      for (final p in placements)
        if (p.phoneId == placement.phoneId) placement else p,
    ],
    instruction: instruction,
    allowGaps: allowGaps,
    // Deliberately dropped: moving a screen invalidates a hugged playfield,
    // and the bounding box is the safe answer until the game says otherwise.
    bounds: null,
  );
}

/// A plan the platform refuses to build a board from.
///
/// These are development-time mistakes, not runtime conditions: they mean the
/// game's `planBoard` is wrong. Failing loudly on the host beats shipping a
/// board where two phones claim the same coordinates and the result merely
/// looks like a rendering glitch.
class BoardPlanError implements Exception {
  const BoardPlanError(this.message);
  final String message;

  @override
  String toString() => 'Bad board plan: $message';
}
