import '../../sdk/contract/sim.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'flood_config.dart';

class FloodBoard {
  const FloodBoard._();

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
      sort: PhoneSort.largestFirst,
      orientation: PhoneOrientation.upright,
      instruction:
          'Two rows facing each other, upright, long edges touching — '
          'blue along the top, red along the bottom.',
    );

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

  static Map<String, String> teamsFor(BoardContext context) {
    final slices = List.of(context.slices)
      ..sort((a, b) => a.viewport.top.compareTo(b.viewport.top));

    if (slices.length < 2) {
      throw const BoardPlanError('Flood needs two rows of phones, not one');
    }

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
        slices[i].phoneId: i < cutAfter ? FloodConfig.blue : FloodConfig.red,
    };
  }

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
