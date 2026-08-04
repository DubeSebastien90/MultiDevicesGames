import '../../sdk/contract/sim.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'flood_config.dart';

/// The two-row grid both Flood variants play on, and the team split that falls
/// out of it.
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
///
/// The packing itself is [Layouts.grid] — a facing-rows board is not a Flood
/// idea, and any team-versus-team game wants the same shape. What is left here
/// is only what is genuinely Flood's: which phones make up each team, and where
/// the line between them sits.
class FloodBoard {
  const FloodBoard._();

  /// Lay out [lobby] as two equal rows.
  ///
  /// Throws [BoardPlanError] on an odd phone count. The manifest's parity rule
  /// already keeps the lobby from offering the game at an odd table, so this is
  /// a backstop: the board is built from the premise of two equal teams, and a
  /// silent wrong answer here would be a game people can see is broken.
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
    final grid = Layouts.grid(
      lobby.phones,
      rows: 2,
      // Largest first, and the grid fills row by row — so the biggest screens
      // land across the top and the seam, where every round is actually
      // decided, falls across the most glass available.
      sort: PhoneSort.largestFirst,
      // Portrait: the push axis is vertical, so each phone gives it the long
      // edge and the most travel.
      orientation: PhoneOrientation.upright,
      instruction:
          'Two rows facing each other, upright, long edges touching — '
          'blue along the top, red along the bottom.',
    );

    // Re-hint with team names. The grid knows about rows; only Flood knows a
    // row is a side.
    return BoardPlan(
      [
        for (var i = 0; i < grid.placements.length; i++)
          PhonePlacement(
            grid.placements[i].phoneId,
            xMm: grid.placements[i].xMm,
            yMm: grid.placements[i].yMm,
            turnDeg: grid.placements[i].turnDeg,
            hint: _hint(i < perTeam, i % perTeam, perTeam),
          ),
      ],
      instruction: grid.instruction,
      bounds: grid.bounds,
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

  /// The grid's own hint says which row you are in; this says which *team*
  /// that makes you, which is what a player actually needs to know before the
  /// countdown starts.
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
