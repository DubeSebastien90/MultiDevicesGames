import '../../sdk/contract/game.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/phone_spec.dart';
import '../flood_common/flood_board.dart';
import '../flood_common/flood_config.dart';
import 'flood_growing_sim.dart';
import 'flood_growing_view.dart';

/// Push-o'-War, option A: two teams facing each other, and taps that get
/// stronger as the round runs.
///
/// The project's first competitive game — two sides, one loses — and its first
/// grid board. Both existing games are co-operative strips; this one needs two
/// rows facing each other, which is why the layout is written as placements
/// rather than through `Layouts.row`.
class FloodGame implements MultiscreenGame {
  const FloodGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'flood',
    title: 'Flood',
    tagline: 'Two teams, one waterline. Tap to push it onto their screens.',
    goal: 'Flood the other team off the board.',
    minPhones: FloodConfig.minPhones,
    maxPhones: FloodConfig.maxPhones,
  );

  /// Two rows facing each other: blue along the top, red along the bottom.
  ///
  /// Throws on an odd phone count — two equal teams is the premise, so a table
  /// of three is a round that cannot be played rather than one to improvise
  /// through. The host sees why on the lobby screen.
  @override
  BoardPlan planBoard(LobbyInfo lobby) => FloodBoard.plan(lobby);

  @override
  GameSim createSim(BoardContext context) => FloodGrowingSim(context);

  @override
  GameView createView(ViewContext context) => FloodGrowingView(context);
}
