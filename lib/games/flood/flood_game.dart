import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
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
    // Two equal teams, so an odd table cannot play at all. The lobby filters
    // on this and never offers the game at three phones.
    players: PlayerCount.range(
      min: FloodConfig.minPhones,
      max: FloodConfig.maxPhones,
      parity: CountParity.even,
    ),
  );

  /// Two rows facing each other: blue along the top, red along the bottom.
  ///
  /// Still throws on an odd phone count, though the manifest's parity rule now
  /// means the lobby never offers the game at one. Kept as a backstop: the
  /// board is built from the assumption of two equal rows, and a silent wrong
  /// answer there would be a game people can see is broken.
  @override
  BoardPlan planBoard(LobbyInfo lobby) => FloodBoard.plan(lobby);

  @override
  GameSim createSim(BoardContext context) => FloodGrowingSim(context);

  @override
  GameView createView(ViewContext context) => FloodGrowingView(context);
}
