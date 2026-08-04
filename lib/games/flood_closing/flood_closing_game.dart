import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/phone_spec.dart';
import '../flood_common/flood_board.dart';
import '../flood_common/flood_config.dart';
import 'flood_shrinking_sim.dart';
import 'flood_shrinking_view.dart';

/// Push-o'-War, option B: the same tug-of-war, fair taps throughout, and a
/// playfield that keeps closing in.
///
/// Shares its board, its teams, its countdown and its tap handling with
/// [FloodGame] — the two variants differ in exactly one thing each, and both
/// of those live in the sim.
class FloodClosingGame implements MultiscreenGame {
  const FloodClosingGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'floodclosing',
    title: 'Flood: Closing In',
    tagline: 'Same taps. The ground between you keeps closing in.',
    goal: 'Hold the lead when the field runs out.',
    players: PlayerCount.range(
      min: FloodConfig.minPhones,
      max: FloodConfig.maxPhones,
      parity: CountParity.even,
    ),
  );

  @override
  BoardPlan planBoard(LobbyInfo lobby) => FloodBoard.plan(lobby);

  @override
  GameSim createSim(BoardContext context) => FloodShrinkingSim(context);

  @override
  GameView createView(ViewContext context) => FloodShrinkingView(context);
}
