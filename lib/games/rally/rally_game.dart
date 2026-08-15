import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'rally_sim.dart';
import 'rally_view.dart';

/// One ball, bounced back and forth the length of the table. Tap near it to
/// send it back; miss, and it rolls past your own baseline for the other
/// side to score.
class RallyGame implements MultiscreenGame {
  const RallyGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'rally',
    title: 'Rally',
    tagline: 'One ball, two baselines. Tap it back before it gets past you.',
    goal: 'First team to 5 points wins the rally.',
    // Two equal teams, one camped at each end of the lane.
    players: PlayerCount.range(min: 2, max: 8, parity: CountParity.even),
  );

  /// A wide, short lane — the same runway Push of War tugs its ball down,
  /// with a team camped at either end. `Layouts.row` names "pong" as one of
  /// the arrangements it exists for; this is the first game to actually play
  /// it.
  @override
  BoardPlan planBoard(LobbyInfo lobby) => Layouts.row(lobby.phones);

  @override
  GameSim createSim(BoardContext context) => RallySim(context);

  @override
  GameView createView(ViewContext context) => RallyView();
}
