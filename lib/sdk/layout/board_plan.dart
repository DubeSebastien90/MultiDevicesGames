/// Where one phone's lit area sits on the board, in millimetres.
///
/// The *lit* area, not the casing — bezels are the game's business, because a
/// game may want the screens touching (leaving a gap the ball flies through) or
/// deliberately spaced.
class PhonePlacement {
  const PhonePlacement(
    this.phoneId, {
    required this.xMm,
    required this.yMm,
    this.quarterTurns = 0,
    this.hint,
  });

  final String phoneId;

  /// Top-left corner of this screen's footprint, in board millimetres. The
  /// board's origin is wherever the plan puts it; the compiler normalises so
  /// the top-left is (0, 0).
  final double xMm;
  final double yMm;

  /// How far this phone is turned within the board, clockwise, in 90° steps.
  ///
  /// The app itself is locked portrait and never rotates. This is the game
  /// saying "put this phone on its side", and the phone then rotates what it
  /// draws so the world reads upright to whoever is standing at the table.
  ///
  /// An odd number of turns swaps the screen's footprint: a phone 68mm wide
  /// and 152mm tall occupies 152 x 68 of the board.
  final int quarterTurns;

  /// Optional line shown on that phone's placement screen: 'below the big one'.
  /// The platform writes a sensible default when this is null.
  final String? hint;
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
  const BoardPlan(this.placements, {this.instruction, this.bounds});

  final List<PhonePlacement> placements;

  /// The one line everyone reads before moving their phone:
  /// 'Stack the phones one above the other, long edges touching.'
  final String? instruction;

  /// The playfield. Null means "the box around every screen", which is the
  /// right answer whenever the phones match.
  final BoardBoundsMm? bounds;

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
