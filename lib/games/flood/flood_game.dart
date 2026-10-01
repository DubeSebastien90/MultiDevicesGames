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

class FloodGame implements MultiscreenGame {
  const FloodGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'flood',
    title: 'Flood',
    tagline: 'Two teams, one waterline. Tap to push it onto their screens.',
    goal: 'Flood the other team off the board.',
    icon: 'assets/icons/icones_minijeux/flood.svg',
    players: PlayerCount.range(
      min: FloodConfig.minPhones,
      max: FloodConfig.maxPhones,
      parity: CountParity.even,
    ),
  );

  @override
  BoardPlan planBoard(LobbyInfo lobby) => FloodBoard.plan(lobby);

  @override
  GameSim createSim(BoardContext context) => FloodGrowingSim(context);

  @override
  GameView createView(ViewContext context) => FloodGrowingView(context);
}
