import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'cargo_run_sim.dart';
import 'cargo_run_view.dart';

/// A belt runs the length of the table, and crates roll down it one after
/// another — over every phone in turn, through the real gap between each pair
/// of casings — until they roll off the far end.
///
/// A green crate tapped while it is close by scores its tapper a point; a red
/// one costs them one. Whoever is standing where a crate currently is gets the
/// only crack at it, and a crate nobody was near just keeps rolling — the
/// point lost, never a penalty.
class CargoRunGame implements MultiscreenGame {
  const CargoRunGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'cargo_run',
    title: 'Cargo Run',
    tagline: 'Crates roll down the belt. Grab the green ones before they '
        'roll past — leave the red ones alone.',
    goal: 'Most points cleared when the belt stops.',
    players: PlayerCount.range(min: 2, max: 8),
  );

  /// One long belt, phones on their sides, short edges touching — the same
  /// runway Subway Skater and Driftwood use, for the same reason: a crate
  /// travels the whole length of the table and wants every centimetre of it.
  @override
  BoardPlan planBoard(LobbyInfo lobby) => Layouts.row(
    lobby.phones,
    sort: PhoneSort.joinOrder,
    instruction: 'Lay the phones on their sides in one long line, short '
        'edges touching — it is one belt.',
  );

  @override
  GameSim createSim(BoardContext context) => CargoRunSim(context);

  @override
  GameView createView(ViewContext context) => CargoRunView(context);
}
