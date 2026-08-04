import 'dart:math' as math;

import '../../sdk/contract/sim.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/phone_spec.dart';
import 'flood_config.dart';

/// The two-row grid both Flood variants play on, and the team split that falls
/// out of it.
///
/// `Layouts.row` and `.column` pack along a single axis, and this board is two
/// axes at once: N columns wide and always exactly **two rows deep**, one row
/// per team. So it is written directly as placements, which is the path the SDK
/// documents for "an L, a grid, a ring".
///
/// ```
///   1v1                2v2                  3v3
///  ┌────┐            ┌────┬────┐        ┌────┬────┬────┐
///  │ B  │            │ B  │ B  │        │ B  │ B  │ B  │
///  ├────┤            ├────┼────┤        ├────┼────┼────┤
///  │ R  │            │ R  │ R  │        │ R  │ R  │ R  │
///  └────┘            └────┴────┘        └────┴────┴────┘
/// ```
///
/// Two rows is what makes the game legible on a table: every player has one
/// phone directly in front of them to tap, teammates sit shoulder to shoulder
/// along their row, and the boundary they are all pushing runs across the
/// single seam between the rows.
class FloodBoard {
  const FloodBoard._();

  /// Phones stand as you normally hold them. Portrait gives the push axis the
  /// most travel per phone, which is the axis the whole game happens on.
  static const int _quarterTurns = 0;

  /// Lay out [lobby] as two equal rows.
  ///
  /// Throws [BoardPlanError] on an odd phone count — two equal teams is the
  /// premise of the game, not a preference. The host sees the message on the
  /// lobby screen and the round never starts.
  static BoardPlan plan(LobbyInfo lobby) {
    final count = lobby.phoneCount;
    if (count.isOdd) {
      throw BoardPlanError(
        'Flood is played in two equal teams, so it needs an even number of '
        'phones — there ${count == 1 ? "is" : "are"} $count. '
        'Connect or drop one.',
      );
    }
    if (count < FloodConfig.minPhones || count > FloodConfig.maxPhones) {
      throw BoardPlanError(
        'Flood needs ${FloodConfig.minPhones}–${FloodConfig.maxPhones} '
        'phones, not $count',
      );
    }

    final perTeam = count ~/ 2;

    // Biggest screens to the middle, so the seam — where every round is
    // actually decided — falls across the most glass available. Ties keep join
    // order, which keeps the layout stable between rounds on matched phones.
    final ordered = List.of(lobby.phones)
      ..sort((a, b) => b.areaMm2.compareTo(a.areaMm2));
    final blue = <PhoneSpec>[];
    final red = <PhoneSpec>[];
    for (var i = 0; i < ordered.length; i++) {
      (i.isEven ? blue : red).add(ordered[i]);
    }

    // Columns are as wide as their widest phone, so a mismatched pair still
    // stacks with its lit areas centred on each other.
    final columnWidths = <double>[
      for (var c = 0; c < perTeam; c++)
        math.max(blue[c].footprintWidthMm(_quarterTurns),
            red[c].footprintWidthMm(_quarterTurns)),
    ];

    // Rows are as deep as their deepest phone, and the two rows are pushed
    // together casing to casing.
    final blueDepth = [
      for (final p in blue) p.footprintHeightMm(_quarterTurns),
    ].reduce(math.max);
    final redDepth = [
      for (final p in red) p.footprintHeightMm(_quarterTurns),
    ].reduce(math.max);

    // The seam: both bezels of whichever pair meets across it. Every column
    // shares one seam line, so the widest bezel pair sets it — that is the
    // phones physically touching.
    var seamMm = 0.0;
    for (var c = 0; c < perTeam; c++) {
      final gap = blue[c].bezelMm + red[c].bezelMm;
      if (gap > seamMm) seamMm = gap;
    }

    final placements = <PhonePlacement>[];
    var x = 0.0;
    // The playfield spans every column, but within a column it is only as wide
    // as the *narrower* of the two phones facing each other — the strip that
    // both teams can actually see. A wider phone's overhang looks like
    // playfield and is not, because the team opposite has no screen under it.
    var playLeft = double.infinity;
    var playRight = double.negativeInfinity;

    for (var c = 0; c < perTeam; c++) {
      final columnWidth = columnWidths[c];
      var columnLeft = double.negativeInfinity;
      var columnRight = double.infinity;

      for (final (spec, isBlue) in [(blue[c], true), (red[c], false)]) {
        final w = spec.footprintWidthMm(_quarterTurns);
        final h = spec.footprintHeightMm(_quarterTurns);
        final left = x + (columnWidth - w) / 2;

        // Bottom-aligned in the top row, top-aligned in the bottom row: both
        // teams' screens run right up to the seam, whatever their depth. A
        // shallower phone loses its far edge, never its front line.
        final top = isBlue
            ? blueDepth - h
            : blueDepth + seamMm;

        placements.add(PhonePlacement(
          spec.phoneId,
          xMm: left,
          yMm: top,
          quarterTurns: _quarterTurns,
          hint: _hint(isBlue, c, perTeam),
        ));

        // Intersect *within* the column: the two phones facing each other.
        if (left > columnLeft) columnLeft = left;
        if (left + w < columnRight) columnRight = left + w;
      }

      // Union *across* columns: they sit side by side, so each adds ground.
      if (columnLeft < playLeft) playLeft = columnLeft;
      if (columnRight > playRight) playRight = columnRight;

      x += columnWidth;
    }

    return BoardPlan(
      placements,
      instruction:
          'Two rows facing each other, upright, long edges touching — '
          'blue along the top, red along the bottom.',
      bounds: BoardBoundsMm(
        leftMm: playLeft,
        topMm: 0,
        widthMm: playRight - playLeft,
        heightMm: blueDepth + seamMm + redDepth,
      ),
    );
  }

  /// Which team each phone plays for, read off the compiled board.
  ///
  /// Deliberately derived from **where the phones ended up**, not from the same
  /// sort [plan] used: a phone in the top half of the board is blue because
  /// that is the territory it is physically sitting in. Recomputing the sort
  /// would be a second source of truth that could drift from the first, and the
  /// sim would then credit taps to the wrong side of a board people can see.
  ///
  /// The seam is found from the screens themselves rather than assumed to be
  /// the board's middle. Those are the same line only when both rows are
  /// equally deep — put a big phone opposite a small one, or two desktop
  /// windows of different sizes, and the board's centre falls *inside* the
  /// deeper row. Splitting on it would then hand one team's phone to the
  /// other side.
  ///
  /// So: sort the screens by where they sit, and cut at the largest vertical
  /// gap between consecutive ones. On a two-row board that gap is the seam by
  /// construction, whatever the rows are made of.
  static Map<String, String> teamsFor(BoardContext context) {
    final slices = List.of(context.slices)
      ..sort((a, b) => a.viewport.top.compareTo(b.viewport.top));

    if (slices.length < 2) {
      throw const BoardPlanError('Flood needs two rows of phones, not one');
    }

    // The widest vertical step between one screen's bottom and the next
    // screen's top. Screens sharing a row overlap or touch, so their step is
    // at or below zero; the two rows are separated by a real gap.
    var seam = double.negativeInfinity;
    var cutAfter = 0;
    var deepestSoFar = slices.first.viewport.bottom;

    for (var i = 1; i < slices.length; i++) {
      final gap = slices[i].viewport.top - deepestSoFar;
      if (gap > seam) {
        seam = gap;
        cutAfter = i;
      }
      if (slices[i].viewport.bottom > deepestSoFar) {
        deepestSoFar = slices[i].viewport.bottom;
      }
    }

    return {
      for (var i = 0; i < slices.length; i++)
        slices[i].phoneId:
            i < cutAfter ? FloodConfig.blue : FloodConfig.red,
    };
  }

  /// Where the two rows meet, in world units — the line boundary 0 sits on.
  ///
  /// The middle of the gap between the rows, not the middle of the board: the
  /// world runs continuously through the bezels, and the midpoint of that dead
  /// space is the line each team's screens are equidistant from. It is also
  /// what makes a phone look exactly half flooded at boundary 0.
  static double seamOf(BoardContext context) {
    final slices = List.of(context.slices)
      ..sort((a, b) => a.viewport.top.compareTo(b.viewport.top));
    if (slices.length < 2) return context.board.centerY;

    var seam = double.negativeInfinity;
    var topRowBottom = slices.first.viewport.bottom;
    var bottomRowTop = slices.last.viewport.top;
    var deepestSoFar = slices.first.viewport.bottom;

    for (var i = 1; i < slices.length; i++) {
      final gap = slices[i].viewport.top - deepestSoFar;
      if (gap > seam) {
        seam = gap;
        topRowBottom = deepestSoFar;
        bottomRowTop = slices[i].viewport.top;
      }
      if (slices[i].viewport.bottom > deepestSoFar) {
        deepestSoFar = slices[i].viewport.bottom;
      }
    }

    return (topRowBottom + bottomRowTop) / 2;
  }

  static String _hint(bool isBlue, int column, int perTeam) {
    final side = isBlue ? 'top' : 'bottom';
    final team = isBlue ? 'BLUE' : 'RED';
    if (perTeam == 1) {
      return '$team — the $side phone, facing your opponent';
    }
    return '$team — $side row, position ${column + 1} of $perTeam '
        'from the left';
  }

}
