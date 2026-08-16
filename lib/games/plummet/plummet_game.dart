import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'plummet_sim.dart';
import 'plummet_view.dart';

/// A ball falls under real gravity down a narrow shaft made of every phone
/// stacked on the table, seam after seam. Tap near it to swat it sideways,
/// clear of the wall spikes zigzagging down toward the floor.
class PlummetGame implements MultiscreenGame {
  const PlummetGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'plummet',
    title: 'Plummet',
    tagline: 'A ball falls down the shaft. Tap to swat it clear of the '
        'spikes.',
    goal: 'Get it to the bottom of the stack without a spike catching it — '
        'together.',
    players: PlayerCount.range(min: 2, max: 8),
  );

  /// Phones stacked top to bottom — `Layouts.column`'s own doc names "falling
  /// things" as exactly what it is for, and this is the first game to build
  /// one. Left at the layout's default orientation, which lies each phone
  /// with its long edge running left-to-right: a wide well, not a coffin.
  @override
  BoardPlan planBoard(LobbyInfo lobby) => Layouts.column(lobby.phones);

  @override
  GameSim createSim(BoardContext context) => PlummetSim(context);

  @override
  GameView createView(ViewContext context) => PlummetView();
}
